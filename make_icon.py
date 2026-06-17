"""
Generates windows/runner/resources/app_icon.ico for YTD GUI.
Design: dark rounded-square background, red YouTube-style play button,
        small "YTD" label beneath it.
Run with: python make_icon.py
"""

import math
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

# ── colours ──────────────────────────────────────────────────────────────────
BG_DARK   = (15,  15,  15,  255)   # #0F0F0F  – app scaffold background
BG_CARD   = (33,  33,  33,  255)   # #212121  – card surface
RED       = (255,  0,   0,  255)   # #FF0000  – YouTube red
RED_DARK  = (180,  0,   0,  255)   # darker red for drop-shadow / depth
WHITE     = (255, 255, 255, 255)
TRANSP    = (  0,   0,   0,   0)

# ── sizes that Windows expects in an .ico ────────────────────────────────────
SIZES = [16, 24, 32, 40, 48, 64, 96, 128, 256]


def rounded_rect(draw: ImageDraw.ImageDraw, xy, radius: int, fill):
    """Fill a rounded rectangle."""
    x0, y0, x1, y1 = xy
    draw.rounded_rectangle([x0, y0, x1, y1], radius=radius, fill=fill)


def draw_icon(size: int) -> Image.Image:
    s = size
    img = Image.new("RGBA", (s, s), TRANSP)
    d   = ImageDraw.Draw(img)

    pad    = max(1, round(s * 0.06))
    radius = max(2, round(s * 0.18))

    # ── background card ──────────────────────────────────────────────────────
    rounded_rect(d, [pad, pad, s - pad - 1, s - pad - 1], radius, BG_CARD)

    # ── red circle behind play button ────────────────────────────────────────
    # sits in the upper ~60 % of the card
    cx     = s / 2
    cy     = s * 0.44
    r_circ = s * 0.28

    # soft glow ring
    glow_r = r_circ + max(1, round(s * 0.04))
    d.ellipse(
        [cx - glow_r, cy - glow_r, cx + glow_r, cy + glow_r],
        fill=(220, 0, 0, 60),
    )

    # main red circle
    d.ellipse(
        [cx - r_circ, cy - r_circ, cx + r_circ, cy + r_circ],
        fill=RED,
    )

    # ── play triangle (centred slightly right to look optical-centre) ─────────
    tri_h   = r_circ * 0.72
    tri_w   = tri_h * 0.90
    tri_cx  = cx + r_circ * 0.07   # nudge right
    tri_cy  = cy

    pts = [
        (tri_cx - tri_w * 0.42, tri_cy - tri_h * 0.50),
        (tri_cx - tri_w * 0.42, tri_cy + tri_h * 0.50),
        (tri_cx + tri_w * 0.58, tri_cy),
    ]
    d.polygon(pts, fill=WHITE)

    # ── "YTD" label ──────────────────────────────────────────────────────────
    if s >= 48:
        font_size = max(7, round(s * 0.155))
        try:
            font = ImageFont.truetype("arialbd.ttf", font_size)
        except OSError:
            try:
                font = ImageFont.truetype("arial.ttf", font_size)
            except OSError:
                font = ImageFont.load_default()

        text  = "YTD"
        bbox  = d.textbbox((0, 0), text, font=font)
        tw    = bbox[2] - bbox[0]
        th    = bbox[3] - bbox[1]
        tx    = (s - tw) / 2 - bbox[0]
        ty    = s * 0.76 - bbox[1]

        # subtle shadow
        d.text((tx + 1, ty + 1), text, font=font, fill=(0, 0, 0, 180))
        d.text((tx, ty),         text, font=font, fill=WHITE)

    return img


def main():
    frames = []
    for size in SIZES:
        frames.append(draw_icon(size))

    out = Path("windows/runner/resources/app_icon.ico")
    out.parent.mkdir(parents=True, exist_ok=True)

    # Save as multi-size ICO
    base = frames[-1]           # largest frame is the "base"
    base.save(
        str(out),
        format="ICO",
        sizes=[(s, s) for s in SIZES],
        append_images=frames[:-1],
    )
    print(f"OK Written {out}  ({len(SIZES)} sizes: {SIZES})")

    # Also export a 256×256 PNG for reference / README
    png_out = Path("icon_preview.png")
    frames[-1].save(str(png_out))
    print(f"OK Preview  {png_out}")


if __name__ == "__main__":
    main()
