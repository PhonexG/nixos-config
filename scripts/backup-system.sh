#!/usr/bin/env bash
# ==============================================================================
# NixOS + Home Manager Portable Backup Generator
# Backs up:
#   1. /etc/nixos (Complete declarative system & Home Manager config)
#   2. ~/.config/rclone/rclone.conf (Sanitized remote structure only — NO tokens,
#      client_id/secret, email, or Drive IDs)
#   3. ~/.gemini/antigravity-acp (Assistant settings)
# Dynamically generates a self-contained deploy.sh inside the archive.
# ==============================================================================
set -euo pipefail

TIMESTAMP="$(date +'%Y-%m-%d_%H-%M-%S')"
DEFAULT_OUT="$HOME"

OUTPUT_DIR="$DEFAULT_OUT"
KEEP_DIR=false

for arg in "$@"; do
    case "$arg" in
        --keep-dir|-k)
            KEEP_DIR=true
            ;;
        *)
            OUTPUT_DIR="$arg"
            ;;
    esac
done

BACKUP_NAME="system-backup_${TIMESTAMP}"
WORK_DIR="/tmp/${BACKUP_NAME}"
ARCHIVE_FILE="${OUTPUT_DIR}/${BACKUP_NAME}.zip"

safe_rsync() {
    rsync "$@" || {
        status=$?
        [ "$status" -eq 24 ] && return 0
        return "$status"
    }
}

echo "=================================================================="
echo " Preparing portable NixOS backup: ${BACKUP_NAME}"
echo " Destination: ${ARCHIVE_FILE}"
echo "=================================================================="

rm -rf "$WORK_DIR"
mkdir -p "$WORK_DIR" "$OUTPUT_DIR"

# ------------------------------------------------------------------------------
# 1. NixOS System & Home Manager Configuration (/etc/nixos)
# ------------------------------------------------------------------------------
echo "-> [1/4] Collecting /etc/nixos..."
mkdir -p "$WORK_DIR/nixos"
if [ -d "/etc/nixos" ]; then
    safe_rsync -a \
        --exclude='result*' \
        --exclude='*.tmp' \
        --exclude='*~' \
        "/etc/nixos/" "$WORK_DIR/nixos/"
fi

# ------------------------------------------------------------------------------
# 2. Sanitized Rclone Remote Structure (~/.config/rclone/rclone.conf)
#    Strips tokens, client_id/client_secret, Drive/team IDs, emails, and passwords.
# ------------------------------------------------------------------------------
echo "-> [2/4] Collecting sanitized Rclone remote structure (no credentials)..."
if [ -f "$HOME/.config/rclone/rclone.conf" ]; then
    mkdir -p "$WORK_DIR/config/rclone"
    awk '
        /^[[:space:]]*\[[^]]+\][[:space:]]*$/ { print; next }
        /^[[:space:]]*(type|scope)[[:space:]]*=/ { print; next }
    ' "$HOME/.config/rclone/rclone.conf" > "$WORK_DIR/config/rclone/rclone.conf"
    if [ -s "$WORK_DIR/config/rclone/rclone.conf" ]; then
        chmod 600 "$WORK_DIR/config/rclone/rclone.conf"
    else
        rm -rf "$WORK_DIR/config/rclone"
    fi
fi

# ------------------------------------------------------------------------------
# 3. Antigravity Settings
# ------------------------------------------------------------------------------
echo "-> [3/4] Collecting Antigravity settings..."
if [ -d "$HOME/.gemini/antigravity-acp" ]; then
    mkdir -p "$WORK_DIR/gemini/antigravity-acp"
    [ -f "$HOME/.gemini/antigravity-acp/settings.json" ] && \
        cp "$HOME/.gemini/antigravity-acp/settings.json" "$WORK_DIR/gemini/antigravity-acp/"
    [ -f "$HOME/.gemini/antigravity-acp/session_titles.json" ] && \
        cp "$HOME/.gemini/antigravity-acp/session_titles.json" "$WORK_DIR/gemini/antigravity-acp/"
fi

# ------------------------------------------------------------------------------
# 4. Generate deploy.sh Dynamically
# ------------------------------------------------------------------------------
echo "-> [4/4] Generating portable deploy.sh inside archive..."
cat << 'DEPLOY_EOF' > "$WORK_DIR/deploy.sh"
#!/usr/bin/env bash
# ==============================================================================
# NixOS Auto-Deploy & Restore Script
# Restores /etc/nixos, sanitized Rclone remote structure, and Antigravity settings.
# ==============================================================================
set -euo pipefail

BACKUP_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET_USER="${SUDO_USER:-$USER}"
TARGET_HOME="$(getent passwd "$TARGET_USER" 2>/dev/null | cut -d: -f6 || true)"
TARGET_HOME="${TARGET_HOME:-$HOME}"

echo "=================================================================="
echo " Restoring NixOS system configuration from: $BACKUP_ROOT"
echo " Target user: $TARGET_USER ($TARGET_HOME)"
echo "=================================================================="

# 1. Restore sanitized Rclone template (never overwrites existing live config)
RCLONE_NEEDS_AUTH=0
if [ -f "$BACKUP_ROOT/config/rclone/rclone.conf" ]; then
    mkdir -p "$TARGET_HOME/.config/rclone"
    if [ -f "$TARGET_HOME/.config/rclone/rclone.conf" ]; then
        echo "-> Existing ~/.config/rclone/rclone.conf found; keeping it intact."
    else
        echo "-> Restoring sanitized Rclone remote template into ~/.config/rclone/rclone.conf ..."
        cp -a "$BACKUP_ROOT/config/rclone/rclone.conf" "$TARGET_HOME/.config/rclone/rclone.conf"
        chmod 600 "$TARGET_HOME/.config/rclone/rclone.conf"
        RCLONE_NEEDS_AUTH=1
    fi
fi

# 2. Restore Antigravity ACP settings
if [ -d "$BACKUP_ROOT/gemini" ]; then
    echo "-> Restoring Antigravity settings into ~/.gemini/ ..."
    mkdir -p "$TARGET_HOME/.gemini"
    cp -a "$BACKUP_ROOT/gemini/." "$TARGET_HOME/.gemini/"
fi

# 3. Restore /etc/nixos
if [ -d "$BACKUP_ROOT/nixos" ]; then
    echo "-> Restoring /etc/nixos (requires sudo)..."
    sudo mkdir -p /etc/nixos
    sudo cp -a "$BACKUP_ROOT/nixos/." /etc/nixos/
    sudo chown -R "${TARGET_USER}:users" /etc/nixos

    # Check if deployed on new hardware
    if [ ! -f /etc/nixos/hardware-configuration.nix ] || [ "${NEW_HARDWARE:-0}" = "1" ]; then
        echo "-> Generating new hardware-configuration.nix for this device..."
        sudo nixos-generate-config --show-hardware-config > /tmp/hw-config.nix
        sudo mv /tmp/hw-config.nix /etc/nixos/hardware-configuration.nix
    fi
fi

echo ""
echo "=================================================================="
echo " Restore completed successfully!"
echo " To apply the system configuration now, run:"
echo "   sudo nixos-rebuild switch --flake /etc/nixos#nixos"
if [ "$RCLONE_NEEDS_AUTH" -eq 1 ]; then
    echo ""
    echo " Rclone credentials were intentionally omitted from this backup."
    echo " Re-authenticate your remote after switch with:"
    echo "   rclone config reconnect gdrive:"
fi
echo "=================================================================="
DEPLOY_EOF

chmod +x "$WORK_DIR/deploy.sh"

# ------------------------------------------------------------------------------
# Compress into ZIP Archive
# ------------------------------------------------------------------------------
echo "-> Compressing archive into ${ARCHIVE_FILE}..."
(cd "/tmp" && zip -q -r -y "${ARCHIVE_FILE}" "${BACKUP_NAME}")

if [ "$KEEP_DIR" = true ]; then
    cp -r "$WORK_DIR" "${OUTPUT_DIR}/${BACKUP_NAME}"
fi

rm -rf "$WORK_DIR"

echo "=================================================================="
echo " Portable backup created successfully!"
echo " File: ${ARCHIVE_FILE}"
echo " Size: $(du -h "${ARCHIVE_FILE}" | cut -f1)"
echo "=================================================================="
