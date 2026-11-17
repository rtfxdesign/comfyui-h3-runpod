# ComfyUI on RunPod — MiniMax H3 Image + Video, scaled to the GPU you rent

One Docker image that turns any RunPod GPU into the same ComfyUI setup as the
home PC (ComfyUI v0.45.0, Python 3.12, **PyTorch 2.14.1 + CUDA 13.0**), but with
**bigger, higher-precision models picked automatically for the card's VRAM**.

- **Image:** MiniMax H3 Image t2i / edit, plus your own workflows — two people,
  4-photo and 5-photo pose versions, one woman from 5 body-part photos, and the
  5-photo character/pose sheet.
- **Video:** official H3 T2V / I2V / FL2VA / R2V / multiframe / ControlNet
  templates, the Multishot long-take chains, the H3 Eros Max NSFW checkpoint,
  and the NSFW video LoRA catalog.
- Models download at **boot** onto your volume, not into the image, so the
  image stays small and changing models is a text edit.

---

## "Do I use Docker?" — what actually happens

You never run Docker yourself. The pieces:

1. **GitHub** holds this folder. When you push, the included GitHub Action
   (`.github/workflows/build.yml`) builds the Docker image on GitHub's
   machines and publishes it to **GHCR** (GitHub's container registry) as
   `ghcr.io/<your-user>/<repo>:latest`.
2. **RunPod** runs that image on a rented GPU. You point a RunPod *template*
   at the image name once; every pod you start from the template is the same
   setup.
3. On first boot the pod checks the GPU's VRAM, picks a **tier**, downloads that
   tier's models to the volume, installs the custom nodes, and opens ComfyUI on
   port 8188. Later boots on the same volume skip everything already there.

---

## Images only (smallest)

Only generating images? Add the pod env var **`H3_MODE=image`**. The pod then
downloads just what the H3 Image workflows load: the H3 Image model, the
Qwen3-VL 32B text encoder, the Qwen3.5 9B prompt enhancer (`TextGenerateV2`,
used by every image workflow), the image VAE, the pDMD 2-step speed LoRA and
the H3 Image LoRA catalog (default ≈ 0.6 GB). It skips the ref2va/fl2va video
models, video + audio VAEs, video turbo LoRAs, adult video LoRAs, Eros Max,
the ControlNet patch, SDPose/RT-DETR, the video-only node packs (Multishot,
sol-attn, VideoHelperSuite, VFI) and the video workflows.

| Tier | Typical GPUs | Images-only download (incl. image LoRAs) | Volume to create | Full stack, for comparison |
|---|---|---|---|---|
| **16** | RTX 4080/5080, A4000/A4500 | **47.7 GB** | **80 GB** | 121.8 GB |
| **24** | RTX 4090, **RTX 5090**, L4, A100 40GB | **61.6 GB** | **100 GB** | 139.9 GB |
| **48** | **L40S**, RTX 6000 Ada, A6000, A40 | **80.8 GB** | **120 GB** | 159.2 GB |
| **80** | **H100 80GB**, A100 80GB | **90.4 GB** | **130 GB** | 226.5 GB |
| **96** | RTX PRO 6000, H100 NVL, H200, B200 | **114.8 GB** | **150 GB** | 250.8 GB |

The volume size is the download plus ~30 GB for ComfyUI, outputs and a few
extra LoRAs. The manifests are `config/tiers/image/<tier>.conf`. Switching a
volume back to `H3_MODE=full` later just downloads the missing video files.
`H3_ADULT_LORAS` is `none` in image mode unless you set it yourself.

## Step by step (first time)

**1. Push this folder to GitHub.** Unzip it, then in the `comfyui-h3-runpod`
folder:

```bash
git init -b main            # skip if it is already your repo clone
git add -A
git commit -m "Scaled RunPod H3 stack"
git remote add origin https://github.com/rtfxdesign/comfyui-h3-runpod.git   # skip if already set
git push -u origin main
```

**2. Wait for the build.** GitHub → your repo → **Actions** → "Build and push
image". The first build takes roughly 15–30 minutes (CUDA 13 base + PyTorch).
A green check means the image is at `ghcr.io/rtfxdesign/comfyui-h3-runpod:latest`.
(You can also start it by hand: Actions → the workflow → **Run workflow**.)

**3. Let RunPod pull the image.** GHCR packages from a private repo are
private. Either
- **easiest:** GitHub → your profile → **Packages** → `comfyui-h3-runpod` →
  **Package settings** → **Change visibility → Public**, or
- keep it private: create a GitHub **classic** token with only `read:packages`,
  then in RunPod **Settings → Container Registry Auth → Add** (username
  `rtfxdesign`, password = that token) and select it in the template.

**4. Create a network volume** (RunPod → **Storage → New Network Volume**), in a
data center that has the GPU you want. Size it from the tier table below —
e.g. **300 GB for an H100** — or from the much smaller
[images-only table](#images-only-smallest) if you set `H3_MODE=image`. A network volume keeps the 120–250 GB of models
between pods, so you only download them once.

**5. Create a pod template** (RunPod → **Templates → New Template**):

| Field | Value |
|---|---|
| Container image | `ghcr.io/rtfxdesign/comfyui-h3-runpod:latest` |
| Container disk | **40 GB** |
| Volume mount path | `/workspace` |
| Expose HTTP ports | **`8188`** (ComfyUI) — add `8888` if you set `JUPYTER_PASSWORD` |
| Expose TCP ports | `22` (only if you want SSH) |
| Env `HF_TOKEN` | your Hugging Face read token |
| Env `CIVITAI_API_TOKEN` | your CivitAI API key (`CIVITAI_TOKEN` also works) |
| Env `H3_TIER` | `auto` (default) — or force `16` `24` `48` `80` `96` |
| Env `H3_MODE` | `image` for images only (≈ 48–115 GB instead of 122–251 GB); leave unset for image + video |
| Env `JUPYTER_PASSWORD` | optional — turns on the JupyterLab file manager |

Put tokens **only** in RunPod's environment variables (RunPod "Secrets" work
too). Never commit them to the repo.

**6. Deploy a pod.** Pick the GPU, attach the network volume, choose your
template, and in the GPU filter set **CUDA version 13.0** (or newer). This
image is CUDA 13 and needs a host driver ≥ 580; an older host fails to start
it.

**7. Watch the first boot.** Pod → **Logs**. You will see the tier it picked,
e.g. `GPU tier 80 (auto: GPU 0 has 81559 MiB …)`, then the downloads. At
~100–300 MB/s, 120–250 GB takes roughly 10–40 minutes.

**8. Open ComfyUI.** Pod → **Connect** → **HTTP 8188**. In the workflow sidebar
open **`H3/<tier>GB/`** — e.g. `H3/80GB/H3_image_two_people_5img_pose` — those
copies already name your tier's model files. `H3/original/` holds the graphs
exactly as shipped (home-PC file names).

**9. Stop the pod when you are done.** The network volume keeps the models
(RunPod bills it per GB per month); delete the volume if you want to stop
paying for storage.

---

## GPU tiers

`H3_TIER=auto` reads the first GPU's memory with `nvidia-smi`. All file names
and sizes come from the Hugging Face / CivitAI APIs (checked 2026-11-15).

| Tier | Auto when VRAM is | Typical RunPod GPUs | Video models (ref2va + fl2va) | Image model | Text encoder (Qwen3-VL 32B) | Prompt enhancer (Qwen3.5 9B) | Video VAE | Eros Max (CivitAI) | **Download** | **Volume** |
|---|---|---|---|---|---|---|---|---|---|---|
| **16** | < 22 GB | RTX 4080/5080, A4000/A4500 | pruned int8_convrot (20.97 GB each) | pruned int8 (20.98) | nvfp4 (15.69) | w4a8 (7.34) | int8 (2.81) | fix1_int8 (21.06) | **121.8 GB** | 200 GB |
| **24** | 22–43 GB | RTX 4090 (24), **RTX 5090 (32)**, L4, A100 40GB | pruned int8_convrot (20.97 each) | pruned int8 (20.98) | **int8** (27.14) | int8 (9.75) | **fp16** (5.21) | int8HQ (22.89) | **139.9 GB** | 200 GB |
| **48** | 44–74 GB | **L40S**, RTX 6000 Ada, A6000, A40 | pruned int8_convrot (20.97 each) | **pruned bf16** (40.23) | int8 (27.14) | int8 (9.75) | fp16 (5.21) | int8HQ (22.89) | **159.2 GB** | 250 GB |
| **80** | 75–91 GB | **H100 80GB**, A100 80GB | **pruned bf16** (40.23 each) | pruned bf16 (40.23) | int8 (27.14) | **bf16** (19.31) | fp16 (5.21) | **bf16** (40.22) | **226.5 GB** | 300 GB |
| **96** | ≥ 92 GB | **RTX PRO 6000 (96)**, H100 NVL, **H200 (141)**, **B200 (180)** | pruned bf16 (40.23 each) | pruned bf16 (40.23) | **bf16** (51.51) | bf16 (19.31) | fp16 (5.21) | bf16 (40.22) | **250.8 GB** | 350 GB |

Every tier also gets: audio VAE fp32 (0.61), image VAE fp16 (1.17), ref2v
4-step turbo + fl2v 8-step turbo (1.96 each), the **H3 Image pDMD 2-step speed
LoRA** (1.96), the Fun ControlNet Union patch (int8 2.30 / bf16 4.22 on 80+),
and SDPose + RT-DETR for the ControlNet template (2.04). On top of the tier:
adult video LoRAs (default 6 ≈ 1.5 GB, `all` ≈ 7.0 GB), H3 Image LoRAs
(default ≈ 0.6 GB, `all` ≈ 0.9 GB). Add ~50 GB to the volume for
`H3_MODEL_PROFILES=fasth3` (two 22 GB checkpoints) and for your outputs.

**Which GPU should I rent?**
- **Images only / cheapest:** RTX 5090 (tier 24) with `H3_MODE=image`
  (61.6 GB download, 100 GB volume). Same models as home but the int8 text
  encoder and 2× the VRAM headroom.
- **Images at full bf16 + video:** L40S (tier 48).
- **Best video quality per dollar:** H100 80GB (tier 80) — everything bf16.
- **Everything resident, no swapping:** H200 / B200 (tier 96, `--highvram` on
  automatically). RTX PRO 6000 96 GB also lands in tier 96 but without
  `--highvram` (the bf16 text encoder swaps in and out).
- **A100 / A6000 / A40 (Ampere):** supported — the torch build has sm_80/sm_86
  kernels and int8_convrot runs on them — just slower than Hopper/Blackwell.

**Why these choices.** Comfy-Org's model card: "prefer `int8_convrot` if you
are able to use pytorch with cu130; `fp8_scaled` should only be used if you
cannot use `int8_convrot`" — this image is cu130, so there are no fp8 tiers.
All tiers use the **pruned** checkpoints, because every official template,
both turbo LoRAs, the ControlNet patch and the community LoRAs target the
pruned builds; unpruned int8/bf16 (34 / 66 GB) are listed commented-out in
`config/models.conf` if you want to experiment. Below ~80 GB, ComfyUI loads
the text encoder to encode the prompt and swaps it out before sampling; on 80
GB the int8 encoder (27 GB) fits next to a bf16 model (40 GB); on 141 GB+ all
of image + video + bf16 encoder fit at once.

To change a tier, edit `tools/tiers_spec.py` and run
`python3 tools/build_tiers.py` — it re-checks every URL and size and
regenerates `config/tiers/*.conf`, the images-only `config/tiers/image/*.conf`
and `workflows/tiers/*/`.

---

## Workflows

Seeded into the ComfyUI sidebar on boot (never overwriting your edits):

- **`H3/<tier>GB/`** — use these. Same graphs, model names switched to the tier.
- **`H3/original/`** — exactly as shipped (home-PC file names).

| Workflow | What it does |
|---|---|
| `H3_image_two_people` | Picture 1 = her, Picture 2 = him → one image of both |
| `H3_image_two_people_4img` | 1 her face, 2 her body, 3 his face, 4 his body |
| `H3_image_two_people_5img_pose` | same four + Picture 5 = the positions/pose photo (pose, angle, framing only) |
| `H3_image_one_woman_5parts` | 1 face, 2 full body, 3 chest, 4 hips/butt, 5 legs → one consistent woman |
| `H3_character_sheet` | the same 5 photos → a 2560×1440 pose sheet (front, ¾, side, back, sitting, walking, hands on hips, 2 head shots) |
| `official/image_minimax_h3_image_t2i`, `official/image_minimax_h3_image_edit` | Comfy-Org H3 Image templates |
| `official/video_minimax_h3_*` | T2V, I2V/FL2VA, continuation, R2V, multiframe, Fun ControlNet pose |
| `official/video_fastvideo_fasth3_*`, `video_fasth3_ominiref_r2v` | need `H3_MODEL_PROFILES=fasth3` |
| `official/video_pika_h3_flex_*` | need `H3_MODEL_PROFILES=pika-flex` |
| `H3_Extend_Take`, `H3_Seamless_Chain_v2`, `_CORE`, `H3_Keyframes` | Multishot long-take chains (below). The tier copies swap their GGUF names for the tier's safetensors — the pack's `H3ModelLoaderAny` / `H3ClipLoaderAny` load both. |

Image tips (same as home): Euler, simple scheduler, 6 steps, CFG 1, ~4 MP.
**2-step mode:** add a `LoraLoaderModelOnly` with
`minimax_h3_pdmd_2nfe_comfyui.safetensors` at **strength 1.0** between the
image model loader and the sampler, and set steps to 2. Image LoRAs from the
catalog are in `loras/H3-Image/`. To try the NSFW **video** LoRAs on the image
model, use the **H3 Image LoRA Stack** node (custom node
`H3-Video-LoRA-Loader-for-Image`), which drops the 6 video-only tensors.

---

## Environment variables

| Variable | Default | Purpose |
|---|---|---|
| `HF_TOKEN` | — | Hugging Face token (read). Sent only to huggingface.co |
| `CIVITAI_API_TOKEN` (or `CIVITAI_TOKEN`) | — | CivitAI downloads: Eros Max, adult + image LoRA catalogs. Sent only to civitai.com |
| `H3_TIER` | `auto` | `auto`, `16`, `24`, `48`, `80`, `96`, or `none` (only `models.conf` + profiles) |
| `H3_MODE` | `full` | `full` = image + video stack; `image` = images only (`config/tiers/image/<tier>.conf`, no video models/LoRAs/nodes/workflows — see [Images only](#images-only-smallest)) |
| `H3_HIGHVRAM` | `auto` | `--highvram` only on ≥ 140 GB GPUs; `1` force on, `0` off |
| `H3_ENABLE_MANAGER` | `1` | ComfyUI-Manager (`--enable-manager`); `0` = off |
| `H3_ADULT_LORAS` | `default` | `default` / `all` / `none` / comma list of keys or CivitAI version ids (`config/adult_loras.conf`) |
| `H3_IMAGE_LORAS` | `default` | same, for `config/image_loras.conf` → `models/loras/H3-Image/` |
| `H3_MODEL_PROFILES` | — | extra sets from `config/profiles/`: `fasth3`, `pika-flex` (the `official-*` / `controlnet` profiles are only for `H3_TIER=none`) |
| `COMFY_EXTRA_ARGS` | — | extra ComfyUI flags (see below) |
| `JUPYTER_PASSWORD` | — | set = JupyterLab on 8888 with this as the token |
| `PROVISION_CONFIG_URL` / `PROVISION_NODES_URL` / `PROVISION_ADULT_LORAS_URL` | — | raw GitHub URLs that override the baked-in `models.conf` / `nodes.conf` / `adult_loras.conf` without a rebuild |
| `GH_CONFIG_TOKEN` | — | PAT for those URLs on a private repo (sent only to GitHub) |
| `NODES_SYNC_PINS` | `0` | `1` moves existing node clones onto the pins in `nodes.conf` |
| `H3_INSTALL_MOTION_CONTEXT` / `H3_INSTALL_WRITER_PACK` | `0` | optional Multishot extras |
| `DRY_RUN` | `0` | `1` prints the plan, downloads nothing |
| `SKIP_PROVISION` | `0` | `1` boots straight to ComfyUI |
| `COMFY_PORT` | `8188` | listen port (must match the exposed HTTP port) |

**Launch flags.** `start.sh` always runs
`python main.py --listen 0.0.0.0 --port 8188 --enable-manager`, adds
`--highvram` on ≥ 140 GB GPUs, then `COMFY_EXTRA_ARGS`. Useful extras:
- `--disable-dynamic-vram` — the fix for the **VBAR MemoryError** in
  `TextGenerateV2` you hit at home; add `--disable-pinned-memory` if it
  persists. Not on by default because pods have plenty of RAM; turn it on if
  you see that error.
- `--lowvram` only for cards under ~16 GB. `--use-sage-attention` only if you
  install sageattention yourself.

**Check the plan without downloading** (on any Linux/WSL box with bash, curl, jq):

```bash
DRY_RUN=1 H3_TIER=80 COMFY_DIR=/tmp/c CONFIG_DIR=./config \
  WORKFLOWS_SRC=./workflows bash scripts/provision.sh
```

---

## What is in the image

| | |
|---|---|
| Base | `nvidia/cuda:13.0.3-cudnn-runtime-ubuntu24.04` (CUDA 13.0.3, cuDNN 9.14) |
| Python | 3.12 (Ubuntu 24.04) in `/opt/venv` |
| PyTorch | torch 2.14.1+cu130, torchvision 0.29.1+cu130, torchaudio 2.11.0+cu130 — kernels for sm_75/80/86/90/100/120 |
| Pinned like home | transformers 5.23.0, safetensors 0.8.0; from ComfyUI's requirements: comfy-kitchen 0.2.41, comfy-aimdo 0.6.0, frontend 1.58.5, comfyui_manager 4.2.2 |
| ComfyUI | v0.45.0 (commit 989d93d0d) |
| Guard | `PIP_CONSTRAINT=/opt/provision/constraints.txt` keeps torch/transformers/safetensors at those versions even when a custom node's requirements.txt asks for something else |
| Custom nodes (installed at boot, `config/nodes.conf`) | H3-Multishot v2.7.2, sol-attn, VideoHelperSuite, VFI, Spectrum-MiniMax-H3, rgthree, KJNodes, Custom-Scripts, Easy-Use, **H3-Video-LoRA-Loader-for-Image** (pinned), GGUF |

---

## How the chaining actually works

This is the part worth understanding before you open the workflow, because it
is not what most people expect.

**You do not render vid1, grab its last frame, and feed it into vid2 by hand.**
`H3MultishotMemorySampler` does the entire chain inside a single node:

| Input | What it does |
|---|---|
| `start_image` | Your opening still — frame one of shot one |
| `shot_count` | How many shots to chain |
| `frames_per_shot` | Length of each |
| `memory_frames` | **The handoff.** Frames carried from the tail of each shot into the next |
| `anchor_frames` | Frames pinned so the join does not drift |
| `handoff_taper` / `handoff_release` / `handoff_depth` | How hard the seam is enforced vs. allowed to breathe |
| `join_blend` / `join_anchor_noise` | Blending across the cut |
| `reference_images` | Wire `H3AutoRefs` here — character identity |

It outputs `master_frames`, `master_audio`, and **`video_latents` + `audio_latents`**,
so the latents are available if you want to post-process rather than re-decode.

Set `shot_count: 6`, and you get six shots handed off tail-to-head as one
continuous take. Raise `memory_frames` for smoother joins, lower it if shots
start feeling like they repeat themselves.

---

## Character consistency: H3AutoRefs

Put one folder per character under `input/h3_refs/` — the pod creates this tree
on first boot with a README in it:

```
input/h3_refs/
    rae/
        rae_front.png
        rae_three_quarter.png
        rae_profile.png
    marcus/
        ...
```

`H3AutoRefs` scans your prompt for those **folder names** and casts the photos
into H3's nine reference slots. A **front / three-quarter / profile** trio holds
identity better than a pile of similar front-on shots.

Nine slots are shared across *all* matched characters, so fewer characters per
run means each face is held more firmly.

### ⚠️ This requires ref2va — it is not interchangeable

The Multishot workflows load **`ref2va`** deliberately. ref2va carries *reference rows*:
the identity bank and the nine reference slots.

**`fl2va` has no reference rows at all.** Swap the checkpoint and H3AutoRefs
silently does nothing — no error, characters just drift. If identity is being
ignored, check which checkpoint the loader names first.

The trade: ref2va holds a supplied keyframe only *softly*, where fl2va lands on
it exactly. For a character-driven chain that is the right trade — identity
re-locks from each shot's closing frames, which is what makes the chain hold.

---

---

## Adult and image LoRA catalogs

`config/adult_loras.conf` lists the MiniMax H3 **video** adult LoRAs by CivitAI
version id (the same 22 that are on the home PC, plus 2 Blowjob versions that
currently return 404 and are skipped with a warning).
`config/image_loras.conf` lists LoRAs trained on the H3 **Image** model. At
boot each selected version's file is resolved through the CivitAI API and
downloaded; anything gone is skipped with a warning. Nothing is switched on in
any workflow — add 1–3 at a time, low strength first. Details:
[`docs/ADULT_LORAS.md`](docs/ADULT_LORAS.md).

---

## Notes

**Turbo LoRA is variant-matched.** ref2v 4-step turbo only with ref2va, fl2v
8-step turbo only with fl2va. Every tier downloads both; never cross them.

**ComfyUI is pinned to v0.45.0** (`COMFYUI_REF` in the Dockerfile, the same
commit as the home PC). An **existing** `/workspace/ComfyUI` on a persistent
volume is NOT replaced by a new image — update it in place:
`git -C /workspace/ComfyUI fetch --tags && git -C /workspace/ComfyUI checkout v0.45.0 && pip install -r /workspace/ComfyUI/requirements.txt -r /workspace/ComfyUI/manager_requirements.txt`.

**Pin your node refs once you are happy.** ComfyUI-H3-Multishot is pinned to
`v2.7.2`. `nodes.conf` is unpinned because
these packs are actively maintained. SSH in, run
`git -C /workspace/ComfyUI/custom_nodes/<pack> rev-parse HEAD`, paste the SHAs
back. Unpinned custom nodes are the top reason a pod that worked last month does
not today.

**Provisioning never blocks startup.** A failed download logs an error and
ComfyUI still comes up so you can diagnose. `401` = token, `404` = moved URL.

**Downloads are atomic** (`.part` then rename), so an interrupted pod cannot
leave a truncated file that a later boot mistakes for complete.

**Your edits are safe.** Seeded workflows are never overwritten on restart, and
an existing `input/h3_refs/` is left alone. Each tier seeds its own folder
(`workflows/H3/<tier>GB/`), so changing tier never mixes file names.

**Frame length snaps to a 17k+5 grid at 24 fps** — 22, 39, 56, 73, 90, 107, 124.
`frames_per_shot` gets rounded to the nearest valid value, so pick from that
list rather than being surprised.
