#!/usr/bin/env node
/**
 * Rebuild SplashBrand.imageset (icon + Katecheo wordmark) for LaunchScreen.
 * Requires Python + Pillow + system fonts (Noto Serif Display Italic, Inter SemiBold).
 *
 * Usage: node scripts/generate-splash-brand.mjs
 */
import { spawnSync } from "node:child_process";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const root = join(dirname(fileURLToPath(import.meta.url)), "..");
const py = `
from PIL import Image, ImageDraw, ImageFont
import numpy as np
from pathlib import Path

OUT = Path(${JSON.stringify(join(root, "ios/App/App/Assets.xcassets/SplashBrand.imageset"))})
SERIF = "/usr/share/fonts/truetype/noto/NotoSerifDisplay-Italic.ttf"
SANS = "/usr/share/fonts/truetype/macos/Inter-SemiBold.ttf"

src3 = Image.open(OUT / "splash-brand-dark@3x.png").convert("RGBA")
arr = np.array(src3)
alpha = arr[:, :, 3]
rgb = arr[:, :, :3].astype(int)
content = (alpha > 10) & (rgb.sum(axis=2) > 30)
icon_mask = content.copy()
icon_mask[300:, :] = False
ys, xs = np.where(icon_mask)
icon3 = src3.crop((xs.min(), ys.min(), xs.max() + 1, ys.max() + 1))

src3l = Image.open(OUT / "splash-brand-light@3x.png").convert("RGBA")
arrl = np.array(src3l)
icon_mask_l = (arrl[:, :, 3] > 10).copy()
icon_mask_l[300:, :] = False
ys, xs = np.where(icon_mask_l)
icon3l = src3l.crop((xs.min(), ys.min(), xs.max() + 1, ys.max() + 1))

def render_wordmark(color):
    serif = ImageFont.truetype(SERIF, 42)
    sans = ImageFont.truetype(SANS, 40)
    tmp = Image.new("RGBA", (600, 120), (0, 0, 0, 0))
    d = ImageDraw.Draw(tmp)
    kate, cheo = "Kate", "cheo"
    kb = d.textbbox((0, 0), kate, font=serif)
    cb = d.textbbox((0, 0), cheo, font=sans)
    gap = -2
    w = (kb[2] - kb[0]) + gap + (cb[2] - cb[0]) + 8
    h = max(kb[3] - kb[1], cb[3] - cb[1]) + 16
    img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    d.text((2, 4), kate, font=serif, fill=color)
    d.text((2 + (kb[2] - kb[0]) + gap, 6), cheo, font=sans, fill=color)
    return img

wm_dark = render_wordmark((255, 255, 255, 255))
wm_light = render_wordmark((28, 28, 30, 255))

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
    icon_d = icon3 if scale == 3 else icon3.resize(
        (max(1, int(icon3.width * factor)), max(1, int(icon3.height * factor))),
        Image.Resampling.LANCZOS,
    )
    icon_l = icon3l if scale == 3 else icon3l.resize(
        (max(1, int(icon3l.width * factor)), max(1, int(icon3l.height * factor))),
        Image.Resampling.LANCZOS,
    )
    wm_d = wm_dark if scale == 3 else wm_dark.resize(
        (max(1, int(wm_dark.width * factor)), max(1, int(wm_dark.height * factor))),
        Image.Resampling.LANCZOS,
    )
    wm_l = wm_light if scale == 3 else wm_light.resize(
        (max(1, int(wm_light.width * factor)), max(1, int(wm_light.height * factor))),
        Image.Resampling.LANCZOS,
    )
    dark = compose(icon_d, wm_d, size)
    light = compose(icon_l, wm_l, size)
    if name == "1x":
        dark.save(OUT / "splash-brand-dark.png")
        light.save(OUT / "splash-brand-light.png")
    else:
        dark.save(OUT / f"splash-brand-dark@{name}.png")
        light.save(OUT / f"splash-brand-light@{name}.png")
    print("wrote", name)
`;

const result = spawnSync("python3", ["-c", py], { cwd: root, encoding: "utf8" });
if (result.status !== 0) {
  console.error(result.stdout || "");
  console.error(result.stderr || "");
  process.exit(result.status ?? 1);
}
console.log(result.stdout.trim());
console.log("SplashBrand Katecheo assets regenerated.");
