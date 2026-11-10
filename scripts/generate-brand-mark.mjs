#!/usr/bin/env node
/**
 * Rebuild BrandMark.imageset — Katecheo logo only (speech bubble + open book),
 * no background plate, no wordmark. Light stroke #1F2328 / dark stroke #F5F4F0.
 * Requires Python + Pillow + cairosvg.
 *
 * Usage: node scripts/generate-brand-mark.mjs
 */
import { spawnSync } from "node:child_process";
import { mkdirSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const root = join(dirname(fileURLToPath(import.meta.url)), "..");
const outDir = join(root, "ios/App/Katecheo/Assets.xcassets/BrandMark.imageset");
mkdirSync(outDir, { recursive: true });

const py = `
from PIL import Image
from pathlib import Path
import io
import cairosvg
import re
import json

ROOT = Path(${JSON.stringify(root)})
OUT = ROOT / "ios/App/Katecheo/Assets.xcassets/BrandMark.imageset"
LIGHT_SVG = ROOT / "design/app-icon/icon.svg"
DARK_SVG = ROOT / "design/app-icon/icon-dark.svg"

def glyph_svg(src: Path) -> bytes:
    """Stroke-only glyph on transparent canvas (drop opaque app-icon plate)."""
    text = src.read_text(encoding="utf-8")
    text = re.sub(r"<rect\\b[^>]*/>", "", text, count=1)
    return text.encode("utf-8")

def render_glyph(svg_path: Path, size: int) -> Image.Image:
    raw = glyph_svg(svg_path)
    png = cairosvg.svg2png(bytestring=raw, output_width=size, output_height=size)
    return Image.open(io.BytesIO(png)).convert("RGBA")

def crop_alpha(im: Image.Image, pad: int = 2) -> Image.Image:
    bbox = im.getbbox()
    if not bbox:
        return im
    l, t, r, b = bbox
    l = max(0, l - pad)
    t = max(0, t - pad)
    r = min(im.width, r + pad)
    b = min(im.height, b + pad)
    return im.crop((l, t, r, b))

# Master at high res, then downscale for 1x/2x/3x (point height ~80).
master_px = 512
light = crop_alpha(render_glyph(LIGHT_SVG, master_px))
dark = crop_alpha(render_glyph(DARK_SVG, master_px))

# Target point size 80 → pixel heights 80 / 160 / 240.
POINT_H = 80
SCALES = {
    "1x": 1,
    "2x": 2,
    "3x": 3,
}

def save_scaled(im: Image.Image, scale: int, path: Path) -> None:
    h = POINT_H * scale
    w = max(1, int(round(h * (im.width / im.height))))
    out = im.resize((w, h), Image.Resampling.LANCZOS)
    out.save(path)
    print(f"wrote {path.name} {out.size}")

for name, scale in SCALES.items():
    suffix = "" if name == "1x" else f"@{name}"
    save_scaled(light, scale, OUT / f"brand-mark-light{suffix}.png")
    save_scaled(dark, scale, OUT / f"brand-mark-dark{suffix}.png")

contents = {
    "images": [
        {"filename": "brand-mark-light.png", "idiom": "universal", "scale": "1x"},
        {"filename": "brand-mark-light@2x.png", "idiom": "universal", "scale": "2x"},
        {"filename": "brand-mark-light@3x.png", "idiom": "universal", "scale": "3x"},
        {
            "appearances": [{"appearance": "luminosity", "value": "dark"}],
            "filename": "brand-mark-dark.png",
            "idiom": "universal",
            "scale": "1x",
        },
        {
            "appearances": [{"appearance": "luminosity", "value": "dark"}],
            "filename": "brand-mark-dark@2x.png",
            "idiom": "universal",
            "scale": "2x",
        },
        {
            "appearances": [{"appearance": "luminosity", "value": "dark"}],
            "filename": "brand-mark-dark@3x.png",
            "idiom": "universal",
            "scale": "3x",
        },
    ],
    "info": {"author": "xcode", "version": 1},
    "properties": {"template-rendering-intent": "original"},
}
(OUT / "Contents.json").write_text(json.dumps(contents, indent=2) + "\\n", encoding="utf-8")
print("wrote Contents.json")
`;

const result = spawnSync("python3", ["-c", py], { cwd: root, encoding: "utf8" });
if (result.status !== 0) {
  console.error(result.stdout || "");
  console.error(result.stderr || "");
  process.exit(result.status ?? 1);
}
console.log(result.stdout.trim());
console.log("BrandMark Katecheo assets regenerated (logo only).");
