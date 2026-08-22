# ComfyUI on RunPod — MiniMax H3 long-form chained video

A ComfyUI image built for one job: **generate a long video as a chain of shots,
each continuing from the last, with the same characters throughout.**

Target: **48 GB VRAM** (A6000 / L40S / A40 class).

Models download at **boot**, not baked into the image — so changing the model
set is a file edit, not a multi-gigabyte rebuild.

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

`models.conf` ships **`ref2va`** deliberately. ref2va carries *reference rows*:
the identity bank and the nine reference slots.

**`fl2va` has no reference rows at all.** Swap the checkpoint and H3AutoRefs
silently does nothing — no error, characters just drift. If identity is being
ignored, check `models.conf` first.

The trade: ref2va holds a supplied keyframe only *softly*, where fl2va lands on
it exactly. For a character-driven chain that is the right trade — identity
re-locks from each shot's closing frames, which is what makes the chain hold.

---

## Which workflow

Four are seeded into the sidebar under **workflows/H3/** on first boot:

| Workflow | Use |
|---|---|
| **`H3_Extend_Take`** | **Start here.** AutoRefs + memory sampler + LoRA stack — one premise, one continuous take |
| `H3_Seamless_Chain_v2` | Same engine, multi-shot scripted scenes |
| `H3_Seamless_Chain_CORE` | Minimal, no extras — good for isolating a problem |
| `H3_Keyframes` | Anchoring a single clip at chosen frame positions |

---

## Setup

**1.** Push to GitHub — Actions builds and publishes to `ghcr.io/<user>/<repo>:latest`.

**2.** Give RunPod pull access to the private image. In RunPod:
**Settings → Container Registry Auth → Add** —
username `rtfxdesign`, password = a GitHub **classic** PAT with `read:packages`
(fine-grained PATs do not cover GHCR pulls). Then select that credential in the
pod template's Container Registry Credentials dropdown.
(Alternative: make the GHCR package public and skip all of this.)

**3.** Create the pod:

- **Image:** `ghcr.io/<user>/<repo>:latest`
- **GPU:** 48 GB
- **Container disk:** 30 GB
- **Volume:** **150 GB** at `/workspace` — the multishot master writer spills
  full-resolution frames per shot, and long takes add up fast
- **Expose HTTP port:** `8188`
- **Env vars:** `HF_TOKEN`, `CIVITAI_API_TOKEN`

**4.** Open the pod's 8188 endpoint. First boot pulls ~41 GB; watch the pod log.

---

## VRAM budget at 48 GB

| | |
|---|---|
| UNet (ref2va pruned int8) | 19.53 GB resident during sampling |
| Video VAE | 4.85 GB |
| Text encoder (nvfp4) | 14.61 GB — loaded to encode, then **evicted** before sampling |
| **Working headroom** | **~23 GB** for latents, activations, reference tokens |

That headroom is the point. Reference tokens ride through every sampling step,
and long chains hold large video+audio latents plus per-shot memory frames. The
unpruned int8 build (31.70 GB) would cut headroom to ~11 GB — fine for a two-shot
clip, an OOM ten shots into a long take. It is commented in `models.conf` if you
want it for short work.

---

## Environment variables

| Variable | Default | Purpose |
|---|---|---|
| `HF_TOKEN` | — | Gated HuggingFace repos |
| `CIVITAI_API_TOKEN` | — | CivitAI downloads (401 without it) |
| `PROVISION_CONFIG_URL` | — | Remote `models.conf` override — change models without a rebuild |
| `PROVISION_NODES_URL` | — | Remote `nodes.conf` override |
| `GH_CONFIG_TOKEN` | — | PAT for fetching the URLs above from a **private** repo (Contents: read). Only ever sent to github.com hosts |
| `SKIP_PROVISION` | `0` | `1` boots straight to ComfyUI, no downloads |
| `COMFY_EXTRA_ARGS` | — | Extra launch flags |
| `COMFY_PORT` | `8188` | Listen port |

---

## Notes

**Turbo LoRA is variant-matched.** `models.conf` ships the **ref2v** 4-step LoRA.
Do not substitute the fl2v one — different variant, degraded output. Wire it
through `H3LoraStack`.

**Pin your node refs once you are happy.** `nodes.conf` is unpinned because
these packs are actively maintained. SSH in, run
`git -C /workspace/ComfyUI/custom_nodes/<pack> rev-parse HEAD`, paste the SHAs
back. Unpinned custom nodes are the top reason a pod that worked last month does
not today.

**Provisioning never blocks startup.** A failed download logs an error and
ComfyUI still comes up so you can diagnose. `401` = token, `404` = moved URL.

**Downloads are atomic** (`.part` then rename), so an interrupted pod cannot
leave a truncated file that a later boot mistakes for complete.

**Your edits are safe.** Seeded workflows are never overwritten on restart, and
an existing `input/h3_refs/` is left alone.

**Frame length snaps to a 17k+5 grid at 24 fps** — 22, 39, 56, 73, 90, 107, 124.
`frames_per_shot` gets rounded to the nearest valid value, so pick from that
list rather than being surprised.
