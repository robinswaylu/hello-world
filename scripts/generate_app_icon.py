"""One-off script to generate ScratchLab's placeholder app icon.

Not part of the Xcode build - run manually if the icon design needs to
change. Draws a simple flat vinyl-record motif matching the app's
dark-mode-first design: no text (illegible at small sizes anyway), no
attempt at a "real" logo.
"""
import math
from PIL import Image, ImageDraw

SIZE = 1024
CENTER = SIZE / 2

img = Image.new("RGB", (SIZE, SIZE), (10, 10, 14))
draw = ImageDraw.Draw(img)

# Background: subtle dark radial-ish gradient via concentric squares.
bg_top = (18, 18, 26)
bg_bottom = (8, 8, 12)
for y in range(SIZE):
    t = y / SIZE
    r = int(bg_top[0] + (bg_bottom[0] - bg_top[0]) * t)
    g = int(bg_top[1] + (bg_bottom[1] - bg_top[1]) * t)
    b = int(bg_top[2] + (bg_bottom[2] - bg_top[2]) * t)
    draw.line([(0, y), (SIZE, y)], fill=(r, g, b))

# The record itself.
record_radius = SIZE * 0.40
draw.ellipse(
    [CENTER - record_radius, CENTER - record_radius, CENTER + record_radius, CENTER + record_radius],
    fill=(24, 24, 30),
)

# Grooves.
for i in range(1, 9):
    r = record_radius * (0.32 + i * 0.075)
    shade = 34 + (i % 2) * 6
    draw.ellipse(
        [CENTER - r, CENTER - r, CENTER + r, CENTER + r],
        outline=(shade, shade, shade + 4),
        width=3,
    )

# Label.
label_radius = record_radius * 0.30
draw.ellipse(
    [CENTER - label_radius, CENTER - label_radius, CENTER + label_radius, CENTER + label_radius],
    fill=(226, 74, 58),
)
spindle_radius = record_radius * 0.045
draw.ellipse(
    [CENTER - spindle_radius, CENTER - spindle_radius, CENTER + spindle_radius, CENTER + spindle_radius],
    fill=(10, 10, 14),
)

# A tonearm-ish diagonal accent, suggesting a scratch/motion stroke.
angle = math.radians(-35)
length = SIZE * 0.62
start_x = CENTER + math.cos(angle) * (record_radius * 0.55)
start_y = CENTER + math.sin(angle) * (record_radius * 0.55)
end_x = CENTER + math.cos(angle) * (length * 0.62)
end_y = CENTER + math.sin(angle) * (length * 0.62)
draw.line([(start_x, start_y), (end_x, end_y)], fill=(240, 240, 245), width=22)
draw.ellipse(
    [end_x - 26, end_y - 26, end_x + 26, end_y + 26],
    fill=(240, 240, 245),
)

img.save("ScratchLab/Assets.xcassets/AppIcon.appiconset/icon-1024.png")
print("wrote icon-1024.png")
