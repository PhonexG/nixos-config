#!/usr/bin/env bash
# ==============================================================================
# NixOS + Home Manager Portable Backup Generator
# Backs up:
#   1. /etc/nixos (Complete declarative system & Home Manager config)
#   2. ~/.config/zed (Zed editor: settings, keymap, tasks, themes)
#   3. ~/.config/rclone (rclone.conf with credentials/tokens)
#   4. ~/.gitconfig & ~/.ssh (Git identity & SSH keys with permissions)
#   5. ~/.gemini/antigravity-acp (Assistant settings)
# Dynamically generates a self-contained deploy.sh inside the archive.
# ==============================================================================
set -euo pipefail

TIMESTAMP="$(date +'%Y-%m-%d_%H-%M-%S')"
DEFAULT_OUT="$HOME"
if [ ! -d "$DEFAULT_OUT" ]; then
    DEFAULT_OUT="$HOME"
fi

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
echo "-> [1/6] Collecting /etc/nixos..."
mkdir -p "$WORK_DIR/nixos"
if [ -d "/etc/nixos" ]; then
    safe_rsync -a \
        --exclude='result*' \
        --exclude='*.tmp' \
        --exclude='*~' \
        "/etc/nixos/" "$WORK_DIR/nixos/"
fi

# ------------------------------------------------------------------------------
# 2. Zed Editor Configuration (~/.config/zed)
# ------------------------------------------------------------------------------
echo "-> [2/6] Collecting Zed editor configuration (~/.config/zed)..."
if [ -d "$HOME/.config/zed" ]; then
    mkdir -p "$WORK_DIR/config/zed"
    safe_rsync -a \
        --exclude='*.bak*' \
        --exclude='*.tmp' \
        --exclude='*.log' \
        --exclude='*.sock' \
        --exclude='conversations' \
        --exclude='prompts' \
        "$HOME/.config/zed/" "$WORK_DIR/config/zed/"
fi

# ------------------------------------------------------------------------------
# 3. Rclone Credentials (~/.config/rclone/rclone.conf)
# ------------------------------------------------------------------------------
echo "-> [3/6] Collecting Rclone session/tokens..."
if [ -f "$HOME/.config/rclone/rclone.conf" ]; then
    mkdir -p "$WORK_DIR/config/rclone"
    cp -a "$HOME/.config/rclone/rclone.conf" "$WORK_DIR/config/rclone/"
fi

# ------------------------------------------------------------------------------
# 4. Git Identity & SSH Keys
# ------------------------------------------------------------------------------
echo "-> [4/6] Collecting Git config & SSH keys..."
if [ -f "$HOME/.gitconfig" ]; then
    cp -a "$HOME/.gitconfig" "$WORK_DIR/gitconfig"
fi

if [ -d "$HOME/.ssh" ]; then
    mkdir -p "$WORK_DIR/ssh"
    safe_rsync -a \
        --exclude='known_hosts.old' \
        "$HOME/.ssh/" "$WORK_DIR/ssh/"
fi

# ------------------------------------------------------------------------------
# 5. Antigravity Settings
# ------------------------------------------------------------------------------
echo "-> [5/6] Collecting Antigravity settings..."
if [ -d "$HOME/.gemini/antigravity-acp" ]; then
    mkdir -p "$WORK_DIR/gemini/antigravity-acp"
    [ -f "$HOME/.gemini/antigravity-acp/settings.json" ] && \
        cp "$HOME/.gemini/antigravity-acp/settings.json" "$WORK_DIR/gemini/antigravity-acp/"
    [ -f "$HOME/.gemini/antigravity-acp/session_titles.json" ] && \
        cp "$HOME/.gemini/antigravity-acp/session_titles.json" "$WORK_DIR/gemini/antigravity-acp/"
fi

# ------------------------------------------------------------------------------
# 6. Generate deploy.sh Dynamically
# ------------------------------------------------------------------------------
echo "-> [6/6] Generating portable deploy.sh inside archive..."
cat << 'DEPLOY_EOF' > "$WORK_DIR/deploy.sh"
#!/usr/bin/env bash
# ==============================================================================
# NixOS Auto-Deploy & Restore Script
# Restores /etc/nixos, Zed config, Rclone credentials, Git identity, and SSH keys.
# ==============================================================================
set -euo pipefail

BACKUP_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET_USER="${SUDO_USER:-$USER}"
TARGET_HOME="${HOME}"

echo "=================================================================="
echo " Restoring NixOS system configuration from: $BACKUP_ROOT"
echo " Target user: $TARGET_USER ($TARGET_HOME)"
echo "=================================================================="

# 1. Restore Zed Editor configuration
if [ -d "$BACKUP_ROOT/config/zed" ]; then
    echo "-> Restoring Zed configuration into ~/.config/zed/ ..."
    mkdir -p "$TARGET_HOME/.config/zed"
    cp -a "$BACKUP_ROOT/config/zed/." "$TARGET_HOME/.config/zed/"
fi

# 2. Restore Rclone credentials
if [ -f "$BACKUP_ROOT/config/rclone/rclone.conf" ]; then
    echo "-> Restoring Rclone tokens into ~/.config/rclone/rclone.conf ..."
    mkdir -p "$TARGET_HOME/.config/rclone"
    cp -a "$BACKUP_ROOT/config/rclone/rclone.conf" "$TARGET_HOME/.config/rclone/rclone.conf"
    chmod 600 "$TARGET_HOME/.config/rclone/rclone.conf"
fi

# 3. Restore Git config
if [ -f "$BACKUP_ROOT/gitconfig" ]; then
    echo "-> Restoring ~/.gitconfig ..."
    cp -a "$BACKUP_ROOT/gitconfig" "$TARGET_HOME/.gitconfig"
fi

# 4. Restore SSH keys with secure permissions
if [ -d "$BACKUP_ROOT/ssh" ]; then
    echo "-> Restoring SSH keys into ~/.ssh/ ..."
    mkdir -p "$TARGET_HOME/.ssh"
    chmod 700 "$TARGET_HOME/.ssh"
    cp -a "$BACKUP_ROOT/ssh/." "$TARGET_HOME/.ssh/"
    find "$TARGET_HOME/.ssh" -type f -name 'id_*' ! -name '*.pub' -exec chmod 600 {} + 2>/dev/null || true
    find "$TARGET_HOME/.ssh" -type f -name '*.pub' -exec chmod 644 {} + 2>/dev/null || true
fi

# 5. Restore Antigravity ACP settings
if [ -d "$BACKUP_ROOT/gemini" ]; then
    echo "-> Restoring Antigravity settings into ~/.gemini/ ..."
    mkdir -p "$TARGET_HOME/.gemini"
    cp -a "$BACKUP_ROOT/gemini/." "$TARGET_HOME/.gemini/"
fi

# 6. Restore /etc/nixos
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
