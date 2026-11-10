#!/usr/bin/env node
/**
 * Rebuild SplashBrand.imageset (new app-icon glyph + uniform Katecheo wordmark)
 * for LaunchScreen. Requires Python + Pillow + cairosvg + Noto Serif Display.
 *
 * Usage: node scripts/generate-splash-brand.mjs
 */
import { spawnSync } from "node:child_process";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const root = join(dirname(fileURLToPath(import.meta.url)), "..");
const py = `
from PIL import Image, ImageDraw, ImageFont
from pathlib import Path
import io
import cairosvg
import re

ROOT = Path(${JSON.stringify(root)})
OUT = ROOT / "ios/App/Katecheo/Assets.xcassets/SplashBrand.imageset"
LIGHT_SVG = ROOT / "design/app-icon/icon.svg"
DARK_SVG = ROOT / "design/app-icon/icon-dark.svg"
# Match Wordmark / former Kate half: display family, medium weight, NO italic.
SERIF = "/usr/share/fonts/truetype/noto/NotoSerifDisplay-Regular.ttf"

def glyph_svg(src: Path, stroke: str) -> bytes:
    """Stroke-only glyph on transparent canvas (no opaque app-icon plate)."""
    text = src.read_text(encoding="utf-8")
    text = re.sub(r"<rect\\b[^>]*/>", "", text, count=1)
    # Keep stroke colour from source; ensure fill none on group already present.
    return text.encode("utf-8")

def render_glyph(svg_path: Path, stroke: str, size: int) -> Image.Image:
    raw = glyph_svg(svg_path, stroke)
    png = cairosvg.svg2png(bytestring=raw, output_width=size, output_height=size)
    return Image.open(io.BytesIO(png)).convert("RGBA")

def render_wordmark(color, font_size=44):
    font = ImageFont.truetype(SERIF, font_size)
    tmp = Image.new("RGBA", (800, 160), (0, 0, 0, 0))
    d = ImageDraw.Draw(tmp)
    text = "Katecheo"
    bb = d.textbbox((0, 0), text, font=font)
    w = (bb[2] - bb[0]) + 8
    h = (bb[3] - bb[1]) + 16
    img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    d.text((4, 4), text, font=font, fill=color)
    return img

# Master glyphs at 3x canvas scale (~290 px icon area inside 420-wide splash).
icon3 = render_glyph(LIGHT_SVG, "#1F2328", 512)
icon3d = render_glyph(DARK_SVG, "#F5F4F0", 512)
# Crop transparent padding so layout matches previous tight icon mark.
def crop_alpha(im: Image.Image) -> Image.Image:
    arr_bbox = im.getbbox()
    if not arr_bbox:
        return im
    return im.crop(arr_bbox)

icon3 = crop_alpha(icon3)
icon3d = crop_alpha(icon3d)

wm_dark = render_wordmark((255, 255, 255, 255))
wm_light = render_wordmark((28, 28, 30, 255))  # ≈ #1C1C1E

def compose(icon, wordmark, canvas_size):
    W, H = canvas_size
    canvas = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    iw = int(W * 0.69)
    ih = int(iw * (icon.height / icon.width))
    icon_r = icon.resize((iw, ih), Image.Resampling.LANCZOS)
    ww = int(W * 0.78)
    wh = max(1, int(ww * (wordmark.height / wordmark.width)))
    wm_r = wordmark.resize((ww, wh), Image.Resampling.LANCZOS)
    gap = int(H * 0.12)
    total_h = ih + gap + wh
    top = max(0, (H - total_h) // 2)
    canvas.paste(icon_r, ((W - iw) // 2, top), icon_r)
    canvas.paste(wm_r, ((W - ww) // 2, top + ih + gap), wm_r)
    return canvas

SIZES = {"1x": (140, 156), "2x": (280, 312), "3x": (420, 468)}
for name, size in SIZES.items():
    scale = int(name[0])
    factor = scale / 3
    if scale == 3:
        icon_l, icon_d = icon3, icon3d
        wm_l, wm_d = wm_light, wm_dark
    else:
        icon_l = icon3.resize(
            (max(1, int(icon3.width * factor)), max(1, int(icon3.height * factor))),
            Image.Resampling.LANCZOS,
        )
        icon_d = icon3d.resize(
            (max(1, int(icon3d.width * factor)), max(1, int(icon3d.height * factor))),
            Image.Resampling.LANCZOS,
        )
        wm_l = wm_light.resize(
            (max(1, int(wm_light.width * factor)), max(1, int(wm_light.height * factor))),
            Image.Resampling.LANCZOS,
        )
        wm_d = wm_dark.resize(
            (max(1, int(wm_dark.width * factor)), max(1, int(wm_dark.height * factor))),
            Image.Resampling.LANCZOS,
        )
    light = compose(icon_l, wm_l, size)
    dark = compose(icon_d, wm_d, size)
    if name == "1x":
        dark.save(OUT / "splash-brand-dark.png")
        light.save(OUT / "splash-brand-light.png")
    else:
        dark.save(OUT / f"splash-brand-dark@{name}.png")
        light.save(OUT / f"splash-brand-light@{name}.png")
    print("wrote", name, size)
`;

const result = spawnSync("python3", ["-c", py], { cwd: root, encoding: "utf8" });
if (result.status !== 0) {
  console.error(result.stdout || "");
  console.error(result.stderr || "");
  process.exit(result.status ?? 1);
}
console.log(result.stdout.trim());
console.log("SplashBrand Katecheo assets regenerated (uniform wordmark).");
