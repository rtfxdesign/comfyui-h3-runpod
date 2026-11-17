# Adult (NSFW) LoRA catalog for MiniMax H3

Catalog file: [`config/adult_loras.conf`](../config/adult_loras.conf) — 24
CivitAI model versions supplied by the repo owner (names, version ids,
strengths and triggers are the owner's list, unchanged).

## How it works

1. At boot `scripts/provision.sh` reads `H3_ADULT_LORAS` (default: `default`).
2. For each selected row it calls
   `https://civitai.com/api/v1/model-versions/<versionId>` (with
   `CIVITAI_API_TOKEN` if set), takes the **primary** file's name and download
   URL with `jq`, and downloads it to `models/loras/` via `.part` → rename.
3. A marker `models/loras/.civitai-version-<id>` remembers the resolved file,
   so later boots skip the API call entirely.
4. `models/loras/H3_ADULT_LORAS_INDEX.txt` maps each downloaded file to its
   catalog key, strength and trigger — use it to pick files in the loaders.

If CivitAI does not answer, returns an error, lists no primary file, or the
file is not `.safetensors`, that entry is **skipped with a WARN** and
provisioning continues; nothing is guessed. A failed CivitAI download is also a
WARN (not a hard failure), since these are optional.

You can also add any CivitAI version to `models.conf` directly:

    loras | civitai-version:3268303

## Selecting

| `H3_ADULT_LORAS` | Result |
|---|---|
| unset or `default` | the 6 rows marked `default=yes` (≈1.4 GB total, observed) |
| `all` | all 24 (≈6.5 GB, observed) |
| `none` | nothing |
| `default,pov_doggy,3405852` | defaults + a key + a version id |

## Using them (nothing is enabled by default)

**No bundled workflow enables an adult adapter.** The Multishot workflows keep
their original LoRA stack (slot 1 = turbo, strength 0 as shipped; slots 2–4
empty) and the official graphs are unmodified. To use one:

- Multishot workflows (`H3_Extend_Take`, `H3_Seamless_Chain_v2`, `CORE`,
  `Keyframes`): pick the file in **H3LoraStack** slot 2/3/4.
- Official graphs: add a stock **LoraLoaderModelOnly** after the turbo loader.

Guidance: **1–3 adapters at a time**, start at the low end of the strength
range, put trigger words first where noted. Official docs: style LoRAs compete
with references on R2V — keep them ≈0.5 there.

## Compatibility and availability — UNVERIFIED

Nothing below has been rendered on a GPU by this repo. CivitAI tags every
version with base model "MiniMax H3"; it does **not** say whether a LoRA was
trained on ref2va or fl2va, except where the author put it in the title or file
name (noted). Pairing a LoRA with the "other" variant may work weaker or not at
all — test both. Availability changes: versions get removed, hidden or gated.

Observed via the public API on **2026-11-05 (no token)**. File names and sizes
are what CivitAI reported that day and are listed **for reference only** — the
provisioner resolves them live.

| key | version | name (owner list) | strength | trigger | default | CivitAI title / version (observed) | primary file (observed) | size | notes |
|---|---:|---|---|---|---|---|---|---:|---|
| `hmnsfw_aio_v25` | 3268303 | HMNSFW AIO Sex V2.5 | 0.4–0.7 | hmmotion first | yes | HMNSFW - AIO Sex LoRA / V2.5 | `HMNSFW-AIO-V2.5.safetensors` | 82 MB | — |
| `hmbreasts_v2` | 3268969 | HMBreasts V2 | 0.6–1.0 | HMBreasts + size/shape/areoles | yes | HMBreasts - Breasts/Areoles LoRA for MiniMax H3 / V2 | `HMBreastsV2.safetensors` | 74 MB | — |
| `hmpenis_v2` | 3247473 | HMPenis v2.0 | ~1.0 | HMPenis + Front/Side | yes | HMPenis - Penis/Cock LoRA for MiniMax H3 / v2.0 | `PenisV2_minimax-h3_epoch60.safetensors` | 74 MB | — |
| `hmcumshot` | 3238531 | HMCumshot | 0.9 | cumshot | yes | HMCumshot - Cumshot LoRA for MiniMax H3 / V0.5 | `HMCumshot_V2.safetensors` | 597 MB | — |
| `h3_motion_booster` | 3205912 | H3 Motion Booster | 0.6–0.8 | dynv2 | yes | Faster! Harder! Shake Harder! / H3 Motion Booster(ANIME Edition Update) / V0.1 | `H3_Motion_Booster.safetensors` | 296 MB | — |
| `better_motion` | 3256084 | Better Motion (AdaptiveVision) | 0.4–0.8 | No trigger | yes | Better Human Motion H3/LTX 2.5 / v1.0-MH3 | `mvmt_h3_lora_v1_500.safetensors` | 296 MB | multi-model page; this version is the H3 one |
| `blowjob_v3` | 3285598 | Blowjob v3 | 0.7–1.0 | bl0w_j0b | no | — | `—` | — | API returned "Model not found" without a token — may need `CIVITAI_API_TOKEN` or may be removed; will WARN and skip if still unavailable |
| `blowjob_classic` | 3212494 | Blowjob classic | 0.7–1.0 | bl0w_j0b | no | — | `—` | — | API returned "Model not found" without a token — may need `CIVITAI_API_TOKEN` or may be removed; will WARN and skip if still unavailable |
| `messy_blowjob` | 3399472 | Messy Blowjob | 0.7–1.0 | ME$$Y + spit/drool language | no | Messy Blowjob H3 / v1.0 | `MessyBlowjob_v1_H3.safetensors` | 296 MB | — |
| `softsuck_blowjob` | 3412628 | Softsuck Blowjob | 0.7–0.8 | Descriptive soft rhythmic suction | no | Minimax Softsuck Blowjob / v1.0 | `MiniMaxH3-TI2V-Softsuck-e82.safetensors` | 273 MB | — |
| `darings_deepthroat` | 3205475 | Daring’s Deepthroat | 0.7–1.0 | Descriptive (throat bulge, saliva) | no | Daring's Deepthroat H3/LTX2.3 / MiniMax H3 FL2VA  v.01 | `deepthroat_v1.safetensors` | 1138 MB | author labels it FL2VA; multi-model page; this version is the H3 one |
| `h3_deep_motion` | 3254522 | H3 Deep Motion Booster | ~0.8 | oraldetail1 / oralmove1 | no | Deeper... Hold It. / H3 Deep Motion Booster / V1 | `H3_Deeper.safetensors` | 148 MB | — |
| `tada_cum_swallow` | 3241306 | TADA Cum Swallow | 0.4–0.5 | TADAA. first | no | TADA - Cum Swallow LoRA / v1.0 MiniMax H3 | `TADA H3 - ORAL SWALLOW.safetensors` | 148 MB | — |
| `cimlg_oral_cp_v2` | 3398711 | CIMLG Oral Creampie v2 | 0.4–0.5 | CUMOUF (keep low) | no | CIMLG - The Oral Creampie LoRa - Minimax H3 / v2 - Minimax H3 | `CIMLG_v2_H3_step2500.safetensors` | 148 MB | — |
| `hmmisdog_v15` | 3356770 | HMMisDog v1.5 | 0.6–0.8 | No trigger (updated) | no | HMMisDog - Missionary / Doggy POV LoRA for Minimax H3 / v1.5 | `HMMisDogV1.5.safetensors` | 296 MB | — |
| `hmmisdog_v1` | 3308736 | HMMisDog | 0.6–0.8 | No trigger — describe missionary/doggy POV | no | HMMisDog - Missionary / Doggy POV LoRA for Minimax H3 / v1.0 | `hm_nsfw_mis_doggy_only_v16_r32_384_minimax-h3_epoch170.safetensors` | 296 MB | — |
| `missionlg` | 3403761 | MISSIONLG Missionary Augmenter | ~1.0 | MISSIONLG (optional) | no | MISSIONLG - Mission Impossible - Missionary Position Augmenter H3 / v1.0 | `MISSIONLG_H3_v1.safetensors` | 592 MB | — |
| `missionary_pov` | 3279596 | Missionary POV | 0.7–0.9 | having missionary sex | no | Missionary Sex - POV / MiniMaxH3 | `missionary-mh3-e64-az420.safetensors` | 296 MB | — |
| `pov_doggy` | 3300169 | POV Doggy | 0.7–0.9 | POV doggystyle sex | no | POV Doggy / MiniMaxH3 | `pov-doggy-mh3-e29-az420.safetensors` | 296 MB | — |
| `cowgirl_position` | 3258236 | Cowgirl Position | variable | cowgirl position + thrusting | no | [MinimaxH3] Cowgirl Position (NSFW) INT8 Convrot / v1.0 | `Minimaxh3-cowgirl_position-Ref2V-512_000000550.safetensors` | 148 MB | author labels it Ref2V |
| `beanflk` | 3267091 | BEANFLK | variable | BEANFLK | no | BEANFLK — Masturbation & Finger Insertion + Audio / v1.0 - H3 MiniMax | `BEANFLK_H3_V1_3150797.safetensors` | 148 MB | 2 files; only the primary is fetched (others: BEANFLK_H3_V1_3150921.safetensors) |
| `hminnie` | 3222484 | HMInnie | variable | inniepussy + direction | no | HMInnie - Innie Pussy LoRA for MiniMax H3 / v1.0 | `HMInnie_v1_e50.safetensors` | 296 MB | — |
| `mystic_xxx` | 3266628 | Mystic XXX latest | 0.6–0.8 | Descriptive anatomy | no | [MMH3] Mystic XXX / v4.0 | `MysticXXX_MMH3-V4.safetensors` | 148 MB | 2 files; only the primary is fetched. The author also publishes a ref2va-specific file (MysticXXX_MMH3-V4-ref2va.safetensors) that is NOT auto-downloaded — get it from the version page if you run it on ref2va |
| `dr34ml4y_aio` | 3405852 | DR34ML4Y All-in-One | 0.6–0.8 | m15510n4ry / bl0wj0b / d0gg1e / c0wg1rl | no | DR34ML4Y - All-In-One NSFW (H3/WAN/LTX2) / DR34ML4Y_H3_P1 | `H3_DR34ML4Y_P1.safetensors` | 564 MB | multi-model page; this version is the H3 one |

Totals above are computed from observed `sizeKB`. Two versions (3285598
"Blowjob v3", 3212494 "Blowjob classic") answered **"Model not found"**
without a token on 2026-11-05; with a token they may resolve (CivitAI hides
some mature content from anonymous API calls) — otherwise they are skipped
with a WARN.

Content on CivitAI is subject to its terms and each model's license; you are
responsible for complying with them and with MiniMax H3's license.
