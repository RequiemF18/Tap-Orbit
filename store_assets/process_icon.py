"""Process the user-provided icon into:
- store_assets/icon_512.png       (Google Play store icon, 512x512 PNG)
- android/app/src/main/res/mipmap-*/ic_launcher.png  (launcher icons all densities)
"""
from PIL import Image
import os

SRC = "/Users/alexfe/Documents/Dev/Tap-Orbit/a-mobile-game-app-icon-featuring-a-glowi_D54QLRg0REWi_IX8QedcTg_jqo62iU2TVi1F5ddD8IlfQ_sd.jpeg"
ROOT = "/Users/alexfe/Documents/Dev/Tap-Orbit"
RES = os.path.join(ROOT, "android/app/src/main/res")
STORE = os.path.join(ROOT, "store_assets")

LAUNCHER_SIZES = {
    "mipmap-mdpi": 48,
    "mipmap-hdpi": 72,
    "mipmap-xhdpi": 96,
    "mipmap-xxhdpi": 144,
    "mipmap-xxxhdpi": 192,
}

src = Image.open(SRC).convert("RGB")
# Make the canvas square (it already is 1024x1024) and convert to RGBA so PNGs are alpha-capable
sq = src.copy()

# Play Store icon: 512x512 PNG
play = sq.resize((512, 512), Image.LANCZOS)
play.save(os.path.join(STORE, "icon_512.png"), "PNG")
print("store_assets/icon_512.png -> 512x512")

# Launcher icons (square)
for folder, size in LAUNCHER_SIZES.items():
    out_dir = os.path.join(RES, folder)
    os.makedirs(out_dir, exist_ok=True)
    img = sq.resize((size, size), Image.LANCZOS)
    out = os.path.join(out_dir, "ic_launcher.png")
    img.save(out, "PNG")
    print(f"{folder}/ic_launcher.png -> {size}x{size}")

print("done")
