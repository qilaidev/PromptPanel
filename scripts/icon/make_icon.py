#!/usr/bin/env python3
"""Generate the PromptPanel macOS app icon.

Design language (matches frontend-draft brand tokens):
  - Squircle background with a subtle dark gradient.
  - Three rounded "prompt cards" stacked at the center.
  - The top card carries an accent stripe in #7c8cf8 — same lavender
    selection tint used in the quick panel UI.
"""

from __future__ import annotations

import math
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter

OUT = Path(sys.argv[1]) if len(sys.argv) > 1 else Path("master_1024.png")

SIZE = 1024
SS = 4  # super-sample factor for AA
W = SIZE * SS

ACCENT = (124, 140, 248, 255)         # #7c8cf8
ACCENT_SOFT = (124, 140, 248, 90)
BG_TOP = (38, 41, 54, 255)            # cool slate, gradient highlight
BG_BOTTOM = (10, 11, 13, 255)         # #0a0b0d brand bg
INNER_HIGHLIGHT = (255, 255, 255, 18)

CARD_LIGHT = (235, 238, 248, 255)
CARD_MID = (188, 194, 214, 255)
CARD_DIM = (140, 148, 170, 255)


def squircle_mask(size: int, radius_ratio: float = 0.225) -> Image.Image:
    """Create a macOS-style rounded-rect mask (close to squircle).

    Apple uses a continuous superellipse, but a rounded-rect with
    ~22.5% radius is visually identical at app-icon scale.
    """
    mask = Image.new("L", (size, size), 0)
    d = ImageDraw.Draw(mask)
    r = int(size * radius_ratio)
    d.rounded_rectangle((0, 0, size - 1, size - 1), radius=r, fill=255)
    return mask


def make_gradient(size: int, top: tuple, bottom: tuple) -> Image.Image:
    """Vertical gradient — simple linear blend."""
    grad = Image.new("RGBA", (1, size), 0)
    for y in range(size):
        t = y / (size - 1)
        # ease so the highlight is concentrated at the top
        e = 1 - (1 - t) ** 2
        r = int(top[0] * (1 - e) + bottom[0] * e)
        g = int(top[1] * (1 - e) + bottom[1] * e)
        b = int(top[2] * (1 - e) + bottom[2] * e)
        grad.putpixel((0, y), (r, g, b, 255))
    return grad.resize((size, size))


def draw_inner_glow(canvas: Image.Image, mask: Image.Image) -> None:
    """Soft inner highlight at the top — gives the icon a glassy lift."""
    glow = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    gd = ImageDraw.Draw(glow)
    w, h = canvas.size
    gd.ellipse(
        (-w * 0.4, -h * 0.85, w * 1.4, h * 0.55),
        fill=(255, 255, 255, 38),
    )
    glow = glow.filter(ImageFilter.GaussianBlur(radius=w * 0.06))
    canvas.alpha_composite(Image.composite(glow, Image.new("RGBA", canvas.size, 0), mask))


def draw_card(
    canvas: Image.Image,
    box: tuple,
    fill: tuple,
    radius: int,
    shadow: bool = True,
) -> None:
    if shadow:
        sh = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
        sd = ImageDraw.Draw(sh)
        offset = int(W * 0.006)
        sd.rounded_rectangle(
            (box[0], box[1] + offset, box[2], box[3] + offset),
            radius=radius,
            fill=(0, 0, 0, 90),
        )
        sh = sh.filter(ImageFilter.GaussianBlur(radius=W * 0.012))
        canvas.alpha_composite(sh)
    d = ImageDraw.Draw(canvas)
    d.rounded_rectangle(box, radius=radius, fill=fill)


def render() -> Image.Image:
    canvas = Image.new("RGBA", (W, W), (0, 0, 0, 0))
    mask = squircle_mask(W, radius_ratio=0.225)

    bg = make_gradient(W, BG_TOP, BG_BOTTOM)
    bg.putalpha(mask)
    canvas.alpha_composite(bg)

    draw_inner_glow(canvas, mask)

    # Three prompt cards, centered, decreasing widths.
    cx, cy = W // 2, W // 2
    card_w = int(W * 0.62)
    card_h = int(W * 0.10)
    gap = int(W * 0.05)
    radius = int(card_h * 0.45)

    # Top card carries the accent stripe.
    top_y = cy - card_h - gap - card_h // 2 - int(W * 0.005)
    mid_y = cy - card_h // 2
    bot_y = cy + gap + card_h // 2

    # Backdrop "panel" behind the cards — subtle, gives depth.
    panel_pad_x = int(W * 0.06)
    panel_pad_y = int(W * 0.06)
    panel_box = (
        cx - card_w // 2 - panel_pad_x,
        top_y - card_h // 2 - panel_pad_y,
        cx + card_w // 2 + panel_pad_x,
        bot_y + card_h // 2 + panel_pad_y,
    )
    panel = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    pd = ImageDraw.Draw(panel)
    pd.rounded_rectangle(panel_box, radius=int(W * 0.04), fill=(255, 255, 255, 14))
    pd.rounded_rectangle(
        panel_box,
        radius=int(W * 0.04),
        outline=(255, 255, 255, 36),
        width=int(W * 0.0035),
    )
    canvas.alpha_composite(panel)

    # Cards (top → bottom): selected, secondary, tertiary.
    cards = [
        (top_y, int(card_w * 1.00), CARD_LIGHT, True),
        (mid_y, int(card_w * 0.86), CARD_MID, False),
        (bot_y, int(card_w * 0.70), CARD_DIM, False),
    ]
    for y, w, color, selected in cards:
        x0 = cx - w // 2
        x1 = cx + w // 2
        y0 = y - card_h // 2
        y1 = y + card_h // 2
        draw_card(canvas, (x0, y0, x1, y1), color, radius, shadow=True)

        if selected:
            # Accent stripe on the left edge of the top card.
            stripe_w = int(card_h * 0.22)
            stripe_pad = int(card_h * 0.18)
            stripe_box = (
                x0 + stripe_pad,
                y0 + stripe_pad,
                x0 + stripe_pad + stripe_w,
                y1 - stripe_pad,
            )
            sd = ImageDraw.Draw(canvas)
            sd.rounded_rectangle(stripe_box, radius=stripe_w // 2, fill=ACCENT)

            # A second accent dot near the right side — a tiny visual rhyme
            # with the keyboard-shortcut chip in the UI.
            dot_r = int(card_h * 0.10)
            dot_cx = x1 - int(card_h * 0.55)
            dot_cy = y
            sd.ellipse(
                (dot_cx - dot_r, dot_cy - dot_r, dot_cx + dot_r, dot_cy + dot_r),
                fill=ACCENT_SOFT,
            )

    # Subtle accent glow behind the top card — ties the eye to the
    # "selected prompt" idea without making the whole icon blue.
    glow = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    gd = ImageDraw.Draw(glow)
    gd.ellipse(
        (cx - card_w // 2 - 60, top_y - card_h, cx + card_w // 2 + 60, top_y + card_h),
        fill=(124, 140, 248, 70),
    )
    glow = glow.filter(ImageFilter.GaussianBlur(radius=W * 0.025))
    glow_masked = Image.composite(glow, Image.new("RGBA", canvas.size, 0), mask)
    canvas.alpha_composite(glow_masked, dest=(0, 0))

    # Re-clip everything to the squircle (panel/cards stay inside corners).
    final = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    final.paste(canvas, (0, 0), mask)

    # Downsample to the target.
    return final.resize((SIZE, SIZE), Image.LANCZOS)


if __name__ == "__main__":
    img = render()
    img.save(OUT, "PNG")
    print(f"wrote {OUT} ({img.size[0]}x{img.size[1]})")
