# RunPod + ComfyUI + JupyterLab + code-server (v3 with port guard)

This version:
- Starts **ComfyUI** in the foreground on `PORT` (default **8188**).
- Starts **JupyterLab** (8888) and **code-server** (8443) in the background.
- **Preflight check** frees `PORT` if something is already bound (defensive).
- Keeps ComfyUI **persistent** on your volume and **never auto-updates** unless you ask.

## Build & Push (amd64)
```bash
docker buildx build --platform linux/amd64   -t maithe09/runpod-comfy:latest   --push .
```

## RunPod Template
- Image: your pushed tag
- Volume: mount to `/runpod-volume`
- HTTP Services: `8188` (ComfyUI), `8888` (Jupyter), `8443` (code-server)
- Env (optional):
  - `JUPYTER_TOKEN` (if you want Jupyter auth; otherwise it runs without a token by default)
  - `CODE_SERVER_AUTH` (`none` by default; set to `password` to require a password)
  - `CODE_SERVER_PASSWORD` (used only when `CODE_SERVER_AUTH=password`; auto-generated and persisted otherwise)

## Quick workaround if 8188 conflicts
Set `PORT=8189` in the template and add an HTTP Service for 8189. Then switch back to 8188 later if desired.
