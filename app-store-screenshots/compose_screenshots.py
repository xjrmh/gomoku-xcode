#!/usr/bin/env python3
"""Compose deterministic 6.9-inch App Store screenshots for Just Gomoku."""

from __future__ import annotations

import hashlib
import json
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont, ImageOps


ROOT = Path(__file__).resolve().parent
SOURCE_DIR = ROOT / "sources"
OUTPUT_DIR = ROOT / "final-6.9-inch"
OUTPUT_65_DIR = ROOT / "final-6.5-inch"
LOGO_PATH = ROOT / "logo.png"
CONTACT_SHEET_PATH = ROOT / "final-contact-sheet.jpg"
FONT_PATH = "/System/Library/Fonts/SFNS.ttf"

WIDTH = 1320
HEIGHT = 2868
WIDTH_65 = 1284
HEIGHT_65 = 2778
SCREEN_X = 140
SCREEN_Y = 590
SCREEN_WIDTH = 1040
SCREEN_RADIUS = 76
CONTACT_COLUMNS = 3
CONTACT_THUMB_WIDTH = 330
CONTACT_THUMB_HEIGHT = round(HEIGHT * CONTACT_THUMB_WIDTH / WIDTH)
CONTACT_LABEL_HEIGHT = 52


ITEMS = [
    {
        "source": "01-focused-play.png",
        "output": "01-five-in-a-row.png",
        "headline": "Five in a row.\nZero distractions.",
        "subheadline": "Pure strategy in a calm, focused space.",
        "top": "#171210",
        "bottom": "#744327",
        "accent": "#F4C542",
    },
    {
        "source": "02-ai-opponent.png",
        "output": "02-ai-opponent.png",
        "headline": "Meet your next\nopponent.",
        "subheadline": "Choose Easy, Medium, or Hard.",
        "top": "#18130D",
        "bottom": "#9A5C20",
        "accent": "#FFD76A",
    },
    {
        "source": "03-smart-hints.png",
        "output": "03-smart-hints.png",
        "headline": "A hint,\nwhen you want it.",
        "subheadline": "Get a nudge only when you ask.",
        "top": "#121B24",
        "bottom": "#486875",
        "accent": "#F0C35B",
    },
    {
        "source": "04-customize.png",
        "output": "04-customize.png",
        "headline": "Play it\nyour way.",
        "subheadline": "Choose board size, stones, appearance, and haptics.",
        "top": "#191512",
        "bottom": "#87684F",
        "accent": "#F5D7A1",
    },
    {
        "source": "05-dark-mode.png",
        "output": "05-dark-mode.png",
        "headline": "Made for\nlight and dark.",
        "subheadline": "A focused board in either appearance.",
        "top": "#050505",
        "bottom": "#30251F",
        "accent": "#F4C542",
    },
    {
        "source": "06-private-by-design.png",
        "output": "06-private-by-design.png",
        "headline": "Private by\ndesign.",
        "subheadline": "No analytics or advertising identifiers.",
        "top": "#111A29",
        "bottom": "#28557B",
        "accent": "#72B7FF",
    },
    {
        "source": "07-game-history.png",
        "output": "07-game-history.png",
        "headline": "Every game,\nready to replay.",
        "subheadline": "Review results and replay every move.",
        "top": "#0C1A17",
        "bottom": "#276654",
        "accent": "#77E0BF",
    },
]


def hex_rgb(value: str) -> tuple[int, int, int]:
    value = value.lstrip("#")
    return tuple(int(value[index : index + 2], 16) for index in (0, 2, 4))


def font(size: int, weight: str) -> ImageFont.FreeTypeFont:
    result = ImageFont.truetype(FONT_PATH, size)
    try:
        result.set_variation_by_name(weight)
    except OSError:
        pass
    return result


def fit_multiline_font(text: str, start_size: int, max_width: int) -> ImageFont.FreeTypeFont:
    for size in range(start_size, 76, -2):
        candidate = font(size, "Heavy")
        box = ImageDraw.Draw(Image.new("RGB", (1, 1))).multiline_textbbox(
            (0, 0), text, font=candidate, spacing=-6
        )
        if box[2] - box[0] <= max_width:
            return candidate
    return font(76, "Heavy")


def gradient(top: tuple[int, int, int], bottom: tuple[int, int, int]) -> Image.Image:
    ramp = Image.linear_gradient("L").resize((WIDTH, HEIGHT), Image.Resampling.BILINEAR)
    return ImageOps.colorize(ramp, black=top, white=bottom)


def add_background_detail(canvas: Image.Image, accent: tuple[int, int, int]) -> Image.Image:
    base = canvas.convert("RGBA")

    glow = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    glow_draw = ImageDraw.Draw(glow)
    glow_draw.ellipse((-220, -250, 760, 730), fill=(*accent, 40))
    glow_draw.ellipse((910, -130, 1510, 470), fill=(255, 255, 255, 18))
    glow = glow.filter(ImageFilter.GaussianBlur(130))
    base = Image.alpha_composite(base, glow)

    pattern = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    pattern_draw = ImageDraw.Draw(pattern)
    for x in range(880, 1480, 84):
        pattern_draw.line((x, 0, x, 570), fill=(255, 255, 255, 10), width=2)
    for y in range(-20, 620, 84):
        pattern_draw.line((850, y, 1320, y), fill=(255, 255, 255, 10), width=2)
    pattern_draw.ellipse((1090, 68, 1218, 196), fill=(0, 0, 0, 35))
    pattern_draw.ellipse((1190, 182, 1318, 310), fill=(255, 255, 255, 30))
    return Image.alpha_composite(base, pattern)


def draw_letterspaced(
    draw: ImageDraw.ImageDraw,
    position: tuple[int, int],
    value: str,
    face: ImageFont.FreeTypeFont,
    fill: tuple[int, int, int, int],
    spacing: int,
) -> None:
    x, y = position
    for character in value:
        draw.text((x, y), character, font=face, fill=fill)
        x += int(draw.textlength(character, font=face)) + spacing


def rounded_capture(source_path: Path) -> tuple[Image.Image, Image.Image]:
    source = Image.open(source_path).convert("RGB")
    if source.size != (WIDTH, HEIGHT):
        raise ValueError(f"Unexpected source dimensions for {source_path}: {source.size}")

    capture_height = round(HEIGHT * SCREEN_WIDTH / WIDTH)
    capture = source.resize((SCREEN_WIDTH, capture_height), Image.Resampling.LANCZOS)
    mask = Image.new("L", capture.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle(
        (0, 0, capture.width - 1, capture.height - 1),
        radius=SCREEN_RADIUS,
        fill=255,
    )
    return capture, mask


def compose(item: dict[str, str]) -> Path:
    accent = hex_rgb(item["accent"])
    canvas = gradient(hex_rgb(item["top"]), hex_rgb(item["bottom"]))
    canvas = add_background_detail(canvas, accent)
    draw = ImageDraw.Draw(canvas)

    logo = Image.open(LOGO_PATH).convert("RGBA").resize((68, 68), Image.Resampling.LANCZOS)
    canvas.alpha_composite(logo, (118, 92))
    draw_letterspaced(draw, (208, 103), "JUST GOMOKU", font(34, "Bold"), (*accent, 255), 5)

    title_font = fit_multiline_font(item["headline"], 116, 1080)
    title_position = (116, 196)
    draw.multiline_text(
        title_position,
        item["headline"],
        font=title_font,
        fill=(255, 255, 255, 255),
        spacing=-6,
    )
    title_box = draw.multiline_textbbox(
        title_position,
        item["headline"],
        font=title_font,
        spacing=-6,
    )
    subtitle_y = title_box[3] + 24
    subtitle_font = font(39, "Medium")
    draw.text(
        (120, subtitle_y),
        item["subheadline"],
        font=subtitle_font,
        fill=(255, 255, 255, 205),
    )

    capture, capture_mask = rounded_capture(SOURCE_DIR / item["source"])
    capture_height = capture.height

    shadow = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    shadow_shape = Image.new("L", (SCREEN_WIDTH, capture_height), 0)
    ImageDraw.Draw(shadow_shape).rounded_rectangle(
        (0, 0, SCREEN_WIDTH - 1, capture_height - 1),
        radius=SCREEN_RADIUS,
        fill=190,
    )
    shadow_shape = shadow_shape.filter(ImageFilter.GaussianBlur(30))
    shadow_patch = Image.new("RGBA", (SCREEN_WIDTH, capture_height), (0, 0, 0, 125))
    shadow_patch.putalpha(shadow_shape)
    shadow.alpha_composite(shadow_patch, (SCREEN_X, SCREEN_Y + 18))
    canvas = Image.alpha_composite(canvas, shadow)

    canvas.paste(capture.convert("RGBA"), (SCREEN_X, SCREEN_Y), capture_mask)
    border = ImageDraw.Draw(canvas)
    border.rounded_rectangle(
        (SCREEN_X, SCREEN_Y, SCREEN_X + SCREEN_WIDTH - 1, SCREEN_Y + capture_height - 1),
        radius=SCREEN_RADIUS,
        outline=(255, 255, 255, 64),
        width=3,
    )

    destination = OUTPUT_DIR / item["output"]
    canvas.convert("RGB").save(destination, format="PNG", optimize=True)
    return destination


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def compose_contact_sheet(exports: list[Path]) -> Path:
    rows = (len(exports) + CONTACT_COLUMNS - 1) // CONTACT_COLUMNS
    sheet = Image.new(
        "RGB",
        (
            CONTACT_COLUMNS * CONTACT_THUMB_WIDTH,
            rows * (CONTACT_LABEL_HEIGHT + CONTACT_THUMB_HEIGHT),
        ),
        (24, 24, 24),
    )
    draw = ImageDraw.Draw(sheet)
    label_font = font(24, "Bold")

    for index, export in enumerate(exports):
        column = index % CONTACT_COLUMNS
        row = index // CONTACT_COLUMNS
        if index == len(exports) - 1 and len(exports) % CONTACT_COLUMNS == 1:
            column = CONTACT_COLUMNS // 2
        x = column * CONTACT_THUMB_WIDTH
        label_y = row * (CONTACT_LABEL_HEIGHT + CONTACT_THUMB_HEIGHT)
        image_y = label_y + CONTACT_LABEL_HEIGHT
        label = export.stem

        draw.text((x + 14, label_y + 11), label, font=label_font, fill=(255, 255, 255))
        with Image.open(export) as source:
            thumbnail = source.convert("RGB").resize(
                (CONTACT_THUMB_WIDTH, CONTACT_THUMB_HEIGHT),
                Image.Resampling.LANCZOS,
            )
        sheet.paste(thumbnail, (x, image_y))

    sheet.save(CONTACT_SHEET_PATH, format="JPEG", quality=92, optimize=True)
    return CONTACT_SHEET_PATH


def compose_6_5_exports(exports: list[Path]) -> list[Path]:
    OUTPUT_65_DIR.mkdir(parents=True, exist_ok=True)
    destinations = []
    for export in exports:
        destination = OUTPUT_65_DIR / export.name
        with Image.open(export) as source:
            adapted = ImageOps.fit(
                source.convert("RGB"),
                (WIDTH_65, HEIGHT_65),
                method=Image.Resampling.LANCZOS,
                centering=(0.5, 0.5),
            )
        adapted.save(destination, format="PNG", optimize=True)
        destinations.append(destination)
    return destinations


def main() -> None:
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    manifest_items = []
    exports = []
    for item in ITEMS:
        output_path = compose(item)
        exports.append(output_path)
        with Image.open(output_path) as image:
            if image.size != (WIDTH, HEIGHT) or image.mode != "RGB":
                raise ValueError(f"Invalid export {output_path}: {image.size}, {image.mode}")
        manifest_items.append(
            {
                "order": len(manifest_items) + 1,
                "file": output_path.name,
                "source": item["source"],
                "headline": item["headline"].replace("\n", " "),
                "subheadline": item["subheadline"],
                "width": WIDTH,
                "height": HEIGHT,
                "color_mode": "RGB",
                "sha256": sha256(output_path),
            }
        )

    contact_sheet = compose_contact_sheet(exports)

    manifest = {
        "app": "Just Gomoku",
        "platform": "iPhone 6.9-inch portrait",
        "device_capture": "iPhone 17 Pro Max simulator, iOS 26.5",
        "export_dimensions": [WIDTH, HEIGHT],
        "alpha_channel": False,
        "contact_sheet": {
            "file": str(Path("..") / contact_sheet.name),
            "sha256": sha256(contact_sheet),
        },
        "items": manifest_items,
    }
    (OUTPUT_DIR / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")

    exports_65 = compose_6_5_exports(exports)
    manifest_items_65 = []
    for item, source_export, output_path in zip(ITEMS, exports, exports_65):
        with Image.open(output_path) as image:
            if image.size != (WIDTH_65, HEIGHT_65) or image.mode != "RGB":
                raise ValueError(f"Invalid 6.5-inch export {output_path}: {image.size}, {image.mode}")
        manifest_items_65.append(
            {
                "order": len(manifest_items_65) + 1,
                "file": output_path.name,
                "source": item["source"],
                "derived_from": str(Path("..") / OUTPUT_DIR.name / source_export.name),
                "headline": item["headline"].replace("\n", " "),
                "subheadline": item["subheadline"],
                "width": WIDTH_65,
                "height": HEIGHT_65,
                "color_mode": "RGB",
                "sha256": sha256(output_path),
            }
        )

    manifest_65 = {
        "app": "Just Gomoku",
        "platform": "iPhone 6.5-inch portrait",
        "device_capture": "iPhone 17 Pro Max simulator, iOS 26.5",
        "export_dimensions": [WIDTH_65, HEIGHT_65],
        "alpha_channel": False,
        "derivation": "Aspect-preserving resize and centered crop from the 6.9-inch compositions.",
        "items": manifest_items_65,
    }
    (OUTPUT_65_DIR / "manifest.json").write_text(json.dumps(manifest_65, indent=2) + "\n")


if __name__ == "__main__":
    main()
