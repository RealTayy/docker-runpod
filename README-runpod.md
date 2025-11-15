# RunPod + ComfyUI (persistent, no auto-update)

This template gives you a Docker image that **installs ComfyUI once** into your RunPod Network Volume
and **never updates or overwrites** it on subsequent pod launches unless you explicitly tell it to.

## What you get

- CUDA-based runtime (Ubuntu 22.04) with **PyTorch 2.3.1** preinstalled (CUDA **12.1** by default).
- First-run bootstrap that clones ComfyUI to `/runpod-volume/ComfyUI` and creates a venv in `/runpod-volume/venv`.
- Subsequent starts skip cloning/reinstalling and simply launch ComfyUI.
- Manual update script: `update-comfy.sh` (never runs automatically).
- ComfyUI served on port **8188** at `http://<pod-hostname>:8188`.

> To rebuild for CUDA 11.8, pass build args during `docker build`:
> `--build-arg CUDA_VERSION=11.8.0 --build-arg TORCH_CUDA=cu118`

## Build & Push

```bash
# From your project folder
docker login
# Optional: make sure buildx is ready
docker buildx ls          # should show "docker-desktop" builder
# If you don't see an active builder, you can do:
# docker buildx create --use

# Build AND push for RunPod's architecture
docker buildx build \
  --platform linux/amd64 \
  -t maithe09/runpod-comfy:latest \
  --push \
  .
```
