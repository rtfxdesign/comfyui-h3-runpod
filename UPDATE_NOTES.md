# Update notes: GPU tiers, CUDA 13 / torch 2.14.1, your image workflows (2026-11-15)

Base: the 2026-11-05 package below (`comfyui-h3-loras-workflow-update.zip`).
Goal: the home-PC setup (RTX 5070 Ti, 16 GB) scaled up for rented RunPod GPUs.

## What changed

**Runtime (Dockerfile)**
- Base `nvidia/cuda:12.8.1-cudnn-runtime-ubuntu22.04` → **`nvidia/cuda:13.0.3-cudnn-runtime-ubuntu24.04`**
  (Docker Hub amd64 digest `sha256:af851538a2bb05f587f27b660d61de3643d964e75ef5c04f4086ff2b36f2a12a`).
- Python 3.11 → **3.12** (Ubuntu 24.04's own) in a venv at `/opt/venv`.
- Unpinned cu128 torch → **torch 2.14.1+cu130, torchvision 0.29.1+cu130,
  torchaudio 2.11.0+cu130** (the home PC's versions; wheels checked on
  download.pytorch.org/whl/cu130). GPU kernels in that wheel: sm_75, 80, 86,
  90, 100, 120 → A100, A6000/A40, L40S/4090, H100/H200, B200, RTX 5090 /
  RTX PRO 6000.
- `PIP_CONSTRAINT` file pins torch/torchvision/torchaudio, transformers 5.23.0
  and safetensors 0.8.0 for every later pip install (custom-node requirements
  can no longer swap torch).
- ComfyUI **v0.44.0 → v0.45.0** (commit 989d93d0d, same as home; needed by the
  official H3 Image templates, minComfyUIVersion 0.45.0).
- ComfyUI-Manager: git clone of ltdrdata/ComfyUI-Manager → pip
  `comfyui_manager==4.2.2` from ComfyUI's `manager_requirements.txt`, launched
  with `--enable-manager` (how v0.45.0 does it, and what home runs).
- Build-time check that torch is 2.14.1 / CUDA 13.0. Healthcheck start period
  raised to 1 h (first boot downloads 120–250 GB).
- A full `uv pip compile` of torch + ComfyUI v0.45.0 requirements + manager +
  jupyterlab under the constraints for Python 3.12 / manylinux_2_28 resolves
  cleanly (190 packages). The image itself was **not built here** (no Docker
  on the box) — the GitHub Action builds it.

**GPU tiers (new)** — `H3_TIER=auto|16|24|48|80|96|none`, auto from
`nvidia-smi` VRAM (`scripts/gpu_tier.sh`).
- `tools/tiers_spec.py` → `tools/build_tiers.py` generates
  `config/tiers/{16,24,48,80,96}.conf` and `workflows/tiers/<tier>/`
  (22 workflows each). The build script HEAD-checks every Hugging Face URL
  (302/307) and reads sizes from `x-linked-size` / the CivitAI API; totals are
  in `tools/tier_summary.json`.
- Totals: 16 = 121.8 GB, 24 = 139.9 GB, 48 = 159.2 GB, 80 = 226.5 GB,
  96 = 250.8 GB (decimal GB, before LoRA catalogs).
- Each tier includes the H3 **Image** model + image VAE + Qwen3.5 9B prompt
  enhancer, both video models, both turbo LoRAs, the **pDMD 2-step** image LoRA,
  the Fun ControlNet patch + SDPose, and **H3 Eros Max beta7** at the tier's
  precision (fix1_int8 / int8HQ / bf16 — the exact CivitAI file is chosen by
  name).
- `config/models.conf` no longer downloads anything by default; it is for your
  extras (and is the only manifest with `H3_TIER=none`). Verified optional
  lines added (unpruned int8/bf16, pDMD merged checkpoint, fl2v 4-step 768p,
  ControlNet Union 2.0).
- Profiles: `official-ref2v`, `official-fl2v`, `controlnet` marked redundant
  with a tier; `fasth3` / `pika-flex` keep only their own files (TE/VAE lines
  commented — the tier provides them).

**Provisioning (`scripts/provision.sh`)**
- Tier manifest first, then models.conf, profiles, adult LoRAs, **image LoRAs**.
- `civitai-version:<id> | <file>` now downloads **that exact file** of the
  version (was: primary file renamed). Missing name → WARN + skip.
- New catalog `config/image_loras.conf` (`H3_IMAGE_LORAS`, into
  `models/loras/H3-Image/`): Anime Classic HD 3466709, Breast Size Slider
  3471708, Natural Breasts 3471964, CROWN realism 3465545, Penis (H3 Image)
  3465094, Uncut Penis 3471151 (opt-in). All returned HTTP 200 with a primary
  .safetensors on 2026-11-15.
- `CIVITAI_TOKEN` accepted as an alias of `CIVITAI_API_TOKEN`.
- Workflows seed to `H3/<tier>GB/` (tier copies) and `H3/original/`.
- `SCRIPTS_DIR` defaults to the script's own folder, so the dry run works from
  the repo.

**Start (`scripts/start.sh`)** — adds `--enable-manager` (`H3_ENABLE_MANAGER`),
`--highvram` automatically on ≥ 140 GB GPUs (`H3_HIGHVRAM`), logs the tier.
`--disable-dynamic-vram` is documented (README, .env.example) as the
VBAR MemoryError fix, not on by default.

**Workflows**
- Added your 5: `H3_image_two_people`, `_4img`, `_5img_pose`,
  `H3_image_one_woman_5parts`, `H3_character_sheet` (from the PC export,
  unchanged).
- `workflows/official/` refreshed to Comfy-Org/workflow_templates
  `79b02f4a79e233c07ec4923e39f40be27448549d` (the home PC's six video
  templates are byte-identical to it) and the two H3 Image templates added.
- Node check: every node type in the 5 custom image workflows and all 13
  official templates is a core ComfyUI v0.45.0 node (1,119 node ids read from
  the v0.45.0 source). Only the 4 Multishot workflows need custom packs.

**Custom nodes (`config/nodes.conf`)** — added
`DeepNeuralNerd/H3-Video-LoRA-Loader-for-Image` pinned to
`bfea69a5043f9b404f35ddaefd526d7e7fc9fd04`. All URLs answered `git ls-remote`.
VideoHelperSuite and rgthree were already there.

## Checks run
- `bash -n` on all 4 scripts; shellcheck (warning level): only "unused
  variable" notes in the sourced `gpu_tier.sh` (silenced).
- All 134 JSON files parse. In every tier copy, every model file a loader names
  is in that tier's manifest or an opt-in profile, and every `models[].url`
  ends in its `name`.
- `DRY_RUN=1` for tiers 16 and 80: exit 0, no warnings, Eros resolved to the
  right file per tier, image LoRAs → `loras/H3-Image/`.
- Real (non-dry) mini run with a 2-line test manifest: downloaded an H3
  embedding, rejected a named non-safetensors CivitAI file and a missing file
  name with WARNs, seeded `H3/24GB/` and `H3/original/` (22 files each).
- Fake `nvidia-smi` at 16/24/32/46/80/96/141/180 GB → tiers 16/24/24/48/80/96/96/96.

## Not verified / skipped
- Nothing was run on a GPU. Speed and quality per tier are not measured.
- The image was not built locally.
- Unpruned video checkpoints are not used by any tier (all LoRAs/templates
  target pruned); they are commented in models.conf.
- No fp8 tier: Comfy-Org says fp8_scaled only if int8_convrot cannot be used,
  and this image is cu130.
- No CUDA 12.8 fallback image: torch 2.14.1 has no cu128 wheel.
- Blowjob v3 (3285598) and Blowjob classic (3212494) still 404 on CivitAI.
- Image-LoRA strengths are starting points, not taken from the pages.

---

# Update notes: adult LoRA catalog + official H3 workflows (2026-11-05)

Base: `rtfxdesign/comfyui-h3-runpod` default branch, tree
`9ba90741ada786faa8f0d85d7147acc9770549e7` (16 files). All 16 were read
through the GitHub API, and each one's git blob SHA-1 was checked against the
tree, so the unchanged files are byte-identical to the repo.

## Files

**Modified (7):**
- `Dockerfile`: `COMFYUI_REF` changes from `master` to **`v0.44.0`**, and `jq` is installed.
- `scripts/provision.sh`: adds `civitai-version:` resolution, model profiles, the adult LoRA catalog, `DRY_RUN`, node-pin checks, optional extras, and seeding of `workflows/official/`.
- `config/models.conf`: documents the new URL scheme and profiles, and adds a commented int8 VAE line. The default model set is unchanged.
- `config/nodes.conf`: Multishot is pinned to `v2.7.2`. Adds notes on Motion-Context and RES4LYF, plus a commented RES4LYF `v1.2.1` line.
- `.env.example`: adds `H3_MODEL_PROFILES`, `H3_ADULT_LORAS`, `PROVISION_ADULT_LORAS_URL`, `NODES_SYNC_PINS`, `H3_INSTALL_MOTION_CONTEXT`, `H3_INSTALL_WRITER_PACK` and `DRY_RUN`. It contains no values for any credential.
- `.github/workflows/build.yml`: adds `workflows/**` to the path triggers, because the image bakes the workflows in.
- `README.md`: adds sections on the official workflows, the LoRA catalog and the new env vars, plus notes on the ComfyUI pin and `context_pin`.

**Added (21):**
- `UPDATE_NOTES.md`: this file.
- `config/adult_loras.conf`: 24 entries, 6 of them default.
- `config/profiles/official-ref2v.conf`, `official-fl2v.conf`, `controlnet.conf`, `fasth3.conf` and `pika-flex.conf`.
- `docs/ADULT_LORAS.md`
- `scripts/install-motion-context.sh`: optional, pinned to v0.7.1.
- `workflows/official/README.md`
- 11 official workflow files in `workflows/official/`, under their upstream names:
  - `video_minimax_h3_r2v.json`
  - `video_minimax_h3_multiframe_reference.json`
  - `video_minimax_h3_i2v.json` (I2V and FL2VA)
  - `video_minimax_h3_i2v_continuation.json`
  - `video_minimax_h3_t2v.json`
  - `video_minimax_h3_fun_controlnet_union.json`
  - `video_fastvideo_fasth3_i2v.json`
  - `video_fastvideo_fasth3_t2v.json`
  - `video_fasth3_ominiref_r2v.json`
  - `video_pika_h3_flex_ref2va.json`
  - `video_pika_h3_flex_fl2va.json`

**Unchanged (9):** `.dockerignore`, `.gitattributes`, `.gitignore`, `scripts/start.sh`,
`workflows/H3_Extend_Take.json`, `H3_Keyframes.json`, `H3_Seamless_Chain_CORE.json`,
`H3_Seamless_Chain_v2.json` and `UPSTREAM-INSTALL.md`.

The original ref2va Multishot defaults and turbo mechanics are untouched. That
covers the ref2va pruned int8 checkpoint, the ref2v 4-step turbo in
models.conf, the fp16 video VAE, and the four workflows with `H3LoraStack`
exactly as shipped. **No workflow enables any adult adapter.** You enable 0 of
them by default and choose 1–3 yourself.

## Configuration

| Env var | Default | Effect |
|---|---|---|
| `H3_ADULT_LORAS` | `default` | `default` gives 6 adapters: HMNSFW AIO V2.5, HMBreasts V2, HMPenis v2.0, HMCumshot, H3 Motion Booster and Better Motion, about 1.4 GB observed. `all` gives all 24, `none` gives none, or you can list keys or ids. |
| `H3_MODEL_PROFILES` | empty | `official-ref2v`, `official-fl2v`, `controlnet`, `fasth3` or `pika-flex` |
| `NODES_SYNC_PINS` | `0` | `1` moves existing node clones onto their pins |
| `H3_INSTALL_MOTION_CONTEXT` | `0` | `1` installs Motion-Context v0.7.1 |
| `H3_INSTALL_WRITER_PACK` | `0` | `1` copies the JoyEcho writer pack from Multishot v2.7.2 |
| `DRY_RUN` | `0` | `1` prints the plan and writes nothing |

**CivitAI resolution.**
1. The provisioner calls `GET https://civitai.com/api/v1/model-versions/<id>`.
2. `jq` picks the file marked `primary`.
3. The download URL must be `https://civitai.com/api/download/models/<id>[?...]`. If it isn't, the canonical URL is used.
4. The file name must be a plain `.safetensors` name.
5. On any non-200 response, missing primary file or other problem, the provisioner logs a WARN, skips that entry and continues.

A marker file means later boots skip the API call. `models/loras/H3_ADULT_LORAS_INDEX.txt`
lists each file with its strength and trigger.

**Turbo families stay separate.** Each profile carries only its own adapter:
- ref2va uses the ref2v 4-step turbo.
- fl2va uses the fl2v 8-step turbo, from the URL the official templates use (`lightx2v/Minimax-h3-Turbo`).
- FastH3 uses no turbo, because it is distilled.
- Pika Flex uses its adapter in place of a turbo.

The official graphs use `minimax_h3_video_vae_int8_convrot`, which the profiles
download. The Multishot graphs keep the fp16 VAE.

## Verified sources

- **Official workflows:** <https://github.com/Comfy-Org/workflow_templates> at
  commit `ece24f0add491c5ffdfb7f01a6f8c2e8b654b4ac`, under `templates/`. Each
  file's blob SHA-1 equals the upstream tree entry; the table is in
  `workflows/official/README.md`. The min ComfyUI versions come from that
  commit's `templates/index.json`.
- **Docs:** <https://docs.comfy.org/tutorials/video/minimax/minimax-h3> and its `-native`,
  `-multiframe` and `-fun-controlnet` pages. They establish that T2V and FL2VA
  use fl2va with the 8-step turbo, R2V and Multiframe use ref2va with the
  4-step turbo, and style LoRAs should run at about 0.5 on R2V.
- **Model files:** <https://huggingface.co/Comfy-Org/MiniMax-H3> (tree listing),
  plus `lightx2v/Minimax-h3-Turbo`, `FastVideo/FastVideo-FastH3-Comfy`,
  `FastVideo/FastH3-OmniRef-Comfy` and `Comfy-Org/SDPose`. Every profile URL is
  either embedded in an official template or already in the original
  models.conf, and each one answered HEAD with a 302 or 307 redirect and a
  file size on 2026-11-05.
- **ComfyUI:** the newest release is `v0.44.0` (published 2026-11-03 20:12 EST). Its
  `comfyui_version.py` reads 0.44.0. Every node class in the 11 official graphs
  exists in the v0.44.0 source, except `MarkdownNote`, which is a
  frontend-only note node.
- **ComfyUI-H3-Multishot:** tag `v2.7.2` (commit `d7d197709fc9`). All 16 custom node
  classes used by the 4 repo workflows exist in that tag.
- **ComfyUI-H3-Motion-Context:** tag `v0.7.1` (commit `518c083d11d8`), which requires
  ComfyUI 0.34.0 or newer.

## Limitations: read before rendering

1. **Nothing was run on a GPU.** RunPod validation is still required: build
   the image, boot a 48 GB pod, confirm the custom nodes import on ComfyUI
   0.44.0, open each workflow, and render R2V, FL2VA, Extend_Take, and each
   adult adapter at a low strength.
2. **The `context_pin` default in Extend_Take and v2 will not run on this stack.**
   Multishot v2.7.2's pre-flight in `h3_multishot_utils.py` refuses any
   Motion-Context release from 0.4.0 on, including 0.7.1, and 0.3.1 only
   supports ComfyUI 0.33 and older. Set `continuity=first_frame`. That's why
   Motion-Context is a separate optional installer and isn't in nodes.conf.
   This problem already existed before this update: the image tracked
   `master`, which is past 0.34.
3. **The `beta57` scheduler in Extend_Take and v2 needs RES4LYF.** It's commented
   out in nodes.conf. Uncomment it, or switch the scheduler to `beta`.
4. **`JoyEcho_LLMEnhance` needs the writer pack.** Turn it on with
   `H3_INSTALL_WRITER_PACK=1`. Its requirements, which pin transformers below
   4.58, are not auto-installed.
5. **The other custom nodes have not been re-verified on ComfyUI 0.44.0.** Only
   Multishot's pin was checked.
6. **Adult LoRAs are unverified.** Compatibility, quality and the best strengths
   are all untested. CivitAI only reports "MiniMax H3" as the base model; a few
   titles say FL2VA or Ref2V (see `docs/ADULT_LORAS.md`). Versions 3285598
   (Blowjob v3) and 3212494 (Blowjob classic) returned "Model not found" to an
   anonymous request. They may work with a token; if not, they're skipped with
   a WARN.
7. **The int8_convrot weights run on cu128 here.** Comfy-Org recommends cu130
   for int8_convrot; that hasn't been measured.
8. **Existing volumes keep their old ComfyUI and node clones.** See the README
   for in-place update commands, and use `NODES_SYNC_PINS=1` for the nodes.
9. **There's no standalone local FL2VA template upstream.** FL2VA means
   `video_minimax_h3_i2v.json` with both `first_frame` and `last_frame`
   wired. The `api_*flf2v` templates are paid API graphs, so they were left out.

## Tests run on the build box (2026-11-05)

- **Scripts:** `bash -n` passes on all 3 scripts. ShellCheck 0.11.0 is clean on
  `provision.sh` and `install-motion-context.sh`. `start.sh` (unchanged) has
  one info-level SC2086 on `${COMFY_EXTRA_ARGS}`; the word splitting there is
  intentional.
- **Config parsing:** all 15 workflow JSON files parse, and `build.yml` parses
  with PyYAML.
- **Full dry run:** `DRY_RUN=1` with every profile, `H3_ADULT_LORAS=all`, plus
  a bogus profile and a bogus key, exited 0.
  - 22 of 24 CivitAI versions resolved to a primary `.safetensors` file.
  - The 2 unavailable versions, the bogus profile and the bogus key each
    produced a WARN and were skipped.
  - Nothing was written to disk.
- **Default dry run** (no env vars): 6 adult LoRAs resolved, 0 warnings.
- **Stubbed-curl run:** this exercised the real write path. It covered:
  - downloads and `.part` handling
  - markers and the index file
  - a failed CivitAI download, which gave a WARN and the run continued
  - an HTTP 404 from the metadata endpoint, which gave a WARN and the run continued
  - an explicit filename override
  - workflow seeding into `H3/` and `H3/official/`

  A second boot made zero API calls and skipped everything. `H3_ADULT_LORAS=none`
  also worked.
- **Node pins:** a real clone at `v2.7.2` landed on the right tag. A
  mismatched existing clone produced a pin WARN.
  `install-motion-context.sh` really cloned `v0.7.1`.
- **Secrets:** regex scans for GitHub, HF, OpenAI, AWS, Slack and private-key
  patterns, credential assignments in env files, and long hex strings all came
  back with no matches. There's no `.env` and no `.git` directory.

## How to push

```bash
cd /path/to/your/clone/comfyui-h3-runpod      # your existing git clone
git pull                                      # be on the latest main
cd ..
unzip -o comfyui-h3-loras-workflow-update.zip # overwrites files inside comfyui-h3-runpod/
cd comfyui-h3-runpod
git status && git diff                        # inspect every change
git add -A
git commit -m "Add CivitAI adult LoRA catalog, official H3 workflows, pin ComfyUI v0.44.0 / Multishot v2.7.2"
git push
```

The zip contains no `.git` directory and doesn't delete anything, so your
history and any local-only files stay as they are. The push triggers the GHCR
image build. After that, set `CIVITAI_API_TOKEN` (and optionally
`H3_MODEL_PROFILES` and `H3_ADULT_LORAS`) as RunPod pod env vars, never in files.
