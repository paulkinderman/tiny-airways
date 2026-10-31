"""Drops the alpha channel from the iOS app icons (the App Store refuses it).

    python3 tool/art/flatten_icons.py
"""

import pathlib

from PIL import Image

icons = pathlib.Path(__file__).resolve().parents[2] / (
    "ios/Runner/Assets.xcassets/AppIcon.appiconset"
)
for png in sorted(icons.glob("*.png")):
    Image.open(png).convert("RGB").save(png)
    print(png.name)
