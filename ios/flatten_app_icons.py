#!/usr/bin/env python3
"""
Flatten iOS AppIcon PNGs to remove alpha and ensure sRGB/8-bit.
"""
import os
from PIL import Image, ImageCms

ICON_DIR = "CourtVision/Assets.xcassets/AppIcon.appiconset"
OUTPUT_BG = (255, 255, 255)  # white background


def flatten_png(path: str) -> None:
    img = Image.open(path).convert("RGBA")
    bg = Image.new("RGBA", img.size, OUTPUT_BG + (255,))
    bg.alpha_composite(img)
    flat = bg.convert("RGB")  # drop alpha
    # Ensure sRGB profile if available
    try:
        srgb_profile = ImageCms.createProfile("sRGB")
        flat = ImageCms.profileToProfile(flat, srgb_profile, srgb_profile)
    except Exception:
        pass
    flat.save(path, format="PNG", optimize=True)


def main():
    for name in os.listdir(ICON_DIR):
        if name.lower().endswith(".png"):
            p = os.path.join(ICON_DIR, name)
            flatten_png(p)
            print(f"Flattened {name}")


if __name__ == "__main__":
    main()
