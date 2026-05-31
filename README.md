# Table of Content
- <a href="#patches--credits">Patches & Credits</a>
- <a href="#description">Description</a>
- <a href="#building-and-install">Building and Install</a>
- <a href="#troubleshooting">Troubleshooting</a>
- <a href="#regarding-upstreaming-of-tuxedo-drivers">Regarding upstreaming of tuxedo-drivers</a>

# Patches & Credits

This is a patched fork of [tuxedo-drivers](https://gitlab.com/tuxedocomputers/development/packages/tuxedo-drivers)
for **non-Tuxedo Clevo ODM hardware** (laptops using a Clevo chassis without TUXEDO DMI branding,
e.g. Acer Aspire 7 Pro).

## Applied Patches

| Patch | File(s) | Description |
|---|---|---|
| **Compatibility bypass** | `tuxedo_compatibility_check.c` | `tuxedo_is_compatible()` always returns `true`. Upstream restricts loading to TUXEDO-branded DMI strings or legacy CPUs — this allows any Clevo ODM device to load the drivers. |
| **Fn+toggle fix** | `clevo_keyboard.h`, `clevo_leds.h` | Toggle key event (`0x9F`/`0x3F`) is now handled in-driver via direct EC brightness command instead of emitting `KEY_KBDILLUMTOGGLE` to userspace. Prevents the DE from silently restoring brightness after toggle. |
| **Fn+cycle guard** | `clevo_keyboard.h` | Color cycle only runs when backlight brightness > 0. Avoids an EC color command accidentally re-enabling the keyboard when it's supposed to be off. |
| **Boot animation** | `kb-boot-anim.py` | RGB rainbow sweep on boot, smoothly converges to red. Installed as a systemd service. |
| **Install script** | `install.sh` | One-command installer with kernel update hook, cross-distro support, and optional boot animation. |

## Patched by

**Izaa** (`izaa` / Nightraven)

---

# Description
Drivers for several platform devices for TUXEDO notebooks meant for DKMS.

## Features implemented by this driver package
- Fn-keys
- Keyboard backlight
- Fan control
- Power control
- Other sensors
- Hardware specific userspace quirks

## Modules included in this package
- clevo_acpi
- clevo_wmi
- tuxedo_keyboard
- uniwill_wmi
- ite_8291
- ite_8291_lb
- ite_8297
- ite_829x
- tuxedo_io
- tuxedo_compatibility_check
- tuxedo_nb05_keyboard
- tuxedo_nb05_power_profiles
- tuxedo_nb05_ec
- tuxedo_nb05_sensors
- tuxedo_nb04_keyboard
- tuxedo_nb04_wmi_ab
- tuxedo_nb04_wmi_bs
- tuxedo_nb04_sensors
- tuxedo_nb04_power_profiles
- tuxedo_nb04_kbd_backlight
- tuxedo_nb05_kbd_backlight
- tuxedo_nb02_nvidia_power_ctrl
- tuxedo_nb05_fan_control
- tuxi_acpi
- tuxedo_tuxi_fan_control
- stk8321
- gxtp7380

# Building and Install

## Quick Install (patched)

```bash
sudo ./install.sh [--animation | --no-animation] [kernel-version]
```

Options:
- `--animation` — install boot animation without prompting
- `--no-animation` — skip boot animation without prompting
- *(no flag)* — asks interactively

The script will build modules, install to `updates/src/`, set up a kernel-update hook in
`/etc/kernel/postinst.d/zz-clevo-drivers`, and optionally install the boot animation service.

## Dependencies:
All:
- make

`make package-*`:
- [simple-package-creator](https://gitlab.com/tuxedocomputers/development/packages/simple-package-creator)
- [simple-package-tools](https://gitlab.com/tuxedocomputers/development/packages/simple-package-tools)

# Troubleshooting

## The keyboard backlight control and/or touchpad toggle key combinations do not work
For all devices with a touchpad toggle key(-combo) and some devices with keyboard backlight control key-combos the driver does nothing more then to send the corresponding key event to userspace where it is the desktop environments duty to carry out the action. Some smaller desktop environments however don't bind an action to these keys by default so it seems that these keys don't work.

Please refer to your desktop environments documentation on how to set custom keybindings to fix this.

For keyboard brightness control you should use the D-Bus interface of UPower as actions for the key presses.

For touchpad toggle on X11 you can use `xinput` to enable/disable the touchpad, on Wayland the correct way is desktop environment specific.

# Regarding upstreaming of tuxedo-drivers
The code, while perfectly functional, is currently not in an upstreamable state. That being said we started an upstreaming effort and the first small part, the keyboard backlight control for the Sirius 16 Gen 1 & 2, already got accepted.

If you want to hack away at this matter yourself please follow the following precautions and guidelines to avoid breakages on both software and hardware level:
- Involve us in the whole process. Nothing is won if at some point tuxedo-control-center or the dkms variant of tuxedo-drivers stops working. Especially when you send something to the LKML, please set us in the cc.
- We mostly can't share documentation, but we can answer questions.
- Code interacting with the EC, which is most of tuxedo-drivers, can brick devices and therefore must be ensured to only run on compatible and tested devices.
- If you use tuxedo-drivers as a reference or code snippets from it, a "Codeveloped-by:\<name\> \<tuxedo_email\>" must be included in your upstream commit, with \<name\> and \<tuxedo_email\> depending on the actual part of tuxedo-drivers being used. Please talk to us regarding this.
