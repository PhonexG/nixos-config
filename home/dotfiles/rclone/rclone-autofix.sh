#!/usr/bin/env bash
set -euo pipefail
umask 077

# Прокидаємо системні шляхи NixOS, щоб systemd бачив необхідні утиліти
export PATH="/run/current-system/sw/bin:/etc/profiles/per-user/${USER:-$(id -un)}/bin:$HOME/.nix-profile/bin:$PATH"

REMOTE="${RCLONE_REMOTE:-gdrive:}"
LOCAL="${RCLONE_LOCAL:-$HOME/GDriveOffline}"
FILTERS="${RCLONE_FILTERS:-$HOME/.config/rclone/bisync-filters.txt}"
CACHE_DIR="$HOME/.cache/rclone/bisync"
STATE_DIR="$HOME/.local/state/rclone"
LOG_FILE="$STATE_DIR/rclone-bisync.log"
SCRIPT_LOCK="$CACHE_DIR/rclone-bisync-wrapper.lock"

SYNC_ARGS=()
for arg in "$@"; do
  case "$arg" in
    --dry-run|-n) SYNC_ARGS=(--dry-run) ;;
    *) printf 'Невідомий аргумент: %s. Дозволено лише --dry-run.\n' "$arg" >&2; exit 2 ;;
  esac
done

mkdir -p "$CACHE_DIR" "$STATE_DIR"
touch "$LOG_FILE"
chmod 600 "$LOG_FILE"

log() {
  printf '%s\n' "$*" | tee -a "$LOG_FILE"
}

notify_error() {
  if command -v notify-send >/dev/null 2>&1; then
    notify-send -u critical "$1" "$2" || true
  fi
}

for tool in rclone flock tee mktemp curl; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    printf 'Помилка: необхідна утиліта %s не встановлена.\n' "$tool" >&2
    exit 127
  fi
done

exec 9>"$SCRIPT_LOCK"
if flock -n -E 75 9; then
  :
else
  LOCK_CODE=$?
  if [[ $LOCK_CODE -eq 75 ]]; then
    log "--- $(date): rclone bisync already running, skipping ---"
    exit 0
  fi
  log "Помилка: не вдалося отримати блокування (Код: $LOCK_CODE)."
  exit "$LOCK_CODE"
fi

# Не створюємо порожні джерела або фільтри: їх відсутність потребує перевірки.
if [[ ! -d "$LOCAL" ]]; then
  log "Помилка: локальна папка '$LOCAL' відсутня. Синхронізацію скасовано."
  exit 2
fi
if [[ ! -f "$FILTERS" || ! -r "$FILTERS" ]]; then
  log "Помилка: файл фільтрів '$FILTERS' відсутній або недоступний."
  exit 2
fi

# OAuth-конфігурація має залишатися приватною, зокрема після оновлення токена.
CONFIG_FILE="${RCLONE_CONFIG:-${XDG_CONFIG_HOME:-$HOME/.config}/rclone/rclone.conf}"
if [[ -f "$CONFIG_FILE" ]]; then
  chmod 600 "$CONFIG_FILE"
fi

# Перевірка наявності віддаленого сховища.
REMOTE_NAME="${REMOTE%%:*}:"
if ! REMOTES=$(rclone listremotes 2>/dev/null); then
  log "Помилка: не вдалося прочитати конфігурацію rclone."
  exit 2
fi
if ! grep -Fxq -- "$REMOTE_NAME" <<< "$REMOTES"; then
  log "Помилка: remote '$REMOTE_NAME' не налаштований."
  exit 2
fi

# Немає мережі — пропускаємо запуск, не змінюючи стан bisync.
if ! ping -c 1 -W 2 8.8.8.8 >/dev/null 2>&1 && ! curl -s --connect-timeout 2 --max-time 5 -I https://www.googleapis.com >/dev/null 2>&1; then
  log "--- $(date): немає мережі, синхронізацію пропущено ---"
  exit 0
fi

log "--- Запуск синхронізації: $(date) ---"

# Lock-файли rclone не видаляємо: ними може користуватися інший процес.
# --recover і --resilient відновлюють стан, не обходячи блокування та захисти.
TEMP_RUN_LOG=$(mktemp "$STATE_DIR/rclone-run.XXXXXX")
trap 'rm -f "$TEMP_RUN_LOG"' EXIT

# Оптимізована функція запуску bisync
# Примітка: --remove-empty-dirs ПРИБРАНО, оскільки воно конфліктує з фільтрами
# (наприклад **/bin/**, де rclone вважає директорію порожньою, але rmdir падає з "directory not empty")
run_sync() {
  rclone bisync "$REMOTE" "$LOCAL" \
    --workdir "$CACHE_DIR" \
    --color NEVER \
    --log-level INFO \
    --drive-acknowledge-abuse \
    --filter-from "$FILTERS" \
    --compare size,modtime \
    --slow-hash-sync-only \
    --conflict-resolve newer \
    --conflict-loser num \
    --transfers 8 \
    --checkers 16 \
    --drive-chunk-size 64M \
    --fast-list \
    --recover \
    --resilient "${SYNC_ARGS[@]}"
}

# Зберігаємо код rclone окремо від tee та перевіряємо лише журнал цього запуску.
if run_sync 2>&1 | tee -a "$LOG_FILE" "$TEMP_RUN_LOG"; then
  RUN_STATUS=("${PIPESTATUS[@]}")
else
  RUN_STATUS=("${PIPESTATUS[@]}")
fi
EXIT_CODE=${RUN_STATUS[0]}

if [[ ${RUN_STATUS[1]} -ne 0 ]]; then
  printf 'Помилка: не вдалося записати журнал rclone.\n' >&2
  if [[ $EXIT_CODE -ne 0 ]]; then
    exit "$EXIT_CODE"
  fi
  exit 1
fi

if [[ $EXIT_CODE -ne 0 ]]; then
  if grep -q "invalid_grant" "$TEMP_RUN_LOG"; then
    log "КРИТИЧНО: Google Drive токен OAuth застарів або відкликаний (invalid_grant)."
    notify_error "Rclone Google Drive" "Сесія Google Drive закінчилась! Виконайте rclone config reconnect '$REMOTE_NAME'."
  else
    log "ПОМИЛКА: rclone bisync завершився з помилкою (Код: $EXIT_CODE)."
    notify_error "rclone sync error" "Синхронізацію зупинено без автоматичного resync. Перевірте журнал: $LOG_FILE"
  fi
  # --resync може перезаписувати новіші файли та відновлювати видалені.
  # Якщо він потрібний, спочатку вручну перевірте --resync-mode newer --dry-run.
  log "Автоматичний --resync вимкнено. Перед ручним відновленням перевірте журнал: $LOG_FILE"
  exit "$EXIT_CODE"
fi

if [[ ${#SYNC_ARGS[@]} -gt 0 ]]; then
  log "Пробна синхронізація успішна. Файли не змінено."
else
  log "Синхронізація успішна."
fi
