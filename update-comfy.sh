#!/usr/bin/env bash
set -euo pipefail
: "${VOLUME_DIR:=/workspace}"
: "${COMFY_DIR:=${VOLUME_DIR}/ComfyUI}"
: "${VENV_DIR:=${VOLUME_DIR}/venv}"

if [ ! -d "$COMFY_DIR" ]; then
  echo "ComfyUI not found at ${COMFY_DIR}. Nothing to update."
  exit 1
fi

echo "[Manual Update] Updating ComfyUI repo and requirements..."
cd "$COMFY_DIR"
git pull --ff-only

source "${VENV_DIR}/bin/activate"
pip install --upgrade pip wheel setuptools ninja
if [ -f requirements.txt ]; then
    pip install -r requirements.txt
fi
echo "[Manual Update] Done."
