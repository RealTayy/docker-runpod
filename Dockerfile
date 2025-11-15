# syntax=docker/dockerfile:1
#
# Minimal CUDA + PyTorch runtime for ComfyUI on RunPod with persistent first-run setup.
# Defaults target CUDA 12.1. To rebuild for CUDA 11.8, set build args:
#   --build-arg CUDA_VERSION=11.8.0 --build-arg TORCH_CUDA=cu118
#
ARG CUDA_VERSION=12.1.1
ARG UBUNTU_VERSION=22.04
FROM nvidia/cuda:${CUDA_VERSION}-cudnn8-runtime-ubuntu${UBUNTU_VERSION}

ENV DEBIAN_FRONTEND=noninteractive     PIP_NO_CACHE_DIR=1     PYTHONUNBUFFERED=1     VOLUME_DIR=/runpod-volume     COMFY_DIR=/runpod-volume/ComfyUI     VENV_DIR=/runpod-volume/venv     PORT=8188     HOST=0.0.0.0     TORCH_CUDA=cu121

# OS packages
RUN apt-get update && apt-get install -y --no-install-recommends       python3 python3-venv python3-pip       git ffmpeg libgl1 libglib2.0-0       ca-certificates curl tini       build-essential     && rm -rf /var/lib/apt/lists/*

# Python tooling
RUN python3 -m pip install --upgrade pip wheel setuptools

# Pre-install PyTorch into the image to avoid re-downloading on first pod start.
# If you rebuild for CUDA 11.8, set TORCH_CUDA=cu118 at build time.
# Use CUDA-specific wheels from the cu121 index.
RUN python3 -m pip install --index-url https://download.pytorch.org/whl/${TORCH_CUDA}       torch==2.3.1+${TORCH_CUDA} torchvision==0.18.1+${TORCH_CUDA}

# Copy startup scripts
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
COPY update-comfy.sh /usr/local/bin/update-comfy.sh
RUN chmod +x /usr/local/bin/entrypoint.sh /usr/local/bin/update-comfy.sh

EXPOSE 8188

ENTRYPOINT ["/usr/bin/tini","--"]
CMD ["/usr/local/bin/entrypoint.sh"]
