#!/usr/bin/env bash
set -Eeuo pipefail

# --------- Config (env-overridable) ----------
: "${VOLUME_DIR:=/runpod-volume}"
: "${COMFY_DIR:=${VOLUME_DIR}/ComfyUI}"
: "${VENV_DIR:=${VOLUME_DIR}/venv}"
: "${HOST:=0.0.0.0}"
: "${PORT:=8188}"

: "${ENABLE_JUPYTER:=1}"
: "${JUPYTER_PORT:=8888}"
: "${JUPYTER_TOKEN:=}"        # persisted if empty

: "${ENABLE_CODE_SERVER:=1}"
: "${CODE_SERVER_PORT:=8443}"
: "${CODE_SERVER_PASSWORD:=Just55Smile}" # persisted if empty
# --------------------------------------------

log(){ echo "[$(date -Iseconds)] $*"; }

log "[Boot] VOLUME_DIR=${VOLUME_DIR}"
log "[Boot] COMFY_DIR=${COMFY_DIR}"
log "[Boot] VENV_DIR=${VENV_DIR}"
log "[Boot] Services -> ComfyUI:${PORT}  Jupyter:${ENABLE_JUPYTER}@${JUPYTER_PORT}  code-server:${ENABLE_CODE_SERVER}@${CODE_SERVER_PORT}"

mkdir -p "${VOLUME_DIR}/logs" "${VOLUME_DIR}/jupyter" "${VOLUME_DIR}/code-server"

# --------- Singleton lock to prevent thrash ----------
LOCKFILE="${VOLUME_DIR}/.entry.lock"
exec 9>"${LOCKFILE}"
if ! flock -n 9; then
  log "[Lock] Another entrypoint instance is running; idling for inspection."
  exec tail -f /dev/null
fi

# --------- First-run install (persistent) ----------
first_run=0
if [ ! -d "${COMFY_DIR}" ]; then
  log "[Init] Cloning ComfyUI (first run)..."
  mkdir -p "${VOLUME_DIR}"
  git clone --depth=1 https://github.com/comfyanonymous/ComfyUI.git "${COMFY_DIR}"
  first_run=1
fi

if [ ! -d "${VENV_DIR}" ]; then
  log "[Init] Creating Python venv (first run)..."
  python3 -m venv --system-site-packages "${VENV_DIR}"
  first_run=1
fi

# Activate venv
# shellcheck disable=SC1090
source "${VENV_DIR}/bin/activate"

if [ ! -f "${VENV_DIR}/.requirements_installed" ]; then
  log "[Init] Installing ComfyUI requirements (first run)..."
  python3 -m pip install --upgrade pip wheel setuptools
  if [ -f "${COMFY_DIR}/requirements.txt" ]; then
    python3 -m pip install -r "${COMFY_DIR}/requirements.txt"
  fi
  touch "${VENV_DIR}/.requirements_installed"
  first_run=1
fi

# No auto-update unless explicitly requested
if [ "${COMFY_NO_AUTO_UPDATE:-1}" != "0" ]; then
  log "[Init] Auto-update disabled (COMFY_NO_AUTO_UPDATE=${COMFY_NO_AUTO_UPDATE:-1})."
else
  log "[Init] Auto-update enabled once (git pull + pip sync)."
  (cd "${COMFY_DIR}" && git pull --ff-only || true)
  if [ -f "${COMFY_DIR}/requirements.txt" ]; then
    python3 -m pip install -r "${COMFY_DIR}/requirements.txt"
  fi
fi

if [ $first_run -eq 1 ]; then
  log "[Init] First-run initialization complete."
else
  log "[Init] Existing installation detected. Skipping updates."
fi

# --------- Stable, SIGPIPE-free credential persistence ----------
rand24() { tr -dc 'A-Za-z0-9' </dev/urandom | head -c 24; }

if [ "${ENABLE_JUPYTER}" = "1" ]; then
  mkdir -p "${VOLUME_DIR}/jupyter"
  TOKEN_FILE="${VOLUME_DIR}/jupyter/.token"
  if [ -z "${JUPYTER_TOKEN}" ]; then
    if [ -f "${TOKEN_FILE}" ]; then
      JUPYTER_TOKEN="$(cat "${TOKEN_FILE}")"
    else
      JUPYTER_TOKEN="$(rand24)"
      echo "${JUPYTER_TOKEN}" > "${TOKEN_FILE}"
      log "[Jupyter] Token persisted at ${TOKEN_FILE}"
    fi
  fi
fi

if [ "${ENABLE_CODE_SERVER}" = "1" ]; then
  mkdir -p "${VOLUME_DIR}/code-server"
  PASS_FILE="${VOLUME_DIR}/code-server/.password"
  if [ -z "${CODE_SERVER_PASSWORD}" ]; then
    if [ -f "${PASS_FILE}" ]; then
      CODE_SERVER_PASSWORD="$(cat "${PASS_FILE}")"
    else
      CODE_SERVER_PASSWORD="$(rand24)"
      echo "${CODE_SERVER_PASSWORD}" > "${PASS_FILE}"
      log "[code-server] Password persisted at ${PASS_FILE}"
    fi
  fi
fi

# --------- Side services (background) ----------
start_jupyter() {
  [ "${ENABLE_JUPYTER}" = "1" ] || return 0
  log "[Jupyter] Starting JupyterLab on 0.0.0.0:${JUPYTER_PORT}"
  python3 -m jupyterlab \
    --ServerApp.ip=0.0.0.0 \
    --ServerApp.port="${JUPYTER_PORT}" \
    --ServerApp.token="${JUPYTER_TOKEN}" \
    --ServerApp.allow_remote_access=True \
    --no-browser \
    > "${VOLUME_DIR}/logs/jupyter.log" 2>&1 &
  echo $! > "${VOLUME_DIR}/logs/jupyter.pid"
}

start_code_server() {
  [ "${ENABLE_CODE_SERVER}" = "1" ] || return 0
  log "[code-server] Starting on 0.0.0.0:${CODE_SERVER_PORT}"
  PASSWORD="${CODE_SERVER_PASSWORD}" code-server \
    --bind-addr "0.0.0.0:${CODE_SERVER_PORT}" \
    --auth password \
    --user-data-dir "${VOLUME_DIR}/code-server/user-data" \
    --extensions-dir "${VOLUME_DIR}/code-server/extensions" \
    --disable-telemetry \
    > "${VOLUME_DIR}/logs/code-server.log" 2>&1 &
  echo $! > "${VOLUME_DIR}/logs/code-server.pid"
}

start_jupyter
start_code_server

# --------- Defensive port check for ComfyUI ----------
is_port_busy() {
  command -v ss >/dev/null 2>&1 || return 1
  ss -ltnH | awk '{print $4}' | grep -q ":${PORT}\$"
}

if is_port_busy; then
  log "[WARN] Port ${PORT} already in use before ComfyUI launch. Aborting launch and idling."
  ss -ltnp || true
  exec tail -f /dev/null
fi

# Final “just-in-time” check + launch
log "[Start] Launching ComfyUI on ${HOST}:${PORT} ..."
cd "${COMFY_DIR}"

cleanup() {
  log "[Shutdown] Stopping side services..."
  for pidfile in "${VOLUME_DIR}/logs"/*.pid; do
    [ -f "$pidfile" ] || continue
    pid="$(cat "$pidfile" || true)"
    [ -n "$pid" ] && kill -TERM "$pid" 2>/dev/null || true
  done
}
trap cleanup SIGINT SIGTERM

# Run ComfyUI in the foreground (keeps container up)
exec python3 main.py --listen "${HOST}" --port "${PORT}" --disable-auto-launch
