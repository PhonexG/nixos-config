#!/usr/bin/env bash
# ==============================================================================
# NixOS + Home Manager Minimal & Essential Backup Generator
# Backs up ONLY:
#   1. /etc/nixos (System modules + Home Manager dotfiles & Niri scripts)
#   2. ~/.config/rclone (rclone.conf, rclone-autofix.sh, filters)
#   3. ~/.config/zed (settings.json, keymap.json, tasks.json, themes)
#   4. ~/.local/bin (custom helper scripts, excluding heavy binaries)
#   5. ~/.gemini/antigravity-acp (essential settings)
# Dynamically generates deploy.sh inside the archive.
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
echo " Preparing NixOS + Home Manager backup: ${BACKUP_NAME}"
echo " Destination: ${ARCHIVE_FILE}"
echo "=================================================================="

rm -rf "$WORK_DIR"
mkdir -p "$WORK_DIR" "$OUTPUT_DIR"

# ------------------------------------------------------------------------------
# 1. NixOS + Home Manager Configuration (/etc/nixos)
# ------------------------------------------------------------------------------
echo "-> [1/5] Collecting /etc/nixos (NixOS modules + Home Manager dotfiles)..."
mkdir -p "$WORK_DIR/nixos"
if [ -d "/etc/nixos" ]; then
    safe_rsync -a \
        --exclude='result*' \
        --exclude='*.tmp' \
        --exclude='*~' \
        "/etc/nixos/" "$WORK_DIR/nixos/"
fi

# ------------------------------------------------------------------------------
# 2. Rclone Configuration & Self-Healing Scripts (~/.config/rclone)
# ------------------------------------------------------------------------------
echo "-> [2/5] Collecting Rclone configuration (~/.config/rclone)..."
if [ -d "$HOME/.config/rclone" ]; then
    mkdir -p "$WORK_DIR/config/rclone"
    safe_rsync -a \
        --exclude='*.tmp' \
        --exclude='*.bak*' \
        --exclude='*.log' \
        "$HOME/.config/rclone/" "$WORK_DIR/config/rclone/"
fi

# ------------------------------------------------------------------------------
# 3. Zed Editor Settings (~/.config/zed)
# ------------------------------------------------------------------------------
echo "-> [3/5] Collecting Zed configuration (~/.config/zed)..."
if [ -d "$HOME/.config/zed" ]; then
    mkdir -p "$WORK_DIR/config/zed"
    safe_rsync -a \
        --exclude='*.bak*' \
        --exclude='*.tmp' \
        --exclude='*.log' \
        --exclude='conversations' \
        --exclude='prompts' \
        "$HOME/.config/zed/" "$WORK_DIR/config/zed/"
fi

# ------------------------------------------------------------------------------
# 4. Essential User Helper Scripts (~/.local/bin) & Antigravity Settings
# ------------------------------------------------------------------------------
echo "-> [4/5] Collecting lightweight user scripts & Antigravity settings..."
if [ -d "$HOME/.local/bin" ]; then
    mkdir -p "$WORK_DIR/local_bin"
    safe_rsync -a --copy-unsafe-links \
        --exclude='backup-system.sh' \
        --exclude='deploy.sh' \
        --exclude='agy*' \
        --exclude='zed' \
        --exclude='__pycache__' \
        --max-size='5m' \
        "$HOME/.local/bin/" "$WORK_DIR/local_bin/"
fi

if [ -d "$HOME/.gemini/antigravity-acp" ]; then
    mkdir -p "$WORK_DIR/gemini/antigravity-acp"
    [ -f "$HOME/.gemini/antigravity-acp/settings.json" ] && \
        cp "$HOME/.gemini/antigravity-acp/settings.json" "$WORK_DIR/gemini/antigravity-acp/"
    [ -f "$HOME/.gemini/antigravity-acp/session_titles.json" ] && \
        cp "$HOME/.gemini/antigravity-acp/session_titles.json" "$WORK_DIR/gemini/antigravity-acp/"
fi

# ------------------------------------------------------------------------------
# 5. Generate deploy.sh Dynamically
# ------------------------------------------------------------------------------
echo "-> [5/5] Generating deploy.sh inside archive..."
cat << 'DEPLOY_EOF' > "$WORK_DIR/deploy.sh"
#!/usr/bin/env bash
# ==============================================================================
# NixOS + Home Manager Auto-Deploy Script
# Restores /etc/nixos, Rclone, Zed, and helper scripts.
# ==============================================================================
set -euo pipefail

BACKUP_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET_USER="${SUDO_USER:-$USER}"

echo "=================================================================="
echo " Restoring system from: $BACKUP_ROOT"
echo "=================================================================="

# 1. Restore Rclone & Zed configs into ~/.config
if [ -d "$BACKUP_ROOT/config" ]; then
    echo "-> [1/4] Restoring Rclone & Zed into ~/.config/ ..."
    mkdir -p "$HOME/.config"
    cp -a "$BACKUP_ROOT/config/." "$HOME/.config/"
    chmod 600 "$HOME/.config/rclone/rclone.conf" 2>/dev/null || true
    chmod +x "$HOME/.config/rclone/rclone-autofix.sh" 2>/dev/null || true
fi

# 2. Restore ~/.local/bin helper scripts
mkdir -p "$HOME/.local/bin"
if [ -d "$BACKUP_ROOT/local_bin" ]; then
    echo "-> [2/4] Restoring helper scripts into ~/.local/bin/ ..."
    cp -a "$BACKUP_ROOT/local_bin/." "$HOME/.local/bin/"
fi
[ -f "$BACKUP_ROOT/backup-system.sh" ] && cp -a "$BACKUP_ROOT/backup-system.sh" "$HOME/.local/bin/"
chmod +x "$HOME/.local/bin"/*.sh 2>/dev/null || true

# 3. Restore Antigravity ACP settings
if [ -d "$BACKUP_ROOT/gemini" ]; then
    echo "-> [3/4] Restoring Antigravity settings into ~/.gemini/ ..."
    mkdir -p "$HOME/.gemini"
    cp -a "$BACKUP_ROOT/gemini/." "$HOME/.gemini/"
fi

# 4. Restore /etc/nixos (NixOS + Home Manager)
if [ -d "$BACKUP_ROOT/nixos" ]; then
    echo "-> [4/4] Restoring /etc/nixos (requires sudo)..."
    sudo mkdir -p /etc/nixos
    sudo cp -a "$BACKUP_ROOT/nixos/." /etc/nixos/
    sudo chown -R "${TARGET_USER}:users" /etc/nixos
fi

echo ""
echo "=================================================================="
echo " Restore complete! Applying NixOS + Home Manager configuration:"
echo "   sudo nixos-rebuild switch --flake /etc/nixos#nixos"
echo "=================================================================="
DEPLOY_EOF

chmod +x "$WORK_DIR/deploy.sh"
cp "${BASH_SOURCE[0]}" "$WORK_DIR/backup-system.sh"
chmod +x "$WORK_DIR/backup-system.sh"

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
echo " Clean backup created successfully!"
echo " File: ${ARCHIVE_FILE}"
echo " Size: $(du -h "${ARCHIVE_FILE}" | cut -f1)"
echo "=================================================================="
