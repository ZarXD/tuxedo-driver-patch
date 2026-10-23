#!/bin/bash
# ============================================================
# Clevo/Nightraven Driver Installer (DKMS Version)
# Patched fork of tuxedo-drivers for non-Tuxedo Clevo ODM hardware
#
# Works on: openSUSE Tumbleweed, Ubuntu/Debian, Arch, Fedora/RHEL
# Uses DKMS for automatic rebuilds across kernel updates.
# ============================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

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

log()  { echo -e "\e[32m[clevo-install]\e[0m $*"; }
warn() { echo -e "\e[33m[clevo-install]\e[0m $*"; }
err()  { echo -e "\e[31m[clevo-install]\e[0m $*" >&2; exit 1; }

if [[ $EUID -ne 0 ]]; then
    err "Run as root: sudo ./install.sh"
fi

# --- Animation-only mode (fast path) ---
if [[ "$UPDATE_ANIM_ONLY" == true ]]; then
    ANIM_BIN="/usr/local/bin/nightraven-kb-boot"

    echo ""
    echo -e "\e[36m[clevo-install]\e[0m Which animation style?"
    echo "  1) Color Tour  — rainbow → pastel → dark → flash → red"
    echo "  2) Pulse       — rainbow + brightness pulse → red"
    read -r -p $'\e[36m[clevo-install]\e[0m Style [1/2]: ' style_ans

    if [[ "$style_ans" == "1" ]]; then
        SRC="$SCRIPT_DIR/kb-boot-anim-1.py"
    else
        SRC="$SCRIPT_DIR/kb-boot-anim-2.py"
    fi

    [[ -f "$SRC" ]] || err "Animation file not found: $SRC"

    log "Updating animation script (style $style_ans)..."
    cp "$SRC" "$ANIM_BIN"
    chmod +x "$ANIM_BIN"
    log "Copied to $ANIM_BIN"

    if command -v systemctl &>/dev/null; then
        systemctl restart nightraven-kb-boot.service 2>/dev/null && \
            log "Service restarted!" || \
            warn "Service not found. Run with --animation first to install it."
    fi

    read -r -p $'\e[36m[clevo-install]\e[0m Preview animation now? [Y/n] ' ans
    [[ ! "$ans" =~ ^[Nn] ]] && python3 "$ANIM_BIN"

    log "Done! Edit kb-boot-anim-${style_ans}.py and re-run: sudo ./install.sh --update-animation"
    exit 0
fi

log "Target Kernel: $KVER"

# --- 1. Dependencies and Package Manager ---
log "Checking and installing dependencies..."
if command -v zypper &>/dev/null; then
    # openSUSE Tumbleweed/Leap
    # Detect if we're on kernel-default or another flavor
    KERNEL_FLAVOR="default"
    if [[ "$KVER" == *"-default"* ]]; then
        KERNEL_FLAVOR="default"
    fi
    log "Detected openSUSE. Using zypper for dependencies."
    zypper --non-interactive in dkms make gcc kernel-${KERNEL_FLAVOR}-devel mokutil || warn "Failed to install some dependencies. Ensure dkms and kernel-devel are installed."
elif command -v apt &>/dev/null; then
    log "Detected Debian/Ubuntu. Using apt for dependencies."
    apt update -y || true
    apt install -y "linux-headers-$KVER" build-essential dkms mokutil || warn "Failed to install some dependencies."
elif command -v dnf &>/dev/null; then
    log "Detected Fedora/RHEL. Using dnf for dependencies."
    dnf install -y "kernel-devel-$KVER" "kernel-headers-$KVER" gcc make dkms mokutil || warn "Failed to install some dependencies."
elif command -v pacman &>/dev/null; then
    log "Detected Arch Linux. Using pacman for dependencies."
    pacman -S --noconfirm linux-headers base-devel dkms mokutil || warn "Failed to install some dependencies."
else
    warn "Unsupported package manager. Please ensure dkms, make, gcc, and kernel headers are installed manually."
fi

# Check for DKMS
if ! command -v dkms &>/dev/null; then
    err "DKMS is required but not installed. Please install dkms package."
fi

# Secure Boot check
if command -v mokutil &>/dev/null; then
    if mokutil --sb-state 2>/dev/null | grep -q "SecureBoot enabled"; then
        warn "Secure Boot is ENABLED."
        warn "DKMS modules must be signed to be loaded by the kernel."
        warn "Ensure you have enrolled a MOK key and configured DKMS for signing."
    fi
fi

# --- 2. DKMS Installation ---
DKMS_NAME="tuxedo-drivers"
DKMS_VERSION="patched"
SRC_DEST="/usr/src/${DKMS_NAME}-${DKMS_VERSION}"

log "Preparing DKMS source directory at $SRC_DEST"

# Remove existing source dir if it exists
rm -rf "$SRC_DEST"
mkdir -p "$SRC_DEST"
cp -a "$SCRIPT_DIR/"* "$SRC_DEST/"
cp "$SCRIPT_DIR/dkms.conf" "$SRC_DEST/dkms.conf"

# Remove existing DKMS installation to make installer idempotent
if dkms status -m "$DKMS_NAME" -v "$DKMS_VERSION" | grep -q "added"; then
    log "Removing existing DKMS module $DKMS_NAME-$DKMS_VERSION"
    dkms remove -m "$DKMS_NAME" -v "$DKMS_VERSION" --all || true
fi

log "Adding module to DKMS..."
dkms add -m "$DKMS_NAME" -v "$DKMS_VERSION"

log "Building module via DKMS (this might take a while)..."
if ! dkms build -m "$DKMS_NAME" -v "$DKMS_VERSION" -k "$KVER"; then
    err "DKMS build failed for kernel $KVER. Please check /var/lib/dkms/$DKMS_NAME/$DKMS_VERSION/build/make.log"
fi

log "Installing module via DKMS..."
if ! dkms install -m "$DKMS_NAME" -v "$DKMS_VERSION" -k "$KVER"; then
    err "DKMS install failed for kernel $KVER."
fi

# Cleanup old postinst hook if it exists
HOOK_PATH="/etc/kernel/postinst.d/zz-clevo-drivers"
if [[ -f "$HOOK_PATH" ]]; then
    log "Removing obsolete Debian kernel hook $HOOK_PATH..."
    rm -f "$HOOK_PATH"
fi

log "DKMS installation complete."

# --- 3. Reload modules ---
log "Reloading modules..."
rmmod tuxedo_io clevo_acpi clevo_wmi tuxedo_keyboard tuxedo_compatibility_check \
    uniwill_wmi 2>/dev/null || true
modprobe tuxedo_keyboard && modprobe clevo_acpi && modprobe clevo_wmi && modprobe tuxedo_io && \
    log "Modules loaded successfully!" || warn "Module load failed — they may be signed incorrectly or require a reboot."

# Persist module loading across boots
printf 'tuxedo_keyboard\nclevo_acpi\nclevo_wmi\ntuxedo_io\n' > /etc/modules-load.d/tuxedo-drivers.conf

# --- 4. Boot animation ---
ANIM_BIN="/usr/local/bin/nightraven-kb-boot"
ANIM_SERVICE="/etc/systemd/system/nightraven-kb-boot.service"
ANIM_STYLE=""

if ! command -v systemctl &>/dev/null; then
    warn "No systemctl found — skipping animation."
    INSTALL_ANIM="no"
fi

if [[ "$INSTALL_ANIM" == "ask" ]]; then
    echo ""
    echo -e "\e[36m[clevo-install]\e[0m Install RGB boot animation?"
    echo "  1) Color Tour  — rainbow → pastel → dark → flash → red"
    echo "  2) Pulse       — rainbow + brightness pulse → red"
    echo "  n) No animation"
    read -r -p $'\e[36m[clevo-install]\e[0m Choice [1/2/n]: ' anim_ans
    case "$anim_ans" in
        1) INSTALL_ANIM="yes"; ANIM_STYLE="1" ;;
        2) INSTALL_ANIM="yes"; ANIM_STYLE="2" ;;
        *) INSTALL_ANIM="no" ;;
    esac
fi

if [[ "$INSTALL_ANIM" == "yes" ]]; then
    # Default to style 2 if flag was --animation without style selection
    [[ -z "$ANIM_STYLE" ]] && ANIM_STYLE="2"
    ANIM_SCRIPT="$SCRIPT_DIR/kb-boot-anim-${ANIM_STYLE}.py"

    if [[ ! -f "$ANIM_SCRIPT" ]]; then
        warn "Animation file not found: $ANIM_SCRIPT — skipping."
    else
        log "Installing boot animation style $ANIM_STYLE..."
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
        log "Boot animation (style $ANIM_STYLE) installed & enabled."
    fi
else
    log "Skipping boot animation."
fi

# --- 5. Keyboard brightness guard ---
GUARD_SCRIPT="$SCRIPT_DIR/nightraven-kbd-guard.py"
GUARD_BIN="/usr/local/bin/nightraven-kbd-guard"

if [[ -f "$GUARD_SCRIPT" ]]; then
    log "Installing keyboard brightness guard..."
    cp "$GUARD_SCRIPT" "$GUARD_BIN"
    chmod +x "$GUARD_BIN"

    # Detect real user (when run via sudo)
    REAL_USER="${SUDO_USER:-$USER}"
    REAL_HOME=$(eval echo "~$REAL_USER")
    REAL_UID=$(id -u "$REAL_USER")
    USER_SYSTEMD_DIR="$REAL_HOME/.config/systemd/user"
    DBUS_ADDR="unix:path=/run/user/${REAL_UID}/bus"
    XDG_RT="/run/user/${REAL_UID}"

    mkdir -p "$USER_SYSTEMD_DIR"
    cat > "$USER_SYSTEMD_DIR/nightraven-kbd-guard.service" << 'GUARDEOF'
[Unit]
Description=Nightraven Keyboard Brightness Guardian
After=graphical-session.target
PartOf=graphical-session.target

[Service]
Type=simple
ExecStart=/usr/bin/python3 /usr/local/bin/nightraven-kbd-guard
Restart=on-failure
RestartSec=3
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=graphical-session.target
GUARDEOF

    chown -R "$REAL_USER:$REAL_USER" "$USER_SYSTEMD_DIR" 2>/dev/null || true

    sudo -u "$REAL_USER" XDG_RUNTIME_DIR="$XDG_RT" \
        systemctl --user daemon-reload 2>/dev/null || true
    sudo -u "$REAL_USER" XDG_RUNTIME_DIR="$XDG_RT" \
        systemctl --user enable nightraven-kbd-guard.service 2>/dev/null && \
        log "Guard service enabled." || \
        warn "Enable manually: systemctl --user enable nightraven-kbd-guard.service"
    sudo -u "$REAL_USER" XDG_RUNTIME_DIR="$XDG_RT" \
        systemctl --user start nightraven-kbd-guard.service 2>/dev/null && \
        log "Guard service started." || \
        warn "Start manually: systemctl --user start nightraven-kbd-guard.service"

    # Disable GNOME idle-dim gracefully (do not fail if gsettings is missing or user is on KDE)
    if command -v gsettings &>/dev/null; then
        sudo -u "$REAL_USER" DBUS_SESSION_BUS_ADDRESS="$DBUS_ADDR" \
            gsettings set org.gnome.settings-daemon.plugins.power idle-dim false 2>/dev/null && \
            log "GNOME idle-dim disabled." || \
            log "GNOME idle-dim disable skipped (likely not on GNOME, which is fine)."
    else
        log "gsettings not found, skipping GNOME idle-dim disable (fine for KDE/openSUSE)."
    fi
else
    warn "Guard script not found: $GUARD_SCRIPT — skipping kbd-guard installation."
fi

echo ""
log "=== Installation complete for kernel $KVER ==="
log "Drivers have been installed via DKMS."
log "They will automatically rebuild during future kernel updates."
log "Log daemon: journalctl --user -u nightraven-kbd-guard.service -f"
