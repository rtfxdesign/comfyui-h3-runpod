#!/usr/bin/env bash
# =============================================================================
#  start.sh — container entrypoint.
#  Optionally starts sshd, runs provisioning, then execs ComfyUI as PID 1.
# =============================================================================
set -Eeuo pipefail

COMFY_DIR="${COMFY_DIR:-/workspace/ComfyUI}"
COMFY_PORT="${COMFY_PORT:-8188}"

log() { printf '\033[36m[start]\033[0m %s\n' "$*"; }

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

if [[ "${SKIP_PROVISION:-0}" != "1" ]]; then
  /opt/provision/scripts/provision.sh
else
  log "SKIP_PROVISION=1 — skipping model/node provisioning"
fi

cd "$COMFY_DIR"
log "starting ComfyUI on 0.0.0.0:$COMFY_PORT"

# exec so ComfyUI becomes PID 1 and receives SIGTERM directly — otherwise the
# pod takes the full kill timeout to stop and can lose in-flight writes.
exec python main.py \
  --listen 0.0.0.0 \
  --port "$COMFY_PORT" \
  ${COMFY_EXTRA_ARGS:-}
