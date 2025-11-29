# CUDA 12.8 devel + cuDNN on Ubuntu 22.04 (for SageAttention build on newer GPUs)
FROM nvidia/cuda:12.8.0-cudnn-devel-ubuntu22.04

ENV DEBIAN_FRONTEND=noninteractive \
    PIP_DISABLE_PIP_VERSION_CHECK=1 \
    PYTHONUNBUFFERED=1

# OS deps (git/venv/curl/wget + small utils for net + video libs used by nodes)
RUN apt-get update && apt-get install -y --no-install-recommends \
    python3 python3-venv python3-pip python3-dev \
    git curl wget ca-certificates \
    iproute2 procps lsof \
    ffmpeg libgl1 libglib2.0-0 \
    build-essential \
 && rm -rf /var/lib/apt/lists/*

ENV CUDA_HOME=/usr/local/cuda
ENV PATH=/usr/local/cuda/bin:${PATH}

# code-server (standalone install script)
RUN curl -fsSL https://code-server.dev/install.sh | sh

# JupyterLab system-wide (entrypoint will run it from here)
RUN python3 -m pip install --no-cache-dir --upgrade pip \
 && python3 -m pip install --no-cache-dir jupyterlab

# Copy your entrypoint + helper
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
COPY update-comfy.sh /usr/local/bin/update-comfy.sh
RUN chmod +x /usr/local/bin/entrypoint.sh /usr/local/bin/update-comfy.sh

# Sensible defaults; override in the RunPod template if you like
ENV COMFY_NO_AUTO_UPDATE=1 \
    ENABLE_JUPYTER=1 JUPYTER_PORT=8888 \
    ENABLE_CODE_SERVER=1 CODE_SERVER_PORT=8443

# Services you will expose as HTTP in the RunPod template
EXPOSE 8188 8888 8443

# IMPORTANT:
# Keep NVIDIA's ENTRYPOINT from the base image and pass our script as CMD.
# On RunPod this will execute as:
#   /sbin/docker-init -- /opt/nvidia/nvidia_entrypoint.sh /usr/local/bin/entrypoint.sh
CMD ["/usr/local/bin/entrypoint.sh"]
