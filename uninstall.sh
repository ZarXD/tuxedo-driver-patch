#!/bin/bash
# ============================================================
# Clevo/Nightraven Driver Uninstaller
# Removes DKMS module, services, and scripts.
# ============================================================

set -e

log()  { echo -e "\e[32m[clevo-uninstall]\e[0m $*"; }
warn() { echo -e "\e[33m[clevo-uninstall]\e[0m $*"; }
err()  { echo -e "\e[31m[clevo-uninstall]\e[0m $*" >&2; exit 1; }

if [[ $EUID -ne 0 ]]; then
    err "Run as root: sudo ./uninstall.sh"
fi

# --- 1. Remove DKMS module ---
DKMS_NAME="tuxedo-drivers"
DKMS_VERSION="patched"
SRC_DEST="/usr/src/${DKMS_NAME}-${DKMS_VERSION}"

log "Removing DKMS module $DKMS_NAME-$DKMS_VERSION..."
if dkms status -m "$DKMS_NAME" -v "$DKMS_VERSION" | grep -q "added"; then
    dkms remove -m "$DKMS_NAME" -v "$DKMS_VERSION" --all || warn "Failed to remove DKMS module completely."
    log "DKMS module removed."
else
    log "DKMS module not found in dkms status."
fi

if [[ -d "$SRC_DEST" ]]; then
    log "Removing source directory $SRC_DEST..."
    rm -rf "$SRC_DEST"
fi

# --- 2. Remove old Debian hook (if exists) ---
HOOK_PATH="/etc/kernel/postinst.d/zz-clevo-drivers"
if [[ -f "$HOOK_PATH" ]]; then
    log "Removing Debian kernel hook..."
    rm -f "$HOOK_PATH"
fi

# --- 3. Unload modules ---
log "Unloading modules..."
rmmod tuxedo_io clevo_acpi clevo_wmi tuxedo_keyboard tuxedo_compatibility_check \
    uniwill_wmi 2>/dev/null || log "Modules already unloaded."

# --- 4. Remove System Services ---
ANIM_SERVICE="/etc/systemd/system/nightraven-kb-boot.service"
ANIM_BIN="/usr/local/bin/nightraven-kb-boot"

if [[ -f "$ANIM_SERVICE" ]]; then
    log "Removing boot animation service..."
    systemctl stop nightraven-kb-boot.service 2>/dev/null || true
    systemctl disable nightraven-kb-boot.service 2>/dev/null || true
    rm -f "$ANIM_SERVICE"
    systemctl daemon-reload
fi

if [[ -f "$ANIM_BIN" ]]; then
    rm -f "$ANIM_BIN"
    log "Removed $ANIM_BIN."
fi

# --- 5. Remove User Services ---
GUARD_BIN="/usr/local/bin/nightraven-kbd-guard"

REAL_USER="${SUDO_USER:-$USER}"
REAL_HOME=$(eval echo "~$REAL_USER")
REAL_UID=$(id -u "$REAL_USER")
USER_SYSTEMD_DIR="$REAL_HOME/.config/systemd/user"
XDG_RT="/run/user/${REAL_UID}"

if [[ -f "$USER_SYSTEMD_DIR/nightraven-kbd-guard.service" ]]; then
    log "Removing user guard service..."
    sudo -u "$REAL_USER" XDG_RUNTIME_DIR="$XDG_RT" \
        systemctl --user stop nightraven-kbd-guard.service 2>/dev/null || true
    sudo -u "$REAL_USER" XDG_RUNTIME_DIR="$XDG_RT" \
        systemctl --user disable nightraven-kbd-guard.service 2>/dev/null || true
    rm -f "$USER_SYSTEMD_DIR/nightraven-kbd-guard.service"
    sudo -u "$REAL_USER" XDG_RUNTIME_DIR="$XDG_RT" \
        systemctl --user daemon-reload 2>/dev/null || true
fi

if [[ -f "$GUARD_BIN" ]]; then
    rm -f "$GUARD_BIN"
    log "Removed $GUARD_BIN."
fi

# --- 6. Restore GNOME Settings (best effort) ---
DBUS_ADDR="unix:path=/run/user/${REAL_UID}/bus"
if command -v gsettings &>/dev/null; then
    sudo -u "$REAL_USER" DBUS_SESSION_BUS_ADDRESS="$DBUS_ADDR" \
        gsettings set org.gnome.settings-daemon.plugins.power idle-dim true 2>/dev/null && \
        log "GNOME idle-dim restored to true." || true
fi

echo ""
log "=== Uninstallation complete ==="
log "All drivers, source files, and services have been removed."
