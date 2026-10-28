#!/usr/bin/env bash
set -u

# Прокидаємо системні шляхи NixOS, щоб systemd бачив необхідні утиліти
export PATH="/run/current-system/sw/bin:/etc/profiles/per-user/${USER:-$(id -un)}/bin:$HOME/.nix-profile/bin:$PATH"

REMOTE="${RCLONE_REMOTE:-gdrive:}"
LOCAL="${RCLONE_LOCAL:-$HOME/GDriveOffline}"
FILTERS="${RCLONE_FILTERS:-$HOME/.config/rclone/bisync-filters.txt}"
CACHE_DIR="$HOME/.cache/rclone/bisync"
STATE_DIR="$HOME/.local/state/rclone"
LOG_FILE="$STATE_DIR/rclone-bisync.log"
SCRIPT_LOCK="$CACHE_DIR/rclone-bisync-wrapper.lock"

mkdir -p "$LOCAL" "$CACHE_DIR" "$STATE_DIR" "$(dirname "$FILTERS")"

if [[ ! -f "$FILTERS" ]]; then
  : > "$FILTERS"
fi

exec 9>"$SCRIPT_LOCK"
if ! flock -n 9; then
  echo "--- $(date): rclone bisync already running, skipping ---" | tee -a "$LOG_FILE"
  exit 0
fi

log() {
  echo "$*" | tee -a "$LOG_FILE"
}

# 1. Перевірка наявності rclone
if ! command -v rclone >/dev/null 2>&1; then
  log "Помилка: rclone не встановлений."
  exit 127
fi

# 2. Перевірка наявності віддаленого сховища
REMOTE_NAME="${REMOTE%%:*}:"
if ! rclone listremotes 2>/dev/null | grep -Fxq "$REMOTE_NAME"; then
  log "Помилка: remote '$REMOTE_NAME' не налаштований."
  exit 2
fi

# 3. Перевірка інтернет-з'єднання перед початком, щоб уникнути помилкових збоїв bisync
if ! ping -c 1 -W 2 8.8.8.8 >/dev/null 2>&1 && ! curl -s --connect-timeout 2 -I https://www.googleapis.com >/dev/null 2>&1; then
  # Немає мережі — просто виходимо без помилки, щоб не псувати базу bisync
  exit 0
fi

log "--- Запуск синхронізації: $(date) ---"

# Очищуємо завислі lock-файли rclone
find "$CACHE_DIR" -maxdepth 1 -type f -name '*.lck' -delete 2>/dev/null || true

# Оптимізована функція запуску bisync
# Примітка: --remove-empty-dirs ПРИБРАНО, оскільки воно конфліктує з фільтрами
# (наприклад **/bin/**, де rclone вважає директорію порожньою, але rmdir падає з "directory not empty")
run_sync() {
  rclone bisync "$REMOTE" "$LOCAL" \
    --log-level INFO \
    --log-file "$LOG_FILE" \
    --drive-acknowledge-abuse \
    --filter-from "$FILTERS" \
    --compare size,modtime \
    --slow-hash-sync-only \
    --conflict-resolve newer \
    --conflict-loser pathname \
    --transfers 8 \
    --checkers 16 \
    --drive-chunk-size 64M \
    --fast-list \
    --force \
    --recover \
    --resilient "$@"
}

# Спроба звичайної синхронізації
TEMP_RUN_LOG=$(mktemp)
run_sync 2>&1 | tee "$TEMP_RUN_LOG"
EXIT_CODE=${PIPESTATUS[0]}

# Перевірка на закінчення терміну дії токена OAuth
if grep -q "invalid_grant" "$TEMP_RUN_LOG" || tail -n 20 "$LOG_FILE" | grep -q "invalid_grant"; then
  log "КРИТИЧНО: Google Drive токен OAuth застарів або відкликаний (invalid_grant)."
  if command -v notify-send >/dev/null 2>&1; then
    notify-send -u critical "Rclone Google Drive" "Сесія Google Drive закінчилась! Запустіть у терміналі: rclone config reconnect gdrive:"
  fi
  rm -f "$TEMP_RUN_LOG"
  exit 1
fi

# Самовідновлення: якщо bisync заблоковано через попередні збої або потрібен --resync
if [[ $EXIT_CODE -ne 0 ]]; then
  log "УВАГА: rclone bisync завершився з помилкою (Код: $EXIT_CODE). Запуск автоматичного відновлення (--resync)..."
  
  run_sync --resync
  RESYNC_CODE=$?
  
  if [[ $RESYNC_CODE -eq 0 ]]; then
    log "УСПІХ: Автоматичне відновлення (--resync) пройшло успішно!"
    rm -f "$TEMP_RUN_LOG"
    exit 0
  else
    log "ПОМИЛКА: Самовідновлення (--resync) також не вдалося (Код: $RESYNC_CODE)."
    if command -v notify-send >/dev/null 2>&1; then
      notify-send -u critical "rclone sync error" "Помилка синхронізації rclone навіть після resync. Перевірте лог: $LOG_FILE"
    fi
    rm -f "$TEMP_RUN_LOG"
    exit "$RESYNC_CODE"
  fi
else
  log "Синхронізація успішна."
  rm -f "$TEMP_RUN_LOG"
  exit 0
fi
