#!/usr/bin/env python3
"""Compose App Store marketing frames from raw iPhone screenshots.

Layout (exact App Store sizes preserved):
  - Warm paper background matching KCDesign.screenBackground (#F1E8DA)
  - Localized headline caption centered in the top band
  - Device screenshot scaled down below the caption
  - Wordmark rule: "Katecheo" is always one unbroken word in one style
    (captions do not split or restyle the brand name)

Usage:
  python3 scripts/compose-appstore-screenshots.py \\
    --input /path/to/raw \\
    --output /path/to/marketing

If --output equals --input, files are replaced in place (after writing to a temp dir).
"""

from __future__ import annotations

import argparse
import os
import shutil
import sys
import tempfile
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

# KCDesign.screenBackground (light) / accent (light)
BG = (0xF1, 0xE8, 0xDA, 255)
TEXT = (0x3A, 0x2E, 0x24, 255)  # warm near-black for paper
ACCENT = (0xB0, 0x7A, 0x45, 255)

DEVICE_SIZES = {
    "iphone-16-pro-max": (1320, 2868),
    "iphone-16-pro": (1206, 2622),
}

# Scene stem → localized captions (pt-BR / en / es)
CAPTIONS: dict[str, dict[str, str]] = {
    "01-caderno": {
        "pt-BR": "Anote sermões com referências",
        "en": "Take sermon notes with references",
        "es": "Anota sermones con referencias",
    },
    "02-editor": {
        "pt-BR": "Referências que abrem na sua Bíblia",
        "en": "References that open in your Bible app",
        "es": "Referencias que abren en tu Biblia",
    },
    "03-listas": {
        "pt-BR": "Organize versículos em listas",
        "en": "Organize verses into lists",
        "es": "Organiza versículos en listas",
    },
    "04-grupos": {
        "pt-BR": "Estude junto com sua igreja",
        "en": "Study together with your church",
        "es": "Estudia junto con tu iglesia",
    },
    "05-perfil": {
        "pt-BR": "Do seu jeito, no seu idioma",
        "en": "Your way, in your language",
        "es": "A tu manera, en tu idioma",
    },
}

FONT_CANDIDATES = [
    "/System/Library/Fonts/Supplemental/Arial Bold.ttf",
    "/System/Library/Fonts/Supplemental/Arial.ttf",
    "/Library/Fonts/Arial Bold.ttf",
    "/usr/share/fonts/truetype/noto/NotoSans-Bold.ttf",
    "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf",
]


def load_font(size: int) -> ImageFont.FreeTypeFont | ImageFont.ImageFont:
    for path in FONT_CANDIDATES:
        if os.path.isfile(path):
            try:
                return ImageFont.truetype(path, size=size)
            except OSError:
                continue
    return ImageFont.load_default()


def wrap_text(text: str, font: ImageFont.ImageFont, max_width: int, draw: ImageDraw.ImageDraw) -> list[str]:
    words = text.split()
    if not words:
        return [""]
    lines: list[str] = []
    current = words[0]
    for word in words[1:]:
        trial = f"{current} {word}"
        if draw.textlength(trial, font=font) <= max_width:
            current = trial
        else:
            lines.append(current)
            current = word
    lines.append(current)
    return lines


def assert_wordmark_intact(caption: str) -> None:
    """Katecheo must appear as one word — never hyphen-broken or spaced."""
    lower = caption.lower()
    if "kate cheo" in lower or "kate-cheo" in lower:
        raise SystemExit(f"Wordmark rule violated in caption: {caption!r}")


def compose_one(
    src: Path,
    dst: Path,
    locale: str,
    device_slug: str,
    stem: str,
) -> None:
    assert_wordmark_intact(CAPTIONS[stem][locale])
    target_w, target_h = DEVICE_SIZES[device_slug]
    caption = CAPTIONS[stem][locale]

    raw = Image.open(src).convert("RGBA")
    # Normalize unexpected capture sizes to the device class before scaling into frame.
    if raw.size != (target_w, target_h):
        raw = raw.resize((target_w, target_h), Image.Resampling.LANCZOS)

    canvas = Image.new("RGBA", (target_w, target_h), BG)
    draw = ImageDraw.Draw(canvas)

    # Caption band ~ top 16%; phone ~ 78% of canvas height with side inset.
    caption_band = int(target_h * 0.155)
    side_inset = int(target_w * 0.08)
    phone_max_w = target_w - 2 * side_inset
    phone_max_h = int(target_h * 0.78)

    scale = min(phone_max_w / target_w, phone_max_h / target_h)
    phone_w = int(target_w * scale)
    phone_h = int(target_h * scale)
    phone = raw.resize((phone_w, phone_h), Image.Resampling.LANCZOS)

    # Soft rounded mask so the inset shot reads as a device, not a hard crop.
    radius = max(28, int(min(phone_w, phone_h) * 0.06))
    mask = Image.new("L", (phone_w, phone_h), 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, phone_w, phone_h), radius=radius, fill=255)
    rounded = Image.new("RGBA", (phone_w, phone_h), (0, 0, 0, 0))
    rounded.paste(phone, (0, 0), mask=mask)

    # Drop shadow under the phone.
    shadow = Image.new("RGBA", (phone_w + 40, phone_h + 40), (0, 0, 0, 0))
    ImageDraw.Draw(shadow).rounded_rectangle(
        (20, 24, phone_w + 20, phone_h + 28),
        radius=radius + 4,
        fill=(58, 46, 36, 55),
    )
    # Simple blur via downsample/upsample.
    shadow = shadow.resize((shadow.width // 4, shadow.height // 4), Image.Resampling.BILINEAR)
    shadow = shadow.resize((phone_w + 40, phone_h + 40), Image.Resampling.BILINEAR)

    phone_x = (target_w - phone_w) // 2
    phone_y = caption_band + max(0, (target_h - caption_band - phone_h - int(target_h * 0.04)) // 2)
    canvas.alpha_composite(shadow, (phone_x - 20, phone_y - 16))
    canvas.alpha_composite(rounded, (phone_x, phone_y))

    # Headline typography scales with device class.
    font_size = int(target_w * 0.062)
    font = load_font(font_size)
    max_text_w = int(target_w * 0.86)
    lines = wrap_text(caption, font, max_text_w, draw)
    line_gap = int(font_size * 1.18)
    block_h = line_gap * len(lines)
    # Vertically center the caption block in the top band (with a little bottom bias).
    y0 = max(int(target_h * 0.045), (caption_band - block_h) // 2)
    for i, line in enumerate(lines):
        tw = draw.textlength(line, font=font)
        x = (target_w - tw) / 2
        draw.text((x, y0 + i * line_gap), line, font=font, fill=TEXT)

    # Thin accent rule under the caption band for polish (not a card).
    rule_y = caption_band - int(target_h * 0.012)
    rule_half = int(target_w * 0.08)
    draw.rounded_rectangle(
        (target_w // 2 - rule_half, rule_y, target_w // 2 + rule_half, rule_y + 4),
        radius=2,
        fill=(ACCENT[0], ACCENT[1], ACCENT[2], 180),
    )

    dst.parent.mkdir(parents=True, exist_ok=True)
    canvas.convert("RGB").save(dst, format="PNG", optimize=True)


def iter_shots(root: Path):
    for locale_dir in sorted(p for p in root.iterdir() if p.is_dir()):
        locale = locale_dir.name
        if locale not in ("pt-BR", "en", "es"):
            continue
        for device_dir in sorted(p for p in locale_dir.iterdir() if p.is_dir()):
            device = device_dir.name
            if device not in DEVICE_SIZES:
                continue
            for png in sorted(device_dir.glob("*.png")):
                stem = png.stem
                if stem not in CAPTIONS:
                    continue
                yield locale, device, stem, png


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--input", required=True, type=Path, help="Raw screenshot tree")
    parser.add_argument("--output", required=True, type=Path, help="Marketing output tree")
    args = parser.parse_args()

    if not args.input.is_dir():
        print(f"Input not found: {args.input}", file=sys.stderr)
        return 1

    in_place = args.output.resolve() == args.input.resolve()
    out_root = Path(tempfile.mkdtemp(prefix="katecheo-marketing-")) if in_place else args.output
    if not in_place:
        out_root.mkdir(parents=True, exist_ok=True)

    count = 0
    for locale, device, stem, src in iter_shots(args.input):
        dst = out_root / locale / device / f"{stem}.png"
        compose_one(src, dst, locale, device, stem)
        w, h = DEVICE_SIZES[device]
        with Image.open(dst) as check:
            if check.size != (w, h):
                raise SystemExit(f"Size mismatch for {dst}: {check.size} != {(w, h)}")
        count += 1
        print(f"composed {locale}/{device}/{stem}.png ({w}x{h})")

    if count == 0:
        print("No screenshots found to compose", file=sys.stderr)
        return 1

    if in_place:
        for locale, device, stem, _src in iter_shots(args.input):
            src_m = out_root / locale / device / f"{stem}.png"
            dst_m = args.output / locale / device / f"{stem}.png"
            dst_m.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(src_m, dst_m)
        shutil.rmtree(out_root, ignore_errors=True)

    print(f"Done: {count} marketing frames")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
