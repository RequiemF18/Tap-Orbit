"""Generate Tap Orbit app icon (512x512) and feature graphic (1024x500).

Icon: pixel-art golden star at center with one cyan planet on a glowing orbit.
Feature graphic: same composition extended horizontally with title text.
"""
from PIL import Image, ImageDraw, ImageFont, ImageFilter
import math
import os

OUT = os.path.dirname(os.path.abspath(__file__))

BG = (3, 4, 10)
GOLD_CORE = (255, 179, 71)
GOLD_HIGH = (255, 241, 168)
GOLD_SHADOW = (204, 106, 0)
CYAN = (86, 231, 255)
MAGENTA = (255, 90, 214)
WHITE = (255, 255, 255)


def add_glow(img, color, alpha=120, radius=18):
    """Return a glow layer (RGBA)."""
    glow = Image.new("RGBA", img.size, (0, 0, 0, 0))
    return glow


def draw_pixel_circle(draw, cx, cy, r, color, pixel=2):
    """Draw a pixelated circle by stepping in chunks of `pixel` size."""
    for y in range(int(cy - r) - pixel, int(cy + r) + pixel, pixel):
        for x in range(int(cx - r) - pixel, int(cx + r) + pixel, pixel):
            dx = x + pixel / 2 - cx
            dy = y + pixel / 2 - cy
            if dx * dx + dy * dy <= r * r:
                draw.rectangle([x, y, x + pixel - 1, y + pixel - 1], fill=color)


def draw_pixel_ring(draw, cx, cy, r, color, pixel=2, thickness=2):
    inner = r - thickness
    for y in range(int(cy - r) - pixel, int(cy + r) + pixel, pixel):
        for x in range(int(cx - r) - pixel, int(cx + r) + pixel, pixel):
            dx = x + pixel / 2 - cx
            dy = y + pixel / 2 - cy
            d = math.sqrt(dx * dx + dy * dy)
            if inner <= d <= r:
                draw.rectangle([x, y, x + pixel - 1, y + pixel - 1], fill=color)


def render_orbit_scene(size, cx, cy, scale=1.0, with_planet=True, with_arc=True):
    """Render the central composition (star + orbit + planet) on transparent canvas."""
    img = Image.new("RGBA", size, (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)
    pixel = max(2, int(2 * scale))

    # Outer star halo (multiple soft circles)
    halo = Image.new("RGBA", size, (0, 0, 0, 0))
    halo_draw = ImageDraw.Draw(halo)
    for r, a in [(int(120 * scale), 22), (int(85 * scale), 38), (int(55 * scale), 65)]:
        halo_draw.ellipse(
            [cx - r, cy - r, cx + r, cy + r],
            fill=(*GOLD_CORE, a),
        )
    halo = halo.filter(ImageFilter.GaussianBlur(radius=int(28 * scale)))
    img = Image.alpha_composite(img, halo)
    draw = ImageDraw.Draw(img)

    # Star body (pixel art)
    star_r = int(38 * scale)
    draw_pixel_circle(draw, cx, cy, star_r, GOLD_SHADOW, pixel=pixel)
    draw_pixel_circle(draw, cx, cy, star_r - pixel, GOLD_CORE, pixel=pixel)
    draw_pixel_circle(draw, cx - pixel * 2, cy - pixel * 2, int(star_r * 0.45), GOLD_HIGH, pixel=pixel)

    # Orbit ring (pixel-perfect, glowing)
    orbit_r = int(150 * scale)

    # Glow under orbit
    orbit_glow = Image.new("RGBA", size, (0, 0, 0, 0))
    og_draw = ImageDraw.Draw(orbit_glow)
    og_draw.ellipse(
        [cx - orbit_r - 3, cy - orbit_r - 3, cx + orbit_r + 3, cy + orbit_r + 3],
        outline=(*CYAN, 90),
        width=int(8 * scale),
    )
    orbit_glow = orbit_glow.filter(ImageFilter.GaussianBlur(radius=int(10 * scale)))
    img = Image.alpha_composite(img, orbit_glow)
    draw = ImageDraw.Draw(img)

    # Sharp orbit ring
    draw.ellipse(
        [cx - orbit_r, cy - orbit_r, cx + orbit_r, cy + orbit_r],
        outline=(*CYAN, 110),
        width=max(1, int(1.5 * scale)),
    )

    # Hit gate arc (top of orbit) - bright cyan band
    if with_arc:
        gate_glow = Image.new("RGBA", size, (0, 0, 0, 0))
        gg_draw = ImageDraw.Draw(gate_glow)
        gg_draw.arc(
            [cx - orbit_r - 4, cy - orbit_r - 4, cx + orbit_r + 4, cy + orbit_r + 4],
            start=210, end=330,
            fill=(*CYAN, 200),
            width=int(14 * scale),
        )
        gate_glow = gate_glow.filter(ImageFilter.GaussianBlur(radius=int(8 * scale)))
        img = Image.alpha_composite(img, gate_glow)
        draw = ImageDraw.Draw(img)

        draw.arc(
            [cx - orbit_r, cy - orbit_r, cx + orbit_r, cy + orbit_r],
            start=210, end=330,
            fill=CYAN,
            width=int(8 * scale),
        )
        # White perfect line on top center of arc
        draw.arc(
            [cx - orbit_r, cy - orbit_r, cx + orbit_r, cy + orbit_r],
            start=255, end=285,
            fill=WHITE,
            width=int(4 * scale),
        )

    # Planet (cyan, on the right of orbit at ~0 degrees, slightly above)
    if with_planet:
        angle_deg = -30  # upper right
        ang = math.radians(angle_deg)
        planet_x = cx + int(orbit_r * math.cos(ang))
        planet_y = cy + int(orbit_r * math.sin(ang))
        planet_r = int(28 * scale)

        # Planet glow
        planet_glow = Image.new("RGBA", size, (0, 0, 0, 0))
        pg_draw = ImageDraw.Draw(planet_glow)
        pg_draw.ellipse(
            [planet_x - planet_r - 8, planet_y - planet_r - 8,
             planet_x + planet_r + 8, planet_y + planet_r + 8],
            fill=(*CYAN, 130),
        )
        planet_glow = planet_glow.filter(ImageFilter.GaussianBlur(radius=int(12 * scale)))
        img = Image.alpha_composite(img, planet_glow)
        draw = ImageDraw.Draw(img)

        # Planet body pixel circle
        draw_pixel_circle(draw, planet_x, planet_y, planet_r, (38, 153, 168), pixel=pixel)
        draw_pixel_circle(draw, planet_x, planet_y, planet_r - pixel, CYAN, pixel=pixel)
        # highlight
        hi_r = int(planet_r * 0.4)
        draw_pixel_circle(
            draw,
            planet_x - pixel * 2,
            planet_y - pixel * 2,
            hi_r,
            (180, 248, 255),
            pixel=pixel,
        )

        # Trail (dim)
        for i in range(8):
            ta = math.radians(angle_deg - 6 - i * 4)
            tx = cx + int(orbit_r * math.cos(ta))
            ty = cy + int(orbit_r * math.sin(ta))
            tr = max(1, int((planet_r - 4 - i * 2) * scale * 0.6))
            if tr <= 0:
                continue
            alpha = max(0, 80 - i * 10)
            trail = Image.new("RGBA", size, (0, 0, 0, 0))
            td = ImageDraw.Draw(trail)
            td.ellipse([tx - tr, ty - tr, tx + tr, ty + tr], fill=(*CYAN, alpha))
            img = Image.alpha_composite(img, trail)
            draw = ImageDraw.Draw(img)

    return img


def add_starfield(base, density=120, seed=42):
    """Add small white pixel stars on the background."""
    import random
    rng = random.Random(seed)
    draw = ImageDraw.Draw(base)
    w, h = base.size
    for _ in range(density):
        x = rng.randint(0, w - 1)
        y = rng.randint(0, h - 1)
        size = rng.choice([1, 1, 1, 2])
        alpha = rng.choice([60, 90, 120, 180, 220])
        draw.rectangle([x, y, x + size - 1, y + size - 1], fill=(255, 255, 255, alpha))
    return base


# ---------- ICON 512x512 ----------
def make_icon():
    size = (512, 512)
    bg = Image.new("RGBA", size, (*BG, 255))
    bg = add_starfield(bg, density=60, seed=7)
    scene = render_orbit_scene(size, 256, 256, scale=0.95)
    out = Image.alpha_composite(bg, scene)
    out.save(os.path.join(OUT, "icon_512.png"))
    print("icon_512.png saved")

    # Round mask version (preview only — Play uses square anyway)
    mask = Image.new("L", size, 0)
    md = ImageDraw.Draw(mask)
    md.ellipse([0, 0, 512, 512], fill=255)
    rounded = Image.new("RGBA", size, (0, 0, 0, 0))
    rounded.paste(out, (0, 0), mask)
    rounded.save(os.path.join(OUT, "icon_512_round_preview.png"))


# ---------- FEATURE GRAPHIC 1024x500 ----------
def make_feature_graphic():
    size = (1024, 500)
    bg = Image.new("RGBA", size, (*BG, 255))
    bg = add_starfield(bg, density=200, seed=12)

    # Background ambient glow blobs
    blob = Image.new("RGBA", size, (0, 0, 0, 0))
    bd = ImageDraw.Draw(blob)
    bd.ellipse([-100, 200, 300, 600], fill=(35, 59, 143, 70))
    bd.ellipse([700, -100, 1100, 300], fill=(123, 47, 143, 60))
    blob = blob.filter(ImageFilter.GaussianBlur(radius=80))
    bg = Image.alpha_composite(bg, blob)

    # Orbit scene on the right side
    scene = render_orbit_scene(size, 780, 250, scale=0.95)
    out = Image.alpha_composite(bg, scene)

    # Title text on the left
    draw = ImageDraw.Draw(out)
    try:
        font_title = ImageFont.truetype(
            "/System/Library/Fonts/Supplemental/Futura.ttc", 110
        )
        font_sub = ImageFont.truetype(
            "/System/Library/Fonts/Supplemental/Futura.ttc", 32
        )
    except Exception:
        font_title = ImageFont.load_default()
        font_sub = ImageFont.load_default()

    # Title with glow
    title = "TAP ORBIT"
    title_pos = (60, 180)

    # Glow
    glow_layer = Image.new("RGBA", size, (0, 0, 0, 0))
    gld = ImageDraw.Draw(glow_layer)
    gld.text(title_pos, title, font=font_title, fill=(*GOLD_CORE, 180))
    glow_layer = glow_layer.filter(ImageFilter.GaussianBlur(radius=14))
    out = Image.alpha_composite(out, glow_layer)
    draw = ImageDraw.Draw(out)

    draw.text(title_pos, title, font=font_title, fill=GOLD_HIGH)
    draw.text((60, 310), "ONE-FINGER COSMIC ARCADE", font=font_sub, fill=(*CYAN, 230))

    out.convert("RGB").save(os.path.join(OUT, "feature_graphic_1024x500.png"))
    print("feature_graphic_1024x500.png saved")


if __name__ == "__main__":
    make_icon()
    make_feature_graphic()
    print("done")
