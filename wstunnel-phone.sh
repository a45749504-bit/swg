#!/data/data/com.termux/files/usr/bin/bash
set -Eeuo pipefail

APP_DIR="${HOME}/.wstunnel-render"
SECRET_FILE="${APP_DIR}/path.secret"
PID_FILE="${APP_DIR}/wstunnel.pid"
LOG_FILE="${APP_DIR}/wstunnel.log"
WSTUNNEL_BIN="${WSTUNNEL_BIN:-${HOME}/bin/wstunnel}"
RENDER_HOST="${RENDER_HOST:-swg-ocys.onrender.com}"
LOCAL_SOCKS_PORT="${LOCAL_SOCKS_PORT:-10808}"

mkdir -p "$APP_DIR"
chmod 700 "$APP_DIR"

say() {
  printf '%s\n' "$*"
}

fail() {
  printf 'Ошибка: %s\n' "$*" >&2
  exit 1
}

find_wstunnel() {
  if [[ -x "$WSTUNNEL_BIN" ]]; then
    return 0
  fi

  if command -v wstunnel >/dev/null 2>&1; then
    WSTUNNEL_BIN="$(command -v wstunnel)"
    return 0
  fi

  fail "не найден wstunnel. Положи бинарник в $HOME/bin/wstunnel и выполни chmod +x $HOME/bin/wstunnel"
}

load_secret() {
  if [[ ! -s "$SECRET_FILE" ]]; then
    say "Введи значение WSTUNNEL_PATH из Render. Ввод не отображается на экране."
    read -r -s -p 'WSTUNNEL_PATH: ' secret
    printf '\n'
    [[ -n "$secret" ]] || fail "секрет не может быть пустым"
    printf '%s' "$secret" > "$SECRET_FILE"
    chmod 600 "$SECRET_FILE"
    unset secret
  fi

  WSTUNNEL_PATH="$(cat "$SECRET_FILE")"
  [[ -n "$WSTUNNEL_PATH" ]] || fail "файл секрета пустой: $SECRET_FILE"
}

is_running() {
  [[ -s "$PID_FILE" ]] || return 1
  local pid
  pid="$(cat "$PID_FILE" 2>/dev/null || true)"
  [[ "$pid" =~ ^[0-9]+$ ]] || return 1
  kill -0 "$pid" 2>/dev/null
}

start_tunnel() {
  find_wstunnel
  load_secret

  if is_running; then
    say "wstunnel уже запущен. SOCKS5: 127.0.0.1:${LOCAL_SOCKS_PORT}"
    say "Лог: $LOG_FILE"
    exit 0
  fi

  rm -f "$PID_FILE"
  say "Запускаю wstunnel через wss://${RENDER_HOST}..."

  nohup "$WSTUNNEL_BIN" client \
    -L "socks5://127.0.0.1:${LOCAL_SOCKS_PORT}" \
    -P "$WSTUNNEL_PATH" \
    --tls-verify-certificate \
    --websocket-ping-frequency 30s \
    "wss://${RENDER_HOST}" \
    >> "$LOG_FILE" 2>&1 &

  local pid=$!
  printf '%s' "$pid" > "$PID_FILE"
  chmod 600 "$PID_FILE" "$LOG_FILE"
  sleep 2

  if is_running; then
    say "Готово. Локальный SOCKS5 поднят на 127.0.0.1:${LOCAL_SOCKS_PORT}."
    say "Теперь добавь в NekoBox/v2rayNG SOCKS5-сервер 127.0.0.1:${LOCAL_SOCKS_PORT} и включи VPN/TUN."
    say "Проверка: $0 status"
  else
    say "Процесс завершился. Последние строки лога:"
    tail -n 30 "$LOG_FILE" 2>/dev/null || true
    rm -f "$PID_FILE"
    exit 1
  fi
}

stop_tunnel() {
  if ! is_running; then
    rm -f "$PID_FILE"
    say "wstunnel не запущен."
    exit 0
  fi

  local pid
  pid="$(cat "$PID_FILE")"
  kill "$pid" 2>/dev/null || true
  sleep 1
  kill -9 "$pid" 2>/dev/null || true
  rm -f "$PID_FILE"
  say "wstunnel остановлен."
}

status_tunnel() {
  if is_running; then
    say "wstunnel работает, PID $(cat "$PID_FILE")."
    say "SOCKS5: 127.0.0.1:${LOCAL_SOCKS_PORT}"
    say "Render: wss://${RENDER_HOST}"
    say "Лог: $LOG_FILE"
  else
    say "wstunnel не запущен."
    [[ -f "$LOG_FILE" ]] && { say 'Последние строки лога:'; tail -n 20 "$LOG_FILE"; }
    exit 1
  fi
}

reset_secret() {
  rm -f "$SECRET_FILE"
  say "Секрет удалён. При следующем start Termux запросит его снова."
}

case "${1:-start}" in
  start) start_tunnel ;;
  stop) stop_tunnel ;;
  restart) stop_tunnel || true; start_tunnel ;;
  status) status_tunnel ;;
  logs) tail -f "$LOG_FILE" ;;
  reset-secret) reset_secret ;;
  *)
    say "Использование: $0 {start|stop|restart|status|logs|reset-secret}"
    exit 2
    ;;
esac
