#!/usr/bin/env python3
"""
Nightraven Keyboard Boot Animation
Effect: Fast RGB rainbow → gradually slows → smooth converge to RED (stay)
"""

import os
import time
import math
import sys

LED_PATH   = "/sys/class/leds/rgb:kbd_backlight"
MI_PATH    = f"{LED_PATH}/multi_intensity"
BR_PATH    = f"{LED_PATH}/brightness"

# ── Tuneable params ──────────────────────────────────────────
RAINBOW_DURATION    = 3.0   # seconds of spinning rainbow
TRANSITION_DURATION = 1.4   # seconds to converge to red
FPS                 = 40    # frames per second (don't go above 60)
START_SPEED_DPS     = 380   # deg/sec at start
END_SPEED_DPS       = 28    # deg/sec at end of rainbow (crawling to red)
# ─────────────────────────────────────────────────────────────


def hsv_to_rgb(h: float, s: float, v: float) -> tuple[int, int, int]:
    """h: 0–360°, s/v: 0–1  →  (R, G, B) each 0–255"""
    h = h % 360
    c = v * s
    x = c * (1 - abs((h / 60) % 2 - 1))
    m = v - c
    if   h < 60:   r, g, b = c, x, 0
    elif h < 120:  r, g, b = x, c, 0
    elif h < 180:  r, g, b = 0, c, x
    elif h < 240:  r, g, b = 0, x, c
    elif h < 300:  r, g, b = x, 0, c
    else:          r, g, b = c, 0, x
    return (int((r + m) * 255), int((g + m) * 255), int((b + m) * 255))


def set_rgb(r: int, g: int, b: int, brightness: int = 255) -> None:
    try:
        with open(MI_PATH, 'w') as f:
            f.write(f"{r} {g} {b}\n")
        with open(BR_PATH, 'w') as f:
            f.write(f"{brightness}\n")
    except OSError:
        pass


def ease_in_out(t: float) -> float:
    """Smooth cosine ease-in-out: t ∈ [0, 1]"""
    return (1 - math.cos(t * math.pi)) / 2


if not os.path.exists(MI_PATH):
    print(f"[kb-anim] LED path not found: {MI_PATH}", file=sys.stderr)
    sys.exit(1)

dt = 1.0 / FPS

# ── Phase 1: Rainbow with decelerating spin ──────────────────
rainbow_frames = int(RAINBOW_DURATION * FPS)
hue = 0.0

for i in range(rainbow_frames):
    progress = i / rainbow_frames          # 0 → 1
    # Interpolate angular speed (linear deceleration)
    speed = START_SPEED_DPS + (END_SPEED_DPS - START_SPEED_DPS) * progress
    hue = (hue + speed * dt) % 360

    r, g, b = hsv_to_rgb(hue, 1.0, 1.0)
    set_rgb(r, g, b)
    time.sleep(dt)

rainbow_end_hue = hue   # where we stopped

# ── Phase 2: Smooth ease-in-out convergence to RED (0°) ──────
trans_frames = int(TRANSITION_DURATION * FPS)

# Shortest angular path to 0° (red)
delta = (0 - rainbow_end_hue) % 360
if delta > 180:
    delta -= 360    # go the short way around

for i in range(trans_frames):
    progress = i / trans_frames
    ease     = ease_in_out(progress)
    current_hue = (rainbow_end_hue + delta * ease) % 360

    r, g, b = hsv_to_rgb(current_hue, 1.0, 1.0)
    set_rgb(r, g, b)
    time.sleep(dt)

# ── Phase 3: Land on RED and stay ────────────────────────────
set_rgb(255, 0, 0)
