#!/usr/bin/env bash
# shellcheck disable=SC2034  # variables are read by the scripts that source this file
# =============================================================================
#  gpu_tier.sh — work out which model tier this pod should use.
#  Sourced by provision.sh and start.sh; defines functions only.
#
#  H3_TIER = auto (default) | 16 | 24 | 48 | 80 | 96 | none
#    auto  reads the first GPU's total memory from nvidia-smi:
#             < 22000 MiB -> 16   (16-23 GB cards; the home-PC file set)
#             < 44000 MiB -> 24   (RTX 4090 24 GB, RTX 5090 32 GB, L4, A100 40GB)
#             < 75000 MiB -> 48   (L40S, RTX 6000 Ada, A6000, A40)
#             < 92000 MiB -> 80   (H100 80GB, A100 80GB)
#             otherwise   -> 96   (RTX PRO 6000 96 GB, H100 NVL, H200, B200)
#          No nvidia-smi / no GPU -> 24, with a warning.
#    none  no tier manifest at all: only config/models.conf + H3_MODEL_PROFILES
#          (the pre-tier behaviour of this repo).
#  Tier N downloads config/tiers/N.conf and seeds workflows/tiers/N/.
# =============================================================================

# Prints "<total MiB> <compute capability>" of GPU 0, or nothing.
gpu_info() {
  command -v nvidia-smi >/dev/null 2>&1 || return 0
  nvidia-smi --query-gpu=memory.total,compute_cap --format=csv,noheader,nounits 2>/dev/null \
    | head -n1 | tr -d ' ' | tr ',' ' '
}

tier_for_mib() {
  local mib="$1"
  if   (( mib < 22000 )); then echo 16
  elif (( mib < 44000 )); then echo 24
  elif (( mib < 75000 )); then echo 48
  elif (( mib < 92000 )); then echo 80
  else echo 96
  fi
}

# Sets H3_TIER_RESOLVED, H3_GPU_MIB, H3_GPU_CC and H3_TIER_REASON.
resolve_tier() {
  local want="${H3_TIER:-auto}" info mib="" cc=""
  info="$(gpu_info || true)"
  if [[ -n "$info" ]]; then
    read -r mib cc <<<"$info"
    [[ "$mib" =~ ^[0-9]+$ ]] || mib=""
  fi
  H3_GPU_MIB="${mib:-0}"
  H3_GPU_CC="${cc:-?}"
  case "${want,,}" in
    16|24|48|80|96|none)
      H3_TIER_RESOLVED="${want,,}"
      H3_TIER_REASON="set by H3_TIER=$want" ;;
    auto|"")
      if [[ -n "$mib" ]]; then
        H3_TIER_RESOLVED="$(tier_for_mib "$mib")"
        H3_TIER_REASON="auto: GPU 0 has ${mib} MiB, compute capability ${cc}"
      else
        H3_TIER_RESOLVED=24
        H3_TIER_REASON="auto: nvidia-smi gave no GPU info, defaulting to 24"
      fi ;;
    *)
      H3_TIER_RESOLVED=24
      H3_TIER_REASON="H3_TIER='$want' is not one of auto,16,24,48,80,96,none - using 24" ;;
  esac
}
