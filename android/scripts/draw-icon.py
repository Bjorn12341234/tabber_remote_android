#!/usr/bin/env python3
"""android/scripts/draw-icon.py: Tabber Spak's icon as Android vector drawables.

The iPhone app's icon (apple/scripts/draw_icon.swift), drawn the same way for Android's adaptive
icon: a spak (a lever) in Tabber Studio's design language, a stick with a long grip and Studio's
teal at the grip band and the gate, on Studio's dark tokens. The shapes, colours and gradients are
the Swift script's, in its 1024-point canvas; CoreGraphics' y grows upwards, so the drawing sits in
a flipped group. Android masks an adaptive icon to its own shape and keeps only a central circle
safe, so the drawing is scaled into that circle (the iPhone's square mask needs no such room).

Writes, under android/app/src/main/res:
  drawable/ic_launcher_background.xml   Studio's bg_2 down to bg_0
  drawable/ic_launcher_foreground.xml   the base, the lever and its shadow
  drawable/ic_launcher_monochrome.xml   the same shapes in one colour, for themed icons
  mipmap-anydpi/ic_launcher.xml and ic_launcher_round.xml (minSdk 29: every Android it runs on has adaptive icons)

Run from anywhere: python3 android/scripts/draw-icon.py
"""

from __future__ import annotations

import math
from pathlib import Path

RES = Path(__file__).resolve().parents[1] / "app/src/main/res"

# The safe circle is 66 of the icon's 108 dp; the drawing reaches 385 points from its centre at
# (512, 524) in the 1024-point canvas (the grip's top and the base's corners).
SCALE = 0.8
LIFT = -10  # the drawing's centre onto the canvas's
PIVOT = (470, 276)  # where the stick enters the gate
ANGLE = -0.30  # radians, leaning right, as in the Swift script


def colour(value: int, alpha: float = 1.0) -> str:
    return f"#{round(alpha * 255):02X}{value:06X}"


def rounded(x: float, y: float, w: float, h: float, rx: float, ry: float | None = None) -> str:
    """A rounded rectangle's path, CoreGraphics' CGPath(roundedRect:cornerWidth:cornerHeight:)."""
    ry = rx if ry is None else ry
    rx, ry = min(rx, w / 2), min(ry, h / 2)
    return (
        f"M{x + rx:g},{y:g} H{x + w - rx:g} A{rx:g},{ry:g} 0 0 1 {x + w:g},{y + ry:g} "
        f"V{y + h - ry:g} A{rx:g},{ry:g} 0 0 1 {x + w - rx:g},{y + h:g} H{x + rx:g} "
        f"A{rx:g},{ry:g} 0 0 1 {x:g},{y + h - ry:g} V{y + ry:g} A{rx:g},{ry:g} 0 0 1 {x + rx:g},{y:g} Z"
    )


def ellipse(x: float, y: float, w: float, h: float) -> str:
    """CoreGraphics' fillEllipse(in:)."""
    rx, ry, cy = w / 2, h / 2, y + h / 2
    return f"M{x:g},{cy:g} A{rx:g},{ry:g} 0 1 0 {x + w:g},{cy:g} A{rx:g},{ry:g} 0 1 0 {x:g},{cy:g} Z"


def fill(path: str, value: int, alpha: float = 1.0) -> str:
    return f'<path android:fillColor="{colour(value, alpha)}" android:pathData="{path}" />'


def gradient(path: str, start: tuple[float, float], end: tuple[float, float], a: int, b: int) -> str:
    """A path filled with CoreGraphics' drawLinearGradient from a at start to b at end."""
    return (
        f'<path android:pathData="{path}"><aapt:attr name="android:fillColor">'
        f'<gradient android:type="linear" android:startX="{start[0]:g}" android:startY="{start[1]:g}" '
        f'android:endX="{end[0]:g}" android:endY="{end[1]:g}" '
        f'android:startColor="{colour(a)}" android:endColor="{colour(b)}" /></aapt:attr></path>'
    )


def placed(body: str) -> str:
    """The drawing, scaled into the safe circle, in CoreGraphics' upward y."""
    return (
        f'<group android:pivotX="512" android:pivotY="512" android:scaleX="{SCALE}" android:scaleY="{SCALE}" android:translateY="{LIFT}">'
        f'<group android:pivotY="512" android:scaleY="-1">{body}</group></group>'
    )


def lever(parts: list[str], shadow: list[str]) -> str:
    """The lever's group: from the gate, tilted; the stick and grip moved 16 points off the shadow."""
    degrees = math.degrees(ANGLE)
    return (
        f'<group android:translateX="{PIVOT[0]}" android:translateY="{PIVOT[1]}" android:rotation="{degrees:.4f}">'
        + "".join(shadow)
        + f'<group android:translateX="-16">{"".join(parts)}</group></group>'
    )


def vector(body: str, gradients: bool = False) -> str:
    aapt = ' xmlns:aapt="http://schemas.android.com/aapt"' if gradients else ""
    return (
        '<?xml version="1.0" encoding="utf-8"?>\n'
        "<!-- Made by android/scripts/draw-icon.py from the iPhone's apple/scripts/draw_icon.swift. -->\n"
        f'<vector xmlns:android="http://schemas.android.com/apk/res/android"{aapt}\n'
        '    android:width="108dp" android:height="108dp" android:viewportWidth="1024" android:viewportHeight="1024">\n'
        f"    {body}\n"
        "</vector>\n"
    )


def background() -> str:
    # Tabber Studio's dark tokens, bg_2 at the top down to bg_0.
    return vector(gradient("M0,0 H1024 V1024 H0 Z", (0, 0), (0, 1024), 0x2B2B42, 0x121219), gradients=True)


def foreground() -> str:
    base = [
        fill(ellipse(236, 156, 552, 120), 0x08080D, 0.55),  # its shadow
        fill(rounded(252, 196, 520, 112, 56), 0x1D1D2B),  # the slab's side
        gradient(rounded(252, 216, 520, 112, 56), (0, 328), (0, 216), 0x3A3A57, 0x2A2A40),  # its top
        fill(rounded(350, 256, 324, 34, 17), 0x101017),  # the gate
        fill(rounded(364, 262, 296, 5, 2.5), 0x00D4AA, 0.9),  # Studio's teal in it
    ]
    shadow = [
        fill(rounded(-10, -18, 56, 400, 28), 0x05050A, 0.42),
        fill(rounded(-44, 350, 124, 232, 62), 0x05050A, 0.42),
    ]
    parts = [
        gradient(rounded(-28, -10, 56, 400, 28), (-28, 0), (28, 0), 0xC2C2D2, 0x8E8EA6),  # the stick
        fill(rounded(-44, 352, 88, 28, 11, 10), 0x00D4AA),  # the teal band where grip meets stick
        gradient(rounded(-62, 372, 124, 214, 62), (-62, 0), (62, 0), 0xFAFAFF, 0xC9C9DA),  # the grip
        fill(rounded(-40, 410, 18, 140, 9, 8), 0xFFFFFF, 0.65),  # its shine
    ]
    boot = [
        fill(ellipse(PIVOT[0] - 64, PIVOT[1] - 24, 128, 52), 0x101017),  # where the stick enters the gate
        fill(ellipse(PIVOT[0] - 50, PIVOT[1] - 6, 100, 34), 0x1D1D2B),
    ]
    return vector(placed("".join(base) + lever(parts, shadow) + "".join(boot)), gradients=True)


def monochrome() -> str:
    """Themed icons (Android 13): the base and the lever as one shape, which the system tints."""
    ink = 0x000000
    base = [fill(rounded(252, 196, 520, 132, 56), ink)]
    parts = [
        fill(rounded(-28, -10, 56, 400, 28), ink),
        fill(rounded(-44, 352, 88, 28, 11, 10), ink),
        fill(rounded(-62, 372, 124, 214, 62), ink),
    ]
    return vector(placed("".join(base) + lever(parts, [])))


ADAPTIVE = """<?xml version="1.0" encoding="utf-8"?>
<!-- Made by android/scripts/draw-icon.py from the iPhone's apple/scripts/draw_icon.swift. -->
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
    <background android:drawable="@drawable/ic_launcher_background" />
    <foreground android:drawable="@drawable/ic_launcher_foreground" />
    <monochrome android:drawable="@drawable/ic_launcher_monochrome" />
</adaptive-icon>
"""


def main() -> None:
    files = {
        "drawable/ic_launcher_background.xml": background(),
        "drawable/ic_launcher_foreground.xml": foreground(),
        "drawable/ic_launcher_monochrome.xml": monochrome(),
        "mipmap-anydpi/ic_launcher.xml": ADAPTIVE,
        "mipmap-anydpi/ic_launcher_round.xml": ADAPTIVE,
    }
    for name, text in files.items():
        path = RES / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text)
        print("wrote", path.relative_to(RES.parents[3]))


if __name__ == "__main__":
    main()
