#!/usr/bin/env bash
# =============================================================================
#  provision.sh — install custom nodes and download models at container start.
#
#  Runs on every boot and is IDEMPOTENT: anything already on disk is skipped,
#  so a restart on a persistent RunPod volume costs seconds, not a re-download.
#
#  DRY_RUN=1 prints the plan (and resolves CivitAI metadata) without cloning,
#  downloading or writing anything — use it to check a config change:
#      DRY_RUN=1 H3_TIER=80 COMFY_DIR=/tmp/c CONFIG_DIR=./config \
#        WORKFLOWS_SRC=./workflows SCRIPTS_DIR=./scripts bash scripts/provision.sh
#
#  Order: custom nodes -> GPU tier manifest (config/tiers/<tier>.conf, picked
#  by H3_TIER / VRAM) -> config/models.conf (your extras) -> H3_MODEL_PROFILES
#  -> adult video LoRA catalog -> H3 Image LoRA catalog -> workflows.
#
#  H3_MODE=image (images only, smallest volume): the tier manifest becomes
#  config/tiers/image/<tier>.conf (H3 Image model, Qwen3-VL text encoder,
#  Qwen3.5 9B prompt enhancer, image VAE, pDMD LoRA), the adult VIDEO LoRA
#  catalog defaults to none, node packs tagged `video` in nodes.conf are not
#  cloned, and only the image workflows are seeded. H3_MODE=full (default)
#  is the complete image + video stack.
# =============================================================================
set -Eeuo pipefail

COMFY_DIR="${COMFY_DIR:-/workspace/ComfyUI}"
CONFIG_DIR="${CONFIG_DIR:-/opt/provision/config}"
WORKFLOWS_SRC="${WORKFLOWS_SRC:-/opt/provision/workflows}"
SCRIPTS_DIR="${SCRIPTS_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"
MODELS_CONF="${MODELS_CONF:-$CONFIG_DIR/models.conf}"
NODES_CONF="${NODES_CONF:-$CONFIG_DIR/nodes.conf}"
ADULT_LORAS_CONF="${ADULT_LORAS_CONF:-$CONFIG_DIR/adult_loras.conf}"
PROFILES_DIR="${PROFILES_DIR:-$CONFIG_DIR/profiles}"
IMAGE_LORAS_CONF="${IMAGE_LORAS_CONF:-$CONFIG_DIR/image_loras.conf}"
TIERS_DIR="${TIERS_DIR:-$CONFIG_DIR/tiers}"
DRY_RUN="${DRY_RUN:-0}"
CIVITAI_API="https://civitai.com/api/v1/model-versions"

# CIVITAI_TOKEN is accepted as an alias for CIVITAI_API_TOKEN (the name the
# home-PC download script uses). Neither value is ever printed.
if [[ -z "${CIVITAI_API_TOKEN:-}" && -n "${CIVITAI_TOKEN:-}" ]]; then
  CIVITAI_API_TOKEN="$CIVITAI_TOKEN"
fi

# GPU tier (H3_TIER=auto|16|24|48|80|96|none) — see scripts/gpu_tier.sh.
# shellcheck source=gpu_tier.sh
source "$SCRIPTS_DIR/gpu_tier.sh"
resolve_tier

log()  { printf '\033[36m[provision]\033[0m %s\n' "$*"; }
warn() { printf '\033[33m[provision] WARN:\033[0m %s\n' "$*" >&2; WARNED=$((WARNED+1)); }
err()  { printf '\033[31m[provision] ERROR:\033[0m %s\n' "$*" >&2; }
plan() { printf '\033[35m[provision] DRY_RUN:\033[0m %s\n' "$*"; }
is_dry() { [[ "$DRY_RUN" == "1" ]]; }

# H3_MODE: full (default, image + video) or image (images only).
case "${H3_MODE:-full}" in
  ""|full|all|video)            H3_MODE=full ;;
  image|images|image-only|img)  H3_MODE=image ;;
  *) printf '\033[33m[provision] WARN:\033[0m H3_MODE=%s is not full or image — using full\n' "$H3_MODE" >&2
     H3_MODE=full ;;
esac
is_image_mode() { [[ "$H3_MODE" == "image" ]]; }

# Strip leading/trailing whitespace without xargs (xargs chokes on quotes).
trim() {
  local s="$1"
  s="${s#"${s%%[![:space:]]*}"}"
  s="${s%"${s##*[![:space:]]}"}"
  printf '%s' "$s"
}

# A model failure must not take the pod down — ComfyUI should still come up so
# you can look around and fix it. Track failures and report at the end instead.
# WARNED counts skipped optional items (e.g. a CivitAI LoRA that is gone).
FAILED=0
WARNED=0

# -----------------------------------------------------------------------------
# Remote config override: point PROVISION_CONFIG_URL at a raw GitHub URL to
# change the model set WITHOUT rebuilding the image. This is the whole reason
# provisioning is a boot-time step rather than baked into a Docker layer.
#
# PRIVATE REPO SUPPORT: raw.githubusercontent.com returns 404 (not 401!) for
# private-repo files fetched without auth. Set GH_CONFIG_TOKEN on the pod to a
# GitHub PAT with read access to the repo and it is attached automatically to
# github.com / raw.githubusercontent.com fetches — and ONLY to those hosts, so
# the token can never leak to an arbitrary URL someone puts in the variable.
# -----------------------------------------------------------------------------
fetch_config() {
  local url="$1" out="$2"
  local -a auth=()
  case "$url" in
    https://raw.githubusercontent.com/*|https://github.com/*|https://api.github.com/*)
      [[ -n "${GH_CONFIG_TOKEN:-}" ]] && auth=(-H "Authorization: token $GH_CONFIG_TOKEN")
      ;;
  esac
  curl -fsSL "${auth[@]}" "$url" -o "$out"
}

if [[ -n "${PROVISION_CONFIG_URL:-}" ]]; then
  log "fetching remote models.conf: $PROVISION_CONFIG_URL"
  if fetch_config "$PROVISION_CONFIG_URL" /tmp/models.conf; then
    MODELS_CONF=/tmp/models.conf
  else
    warn "could not fetch remote config; falling back to baked-in $MODELS_CONF"
    warn "(private repo? raw.githubusercontent.com 404s without auth — set GH_CONFIG_TOKEN)"
  fi
fi

if [[ -n "${PROVISION_NODES_URL:-}" ]]; then
  log "fetching remote nodes.conf: $PROVISION_NODES_URL"
  if fetch_config "$PROVISION_NODES_URL" /tmp/nodes.conf; then
    NODES_CONF=/tmp/nodes.conf
  else
    warn "could not fetch remote nodes config; using baked-in $NODES_CONF"
  fi
fi

if [[ -n "${PROVISION_ADULT_LORAS_URL:-}" ]]; then
  log "fetching remote adult_loras.conf: $PROVISION_ADULT_LORAS_URL"
  if fetch_config "$PROVISION_ADULT_LORAS_URL" /tmp/adult_loras.conf; then
    ADULT_LORAS_CONF=/tmp/adult_loras.conf
  else
    warn "could not fetch remote adult LoRA catalog; using baked-in $ADULT_LORAS_CONF"
  fi
fi

# -----------------------------------------------------------------------------
# Custom nodes
#
# A <ref> (tag/branch/SHA) pins a pack. Fresh clones land on the pin. An
# EXISTING clone on a persistent volume is left alone but checked: if it is not
# on the pin you get a WARN, and NODES_SYNC_PINS=1 moves it onto the pin.
# -----------------------------------------------------------------------------
install_nodes() {
  [[ -f "$NODES_CONF" ]] || { log "no nodes.conf; skipping custom nodes"; return; }
  is_dry || mkdir -p "$COMFY_DIR/custom_nodes"

  while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line%%#*}"
    line="$(trim "$line")"
    [[ -z "$line" ]] && continue

    local url ref tag name dest
    url="$(trim "$(echo "$line" | awk -F'|' '{print $1}')")"
    ref="$(trim "$(echo "$line" | awk -F'|' '{print $2}')")"
    tag="$(trim "$(echo "$line" | awk -F'|' '{print $3}')")"
    name="$(basename "$url" .git)"
    dest="$COMFY_DIR/custom_nodes/$name"

    if is_image_mode && [[ "${tag,,}" == "video" ]]; then
      log "H3_MODE=image: skipping video-only node $name"
      continue
    fi

    if is_dry; then
      plan "node $name ${ref:+@ $ref }<- $url"
      continue
    fi

    if [[ -d "$dest" ]]; then
      log "node present, skipping: $name"
      if [[ -n "$ref" && -d "$dest/.git" ]]; then
        local cur want
        cur="$(git -C "$dest" rev-parse HEAD 2>/dev/null || true)"
        want="$(git -C "$dest" rev-parse -q --verify "$ref^{commit}" 2>/dev/null || true)"
        if [[ -z "$want" || "$cur" != "$want" ]]; then
          if [[ "${NODES_SYNC_PINS:-0}" == "1" ]]; then
            log "  moving $name onto pin $ref (NODES_SYNC_PINS=1)"
            if git -C "$dest" fetch -q --depth 1 origin "$ref" \
               && git -C "$dest" checkout -q FETCH_HEAD; then
              log "  $name now at $ref"
            else
              err "could not move $name to $ref"; FAILED=$((FAILED+1))
            fi
          else
            warn "$name is pinned to $ref in nodes.conf but the existing checkout differs — set NODES_SYNC_PINS=1 to move it"
          fi
        fi
      fi
    else
      log "cloning $name ${ref:+@ $ref}"
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
        || { err "requirements failed for $name (node may not load)"; FAILED=$((FAILED+1)); }
    fi
  done < "$NODES_CONF"
}

# -----------------------------------------------------------------------------
# CivitAI version resolution.
#
#   civitai-version:<versionId>   in the url column of any *.conf model line
#
# asks CivitAI's public API which file is the version's PRIMARY file and where
# it downloads from, instead of guessing a filename. Results (on success):
#   CIV_NAME  primary file name        CIV_URL  its civitai.com download URL
#   CIV_INFO  "model / version / baseModel" for the log
# Returns 1 (after a WARN) when anything is missing, so callers skip cleanly.
# -----------------------------------------------------------------------------
CIV_NAME="" CIV_URL="" CIV_INFO=""
resolve_civitai() {
  local id="$1" wanted="${2:-}" meta name durl
  CIV_NAME="" CIV_URL="" CIV_INFO=""

  if ! command -v jq >/dev/null 2>&1; then
    warn "jq is not installed — cannot resolve CivitAI version $id; skipping (apt-get install jq)"
    return 1
  fi

  local -a auth=()
  [[ -n "${CIVITAI_API_TOKEN:-}" ]] && auth=(-H "Authorization: Bearer $CIVITAI_API_TOKEN")

  local resp code
  if ! resp="$(curl -sSL --retry 2 --retry-delay 3 --max-time 60 "${auth[@]}" \
                 -w '\n%{http_code}' "$CIVITAI_API/$id" 2>/dev/null)"; then
    warn "CivitAI version $id: metadata endpoint unreachable (network/DNS) — skipping"
    return 1
  fi
  code="${resp##*$'\n'}"
  meta="${resp%$'\n'*}"
  if [[ "$code" != "200" ]]; then
    warn "CivitAI version $id: metadata endpoint returned HTTP $code (404 = removed/hidden or needs CIVITAI_API_TOKEN, 401/403 = token, 429 = rate limit) — skipping"
    return 1
  fi
  if ! jq -e 'type == "object" and (.error | not)' >/dev/null 2>&1 <<<"$meta"; then
    warn "CivitAI version $id: API returned an error ($(jq -r '.error // "unparseable response"' <<<"$meta" 2>/dev/null | head -c 120)) — skipping"
    return 1
  fi

  CIV_INFO="$(jq -r '"\(.model.name // "?") / \(.name // "?") / base: \(.baseModel // "?")"' <<<"$meta")"
  if [[ -n "$wanted" ]]; then
    # A manifest line named an exact file of this version (e.g. the int8 vs
    # bf16 build of one CivitAI checkpoint): take that file, never another.
    name="$(jq -r --arg n "$wanted" '[.files[]? | select(.name == $n)][0].name // empty' <<<"$meta")"
    durl="$(jq -r --arg n "$wanted" '[.files[]? | select(.name == $n)][0].downloadUrl // empty' <<<"$meta")"
    if [[ -z "$name" ]]; then
      warn "CivitAI version $id ($CIV_INFO): no file named '$wanted' — skipping"
      return 1
    fi
  else
    name="$(jq -r '[.files[]? | select(.primary == true)][0].name // empty' <<<"$meta")"
    durl="$(jq -r '[.files[]? | select(.primary == true)][0].downloadUrl // empty' <<<"$meta")"
  fi

  if [[ -z "$name" ]]; then
    warn "CivitAI version $id ($CIV_INFO): no primary file listed — skipping"
    return 1
  fi
  # The name comes from a remote API and becomes a path: keep it a plain file.
  if [[ "$name" == */* || "$name" == .* || "$name" == *..* || "$name" =~ [[:cntrl:]] ]]; then
    warn "CivitAI version $id: refusing unsafe file name '$name' — skipping"
    return 1
  fi
  if [[ "$name" != *.safetensors ]]; then
    warn "CivitAI version $id: file '$name' is not .safetensors — skipping"
    return 1
  fi
  # Only ever download from civitai.com, and only for this version id.
  if [[ "$durl" != "https://civitai.com/api/download/models/$id" && "$durl" != "https://civitai.com/api/download/models/$id?"* ]]; then
    durl="https://civitai.com/api/download/models/$id"
  fi

  CIV_NAME="$name"
  CIV_URL="$durl"
  return 0
}

# -----------------------------------------------------------------------------
# Download one model:  download_one <category> <url> [filename] [label]
# -----------------------------------------------------------------------------
download_one() {
  local category="$1" url="$2" filename="${3:-}" label="${4:-}"
  local dest target civ_id="" marker=""

  # Reject path traversal — conf files may come from a remote URL.
  if [[ "$category" == /* || "$category" == *..* || -z "$category" ]]; then
    err "unsafe category '$category'; skipping"; FAILED=$((FAILED+1)); return 0
  fi
  if [[ "$filename" == */* || "$filename" == *..* ]]; then
    err "unsafe filename '$filename'; skipping"; FAILED=$((FAILED+1)); return 0
  fi
  dest="$COMFY_DIR/models/$category"

  if [[ "$url" =~ ^civitai-version:([0-9]+)$ ]]; then
    civ_id="${BASH_REMATCH[1]}"
    marker="$dest/.civitai-version-$civ_id"
    # Already downloaded on an earlier boot? Skip without touching the API.
    if [[ -n "$filename" && -s "$dest/$filename" ]]; then
      log "have $category/$filename (CivitAI $civ_id${label:+, $label})"
      if ! is_dry; then printf '%s\n' "$filename" > "$marker"; fi
      return 0
    fi
    if [[ -z "$filename" && -s "$marker" ]]; then
      local known; known="$(head -n1 "$marker")"
      if [[ -n "$known" && "$known" != */* && -s "$dest/$known" ]]; then
        log "have $category/$known (CivitAI $civ_id${label:+, $label})"
        return 0
      fi
    fi
    # With a file name on the line, that exact file of the version is fetched.
    if ! resolve_civitai "$civ_id" "$filename"; then
      return 0
    fi
    url="$CIV_URL"
    [[ -z "$filename" ]] && filename="$CIV_NAME"
    log "CivitAI $civ_id -> $CIV_NAME  [$CIV_INFO]"
  fi

  [[ -z "$filename" ]] && filename="$(basename "${url%%\?*}")"
  target="$dest/$filename"

  if [[ -s "$target" ]]; then
    log "have $category/$filename"
    if [[ -n "$marker" ]] && ! is_dry; then printf '%s\n' "$filename" > "$marker"; fi
    return 0
  fi

  if is_dry; then
    plan "download $category/$filename <- ${url%%\?*}${label:+  ($label)}"
    return 0
  fi

  if [[ "$url" == *civitai.com* && -z "${CIVITAI_API_TOKEN:-}" ]]; then
    warn "CIVITAI_API_TOKEN is not set — the download of $filename will most likely 401"
  fi

  mkdir -p "$dest"

  # Attach the right credential for the host.
  local -a auth=()
  case "$url" in
    https://huggingface.co/*) [[ -n "${HF_TOKEN:-}" ]] &&
                                auth=(-H "Authorization: Bearer $HF_TOKEN") ;;
    https://civitai.com/*)    [[ -n "${CIVITAI_API_TOKEN:-}" ]] &&
                                auth=(-H "Authorization: Bearer $CIVITAI_API_TOKEN") ;;
  esac

  log "downloading $category/$filename"
  # Download to .part and move only on success, so an interrupted pod never
  # leaves a truncated file that looks complete to the skip-check above.
  # (curl drops the Authorization header on cross-host redirects, so tokens
  # never follow a redirect to a CDN.)
  if curl -fL --retry 3 --retry-delay 5 --progress-bar \
          "${auth[@]}" "$url" -o "$target.part"; then
    mv "$target.part" "$target"
    if [[ -n "$marker" ]]; then printf '%s\n' "$filename" > "$marker"; fi
  else
    rm -f "$target.part"
    if [[ -n "$civ_id" ]]; then
      warn "CivitAI download failed for version $civ_id ($filename) — 401 = token, 404 = removed; continuing"
    else
      err "download failed: ${url%%\?*}"
      FAILED=$((FAILED+1))
    fi
  fi
}

# Process a manifest:  <category> | <url-or-civitai-version:ID> | [filename]
download_conf() {
  local conf="$1" line category url filename
  [[ -f "$conf" ]] || { warn "model manifest not found: $conf"; return; }
  log "model manifest: $conf"
  while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line%%#*}"
    line="$(trim "$line")"
    [[ -z "$line" ]] && continue

    category="$(trim "$(echo "$line" | awk -F'|' '{print $1}')")"
    url="$(trim "$(echo "$line"      | awk -F'|' '{print $2}')")"
    filename="$(trim "$(echo "$line" | awk -F'|' '{print $3}')")"

    [[ -z "$category" || -z "$url" ]] && { warn "malformed line: $line"; continue; }
    download_one "$category" "$url" "$filename"
  done < "$conf"
}

# -----------------------------------------------------------------------------
# Models: the base manifest, then any opt-in profiles.
#   H3_MODEL_PROFILES="official-ref2v,official-fl2v,controlnet,fasth3,pika-flex"
# Each profile is config/profiles/<name>.conf and carries ITS OWN matched turbo
# (or none), so profiles never mix turbo families.
# -----------------------------------------------------------------------------
download_models() {
  local manifest="$TIERS_DIR/$H3_TIER_RESOLVED.conf"
  is_image_mode && manifest="$TIERS_DIR/image/$H3_TIER_RESOLVED.conf"
  if [[ "$H3_TIER_RESOLVED" == "none" ]]; then
    log "GPU tier: none (H3_TIER=none) — only models.conf and profiles"
  elif [[ -f "$manifest" ]]; then
    log "GPU tier $H3_TIER_RESOLVED ($H3_TIER_REASON), H3_MODE=$H3_MODE"
    download_conf "$manifest"
  else
    warn "GPU tier manifest missing: $manifest"
  fi

  if [[ -f "$MODELS_CONF" ]]; then
    download_conf "$MODELS_CONF"
  else
    log "no models.conf; skipping base models"
  fi

  local profiles="${H3_MODEL_PROFILES:-}" p
  profiles="${profiles//,/ }"
  for p in $profiles; do
    if [[ ! "$p" =~ ^[A-Za-z0-9_-]+$ ]]; then
      warn "ignoring invalid profile name '$p'"; continue
    fi
    if [[ -f "$PROFILES_DIR/$p.conf" ]]; then
      log "profile: $p"
      download_conf "$PROFILES_DIR/$p.conf"
    else
      warn "unknown profile '$p' (no $PROFILES_DIR/$p.conf)"
    fi
  done
}

# -----------------------------------------------------------------------------
# Adult LoRA catalog (config/adult_loras.conf), selected by H3_ADULT_LORAS.
#   unset/"default" = rows marked default=yes, "all", "none", or a comma list
#   of keywords, keys and version ids. Unknown tokens WARN and are ignored.
# Writes models/loras/H3_ADULT_LORAS_INDEX.txt mapping files to strength/trigger.
# -----------------------------------------------------------------------------
download_adult_loras() {
  # These are VIDEO LoRAs: images-only mode skips them unless asked for.
  local sel="${H3_ADULT_LORAS-default}"
  if is_image_mode && [[ -z "${H3_ADULT_LORAS+x}" ]]; then
    sel=none
  fi
  download_catalog "$ADULT_LORAS_CONF" "$sel" H3_ADULT_LORAS \
    loras H3_ADULT_LORAS_INDEX.txt "adult LoRAs"
}

# H3 Image LoRAs (config/image_loras.conf), selected by H3_IMAGE_LORAS, into
# models/loras/H3-Image/.
download_image_loras() {
  download_catalog "$IMAGE_LORAS_CONF" "${H3_IMAGE_LORAS-default}" H3_IMAGE_LORAS \
    loras/H3-Image H3_IMAGE_LORAS_INDEX.txt "H3 Image LoRAs"
}

# download_catalog <conf> <selection> <env var name> <models/ category> <index file> <label>
download_catalog() {
  local conf="$1" selection="$2" var="$3" category="$4" index_name="$5" what="$6"
  selection="$(trim "${selection//,/ }")"
  case "${selection,,}" in
    ""|none|off|0|false) log "$what: none selected ($var=$selection)"; return ;;
  esac
  [[ -f "$conf" ]] || { warn "$what catalog not found: $conf"; return; }

  local -a keys=() ids=() names=() strengths=() triggers=() defaults=()
  local line k i n s t d
  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ "$line" =~ ^[[:space:]]*# ]] && continue
    line="$(trim "$line")"
    [[ -z "$line" ]] && continue
    IFS='|' read -r k i n s t d <<<"$line"
    k="$(trim "$k")"; i="$(trim "$i")"; n="$(trim "$n")"
    s="$(trim "$s")"; t="$(trim "$t")"; d="$(trim "$d")"
    if [[ -z "$k" || ! "$i" =~ ^[0-9]+$ ]]; then
      warn "adult LoRA catalog: malformed line: $line"; continue
    fi
    keys+=("$k"); ids+=("$i"); names+=("$n"); strengths+=("$s"); triggers+=("$t"); defaults+=("${d,,}")
  done < "$conf"

  local -A want=()
  local tok idx matched
  for tok in $selection; do
    matched=0
    for idx in "${!keys[@]}"; do
      case "${tok,,}" in
        all)     want[$idx]=1; matched=1 ;;
        default) [[ "${defaults[$idx]}" == "yes" ]] && want[$idx]=1; matched=1 ;;
        *)       if [[ "${tok,,}" == "${keys[$idx],,}" || "$tok" == "${ids[$idx]}" ]]; then
                   want[$idx]=1; matched=1
                 fi ;;
      esac
    done
    (( matched )) || warn "$var: '$tok' is not a key or version id in $conf — ignored"
  done

  log "$what: ${#want[@]} selected from catalog of ${#keys[@]} ($var=$selection)"
  local index="$COMFY_DIR/models/$category/$index_name" marker file
  if ! is_dry; then
    mkdir -p "$COMFY_DIR/models/$category"
    {
      echo "# Written by provision.sh — $what on this volume."
      echo "# file | catalog key | CivitAI version | name | suggested strength | trigger"
      echo "# Pick these in H3LoraStack / LoraLoaderModelOnly. 1-3 at a time, low strength first."
    } > "$index"
  fi
  for idx in $(printf '%s\n' "${!want[@]}" | sort -n); do
    log "  [${keys[$idx]}] ${names[$idx]} — strength ${strengths[$idx]}, trigger: ${triggers[$idx]}"
    download_one "$category" "civitai-version:${ids[$idx]}" "" "${keys[$idx]}"
    if ! is_dry; then
      marker="$COMFY_DIR/models/$category/.civitai-version-${ids[$idx]}"
      file="(not downloaded)"
      [[ -s "$marker" ]] && file="$(head -n1 "$marker")"
      printf '%s | %s | %s | %s | %s | %s\n' "$file" "${keys[$idx]}" "${ids[$idx]}" \
        "${names[$idx]}" "${strengths[$idx]}" "${triggers[$idx]}" >> "$index"
    fi
  done
}

# -----------------------------------------------------------------------------
# Optional extras (both OFF by default):
#   H3_INSTALL_MOTION_CONTEXT=1  run install-motion-context.sh (see its header:
#                                NOT compatible with Multishot's context_pin)
#   H3_INSTALL_WRITER_PACK=1     copy the JoyEcho writer pack that ships inside
#                                ComfyUI-H3-Multishot (needed by the
#                                JoyEcho_LLMEnhance node in Extend_Take / v2)
# -----------------------------------------------------------------------------
install_extras() {
  if [[ "${H3_INSTALL_MOTION_CONTEXT:-0}" == "1" ]]; then
    if is_dry; then
      plan "run $SCRIPTS_DIR/install-motion-context.sh"
    else
      COMFY_DIR="$COMFY_DIR" bash "$SCRIPTS_DIR/install-motion-context.sh" \
        || { err "Motion Context install failed"; FAILED=$((FAILED+1)); }
    fi
  fi

  if [[ "${H3_INSTALL_WRITER_PACK:-0}" == "1" ]]; then
    local src="$COMFY_DIR/custom_nodes/ComfyUI-H3-Multishot/writer_pack/ComfyUI_JoyAI_Echo_GGUF_Nodes"
    local dst="$COMFY_DIR/custom_nodes/ComfyUI_JoyAI_Echo_GGUF_Nodes"
    if is_dry; then
      plan "copy $src -> $dst (requirements NOT auto-installed)"
    elif [[ -d "$dst" ]]; then
      log "writer pack present, leaving it alone: $dst"
    elif [[ -d "$src" ]]; then
      cp -a "$src" "$dst" && log "copied JoyEcho writer pack from ComfyUI-H3-Multishot"
      warn "writer pack requirements.txt pins transformers<4.58 and was NOT installed automatically; install it by hand only if the node fails to import"
    else
      warn "H3_INSTALL_WRITER_PACK=1 but $src does not exist (is ComfyUI-H3-Multishot installed?)"
    fi
  fi
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

  if is_dry; then
    if [[ "$H3_TIER_RESOLVED" != "none" ]]; then
      plan "seed workflows from $WORKFLOWS_SRC/tiers/$H3_TIER_RESOLVED into $wf/${H3_TIER_RESOLVED}GB (and $wf/${H3_TIER_RESOLVED}GB/official)"
    fi
    plan "scaffold $refs and seed workflows from $WORKFLOWS_SRC into $wf/original (and $wf/original/official)"
    if is_image_mode; then
      plan "H3_MODE=image: only H3_image_*, H3_character_sheet* and official image_* workflows are seeded"
    fi
    return
  fi

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
  # workflows/tiers/<T>/*.json          -> workflows/H3/<T>GB/   (USE THESE: model
  # workflows/tiers/<T>/official/*.json -> workflows/H3/<T>GB/official/   names match tier T)
  # workflows/*.json, official/*.json   -> workflows/H3/original/ (as shipped)
  # Each tier gets its own folder, so switching tiers on one volume never
  # leaves you opening a graph that names another tier's files.
  seed_dir() {
    local from="$1" to="$2" f base
    [[ -d "$from" ]] || return 0
    mkdir -p "$to"
    for f in "$from"/*.json; do
      [[ -e "$f" ]] || continue
      base="$(basename "$f")"
      # Images only: video graphs would just open with missing models.
      if is_image_mode; then
        case "$base" in
          H3_image_*|H3_character_sheet*|image_*) ;;
          *) continue ;;
        esac
      fi
      if [[ -e "$to/$base" ]]; then
        log "workflow exists, keeping yours: ${to#"$COMFY_DIR"/}/$base"
      else
        cp "$f" "$to/$base" && log "seeded workflow: ${to#"$COMFY_DIR"/}/$base"
      fi
    done
  }
  if [[ "$H3_TIER_RESOLVED" != "none" ]]; then
    seed_dir "$WORKFLOWS_SRC/tiers/$H3_TIER_RESOLVED" "$wf/${H3_TIER_RESOLVED}GB"
    seed_dir "$WORKFLOWS_SRC/tiers/$H3_TIER_RESOLVED/official" "$wf/${H3_TIER_RESOLVED}GB/official"
  fi
  seed_dir "$WORKFLOWS_SRC" "$wf/original"
  seed_dir "$WORKFLOWS_SRC/official" "$wf/original/official"
}

if is_dry; then
  log "provisioning into $COMFY_DIR (DRY_RUN=1: nothing is cloned, downloaded or written)"
else
  log "provisioning into $COMFY_DIR"
fi
log "GPU tier: $H3_TIER_RESOLVED  ($H3_TIER_REASON)"
log "H3_MODE: $H3_MODE$(is_image_mode && printf ' (images only: no video models, video LoRAs or video-only nodes)')"
install_nodes
download_models
download_adult_loras
download_image_loras
install_extras
scaffold_h3

if (( FAILED > 0 )); then
  warn "provisioning finished with $FAILED failure(s) and $WARNED warning(s) — ComfyUI will still start."
  warn "Check the log above; a 401 means a missing or expired token."
elif (( WARNED > 0 )); then
  log "provisioning complete with $WARNED warning(s) (skipped optional items — see WARN lines)."
else
  log "provisioning complete."
fi
