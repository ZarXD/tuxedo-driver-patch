#!/usr/bin/env python3
"""
nightraven-kbd-guard
Prevents GNOME from restoring keyboard brightness after screen unlock.
Saves the brightness at lock time and restores exactly that on unlock,
overriding whatever gsd-power tries to set.
"""
import dbus
import dbus.mainloop.glib
from gi.repository import GLib
import subprocess
import sys
import os

BRIGHTNESS_FILE = "/sys/class/leds/rgb:kbd_backlight/brightness"
TAG = "[nightraven-kbd-guard]"


def log(msg):
    print(f"{TAG} {msg}", flush=True)


def read_brightness():
    try:
        with open(BRIGHTNESS_FILE) as f:
            return int(f.read().strip())
    except Exception as e:
        log(f"Error reading brightness: {e}")
        return -1


def upower_set(val):
    """Set brightness via UPower system DBus (UPower runs as root → can write sysfs)."""
    r = subprocess.run(
        ["gdbus", "call", "--system",
         "--dest", "org.freedesktop.UPower",
         "--object-path", "/org/freedesktop/UPower/KbdBacklight",
         "--method", "org.freedesktop.UPower.KbdBacklight.SetBrightness",
         str(val)],
        capture_output=True, text=True
    )
    return r.returncode == 0


# ── State ──────────────────────────────────────────────────────────────────────
saved_brightness = [read_brightness()]
log(f"Started. Initial brightness={saved_brightness[0]}")


def on_screen_active_changed(active):
    active = bool(active)

    if active:
        # Screen is LOCKING → save current brightness
        saved_brightness[0] = read_brightness()
        log(f"Screen locked. Saved brightness={saved_brightness[0]}")
    else:
        # Screen is UNLOCKING → override gsd-power's restore after short delay
        target = saved_brightness[0]
        log(f"Screen unlocked. Scheduling restore to brightness={target} in 400ms")

        def do_restore():
            ok = upower_set(target)
            log(f"Restored brightness={target} (ok={ok})")
            return False  # one-shot timeout

        GLib.timeout_add(400, do_restore)


# ── D-Bus setup ────────────────────────────────────────────────────────────────
dbus.mainloop.glib.DBusGMainLoop(set_as_default=True)

try:
    bus = dbus.SessionBus()
    proxy = bus.get_object("org.gnome.ScreenSaver", "/org/gnome/ScreenSaver")
    proxy.connect_to_signal("ActiveChanged", on_screen_active_changed)
    log("Listening for org.gnome.ScreenSaver.ActiveChanged …")
except Exception as e:
    log(f"Failed to connect to ScreenSaver DBus: {e}")
    sys.exit(1)

GLib.MainLoop().run()
