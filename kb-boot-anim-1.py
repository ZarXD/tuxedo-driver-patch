#!/usr/bin/env python3
"""
Nightraven Keyboard Boot Animation — Style 1: Color Tour
Effect:
  1. Fast pure rainbow (hue sweep, no pulse)
  2. Desaturation drift → pastel/white while hue still moves
  3. Dark sweep → deep moody colors (V dims)
  4. Flash burst → snap back to full vivid
  5. Converge to RED and stay
"""

import os
import time
import math
import sys

LED_PATH   = "/sys/class/leds/rgb:kbd_backlight"
MI_PATH    = f"{LED_PATH}/multi_intensity"
BR_PATH    = f"{LED_PATH}/brightness"

# ── Tuneable params ──────────────────────────────────────────
RAINBOW_DURATION    = 4.5   # seconds — fast pure hue sweep
DESAT_DURATION      = 2.0   # seconds — vivid → pastel
DARK_DURATION       = 1.5   # seconds — bright → dark
FLASH_DURATION      = 0.6   # seconds — dramatic flash burst
TRANSITION_DURATION = 1.2   # seconds — converge to red
FPS                 = 40
RAINBOW_SPEED_DPS   = 200   # constant hue rotation speed (deg/sec)
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


def set_rgb(r: int, g: int, b: int) -> None:
    try:
        with open(MI_PATH, 'w') as f:
            f.write(f"{r} {g} {b}\n")
        with open(BR_PATH, 'w') as f:
            f.write("255\n")
    except OSError:
        pass


def ease_in_out(t: float) -> float:
    return (1 - math.cos(t * math.pi)) / 2


if not os.path.exists(MI_PATH):
    print(f"[kb-anim] LED path not found: {MI_PATH}", file=sys.stderr)
    sys.exit(1)

dt  = 1.0 / FPS
hue = 0.0

# ── Phase 1: Fast pure rainbow (constant speed) ───────────────
for i in range(int(RAINBOW_DURATION * FPS)):
    hue = (hue + RAINBOW_SPEED_DPS * dt) % 360
    r, g, b = hsv_to_rgb(hue, 1.0, 1.0)
    set_rgb(r, g, b)
    time.sleep(dt)

# ── Phase 2: Desaturation drift → pastel/white ───────────────
for i in range(int(DESAT_DURATION * FPS)):
    progress = i / (DESAT_DURATION * FPS)
    ease     = ease_in_out(progress)
    hue = (hue + RAINBOW_SPEED_DPS * 0.4 * dt) % 360   # hue still drifts (slower)
    sat = 1.0 - ease                                     # vivid → white
    r, g, b = hsv_to_rgb(hue, sat, 1.0)
    set_rgb(r, g, b)
    time.sleep(dt)

# ── Phase 3: Re-saturate + dark sweep → deep moody ───────────
for i in range(int(DARK_DURATION * FPS)):
    progress = i / (DARK_DURATION * FPS)
    ease     = ease_in_out(progress)
    hue = (hue + RAINBOW_SPEED_DPS * 0.2 * dt) % 360   # very slow hue drift
    sat = ease                                           # white → vivid again
    val = 1.0 - 0.7 * ease                              # bright → dark (min 0.3)
    r, g, b = hsv_to_rgb(hue, sat, val)
    set_rgb(r, g, b)
    time.sleep(dt)

# ── Phase 4: Flash burst — snap to vivid then release ─────────
flash_frames = int(FLASH_DURATION * FPS)
for i in range(flash_frames):
    progress = i / flash_frames
    # Fast rise then ease out
    if progress < 0.3:
        v = progress / 0.3        # 0 → 1 fast
    else:
        v = 1.0 - ease_in_out((progress - 0.3) / 0.7) * 0.3  # settle at 0.7
    r, g, b = hsv_to_rgb(hue, 1.0, 1.0)
    r, g, b = int(r * v), int(g * v), int(b * v)
    set_rgb(r, g, b)
    time.sleep(dt)

# ── Phase 5: Smooth converge to RED (0°) ──────────────────────
trans_frames = int(TRANSITION_DURATION * FPS)

delta = (0 - hue) % 360
if delta > 180:
    delta -= 360

for i in range(trans_frames):
    progress    = i / trans_frames
    ease        = ease_in_out(progress)
    current_hue = (hue + delta * ease) % 360
    v           = 0.7 + 0.3 * ease
    r, g, b     = hsv_to_rgb(current_hue, 1.0, 1.0)
    r, g, b     = int(r * v), int(g * v), int(b * v)
    set_rgb(r, g, b)
    time.sleep(dt)

# ── Phase 6: Land on RED and stay ─────────────────────────────
set_rgb(255, 0, 0)
