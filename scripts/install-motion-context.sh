#!/usr/bin/env bash
# =============================================================================
#  install-motion-context.sh — OPTIONAL. Installs NikoDemon80's
#  ComfyUI-H3-Motion-Context pinned to v0.7.1 (released 2026-10-18).
#
#  Run on the pod:     bash /opt/provision/scripts/install-motion-context.sh
#  or at every boot:   H3_INSTALL_MOTION_CONTEXT=1  (pod env var)
#  then restart ComfyUI.
#
#  READ THIS FIRST — why it is not in nodes.conf:
#
#  * Motion-Context 0.7.1 requires ComfyUI >= 0.34.0 (its CHANGELOG). The image
#    pins ComfyUI v0.44.0, so the pack itself is fine for its OWN chaining
#    nodes (MiniMaxH3MotionContext*, H3 Join Match, H3 Refine Blend, ...) and
#    its example workflow (example_workflows/H3-Motion-Context-v0.7.json inside
#    the pack).
#
#  * It does NOT make `continuity = context_pin` work in this repo's Multishot
#    workflows. ComfyUI-H3-Multishot v2.7.2 runs a pre-flight
#    (h3_multishot_utils.py) that refuses any Motion-Context exposing only
#    `_ensure_layout_ok` — i.e. every release from 0.4.0 on, including 0.7.1 —
#    with "Motion-Context 0.4.0 detected ... Install Motion-Context 0.3.1".
#    And 0.3.1 is for ComfyUI 0.33.x and older only.
#
#    So on this stack set `continuity` to `first_frame` on the
#    H3MultishotMemorySampler in H3_Extend_Take / H3_Seamless_Chain_v2 (that is
#    the model's own trained hand-off; UPSTREAM-INSTALL.md documents it).
#
#  Idempotent: an existing checkout is left alone (set MOTION_CONTEXT_SYNC=1 to
#  move it to the pin).
# =============================================================================
set -Eeuo pipefail

COMFY_DIR="${COMFY_DIR:-/workspace/ComfyUI}"
MC_URL="https://github.com/NikoDemon80/ComfyUI-H3-Motion-Context"
MC_REF="${MOTION_CONTEXT_REF:-v0.7.1}"
DEST="$COMFY_DIR/custom_nodes/ComfyUI-H3-Motion-Context"

log()  { printf '\033[36m[motion-context]\033[0m %s\n' "$*"; }
warn() { printf '\033[33m[motion-context] WARN:\033[0m %s\n' "$*" >&2; }

mkdir -p "$COMFY_DIR/custom_nodes"

if [[ -d "$DEST" ]]; then
  log "already installed at $DEST"
  if [[ "${MOTION_CONTEXT_SYNC:-0}" == "1" ]]; then
    log "moving to $MC_REF"
    git -C "$DEST" fetch -q --depth 1 origin "$MC_REF"
    git -C "$DEST" checkout -q FETCH_HEAD
  fi
else
  log "cloning $MC_URL @ $MC_REF"
  git -c advice.detachedHead=false clone -q --depth 1 --branch "$MC_REF" "$MC_URL" "$DEST"
fi

# v0.7.1 ships no requirements.txt; install one only if a future ref adds it.
if [[ -f "$DEST/requirements.txt" ]]; then
  pip install --no-cache-dir -r "$DEST/requirements.txt"
fi

warn "Multishot v2.7.2 refuses Motion-Context >= 0.4.0 for continuity=context_pin."
warn "Use continuity=first_frame in the Multishot workflows; use this pack's own nodes/workflow for MC chaining."
log "done — restart ComfyUI to load it."
