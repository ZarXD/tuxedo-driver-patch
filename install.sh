#!/bin/bash
# ============================================================
# Clevo/Nightraven Driver Installer
# Patched fork of tuxedo-drivers for non-Tuxedo Clevo ODM hardware
#
# Patches applied:
#   - tuxedo_is_compatible() bypass (Clevo ODM, e.g. Acer Aspire Pro)
#   - Fn+toggle: properly turns RGB off/on instead of bouncing
#   - Fn+cycle: only cycles color when backlight is on
#   - Boot animation: RGB rainbow → converges to red on startup
#
# Usage:
#   sudo ./install.sh [flags] [kernel-version]
#
#   --animation         Install boot animation (no prompt)
#   --no-animation      Skip boot animation (no prompt)
#   --update-animation  ONLY update animation speed/script, skip driver rebuild
#   (no flag)           Asks interactively
#
# Works on: Ubuntu/Debian, Arch, Fedora/RHEL
# Persists across kernel updates via /etc/kernel/postinst.d/
# ============================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK_PATH="/etc/kernel/postinst.d/zz-clevo-drivers"

# --- Parse args ---
INSTALL_ANIM="ask"   # ask | yes | no
UPDATE_ANIM_ONLY=false
KVER=""
for arg in "$@"; do
    case "$arg" in
        --animation)        INSTALL_ANIM="yes" ;;
        --no-animation)     INSTALL_ANIM="no"  ;;
        --update-animation) UPDATE_ANIM_ONLY=true ;;
        *)                  KVER="$arg"        ;;
    esac
done
[[ -z "$KVER" ]] && KVER="$(uname -r)"

KBUILD="/lib/modules/$KVER/build"

log()  { echo -e "\e[32m[clevo-install]\e[0m $*"; }
warn() { echo -e "\e[33m[clevo-install]\e[0m $*"; }
err()  { echo -e "\e[31m[clevo-install]\e[0m $*" >&2; exit 1; }

if [[ $EUID -ne 0 ]]; then
    err "Run as root: sudo ./install.sh"
fi

# --- Animation-only mode (fast path) ---
if [[ "$UPDATE_ANIM_ONLY" == true ]]; then
    ANIM_SCRIPT="$SCRIPT_DIR/kb-boot-anim.py"
    ANIM_BIN="/usr/local/bin/nightraven-kb-boot"

    [[ -f "$ANIM_SCRIPT" ]] || err "kb-boot-anim.py not found in $SCRIPT_DIR"

    log "Updating animation script only..."
    cp "$ANIM_SCRIPT" "$ANIM_BIN"
    chmod +x "$ANIM_BIN"
    log "Copied to $ANIM_BIN"

    if command -v systemctl &>/dev/null; then
        systemctl restart nightraven-kb-boot.service 2>/dev/null && \
            log "Service restarted — animation played!" || \
            warn "Service not found. Run with --animation first to install it."
    fi

    read -r -p $'\e[36m[clevo-install]\e[0m Preview animation now? [Y/n] ' ans
    [[ ! "$ans" =~ ^[Nn] ]] && python3 "$ANIM_BIN"

    log "Done! Edit kb-boot-anim.py and re-run: sudo ./install.sh --update-animation"
    exit 0
fi

log "Kernel: $KVER"
log "Build dir: $KBUILD"

# --- 1. Check kernel headers ---
if [[ ! -d "$KBUILD" ]]; then
    warn "Kernel headers not found. Trying to install..."
    if command -v apt &>/dev/null; then
        apt install -y "linux-headers-$KVER" build-essential
    elif command -v dnf &>/dev/null; then
        dnf install -y "kernel-devel-$KVER" "kernel-headers-$KVER" gcc make
    elif command -v pacman &>/dev/null; then
        pacman -S --noconfirm linux-headers base-devel
    else
        err "Cannot find kernel headers at $KBUILD. Install them manually."
    fi
fi

[[ -d "$KBUILD" ]] || err "Kernel headers still not found at $KBUILD"

# --- 2. Build ---
log "Building modules from $SCRIPT_DIR ..."
make -C "$KBUILD" M="$SCRIPT_DIR" clean 2>/dev/null || true
make -C "$KBUILD" M="$SCRIPT_DIR" -j"$(nproc)" modules
log "Build complete."

# --- 3. Install ---
log "Installing modules..."
make -C "$KBUILD" M="$SCRIPT_DIR" modules_install
depmod -a "$KVER"
log "Install complete."

# --- 4. Set up auto-rebuild hook for kernel updates ---
if [[ -d /etc/kernel/postinst.d ]]; then
    log "Installing kernel update hook to $HOOK_PATH ..."
    cat > "$HOOK_PATH" << EOF
#!/bin/bash
# Auto-rebuild clevo patched drivers after kernel update
# Installed by: $SCRIPT_DIR/install.sh
KVER="\$1"
KBUILD="/lib/modules/\$KVER/build"
DRIVER_DIR="$SCRIPT_DIR"

if [[ -d "\$KBUILD" && -d "\$DRIVER_DIR" ]]; then
    echo "[clevo-drivers] Rebuilding for kernel \$KVER ..."
    make -C "\$KBUILD" M="\$DRIVER_DIR" clean 2>/dev/null || true
    make -C "\$KBUILD" M="\$DRIVER_DIR" -j\$(nproc) modules && \
    make -C "\$KBUILD" M="\$DRIVER_DIR" modules_install && \
    depmod -a "\$KVER" && \
    echo "[clevo-drivers] Done for \$KVER" || \
    echo "[clevo-drivers] Build failed for \$KVER — install linux-headers-\$KVER"
fi
EOF
    chmod +x "$HOOK_PATH"
    log "Kernel update hook installed."
else
    warn "/etc/kernel/postinst.d not found — no auto-rebuild on kernel update."
    warn "On kernel update, re-run: sudo ./install.sh <new-kernel-version>"
fi

# --- 5. Reload modules ---
log "Reloading modules..."
rmmod tuxedo_io clevo_acpi clevo_wmi tuxedo_keyboard tuxedo_compatibility_check \
    uniwill_wmi 2>/dev/null || true
modprobe tuxedo_keyboard && modprobe tuxedo_io && \
    log "Modules loaded successfully!" || warn "Module load failed — try rebooting."

# --- 6. Boot animation ---
ANIM_SCRIPT="$SCRIPT_DIR/kb-boot-anim.py"
ANIM_BIN="/usr/local/bin/nightraven-kb-boot"
ANIM_SERVICE="/etc/systemd/system/nightraven-kb-boot.service"

if [[ ! -f "$ANIM_SCRIPT" ]] || ! command -v systemctl &>/dev/null; then
    warn "kb-boot-anim.py not found or no systemctl — skipping animation."
    INSTALL_ANIM="no"
fi

if [[ "$INSTALL_ANIM" == "ask" ]]; then
    echo ""
    read -r -p $'\e[36m[clevo-install]\e[0m Install RGB boot animation (rainbow → red on startup)? [Y/n] ' ans
    [[ "$ans" =~ ^[Nn] ]] && INSTALL_ANIM="no" || INSTALL_ANIM="yes"
fi

if [[ "$INSTALL_ANIM" == "yes" ]]; then
    log "Installing keyboard boot animation..."
    cp "$ANIM_SCRIPT" "$ANIM_BIN"
    chmod +x "$ANIM_BIN"

    cat > "$ANIM_SERVICE" << SVCEOF
[Unit]
Description=Nightraven Keyboard RGB Boot Animation
After=systemd-modules-load.service
Wants=systemd-modules-load.service

[Service]
Type=oneshot
ExecStart=/usr/bin/python3 $ANIM_BIN
RemainAfterExit=yes
StandardOutput=journal

[Install]
WantedBy=multi-user.target
SVCEOF

    systemctl daemon-reload
    systemctl enable nightraven-kb-boot.service 2>/dev/null
    log "Boot animation installed & enabled."
else
    log "Skipping boot animation."
fi

echo ""
log "=== Installation complete for kernel $KVER ==="
log "On a NEW Linux install:"
log "  1. git clone <your-repo>"
log "  2. sudo ./install.sh"
