"""Build every generated graphics/collision file consumed by ``pinball.asm``.

The source of truth is split deliberately:

* ``pinbalmap.tmx`` layer ``achtergrond`` supplies static art and tile collision.
* Layer ``elementen`` supplies the visible 16x16 post/bumper artwork.
* Object layer ``PinballObjects`` supplies precise ellipse/polygon geometry.
* ``flippers.tmx`` supplies six reusable frame-local flipper polygons.
* ``tileset.png`` stores an object's hit frame exactly 16 pixels below normal.

The ROM never parses XML or PNG. This script converts those editor-friendly
sources into SCREEN 5 pixels, sprite bitplanes and compact runtime records.
"""

import csv
import math
import os
from pathlib import Path
import shutil
import subprocess
import xml.etree.ElementTree as ET

from PIL import Image


ROOT = Path(__file__).resolve().parents[1]
GFX = ROOT / "gfx"
MAPS = ROOT / "maps"
TILESET_SOURCE = GFX / "tileset.png"
TILESET_DEFINITION = MAPS / "pinball.tsx"
MAP_SOURCE = MAPS / "pinbalmap.tmx"
FLIPPER_MAP_SOURCE = MAPS / "flippers.tmx"
FLIPPER_SOURCE = GFX / "pinball1.png"
BALL_SOURCE = GFX / "ball.bmp"
PREVIEW = GFX / "playfield_assets.png"
SCREEN5 = GFX / "playfield_assets.cor"
RLE_BANK0 = GFX / "playfield_assets_0.rle"
RLE_BANK1 = GFX / "playfield_assets_1.rle"
PLETTER_BANK0 = GFX / "playfield_assets_0.plet5"
PLETTER_BANK1 = GFX / "playfield_assets_1.plet5"
FLIPPER_FRAMES = GFX / "flipper_frames.cor"
FLIPPER_COLLISIONS = GFX / "flipper_collisions.bin"
FLIPPER_INSTANCES = GFX / "flipper_instances.bin"
BALL_FRAMES = GFX / "ball_frames.spr"
COLLISION_MAP = GFX / "collision_map.bin"
CIRCLE_OBJECTS = GFX / "collision_circles.bin"
POLYGON_OBJECTS = GFX / "collision_polygons.bin"
POLYGON_OBJECTS_PLETTER = GFX / "collision_polygons.plet5"
COLLISION_DEBUG = GFX / "collision_debug.png"

BALL_COLLISION_RADIUS = 7
FLIPPER_BALL_COLLISION_RADIUS = 8

# Palette indices shared with Screen5Palette in pinball.asm.
COLOR_TO_INDEX = {
    (0, 0, 0): 1,
    (59, 255, 16): 2,
    (0, 232, 216): 3,
    (21, 0, 130): 4,
    (0, 20, 254): 5,
    (216, 40, 0): 6,
    (255, 0, 0): 6,
    (255, 115, 94): 7,
    (218, 145, 109): 7,
    (219, 144, 108): 7,
    (255, 152, 53): 8,
    (228, 0, 88): 9,
    (72, 72, 72): 12,
    (255, 254, 253): 15,
    (255, 255, 255): 15,
}

INDEX_TO_COLOR = {
    0: (1, 2, 3), 1: (0, 0, 0), 2: (59, 255, 16), 3: (0, 232, 216),
    4: (21, 0, 130), 5: (0, 20, 254), 6: (255, 0, 0), 7: (218, 145, 109),
    8: (255, 152, 53), 9: (228, 0, 88), 10: (255, 255, 0),
    11: (255, 255, 128), 12: (72, 72, 72), 13: (128, 0, 0),
    14: (170, 170, 170), 15: (255, 255, 255),
}


def load_map() -> tuple[
    list[list[list[int]]], list[list[int]], list[list[int]], ET.Element
]:
    """Read visible tile layers plus the two specially named gameplay layers.

    Tiled GIDs are one-based and may contain flip flags. Masking with
    ``0x1fffffff`` removes those flags before converting to a zero-based tile ID.
    """
    root = ET.parse(MAP_SOURCE).getroot()
    width = int(root.get("width", "0"))
    height = int(root.get("height", "0"))
    if (width, height) != (32, 24):
        raise ValueError("pinbalmap.tmx must contain exactly a 32x24 map")

    tileset = root.find("tileset")
    layers = root.findall("layer")
    if tileset is None or not layers:
        raise ValueError("pinbalmap.tmx must contain a tileset and tile layer")

    first_gid = int(tileset.get("firstgid", "1"))
    rendered_layers = []
    collision_rows = None
    element_rows = None
    for layer in layers:
        layer_data = layer.find("data")
        if layer_data is None or layer_data.get("encoding") != "csv":
            raise ValueError(f"TMX layer {layer.get('name')!r} must use CSV encoding")
        gids = [
            int(value)
            for row in csv.reader((layer_data.text or "").strip().splitlines())
            for value in row
            if value.strip()
        ]
        if len(gids) != width * height:
            raise ValueError(f"TMX layer {layer.get('name')!r} must contain 32x24 GIDs")
        tile_ids = [
            -1 if gid == 0 else (gid & 0x1fffffff) - first_gid
            for gid in gids
        ]
        rows = [tile_ids[y * width:(y + 1) * width] for y in range(height)]
        if layer.get("visible", "1") != "0":
            rendered_layers.append(rows)
        if layer.get("name", "").casefold() == "achtergrond":
            collision_rows = rows
        if layer.get("name", "").casefold() == "elementen":
            element_rows = rows

    if collision_rows is None:
        raise ValueError("pinbalmap.tmx must contain tile layer 'achtergrond'")
    if element_rows is None:
        raise ValueError("pinbalmap.tmx must contain tile layer 'elementen'")
    return rendered_layers, collision_rows, element_rows, root


def build_table(layers: list[list[list[int]]]) -> Image.Image:
    """Composite visible Tiled layers into a 256x256 intermediate bitmap.

    Only the first 192 lines are the playfield. Lines 212..227 later hold the
    hidden object-animation atlas; using 256 lines makes two complete VRAM banks.
    """
    source = Image.open(TILESET_SOURCE).convert("RGBA")
    table = Image.new("RGBA", (256, 256), (0, 0, 0, 255))
    columns = source.width // 8
    for rows in layers:
        for tile_y, row in enumerate(rows):
            for tile_x, tile_id in enumerate(row):
                if tile_id < 0:
                    continue
                source_x = (tile_id % columns) * 8
                source_y = (tile_id // columns) * 8
                tile = source.crop((source_x, source_y, source_x + 8, source_y + 8))
                table.alpha_composite(tile, (tile_x * 8, tile_y * 8))
    return table


def build_collision_data(rows: list[list[int]]) -> tuple[bytes, list[tuple[int, int, int]], Image.Image]:
    """Convert background tile properties into the 32x24 collision byte map.

    ``collision_shape=8`` is special: four visual tiles form one 16x16 circle.
    It becomes a legacy circle object and leaves an empty byte in the tile map.
    """
    root = ET.parse(TILESET_DEFINITION).getroot()
    shapes = {}
    for tile in root.findall("tile"):
        prop = tile.find("./properties/property[@name='collision_shape']")
        if prop is not None:
            shapes[int(tile.get("id"))] = int(prop.get("value", "0"))

    compiled = bytearray()
    circles = []
    debug_colors = {
        0: (0, 0, 0), 1: (255, 255, 255), 2: (255, 0, 0),
        3: (0, 255, 0), 4: (0, 128, 255), 5: (255, 128, 0),
        6: (255, 0, 255), 7: (0, 255, 255), 8: (255, 255, 0),
    }
    debug = Image.new("RGB", (256, 192))
    for tile_y, row in enumerate(rows):
        for tile_x, tile_id in enumerate(row):
            shape = shapes.get(tile_id, 0)
            if shape == 8:
                circles.append((tile_x * 8 + 8, tile_y * 8 + 8, 7))
                compiled.append(0)
            else:
                compiled.append(shape)
            color = debug_colors[shape]
            for y in range(tile_y * 8, tile_y * 8 + 8):
                for x in range(tile_x * 8, tile_x * 8 + 8):
                    debug.putpixel((x, y), color)
    return bytes(compiled), circles, debug


def point_inside_polygon(x: float, y: float, points: list[tuple[float, float]]) -> bool:
    inside = False
    previous = points[-1]
    for current in points:
        x1, y1 = previous
        x2, y2 = current
        if (y1 > y) != (y2 > y):
            crossing_x = x1 + (y - y1) * (x2 - x1) / (y2 - y1)
            if x < crossing_x:
                inside = not inside
        previous = current
    return inside


def closest_polygon_edge(
    x: float, y: float, points: list[tuple[float, float]], centroid: tuple[float, float]
) -> tuple[float, float, float, float, float]:
    """Return squared distance and an outward vector for the closest edge."""
    best = None
    previous = points[-1]
    for current in points:
        x1, y1 = previous
        x2, y2 = current
        edge_x = x2 - x1
        edge_y = y2 - y1
        length_sq = edge_x * edge_x + edge_y * edge_y
        if length_sq == 0:
            previous = current
            continue
        amount = max(0.0, min(1.0, ((x - x1) * edge_x + (y - y1) * edge_y) / length_sq))
        closest_x = x1 + amount * edge_x
        closest_y = y1 + amount * edge_y
        away_x = x - closest_x
        away_y = y - closest_y
        distance_sq = away_x * away_x + away_y * away_y

        # At or inside the polygon the point-to-edge vector can face inward.
        # Select the perpendicular that points away from the polygon centroid.
        normal_x, normal_y = -edge_y, edge_x
        middle_x = (x1 + x2) * 0.5
        middle_y = (y1 + y2) * 0.5
        if normal_x * (centroid[0] - middle_x) + normal_y * (centroid[1] - middle_y) > 0:
            normal_x = -normal_x
            normal_y = -normal_y
        candidate = (distance_sq, away_x, away_y, normal_x, normal_y)
        if best is None or candidate[0] < best[0]:
            best = candidate
        previous = current
    if best is None:
        raise ValueError("Polygon contains no usable edges")
    distance_sq, away_x, away_y, normal_x, normal_y = best
    return distance_sq, away_x, away_y, normal_x, normal_y


def quantize_normal(dx: float, dy: float) -> int:
    """Return the BALL_SIDE direction 0..7 used by pinball.asm."""
    abs_x = abs(dx)
    abs_y = abs(dy)
    if abs_y >= abs_x * 2:
        return 2 if dy >= 0 else 6
    if abs_x >= abs_y * 2:
        return 0 if dx >= 0 else 4
    if dx >= 0:
        return 1 if dy >= 0 else 7
    return 3 if dy >= 0 else 5


def build_polygon_field(
    points: list[tuple[float, float]], collision_radius: int = BALL_COLLISION_RADIUS
) -> tuple[int, int, int, int, bytes]:
    """Precompute exact ball-centre collision and normals around one polygon.

    Expanding by the ball radius turns runtime circle-vs-polygon testing into a
    single lookup. Value zero is empty; values 1..8 encode outward normal 0..7.
    Two four-bit lookup values are packed into every output byte.
    """
    min_x = math.floor(min(point[0] for point in points)) - collision_radius
    min_y = math.floor(min(point[1] for point in points)) - collision_radius
    max_x = math.ceil(max(point[0] for point in points)) + collision_radius
    max_y = math.ceil(max(point[1] for point in points)) + collision_radius
    width = max_x - min_x + 1
    height = max_y - min_y + 1
    if not (1 <= width <= 255 and 1 <= height <= 255):
        raise ValueError("Polygon collision field must fit in 255x255 pixels")

    centroid = (
        sum(point[0] for point in points) / len(points),
        sum(point[1] for point in points) / len(points),
    )
    collision_sq = collision_radius * collision_radius
    field = bytearray()
    for y in range(min_y, max_y + 1):
        for x in range(min_x, max_x + 1):
            inside = point_inside_polygon(x, y, points)
            distance_sq, away_x, away_y, edge_normal_x, edge_normal_y = closest_polygon_edge(
                x, y, points, centroid
            )
            in_collision = inside or distance_sq <= collision_sq
            value = 0
            if in_collision:
                if inside or (away_x == 0 and away_y == 0):
                    normal_x, normal_y = edge_normal_x, edge_normal_y
                else:
                    normal_x, normal_y = away_x, away_y
                value |= quantize_normal(normal_x, normal_y) + 1
            field.append(value)

    # Two four-bit normals per byte: even pixel in the low nibble, odd pixel
    # in the high nibble. Four 31x31 bumper fields then remain below 8000h.
    packed = bytearray()
    for index in range(0, len(field), 2):
        value = field[index]
        if index + 1 < len(field):
            value |= field[index + 1] << 4
        packed.append(value)
    return min_x, min_y, width, height, bytes(packed)


def polygon_is_convex(points: list[tuple[float, float]]) -> bool:
    """Return true when all non-zero turns have the same orientation."""
    turns = set()
    for index in range(len(points)):
        first = points[index - 2]
        second = points[index - 1]
        third = points[index]
        cross = (
            (second[0] - first[0]) * (third[1] - second[1])
            - (second[1] - first[1]) * (third[0] - second[0])
        )
        if cross:
            turns.add(1 if cross > 0 else -1)
    return len(turns) <= 1


def find_flipper_pivot(source: Image.Image, source_index: int) -> tuple[int, int]:
    """Find the single black axle pixel in one 32x16 source frame."""
    source_frame = source.crop((source_index * 32, 0, source_index * 32 + 32, 16))
    pivot_pixels = [
        (x, y)
        for y in range(16)
        for x in range(32)
        if source_frame.getpixel((x, y))[:3] == (0, 0, 0)
        and source_frame.getpixel((x, y))[3] != 0
    ]
    if len(pivot_pixels) != 1:
        raise ValueError(
            f"Flipper source frame {source_index} needs exactly one black pivot pixel"
        )
    return pivot_pixels[0]


def build_flipper_collision_data() -> bytes:
    """Compile the six Tiled flipper polygons into pivot-relative fields.

    The binary begins with six little-endian offsets in left0..2,right0..2
    order. Every target record contains signed field X/Y relative to the pivot,
    width, height, two generated distance thresholds and packed normal nibbles.

    No pivot property is required: each 32x16 source frame contains exactly one
    pure-black axle pixel. Polygon coordinates are normalised against the Tiled
    tile placement and then against that detected local pivot.
    """
    root = ET.parse(FLIPPER_MAP_SOURCE).getroot()
    map_tile_width = int(root.get("tilewidth", "0"))
    map_tile_height = int(root.get("tileheight", "0"))
    map_width = int(root.get("width", "0"))
    tileset_ref = root.find("tileset")
    layer = root.find("layer")
    group = next(
        (item for item in root.findall("objectgroup") if item.get("name") == "FlipperCollisions"),
        None,
    )
    if tileset_ref is None or layer is None or group is None:
        raise ValueError("flippers.tmx needs a tileset, tile layer and FlipperCollisions")

    first_gid = int(tileset_ref.get("firstgid", "1"))
    tileset_source = (FLIPPER_MAP_SOURCE.parent / tileset_ref.get("source", "")).resolve()
    tileset_root = ET.parse(tileset_source).getroot()
    tile_width = int(tileset_root.get("tilewidth", "0"))
    tile_height = int(tileset_root.get("tileheight", "0"))
    if (tile_width, tile_height) != (32, 16):
        raise ValueError("flippers.tsx must use 32x16 tiles")

    data = layer.find("data")
    if data is None or data.get("encoding") != "csv":
        raise ValueError("flippers.tmx tile layer must use CSV encoding")
    gids = [
        int(value)
        for row in csv.reader((data.text or "").strip().splitlines())
        for value in row
        if value.strip()
    ]

    # Tiled bottom-aligns tiles that are taller than the map grid cell.
    tile_origins: dict[int, tuple[int, int]] = {}
    for index, gid in enumerate(gids):
        if gid == 0:
            continue
        tile_id = (gid & 0x1fffffff) - first_gid
        cell_x = index % map_width
        cell_y = index // map_width
        origin = (
            cell_x * map_tile_width,
            cell_y * map_tile_height + map_tile_height - tile_height,
        )
        if tile_id in tile_origins:
            raise ValueError(f"flippers.tmx displays tile {tile_id} more than once")
        tile_origins[tile_id] = origin

    source = Image.open(FLIPPER_SOURCE).convert("RGBA")
    records: dict[tuple[str, int], bytes] = {}
    for item in group.findall("object"):
        properties = {
            prop.get("name"): prop.get("value", "")
            for prop in item.findall("./properties/property")
        }
        if properties.get("collision_type", "").casefold() != "flipper":
            continue
        side = properties.get("side", "").casefold()
        frame = int(properties.get("frame", "-1"))
        if side not in {"left", "right"} or frame not in range(3):
            raise ValueError(f"Invalid flipper side/frame on {item.get('name')!r}")
        key = (side, frame)
        if key in records:
            raise ValueError(f"Duplicate flipper polygon for {side} frame {frame}")

        polygon = item.find("polygon")
        if polygon is None:
            raise ValueError(f"Flipper {item.get('name')!r} must be a polygon")
        origin_x = float(item.get("x", "0"))
        origin_y = float(item.get("y", "0"))
        absolute_points = [
            (origin_x + float(x), origin_y + float(y))
            for x, y in (
                tuple(float(axis) for axis in point.split(","))
                for point in polygon.get("points", "").split()
            )
        ]
        if len(absolute_points) < 3 or not polygon_is_convex(absolute_points):
            raise ValueError(f"Flipper {item.get('name')!r} must be a convex polygon")

        source_index = frame if side == "left" else frame + 3
        if source_index not in tile_origins:
            raise ValueError(f"flippers.tmx does not display source frame {source_index}")
        tile_origin_x, tile_origin_y = tile_origins[source_index]
        pivot_x, pivot_y = find_flipper_pivot(source, source_index)
        relative_points = [
            (x - tile_origin_x - pivot_x, y - tile_origin_y - pivot_y)
            for x, y in absolute_points
        ]
        # The 15-pixel ball artwork is centred at sprite coordinate (8,8), so
        # its visible top/left extent is eight pixels. Flippers use that full
        # radius to catch their narrow inner tips before visible intersection.
        field_x, field_y, width, height, field = build_polygon_field(
            relative_points, FLIPPER_BALL_COLLISION_RADIUS
        )
        if not (-128 <= field_x <= 127 and -128 <= field_y <= 127):
            raise ValueError("Pivot-relative flipper field origin must fit a signed byte")

        blade_length = max(abs(round(x)) for x, _ in relative_points)
        base_limit = max(1, round(blade_length / 3))
        tip_start = max(base_limit + 1, round(blade_length * 2 / 3))
        records[key] = bytes((
            field_x & 0xff, field_y & 0xff, width, height,
            base_limit, tip_start,
        )) + field

    order = [(side, frame) for side in ("left", "right") for frame in range(3)]
    missing = [key for key in order if key not in records]
    if missing:
        raise ValueError(f"Missing flipper polygons: {missing}")
    header_size = len(order) * 2
    result = bytearray(header_size)
    offset = header_size
    for index, key in enumerate(order):
        result[index * 2:index * 2 + 2] = offset.to_bytes(2, "little")
        record = records[key]
        result.extend(record)
        offset += len(record)
    return bytes(result)


def add_object_animation(
    table: Image.Image,
    element_rows: list[list[int]],
    screen_x: int,
    screen_y: int,
    slots: dict[tuple[int, int], int],
) -> int:
    """Add a normal-XOR-hit frame to hidden scanlines and return its X.

    The top-left tile at the object's screen position identifies its source art
    in ``tileset.png``. Applying the XOR delta once shows hit and twice restores
    normal, so only one 16x16 frame per unique graphic is stored in VRAM.
    """
    tile_x = screen_x // 8
    tile_y = screen_y // 8
    if not (0 <= tile_x < 32 and 0 <= tile_y < 24):
        raise ValueError("Pinball object graphic lies outside the tile map")
    tile_id = element_rows[tile_y][tile_x]
    if tile_id < 0:
        raise ValueError(
            f"Pinball object at ({screen_x},{screen_y}) has no graphic in layer 'elementen'"
        )

    source = Image.open(TILESET_SOURCE).convert("RGBA")
    columns = source.width // 8
    source_x = (tile_id % columns) * 8
    source_y = (tile_id // columns) * 8
    key = (source_x, source_y)
    if key in slots:
        return slots[key]
    if len(slots) >= 16:
        raise ValueError("The hidden animation atlas supports at most 16 unique object graphics")
    if source_y + 32 > source.height:
        raise ValueError(
            f"Object graphic at tileset ({source_x},{source_y}) has no hit frame 16 pixels below it"
        )

    atlas_x = len(slots) * 16
    slots[key] = atlas_x
    frames = []
    for source_offset_y in (0, 16):
        composed = Image.new("RGBA", (16, 16), (255, 255, 255, 255))
        composed.alpha_composite(
            source.crop((source_x, source_y + source_offset_y,
                         source_x + 16, source_y + source_offset_y + 16))
        )
        frames.append(composed.convert("RGB"))
    delta = Image.new("RGB", (16, 16))
    for y in range(16):
        for x in range(16):
            normal = nearest_palette_index(frames[0].getpixel((x, y)))
            hit = nearest_palette_index(frames[1].getpixel((x, y)))
            delta.putpixel((x, y), INDEX_TO_COLOR[normal ^ hit])
        table.alpha_composite(delta.convert("RGBA"), (atlas_x, 212))
    return atlas_x


def build_object_data(
    root: ET.Element,
    legacy_circles: list[tuple[int, int, int]],
    element_rows: list[list[int]],
    table: Image.Image,
) -> tuple[bytes, bytes]:
    """Compile ellipses as circles and Tiled polygons as lookup fields.

    Circle records have a fixed eight-byte layout. Polygon records are variable
    length because each owns a packed lookup field. Both retain kick, score and
    animation metadata from Tiled for the assembly runtime.
    """
    circle_records = []
    polygon_records = []
    animation_slots: dict[tuple[int, int], int] = {}
    for center_x, center_y, radius in legacy_circles:
        circle_records.append((0, center_x, center_y, radius, 0, 0, 0xff))

    group = next(
        (item for item in root.findall("objectgroup") if item.get("name") == "PinballObjects"),
        None,
    )
    if group is None:
        raise ValueError("pinbalmap.tmx must contain object layer 'PinballObjects'")

    for item in group.findall("object"):
        object_class = (item.get("class") or item.get("type") or "").casefold()
        if object_class not in {"post", "bumper"}:
            continue
        properties = {
            prop.get("name"): int(prop.get("value", "0"))
            for prop in item.findall("./properties/property")
        }
        origin_x = float(item.get("x", "0"))
        origin_y = float(item.get("y", "0"))
        if item.find("ellipse") is not None:
            min_x = origin_x
            min_y = origin_y
            max_x = min_x + float(item.get("width", "0"))
            max_y = min_y + float(item.get("height", "0"))
            width = max_x - min_x
            height = max_y - min_y
            center_x = round((min_x + max_x) / 2)
            center_y = round((min_y + max_y) / 2)
            radius = max(1, round(min(width, height) / 2) - 1)
            type_id = 1 if object_class == "bumper" else 0
            animation_x = add_object_animation(
                table, element_rows, round(min_x), round(min_y), animation_slots
            )
            circle_records.append((
                type_id, center_x, center_y, radius,
                properties.get("kick", 0), properties.get("score", 0), animation_x,
            ))
            continue

        polygon = item.find("polygon")
        if polygon is None:
            raise ValueError(f"Object {item.get('name')!r} must be ellipse or polygon")
        points = [
            (origin_x + float(x), origin_y + float(y))
            for x, y in (
                tuple(float(axis) for axis in point.split(","))
                for point in polygon.get("points", "").split()
            )
        ]
        field_x, field_y, field_width, field_height, field = build_polygon_field(points)
        if not (0 <= field_x <= 255 and 0 <= field_y <= 255):
            raise ValueError(f"Object {item.get('name')!r} collision field leaves the screen")
        type_id = 1 if object_class == "bumper" else 0
        score = properties.get("score", 0)
        graphic_x = round(min(point[0] for point in points))
        graphic_y = round(min(point[1] for point in points))
        animation_x = add_object_animation(
            table, element_rows, graphic_x, graphic_y, animation_slots
        )
        record_size = 11 + len(field)
        if record_size > 0xffff:
            raise ValueError(f"Object {item.get('name')!r} collision field is too large")
        polygon_records.append(bytes((
            record_size & 0xff, record_size >> 8, type_id,
            field_x, field_y, field_width, field_height,
            properties.get("kick", 0), score & 0xff, score >> 8,
            animation_x,
        )) + field)

    if len(circle_records) > 255 or len(polygon_records) > 255:
        raise ValueError("PinballObjects supports at most 255 collision objects")
    circles = bytearray((len(circle_records),))
    for type_id, center_x, center_y, radius, kick, score, animation_x in circle_records:
        circles.extend((
            type_id, center_x, center_y, radius, kick,
            score & 0xff, score >> 8, animation_x,
        ))
    polygons = bytearray((len(polygon_records),))
    for record in polygon_records:
        polygons.extend(record)
    return bytes(circles), bytes(polygons)


def nearest_palette_index(rgb) -> int:
    if rgb == (1, 2, 3):
        return 0  # private sentinel used only by zero-valued XOR atlas pixels
    if rgb in COLOR_TO_INDEX:
        return COLOR_TO_INDEX[rgb]
    nearest = min(
        COLOR_TO_INDEX,
        key=lambda color: sum((color[channel] - rgb[channel]) ** 2 for channel in range(3)),
    )
    return COLOR_TO_INDEX[nearest]


def encode_screen5(table: Image.Image) -> bytes:
    """Pack two four-bit palette indices into each SCREEN 5 VRAM byte."""
    rgb = table.convert("RGB")
    packed = bytearray()
    for y in range(256):
        for x in range(0, 256, 2):
            left = nearest_palette_index(rgb.getpixel((x, y)))
            right = nearest_palette_index(rgb.getpixel((x + 1, y)))
            packed.append((left << 4) | right)
    return bytes(packed)


def load_flipper_instances() -> list[dict[str, int]]:
    """Read reusable tile-object placements from pinbalmap.tmx layer Flippers."""
    root = ET.parse(MAP_SOURCE).getroot()
    group = next(
        (item for item in root.findall("objectgroup") if item.get("name") == "Flippers"),
        None,
    )
    if group is None:
        raise ValueError("pinbalmap.tmx must contain object layer 'Flippers'")

    tileset_ref = next(
        (
            item for item in root.findall("tileset")
            if Path(item.get("source", "")).name.casefold() == "flippers.tsx"
        ),
        None,
    )
    if tileset_ref is None:
        raise ValueError("pinbalmap.tmx must reference flippers.tsx")
    first_gid = int(tileset_ref.get("firstgid", "0"))
    source = Image.open(FLIPPER_SOURCE).convert("RGBA")
    instances = []
    for item in group.findall("object"):
        object_class = (item.get("class") or item.get("type") or "").casefold()
        if object_class != "flipper":
            continue
        raw_gid = int(item.get("gid", "0"))
        if raw_gid == 0 or raw_gid & ~0x1fffffff:
            raise ValueError(f"Flipper {item.get('name')!r} must be an unflipped tile object")
        source_index = raw_gid - first_gid
        properties = {
            prop.get("name"): prop.get("value", "")
            for prop in item.findall("./properties/property")
        }
        side_name = properties.get("side", "").casefold()
        if side_name not in {"left", "right"}:
            raise ValueError(f"Flipper {item.get('name')!r} needs side=left/right")
        side = 0 if side_name == "left" else 1
        expected_source = 0 if side == 0 else 3
        if source_index != expected_source:
            raise ValueError(
                f"Flipper {item.get('name')!r} must use the {side_name} rest-frame tile"
            )
        width = round(float(item.get("width", "0")))
        height = round(float(item.get("height", "0")))
        if (width, height) != (32, 16):
            raise ValueError(f"Flipper {item.get('name')!r} must remain 32x16")

        # Tile objects use a bottom-left anchor in orthogonal Tiled maps.
        origin_x = round(float(item.get("x", "0")))
        origin_y = round(float(item.get("y", "0"))) - height
        pivot_local_x, pivot_local_y = find_flipper_pivot(source, source_index)
        pivot_x = origin_x + pivot_local_x
        pivot_y = origin_y + pivot_local_y
        control_name = properties.get("control", side_name).casefold()
        if control_name not in {"left", "right"}:
            raise ValueError(f"Flipper {item.get('name')!r} control must be left/right")
        control = 0 if control_name == "left" else 1

        frame_indices = range(0, 3) if side == 0 else range(3, 6)
        relative_extents = []
        for frame_index in frame_indices:
            frame_pivot_x, frame_pivot_y = find_flipper_pivot(source, frame_index)
            relative_extents.append((-frame_pivot_x, 31 - frame_pivot_x,
                                     -frame_pivot_y, 15 - frame_pivot_y))
        min_relative_x = min(value[0] for value in relative_extents)
        max_relative_x = max(value[1] for value in relative_extents)
        min_relative_y = min(value[2] for value in relative_extents)
        max_relative_y = max(value[3] for value in relative_extents)
        box_x = ((pivot_x + min_relative_x) // 2) * 2
        box_y = pivot_y + min_relative_y
        if max_relative_x + pivot_x >= box_x + 34 or max_relative_y + pivot_y >= box_y + 23:
            raise ValueError("Internal flipper swept box calculation is too small")
        if not (0 <= box_x <= 222 and 0 <= box_y <= 189):
            raise ValueError(f"Flipper {item.get('name')!r} swept area leaves SCREEN 5")
        instances.append({
            "side": side, "control": control, "pivot_x": pivot_x, "pivot_y": pivot_y,
            "box_x": box_x, "box_y": box_y,
        })
    if not instances:
        raise ValueError("Flippers layer must contain at least one flipper tile object")
    if len(instances) > 16:
        raise ValueError("ROM currently supports at most 16 flipper instances")
    return instances


def encode_flipper_assets(
    table: Image.Image, instances: list[dict[str, int]]
) -> tuple[bytes, bytes]:
    """Bake three background-restoring frames and one runtime record per instance."""
    source = Image.open(FLIPPER_SOURCE).convert("RGBA")
    packed = bytearray()
    records = bytearray((len(instances),))
    for instance_index, instance in enumerate(instances):
        side = instance["side"]
        box_x = instance["box_x"]
        box_y = instance["box_y"]
        pivot_x = instance["pivot_x"]
        pivot_y = instance["pivot_y"]
        frame_base_offset = len(packed)
        frame_indices = range(0, 3) if side == 0 else range(3, 6)
        for frame_index in frame_indices:
            frame = table.crop((box_x, box_y, box_x + 34, box_y + 23)).convert("RGBA")
            source_frame = source.crop((frame_index * 32, 0, frame_index * 32 + 32, 16))
            local_pivot_x, local_pivot_y = find_flipper_pivot(source, frame_index)
            target_x = pivot_x - local_pivot_x - box_x
            target_y = pivot_y - local_pivot_y - box_y
            for y in range(16):
                for x in range(32):
                    pixel = source_frame.getpixel((x, y))
                    red, green, blue, alpha = pixel
                    if alpha != 0 and (red, green, blue) != (255, 255, 255):
                        frame.putpixel((target_x + x, target_y + y), pixel)
            for y in range(23):
                for x in range(0, 34, 2):
                    indices = []
                    for pixel_x in (x, x + 1):
                        red, green, blue, alpha = frame.getpixel((pixel_x, y))
                        indices.append(
                            1 if alpha == 0 else nearest_palette_index((red, green, blue))
                        )
                    packed.append((indices[0] << 4) | indices[1])

        destination = box_y * 128 + box_x // 2
        records.extend((
            side, instance["control"], pivot_x, pivot_y,
            destination & 0xff, destination >> 8,
            frame_base_offset & 0xff, frame_base_offset >> 8,
        ))
    return bytes(packed), bytes(records)


def encode_ball_frames() -> bytes:
    """Split each 16x16 frame into grey and black OR-sprite bitplanes."""
    source = Image.open(BALL_SOURCE).convert("RGB")
    transparent = (72, 182, 72)
    grey = (145, 145, 145)
    black = (0, 0, 0)
    white = (255, 255, 255)
    encoded = bytearray()

    for frame in range(8):
        image = source.crop((frame * 16, 0, frame * 16 + 16, 16))
        for colors in ((grey, white), (black, white)):
            for half in (0, 8):
                for y in range(16):
                    value = 0
                    for x in range(8):
                        pixel = image.getpixel((half + x, y))
                        if pixel != transparent and pixel in colors:
                            value |= 0x80 >> x
                    encoded.append(value)
    return bytes(encoded)


def encode_rle(data: bytes) -> bytes:
    """Encode literals (1..127) and repeated runs (2..128); zero ends a stream."""
    encoded = bytearray()
    position = 0
    while position < len(data):
        run = 1
        while (
            position + run < len(data)
            and data[position + run] == data[position]
            and run < 128
        ):
            run += 1
        if run >= 3:
            encoded.extend((0x80 | (run - 1), data[position]))
            position += run
            continue

        literal_start = position
        position += run
        while position < len(data) and position - literal_start < 127:
            next_run = 1
            while (
                position + next_run < len(data)
                and data[position + next_run] == data[position]
                and next_run < 3
            ):
                next_run += 1
            if next_run >= 3:
                break
            position += next_run
        literal = data[literal_start:position]
        encoded.append(len(literal))
        encoded.extend(literal)
    encoded.append(0)
    return bytes(encoded)


def find_pletter() -> Path:
    """Locate the Pletter executable shared by graphics and collision assets."""
    configured = os.environ.get("PLETTER_EXE")
    candidates = (
        Path(configured) if configured else None,
        ROOT.parent / "pletter" / "pletter.exe",
        Path(shutil.which("pletter") or ""),
    )
    executable = next((path for path in candidates if path and path.is_file()), None)
    if executable is None:
        raise FileNotFoundError(
            "Pletter was not found; set PLETTER_EXE or install it at ../pletter/pletter.exe"
        )
    return executable


def encode_pletter_banks() -> None:
    """Compress both complete 16 KiB VRAM banks with the external Pletter tool."""
    executable = find_pletter()
    for offset, destination in ((0, PLETTER_BANK0), (0x4000, PLETTER_BANK1)):
        subprocess.run(
            (str(executable), str(SCREEN5), str(offset), str(0x4000), str(destination)),
            check=True,
        )


def encode_pletter_file(source: Path, destination: Path) -> None:
    """Compress one complete runtime data file for expansion into page-2 RAM."""
    subprocess.run(
        (str(find_pletter()), str(source), "0", str(source.stat().st_size), str(destination)),
        check=True,
    )


def main() -> None:
    """Run the complete deterministic asset pipeline used before assembling."""
    layers, collision_rows, element_rows, map_root = load_map()
    table = build_table(layers)
    collision_map, legacy_circles, collision_debug = build_collision_data(collision_rows)
    circle_objects, polygon_objects = build_object_data(
        map_root, legacy_circles, element_rows, table
    )
    flipper_collisions = build_flipper_collision_data()
    flipper_instances = load_flipper_instances()
    flipper_frames, flipper_instance_data = encode_flipper_assets(table, flipper_instances)
    table.crop((0, 0, 256, 212)).convert("RGB").save(PREVIEW)
    screen5 = encode_screen5(table)
    SCREEN5.write_bytes(screen5)
    RLE_BANK0.write_bytes(encode_rle(screen5[:0x4000]))
    RLE_BANK1.write_bytes(encode_rle(screen5[0x4000:]))
    FLIPPER_FRAMES.write_bytes(flipper_frames)
    FLIPPER_COLLISIONS.write_bytes(flipper_collisions)
    FLIPPER_INSTANCES.write_bytes(flipper_instance_data)
    BALL_FRAMES.write_bytes(encode_ball_frames())
    COLLISION_MAP.write_bytes(collision_map)
    CIRCLE_OBJECTS.write_bytes(circle_objects)
    POLYGON_OBJECTS.write_bytes(polygon_objects)
    encode_pletter_banks()
    encode_pletter_file(POLYGON_OBJECTS, POLYGON_OBJECTS_PLETTER)
    collision_debug.save(COLLISION_DEBUG)
    print(f"Wrote {PREVIEW.relative_to(ROOT)}")
    print(f"Wrote {SCREEN5.relative_to(ROOT)} ({SCREEN5.stat().st_size} bytes)")
    print(
        "Wrote RLE banks "
        f"({RLE_BANK0.stat().st_size + RLE_BANK1.stat().st_size} bytes total)"
    )
    print(
        "Wrote Pletter banks "
        f"({PLETTER_BANK0.stat().st_size + PLETTER_BANK1.stat().st_size} bytes total)"
    )
    print(f"Wrote {FLIPPER_FRAMES.relative_to(ROOT)} ({FLIPPER_FRAMES.stat().st_size} bytes)")
    print(
        f"Wrote {FLIPPER_COLLISIONS.relative_to(ROOT)} "
        f"({FLIPPER_COLLISIONS.stat().st_size} bytes)"
    )
    print(
        f"Wrote {FLIPPER_INSTANCES.relative_to(ROOT)} "
        f"({FLIPPER_INSTANCES.stat().st_size} bytes, {len(flipper_instances)} instances)"
    )
    print(f"Wrote {BALL_FRAMES.relative_to(ROOT)} ({BALL_FRAMES.stat().st_size} bytes)")
    print(f"Wrote {COLLISION_MAP.relative_to(ROOT)} ({COLLISION_MAP.stat().st_size} bytes)")
    print(f"Wrote {CIRCLE_OBJECTS.relative_to(ROOT)} ({CIRCLE_OBJECTS.stat().st_size} bytes)")
    print(f"Wrote {POLYGON_OBJECTS.relative_to(ROOT)} ({POLYGON_OBJECTS.stat().st_size} bytes)")
    print(
        f"Wrote {POLYGON_OBJECTS_PLETTER.relative_to(ROOT)} "
        f"({POLYGON_OBJECTS_PLETTER.stat().st_size} bytes compressed)"
    )


if __name__ == "__main__":
    main()
