#!/usr/bin/env bash
# =============================================================================
#  provision.sh — install custom nodes and download models at container start.
#
#  Runs on every boot and is IDEMPOTENT: anything already on disk is skipped,
#  so a restart on a persistent RunPod volume costs seconds, not a re-download.
# =============================================================================
set -Eeuo pipefail

COMFY_DIR="${COMFY_DIR:-/workspace/ComfyUI}"
CONFIG_DIR="${CONFIG_DIR:-/opt/provision/config}"
MODELS_CONF="${MODELS_CONF:-$CONFIG_DIR/models.conf}"
NODES_CONF="${NODES_CONF:-$CONFIG_DIR/nodes.conf}"

log()  { printf '\033[36m[provision]\033[0m %s\n' "$*"; }
warn() { printf '\033[33m[provision] WARN:\033[0m %s\n' "$*" >&2; }
err()  { printf '\033[31m[provision] ERROR:\033[0m %s\n' "$*" >&2; }

# A model failure must not take the pod down — ComfyUI should still come up so
# you can look around and fix it. Track failures and report at the end instead.
FAILED=0

# -----------------------------------------------------------------------------
# Remote config override: point PROVISION_CONFIG_URL at a raw GitHub URL to
# change the model set WITHOUT rebuilding the image. This is the whole reason
# provisioning is a boot-time step rather than baked into a Docker layer.
# -----------------------------------------------------------------------------
if [[ -n "${PROVISION_CONFIG_URL:-}" ]]; then
  log "fetching remote models.conf: $PROVISION_CONFIG_URL"
  if curl -fsSL "$PROVISION_CONFIG_URL" -o /tmp/models.conf; then
    MODELS_CONF=/tmp/models.conf
  else
    warn "could not fetch remote config; falling back to baked-in $MODELS_CONF"
  fi
fi

if [[ -n "${PROVISION_NODES_URL:-}" ]]; then
  log "fetching remote nodes.conf: $PROVISION_NODES_URL"
  if curl -fsSL "$PROVISION_NODES_URL" -o /tmp/nodes.conf; then
    NODES_CONF=/tmp/nodes.conf
  else
    warn "could not fetch remote nodes config; using baked-in $NODES_CONF"
  fi
fi

# -----------------------------------------------------------------------------
# Custom nodes
# -----------------------------------------------------------------------------
install_nodes() {
  [[ -f "$NODES_CONF" ]] || { log "no nodes.conf; skipping custom nodes"; return; }
  mkdir -p "$COMFY_DIR/custom_nodes"

  while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line%%#*}"
    line="$(echo "$line" | xargs || true)"
    [[ -z "$line" ]] && continue

    local url ref name dest
    url="$(echo "$line"  | awk -F'|' '{print $1}' | xargs)"
    ref="$(echo "$line"  | awk -F'|' '{print $2}' | xargs)"
    name="$(basename "$url" .git)"
    dest="$COMFY_DIR/custom_nodes/$name"

    if [[ -d "$dest" ]]; then
      log "node present, skipping: $name"
    else
      log "cloning $name"
      if ! git clone --depth 1 ${ref:+--branch "$ref"} "$url" "$dest" 2>/dev/null; then
        # --depth 1 --branch fails on a raw commit SHA; retry as a full clone.
        if ! { git clone "$url" "$dest" && { [[ -z "$ref" ]] || git -C "$dest" checkout -q "$ref"; }; }; then
          err "clone failed: $url"; FAILED=$((FAILED+1)); continue
        fi
      fi
    fi

    if [[ -f "$dest/requirements.txt" ]]; then
      log "  installing requirements for $name"
      pip install --no-cache-dir -r "$dest/requirements.txt" \
        || { warn "requirements failed for $name (node may not load)"; FAILED=$((FAILED+1)); }
    fi
  done < "$NODES_CONF"
}

# -----------------------------------------------------------------------------
# Models
# -----------------------------------------------------------------------------
download_models() {
  [[ -f "$MODELS_CONF" ]] || { log "no models.conf; skipping models"; return; }

  while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line%%#*}"
    line="$(echo "$line" | xargs || true)"
    [[ -z "$line" ]] && continue

    local category url filename dest target
    category="$(echo "$line" | awk -F'|' '{print $1}' | xargs)"
    url="$(echo "$line"      | awk -F'|' '{print $2}' | xargs)"
    filename="$(echo "$line" | awk -F'|' '{print $3}' | xargs)"

    [[ -z "$category" || -z "$url" ]] && { warn "malformed line: $line"; continue; }

    # Reject path traversal — models.conf may come from a remote URL.
    if [[ "$category" == /* || "$category" == *..* ]]; then
      err "unsafe category '$category'; skipping"; FAILED=$((FAILED+1)); continue
    fi

    [[ -z "$filename" ]] && filename="$(basename "${url%%\?*}")"
    dest="$COMFY_DIR/models/$category"
    target="$dest/$filename"
    mkdir -p "$dest"

    if [[ -s "$target" ]]; then
      log "have $category/$filename"
      continue
    fi

    # Attach the right credential for the host.
    local -a auth=()
    case "$url" in
      *huggingface.co*) [[ -n "${HF_TOKEN:-}" ]] &&
                          auth=(-H "Authorization: Bearer $HF_TOKEN") ;;
      *civitai.com*)    [[ -n "${CIVITAI_API_TOKEN:-}" ]] &&
                          auth=(-H "Authorization: Bearer $CIVITAI_API_TOKEN") ;;
    esac

    log "downloading $category/$filename"
    # Download to .part and move only on success, so an interrupted pod never
    # leaves a truncated file that looks complete to the skip-check above.
    if curl -fL --retry 3 --retry-delay 5 --progress-bar \
            "${auth[@]}" "$url" -o "$target.part"; then
      mv "$target.part" "$target"
    else
      err "download failed: $url"
      rm -f "$target.part"
      FAILED=$((FAILED+1))
    fi
  done < "$MODELS_CONF"
}

# -----------------------------------------------------------------------------
# H3 scaffolding: reference folders for H3AutoRefs, and the workflow library.
#
# H3AutoRefs scans your prompt for character names and matches them against
# SUBFOLDER NAMES under input/h3_refs/. No folder, no reference photos — it
# warns and renders the character from prose alone. Creating the tree up front
# makes that convention visible instead of something you discover by failing.
# -----------------------------------------------------------------------------
scaffold_h3() {
  local refs="$COMFY_DIR/input/h3_refs"
  local wf="$COMFY_DIR/user/default/workflows/H3"

  if [[ ! -d "$refs" ]]; then
    log "creating H3AutoRefs reference tree at input/h3_refs/"
    mkdir -p "$refs/example_character"
    cat > "$refs/README.txt" <<'EOF'
H3AutoRefs — reference photo folders
====================================

One SUBFOLDER PER CHARACTER. The folder name is what H3AutoRefs matches
against your prompt text, so name it exactly how you refer to the character.

    input/h3_refs/
        rae/
            rae_front.png
            rae_three_quarter.png
            rae_profile.png
        marcus/
            ...

WHAT ACTUALLY HOLDS IDENTITY
  A front / three-quarter / profile set. That trio is what the node's own
  docs recommend, and it beats a larger pile of similar front-on shots.

HOW MANY GET USED
  max_per_character on the node (default 3, hard max 9 — H3 has nine
  reference slots total, shared across every matched character). Fewer
  characters per run holds each face more firmly, because each one gets
  more of the nine slots.

PER-SCENE VARIANTS
  Make a second folder and remap with the node's `overrides` input:
      rae=rae_night
  Same character, different reference set for that scene.

REQUIRES ref2va
  These reference folders do NOTHING on an fl2va checkpoint — it has no
  reference rows at all. Check models.conf if identity is being ignored.
EOF
  else
    log "input/h3_refs/ already present, leaving it alone"
  fi

  # Seed the bundled workflows into the sidebar library. Copy per-file and
  # never overwrite: these are editable documents, and clobbering a user's
  # tweaked copy on every pod restart would be its own bug.
  if [[ -d /opt/provision/workflows ]]; then
    mkdir -p "$wf"
    local f base
    for f in /opt/provision/workflows/*.json; do
      [[ -e "$f" ]] || continue
      base="$(basename "$f")"
      if [[ -e "$wf/$base" ]]; then
        log "workflow exists, keeping yours: $base"
      else
        cp "$f" "$wf/$base" && log "seeded workflow: $base"
      fi
    done
  fi
}

log "provisioning into $COMFY_DIR"
install_nodes
download_models
scaffold_h3

if (( FAILED > 0 )); then
  warn "provisioning finished with $FAILED failure(s) — ComfyUI will still start."
  warn "Check the log above; a 401 means a missing or expired token."
else
  log "provisioning complete."
fi
