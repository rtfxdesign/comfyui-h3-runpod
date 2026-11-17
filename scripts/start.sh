#!/usr/bin/env bash
# =============================================================================
#  start.sh — container entrypoint.
#  Optionally starts sshd, runs provisioning, then execs ComfyUI as PID 1.
# =============================================================================
set -Eeuo pipefail

COMFY_DIR="${COMFY_DIR:-/workspace/ComfyUI}"
COMFY_PORT="${COMFY_PORT:-8188}"
SCRIPTS_DIR="${SCRIPTS_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"

log() { printf '\033[36m[start]\033[0m %s\n' "$*"; }

# CIVITAI_TOKEN is accepted as an alias for CIVITAI_API_TOKEN.
if [[ -z "${CIVITAI_API_TOKEN:-}" && -n "${CIVITAI_TOKEN:-}" ]]; then
  export CIVITAI_API_TOKEN="$CIVITAI_TOKEN"
fi

# -----------------------------------------------------------------------------
# RunPod mounts the persistent volume at /workspace. The image builds ComfyUI
# at /opt/ComfyUI so it survives having an empty volume mounted over
# /workspace; first boot copies it across. Without this, attaching a fresh
# network volume would shadow the install and the pod would start empty.
# -----------------------------------------------------------------------------
if [[ ! -d "$COMFY_DIR" ]]; then
  log "seeding $COMFY_DIR from image build at /opt/ComfyUI"
  mkdir -p "$(dirname "$COMFY_DIR")"
  cp -a /opt/ComfyUI "$COMFY_DIR"
fi

# RunPod injects PUBLIC_KEY for SSH access; only bother if it is actually set.
if [[ -n "${PUBLIC_KEY:-}" ]]; then
  log "configuring ssh"
  mkdir -p ~/.ssh && chmod 700 ~/.ssh
  echo "$PUBLIC_KEY" >> ~/.ssh/authorized_keys
  chmod 600 ~/.ssh/authorized_keys
  service ssh start || log "sshd failed to start (continuing)"
fi

# JupyterLab file manager on :8888 — upload LoRAs into models/loras, pull
# rendered videos out of output/, edit h3_refs. Gated on JUPYTER_PASSWORD so
# an unset variable never exposes an unauthenticated server; the password is
# the login token. Rooted at /workspace so everything that matters is in reach.
if [[ -n "${JUPYTER_PASSWORD:-}" ]]; then
  log "starting JupyterLab on 0.0.0.0:8888"
  jupyter lab \
    --allow-root --no-browser \
    --ip=0.0.0.0 --port 8888 \
    --ServerApp.token="$JUPYTER_PASSWORD" \
    --ServerApp.root_dir=/workspace \
    --ServerApp.terminals_enabled=True \
    >/tmp/jupyter.log 2>&1 &
else
  log "JUPYTER_PASSWORD not set — JupyterLab disabled"
fi

if [[ "${SKIP_PROVISION:-0}" != "1" ]]; then
  "$SCRIPTS_DIR/provision.sh"
else
  log "SKIP_PROVISION=1 — skipping model/node provisioning"
fi

# -----------------------------------------------------------------------------
# Launch flags.
#   --enable-manager   ComfyUI-Manager (pip package comfyui_manager, v0.45.0
#                      way). H3_ENABLE_MANAGER=0 turns it off.
#   --highvram         H3_HIGHVRAM=auto (default): only when GPU 0 has
#                      >= 140000 MiB (H200 141 GB, B200 180 GB). There the
#                      image model, a video model and the bf16 text encoder
#                      (40 + 40 + 52 GB) all fit, so keeping them resident
#                      skips reloads. On 80-96 GB cards it would force
#                      unload/reload churn instead, so it stays off.
#                      H3_HIGHVRAM=1 forces it on, 0 forces it off.
#   COMFY_EXTRA_ARGS   anything else, e.g. --disable-dynamic-vram (fixes the
#                      VBAR MemoryError seen in TextGenerateV2 on the home PC;
#                      add --disable-pinned-memory too if it persists),
#                      --lowvram, --use-sage-attention.
# -----------------------------------------------------------------------------
# shellcheck source=gpu_tier.sh
source "$SCRIPTS_DIR/gpu_tier.sh"
resolve_tier
args=(--listen 0.0.0.0 --port "$COMFY_PORT")

if [[ "${H3_ENABLE_MANAGER:-1}" == "1" ]] && python -c "import comfyui_manager" >/dev/null 2>&1; then
  args+=(--enable-manager)
fi

case "${H3_HIGHVRAM:-auto}" in
  1|true|yes) args+=(--highvram) ;;
  auto)       if (( H3_GPU_MIB >= 140000 )); then args+=(--highvram); fi ;;
esac

cd "$COMFY_DIR"
log "GPU 0: ${H3_GPU_MIB} MiB (cc ${H3_GPU_CC}); tier $H3_TIER_RESOLVED ($H3_TIER_REASON)"
log "starting ComfyUI: python main.py ${args[*]} ${COMFY_EXTRA_ARGS:-}"

# exec so ComfyUI becomes PID 1 and receives SIGTERM directly — otherwise the
# pod takes the full kill timeout to stop and can lose in-flight writes.
# shellcheck disable=SC2086
exec python main.py "${args[@]}" ${COMFY_EXTRA_ARGS:-}
