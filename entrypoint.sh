#!/usr/bin/env bash
set -Eeuo pipefail

# --------- Config (env-overridable) ----------
: "${VOLUME_DIR:=/workspace}"
: "${COMFY_DIR:=${VOLUME_DIR}/ComfyUI}"
: "${VENV_DIR:=${VOLUME_DIR}/venv}"
: "${HOST:=0.0.0.0}"
: "${PORT:=8188}"

: "${ENABLE_JUPYTER:=1}"
: "${JUPYTER_PORT:=8888}"
: "${JUPYTER_TOKEN:=}"              # if empty and JUPYTER_NO_AUTH=0, auto-generate & persist
: "${JUPYTER_NO_AUTH:=1}"           # 1 => no token/password (your request)
: "${JUPYTER_THEME:=JupyterLab Dark}"  # default JupyterLab theme

: "${ENABLE_CODE_SERVER:=1}"
: "${CODE_SERVER_PORT:=8443}"
: "${CODE_SERVER_AUTH:=none}"       # "none" or "password"
: "${CODE_SERVER_PASSWORD:=}"       # used only when CODE_SERVER_AUTH=password
: "${CODE_SERVER_THEME:=Default Dark+}"  # VS Code theme name for code-server

: "${COMFY_NO_AUTO_UPDATE:=1}"
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
  # Ensure JupyterLab is available in the venv
  if [ "${ENABLE_JUPYTER}" = "1" ]; then
    log "[Init] Installing JupyterLab + ipykernel into venv (first run)..."
    python3 -m pip install "jupyterlab>=4" "ipykernel"
  fi
  touch "${VENV_DIR}/.requirements_installed"
  first_run=1
fi

# Ensure Jupyter kernel is available even on existing installs
if [ "${ENABLE_JUPYTER}" = "1" ]; then
  if ! python3 -m pip show ipykernel >/dev/null 2>&1; then
    log "[Init] Installing ipykernel into venv (existing install)..."
    python3 -m pip install "ipykernel"
  fi
  log "[Init] Ensuring Jupyter ipykernel is registered for this venv..."
  python3 -m ipykernel install --sys-prefix \
    --name comfy-venv \
    --display-name "Python 3 (Comfy venv)" >/dev/null 2>&1 || true
fi

# No auto-update unless explicitly requested
if [ "${COMFY_NO_AUTO_UPDATE}" != "0" ]; then
  log "[Init] Auto-update disabled (COMFY_NO_AUTO_UPDATE=${COMFY_NO_AUTO_UPDATE})."
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

# --------- SIGPIPE-free credential helpers ----------
py_alnum_24() {
  # Generates 24-char [A-Za-z0-9] string via Python (no pipes => safe under pipefail)
  python3 - "$@" <<'PY'
import secrets, string
alphabet = string.ascii_letters + string.digits
print(''.join(secrets.choice(alphabet) for _ in range(24)))
PY
}

# --------- Persist Jupyter token / disable auth ----------
if [ "${ENABLE_JUPYTER}" = "1" ]; then
  mkdir -p "${VOLUME_DIR}/jupyter"
  TOKEN_FILE="${VOLUME_DIR}/jupyter/.token"
  if [ "${JUPYTER_NO_AUTH}" = "1" ]; then
    # Explicitly disable auth
    JUPYTER_TOKEN=""
    log "[Jupyter] Auth disabled (JUPYTER_NO_AUTH=1)."
  else
    # Token required -> generate/persist if not supplied
    if [ -z "${JUPYTER_TOKEN}" ]; then
      if [ -f "${TOKEN_FILE}" ]; then
        JUPYTER_TOKEN="$(cat "${TOKEN_FILE}")"
      else
        JUPYTER_TOKEN="$(py_alnum_24)"
        echo "${JUPYTER_TOKEN}" > "${TOKEN_FILE}"
        log "[Jupyter] Token persisted at ${TOKEN_FILE}"
      fi
    fi
  fi
fi

# --------- Jupyter theme / settings ----------
if [ "${ENABLE_JUPYTER}" = "1" ]; then
  export JUPYTERLAB_SETTINGS_DIR="${VOLUME_DIR}/jupyter/lab/user-settings"
  THEME_SETTINGS_FILE="${JUPYTERLAB_SETTINGS_DIR}/@jupyterlab/apputils-extension/themes.jupyterlab-settings"
  if [ ! -f "${THEME_SETTINGS_FILE}" ]; then
    mkdir -p "$(dirname "${THEME_SETTINGS_FILE}")"
    cat > "${THEME_SETTINGS_FILE}" <<EOF
{
  "theme": "${JUPYTER_THEME}"
}
EOF
    log "[Jupyter] Initialized JupyterLab theme settings: ${JUPYTER_THEME}"
  fi
fi

# --------- Persist code-server password (if using password auth) ----------
if [ "${ENABLE_CODE_SERVER}" = "1" ] && [ "${CODE_SERVER_AUTH}" = "password" ]; then
  mkdir -p "${VOLUME_DIR}/code-server"
  PASS_FILE="${VOLUME_DIR}/code-server/.password"
  if [ -z "${CODE_SERVER_PASSWORD}" ]; then
    if [ -f "${PASS_FILE}" ]; then
      CODE_SERVER_PASSWORD="$(cat "${PASS_FILE}")"
    else
      CODE_SERVER_PASSWORD="$(py_alnum_24)"
      echo "${CODE_SERVER_PASSWORD}" > "${PASS_FILE}"
      log "[code-server] Password persisted at ${PASS_FILE}"
    fi
  fi
else
  if [ "${ENABLE_CODE_SERVER}" = "1" ]; then
    log "[code-server] Auth disabled (CODE_SERVER_AUTH=${CODE_SERVER_AUTH})."
  fi
fi

# --------- Initialize / update code-server settings (theme, trust, etc.) ----------
if [ "${ENABLE_CODE_SERVER}" = "1" ]; then
  SETTINGS_DIR="${VOLUME_DIR}/code-server/user-data/User"
  SETTINGS_FILE="${SETTINGS_DIR}/settings.json"
  mkdir -p "${SETTINGS_DIR}"
  python3 - "${SETTINGS_FILE}" "${CODE_SERVER_THEME}" <<'PY'
import json, os, sys

path, theme = sys.argv[1], sys.argv[2]
data = {}
if os.path.exists(path):
    try:
        with open(path) as f:
            data = json.load(f)
    except Exception:
        data = {}

# Set defaults without overriding user-changed settings
data.setdefault("workbench.colorTheme", theme)
# Disable workspace trust prompts
data.setdefault("security.workspace.trust.enabled", False)

os.makedirs(os.path.dirname(path), exist_ok=True)
with open(path, "w") as f:
    json.dump(data, f, indent=2)
PY
  log "[code-server] Ensured settings.json (theme=${CODE_SERVER_THEME}, workspace trust disabled)."
fi

# --------- Side services (background) ----------
start_jupyter() {
  [ "${ENABLE_JUPYTER}" = "1" ] || return 0
  log "[Jupyter] Starting JupyterLab on 0.0.0.0:${JUPYTER_PORT} (no_auth=${JUPYTER_NO_AUTH})"
  local jupyter_log="${VOLUME_DIR}/logs/jupyter.log"
  if [ "${JUPYTER_NO_AUTH}" = "1" ]; then
    python3 -m jupyterlab \
      --ServerApp.ip=0.0.0.0 \
      --ServerApp.port="${JUPYTER_PORT}" \
      --ServerApp.token= \
      --ServerApp.password= \
      --ServerApp.allow_remote_access=True \
      --ServerApp.trust_xheaders=True \
      --ServerApp.allow_origin='*' \
      --ServerApp.disable_check_xsrf=True \
      --ServerApp.allow_root=True \
      --LabApp.app_dir=/usr/local/share/jupyter/lab \
      --no-browser \
      > >(tee -a "${jupyter_log}") 2>&1 &
  else
    python3 -m jupyterlab \
      --ServerApp.ip=0.0.0.0 \
      --ServerApp.port="${JUPYTER_PORT}" \
      --ServerApp.token="${JUPYTER_TOKEN}" \
      --ServerApp.allow_remote_access=True \
      --ServerApp.trust_xheaders=True \
      --ServerApp.allow_origin='*' \
      --ServerApp.disable_check_xsrf=True \
      --ServerApp.allow_root=True \
      --LabApp.app_dir=/usr/local/share/jupyter/lab \
      --no-browser \
      > >(tee -a "${jupyter_log}") 2>&1 &
  fi
  jupyter_pid=$!
  echo "${jupyter_pid}" > "${VOLUME_DIR}/logs/jupyter.pid"

  # Lightweight health check: is the port actually listening?
  sleep 3
  if command -v ss >/dev/null 2>&1; then
    if ss -ltnH | awk '{print $4}' | grep -q ":${JUPYTER_PORT}\$"; then
      log "[Jupyter] Port ${JUPYTER_PORT} is listening (pid=${jupyter_pid})."
    else
      log "[Jupyter] WARNING: Jupyter did not open port ${JUPYTER_PORT}; see ${jupyter_log}"
    fi
  fi
}

start_code_server() {
  [ "${ENABLE_CODE_SERVER}" = "1" ] || return 0
  log "[code-server] Starting on 0.0.0.0:${CODE_SERVER_PORT} (auth=${CODE_SERVER_AUTH})"
  if [ "${CODE_SERVER_AUTH}" = "password" ]; then
    PASSWORD="${CODE_SERVER_PASSWORD}" code-server \
      --bind-addr "0.0.0.0:${CODE_SERVER_PORT}" \
      --auth password \
      --user-data-dir "${VOLUME_DIR}/code-server/user-data" \
      --extensions-dir "${VOLUME_DIR}/code-server/extensions" \
      --disable-telemetry \
      > "${VOLUME_DIR}/logs/code-server.log" 2>&1 &
  else
    code-server \
      --bind-addr "0.0.0.0:${CODE_SERVER_PORT}" \
      --auth none \
      --user-data-dir "${VOLUME_DIR}/code-server/user-data" \
      --extensions-dir "${VOLUME_DIR}/code-server/extensions" \
      --disable-telemetry \
      > "${VOLUME_DIR}/logs/code-server.log" 2>&1 &
  fi
  echo $! > "${VOLUME_DIR}/logs/code-server.pid"
}

# --------- Defensive port check for ComfyUI ----------
is_port_busy() {
  command -v ss >/dev/null 2>&1 || return 1
  ss -ltnH | awk '{print $4}' | grep -q ":${PORT}\$" && return 0 || return 1
}

start_jupyter
start_code_server

if is_port_busy; then
  log "[WARN] Port ${PORT} already in use before ComfyUI launch. Aborting launch and idling."
  ss -ltnp || true
  exec tail -f /dev/null
fi

# --------- Launch ComfyUI (foreground via wait) ----------
log "[Start] Launching ComfyUI on ${HOST}:${PORT} ..."
cd "${COMFY_DIR}"

cleanup() {
  log "[Shutdown] Stopping services..."
  # stop ComfyUI if running
  if [ -n "${COMFY_PID:-}" ]; then
    kill -TERM "${COMFY_PID}" 2>/dev/null || true
  fi
  # stop side services
  for pidfile in "${VOLUME_DIR}/logs"/*.pid; do
    [ -f "$pidfile" ] || continue
    pid="$(cat "$pidfile" || true)"
    [ -n "$pid" ] && kill -TERM "$pid" 2>/dev/null || true
  done
}
trap cleanup SIGINT SIGTERM

python3 main.py --listen "${HOST}" --port "${PORT}" --disable-auto-launch \
  > "${VOLUME_DIR}/logs/comfy.log" 2>&1 &
COMFY_PID=$!
echo "${COMFY_PID}" > "${VOLUME_DIR}/logs/comfy.pid"

# Keep container alive as long as ComfyUI is alive
wait "${COMFY_PID}"
