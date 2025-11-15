#!/usr/bin/env bash
set -euo pipefail

: "${VOLUME_DIR:=/runpod-volume}"
: "${COMFY_DIR:=${VOLUME_DIR}/ComfyUI}"
: "${VENV_DIR:=${VOLUME_DIR}/venv}"
: "${PORT:=8188}"
: "${HOST:=0.0.0.0}"

echo "[Boot] VOLUME_DIR=${VOLUME_DIR}"
echo "[Boot] COMFY_DIR=${COMFY_DIR}"
echo "[Boot] VENV_DIR=${VENV_DIR}"

first_run=0

if [ ! -d "$COMFY_DIR" ]; then
  echo "[Init] Cloning ComfyUI into ${COMFY_DIR} (first run)..."
  mkdir -p "$VOLUME_DIR"
  git clone --depth=1 https://github.com/comfyanonymous/ComfyUI.git "$COMFY_DIR"
  first_run=1
fi

if [ ! -d "$VENV_DIR" ]; then
  echo "[Init] Creating Python venv at ${VENV_DIR} (first run)..."
  python3 -m venv --system-site-packages "$VENV_DIR"
  first_run=1
fi

# Always activate venv for ComfyUI and custom-node installs
source "${VENV_DIR}/bin/activate"

# Only install requirements on first run (or if marker absent)
if [ ! -f "${VENV_DIR}/.requirements_installed" ]; then
  echo "[Init] Installing ComfyUI Python requirements (first run)..."
  pip install --upgrade pip wheel setuptools
  if [ -f "${COMFY_DIR}/requirements.txt" ]; then
      pip install -r "${COMFY_DIR}/requirements.txt"
  fi
  touch "${VENV_DIR}/.requirements_installed"
  first_run=1
fi

# DO NOT auto-update existing installs unless explicitly requested.
if [ "${COMFY_NO_AUTO_UPDATE:-1}" != "0" ]; then
  echo "[Init] Auto-update is disabled. Existing files will not be modified."
else
  echo "[Init] COMFY_NO_AUTO_UPDATE=0 -> performing a one-off update."
  (cd "${COMFY_DIR}" && git pull --ff-only || true)
  if [ -f "${COMFY_DIR}/requirements.txt" ]; then
      pip install -r "${COMFY_DIR}/requirements.txt"
  fi
fi

if [ $first_run -eq 1 ]; then
  echo "[Init] First-run initialization complete."
else
  echo "[Init] Existing installation detected. Skipping updates."
fi

echo "[Start] Launching ComfyUI on ${HOST}:${PORT} ..."
cd "${COMFY_DIR}"
exec python3 main.py --listen "${HOST}" --port "${PORT}" --disable-auto-launch
