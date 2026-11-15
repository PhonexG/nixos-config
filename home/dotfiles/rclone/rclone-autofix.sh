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
IS_DRY_RUN=false
IS_RESYNC=false
while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run|-n)
      SYNC_ARGS+=(--dry-run)
      IS_DRY_RUN=true
      shift
      ;;
    --resync)
      SYNC_ARGS+=(--resync)
      IS_RESYNC=true
      shift
      ;;
    --resync-mode=*)
      SYNC_ARGS+=("$1")
      shift
      ;;
    --resync-mode)
      if [[ $# -lt 2 ]]; then
        printf 'Помилка: для %s потрібно вказати значення.\n' "$1" >&2
        exit 2
      fi
      SYNC_ARGS+=("$1" "$2")
      shift 2
      ;;
    *)
      printf 'Невідомий аргумент: %s. Дозволено лише --dry-run/-n, --resync та --resync-mode=... .\n' "$1" >&2
      exit 2
      ;;
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

for tool in rclone flock tee mktemp curl stat mv rm grep; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    printf 'Помилка: необхідна утиліта %s не встановлена.\n' "$tool" >&2
    exit 127
  fi
done

rotate_log_if_needed() {
  local max_bytes=10485760
  local log_size=0
  if [[ -f "$LOG_FILE" ]]; then
    log_size=$(stat -c%s -- "$LOG_FILE" 2>/dev/null || printf '0')
    if [[ "$log_size" =~ ^[0-9]+$ ]] && (( log_size > max_bytes )); then
      mv -f -- "$LOG_FILE" "$LOG_FILE.1"
      chmod 600 "$LOG_FILE.1" 2>/dev/null || true
    fi
  fi
  touch "$LOG_FILE"
  chmod 600 "$LOG_FILE"
}

has_live_rclone_bisync() {
  local pid_dir stat_line proc_state exe_base arg
  local -a cmd_args=()
  for pid_dir in /proc/[0-9]*; do
    [[ -r "$pid_dir/stat" && -r "$pid_dir/cmdline" ]] || continue
    stat_line=$(<"$pid_dir/stat" 2>/dev/null) || continue
    proc_state="${stat_line##*) }"
    proc_state="${proc_state%% *}"
    # Ігноруємо зомбі/мертві процеси (Z, X), щоб вони не блокували очищення lock-файлів.
    [[ "$proc_state" == "Z" || "$proc_state" == "X" ]] && continue
    { mapfile -d '' -t cmd_args < "$pid_dir/cmdline"; } 2>/dev/null || continue
    [[ ${#cmd_args[@]} -gt 0 ]] || continue
    exe_base="${cmd_args[0]##*/}"
    if [[ "$exe_base" == "rclone" || "$exe_base" == ".rclone-wrapped" ]]; then
      for arg in "${cmd_args[@]:1}"; do
        if [[ "$arg" == "bisync" ]]; then
          return 0
        fi
      done
    fi
  done
  return 1
}

cleanup_stale_bisync_state() {
  local was_nullglob=0
  local -a stale_locks=() stale_errs=()
  shopt -q nullglob && was_nullglob=1
  shopt -s nullglob
  stale_locks=("$CACHE_DIR"/*.lck)
  stale_errs=("$CACHE_DIR"/*.lst-err)
  (( was_nullglob == 0 )) && shopt -u nullglob

  if (( ${#stale_locks[@]} == 0 && ${#stale_errs[@]} == 0 )); then
    return 0
  fi

  if has_live_rclone_bisync; then
    log "Увага: виявлено активний процес rclone bisync; файли блокування не видаляються."
    return 0
  fi

  if (( ${#stale_locks[@]} > 0 )); then
    log "Увага: активного процесу rclone bisync не знайдено; очищення застарілих lock-файлів: ${stale_locks[*]}"
    rm -f -- "${stale_locks[@]}"
  fi
  if (( ${#stale_errs[@]} > 0 )); then
    log "Увага: очищення застарілих файлів помилок (*.lst-err): ${stale_errs[*]}"
    rm -f -- "${stale_errs[@]}"
  fi
}

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

rotate_log_if_needed
cleanup_stale_bisync_state

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

# Застарілі lock-файли вже очищено під flock після перевірки живих процесів.
# --recover і --resilient відновлюють стан, не обходячи захисти bisync.
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
    --filters-file "$FILTERS" \
    --compare size,modtime \
    --slow-hash-sync-only \
    --conflict-resolve newer \
    --conflict-loser num \
    --transfers 4 \
    --checkers 8 \
    --tpslimit 10 \
    --tpslimit-burst 10 \
    --timeout 5m \
    --contimeout 60s \
    --retries 5 \
    --low-level-retries 10 \
    --max-delete 50 \
    --max-lock 15m \
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

if [[ "$IS_DRY_RUN" == true ]]; then
  log "Пробна синхронізація успішна. Файли не змінено."
elif [[ "$IS_RESYNC" == true ]]; then
  log "Пересинхронізація (--resync) успішна."
else
  log "Синхронізація успішна."
fi
