# Official Comfy-Org MiniMax H3 workflows (unmodified)

These graphs are **byte-for-byte copies** of the official ComfyUI templates.
Nothing in them was edited: file names are the upstream names, and each file's
git blob SHA-1 matches the upstream tree entry.

- Source repo: <https://github.com/Comfy-Org/workflow_templates>
- Commit: `79b02f4a79e233c07ec4923e39f40be27448549d` (main as of 2026-11-15; the home PC's copies of the six H3 video templates are byte-identical to this commit)
- Raw URL pattern: `https://raw.githubusercontent.com/Comfy-Org/workflow_templates/79b02f4a79e233c07ec4923e39f40be27448549d/templates/<file>`
- Docs: <https://docs.comfy.org/tutorials/video/minimax/minimax-h3>,
  <https://docs.comfy.org/tutorials/video/minimax/minimax-h3-native>,
  <https://docs.comfy.org/tutorials/video/minimax/minimax-h3-multiframe>,
  <https://docs.comfy.org/tutorials/video/minimax/minimax-h3-fun-controlnet>
- Model weights: <https://huggingface.co/Comfy-Org/MiniMax-H3>

On boot they are seeded into the ComfyUI sidebar under **workflows/H3/original/official/**, and a
copy with the GPU tier's model names under **workflows/H3/<tier>GB/official/** (use that one)
(never overwriting a copy you edited). Every node class they use is a **core
ComfyUI node** — checked against the ComfyUI v0.45.0 source that the image pins —
so they need **no custom node packs**. They use stock `UNETLoader` /
`LoraLoaderModelOnly`, not the Multishot pack's loaders.

## Which file, which base, which turbo

| File (upstream name) | What it is | Base checkpoint | Speed adapter in the graph | Min ComfyUI | Model profile |
|---|---|---|---|---|---|
| `image_minimax_h3_image_t2i.json` | **H3 Image** text-to-image (Euler, simple, 6 steps, CFG 1) | `minimax_h3_image_pruned_int8_convrot` (H3-Image repo) + `qwen3.5_9b_w4a8_gptq` prompt enhancer | none (add the pDMD 2-step LoRA for 2 steps) | 0.45.0 | every GPU tier |
| `image_minimax_h3_image_edit.json` | **H3 Image** edit / multi-reference (`MiniMaxH3ImageConditioning`, `<Picture N>`) | same | same | 0.45.0 | every GPU tier |
| `video_minimax_h3_r2v.json` | **R2V** — reference images/video/audio → video | ref2va pruned int8 | **ref2v turbo 4-step** (optional switch) | 0.30.0 | `official-ref2v` |
| `video_minimax_h3_multiframe_reference.json` | **Multiframe** — up to 4 guide frames anchored on the timeline (`MiniMaxH3AddGuide`) | ref2va pruned int8 | **ref2v turbo 4-step** | 0.34.0 | `official-ref2v` |
| `video_minimax_h3_i2v.json` | **I2V / FL2VA** — wire `first_frame` **and** `last_frame` on `MiniMaxH3ImageToVideo` for first/last-frame | fl2va pruned int8 | **fl2v turbo 8-step** (`turbo_mode`) | 0.30.0 | `official-fl2v` |
| `video_minimax_h3_i2v_continuation.json` | I2V continuation (start image, empty prompt) | fl2va pruned int8 | **fl2v turbo 8-step** | 0.30.0 | `official-fl2v` |
| `video_minimax_h3_t2v.json` | T2V | fl2va pruned int8 | **fl2v turbo 8-step** | 0.30.0 | `official-fl2v` |
| `video_minimax_h3_fun_controlnet_union.json` | **Fun ControlNet Union** — pose-control video (SDPose + RT-DETR extractor) | ref2va pruned int8 + `fun_controlnet_union_pruned_int8_convrot` patch | **ref2v turbo 4-step** | 0.35.0 | `official-ref2v,controlnet` |
| `video_fastvideo_fasth3_i2v.json` | **FastH3** I2V (8-step distilled, sparse attention) | `fastvideo_fasth3_8step_v2_pruned_int8_convrot` | none (distilled) | 0.36.0 | `fasth3` |
| `video_fastvideo_fasth3_t2v.json` | **FastH3** T2V | `fastvideo_fasth3_8step_v2_pruned_int8_convrot` | none (distilled) | 0.36.0 | `fasth3` |
| `video_fasth3_ominiref_r2v.json` | **FastH3 OmniRef** R2V (upstream spells it "ominiref") | `fasth3_omniref_8step_pruned_int8_convrot` | none (distilled) | 0.43.0 | `fasth3` |
| `video_pika_h3_flex_ref2va.json` | Pika H3 Flex R2V (6-step lcm, ManualSigmas) | ref2va pruned int8 | Pika Flex ref2va adapter (replaces turbo) | 0.44.0 | `pika-flex` (+ `official-ref2v`) |
| `video_pika_h3_flex_fl2va.json` | Pika H3 Flex FL2VA (first + last frame) | fl2va pruned int8 | Pika Flex fl2va adapter (replaces turbo) | 0.44.0 | `pika-flex` + `official-fl2v` |

Min-version values are the `minComfyUIVersion` fields in the upstream
`templates/index.json` (and docs.comfy.org: Multiframe 0.34.0+, Fun
ControlNet 0.35.0+ / Union 2.0 0.38.0+, FastH3 0.36.0+).

Rules from the official docs worth repeating:

- **R2V uses `ref2va`; T2V/I2V/FL2VA use `fl2va`.** One template covers T2V and
  first/last-frame I2V (`fl2va`); the R2V template covers `ref2va`.
- **Never cross turbo families**: ref2v turbo (4-step) only with ref2va,
  fl2v turbo (8-step) only with fl2va, no turbo on FastH3 or with Pika Flex.
- I2V/T2V: default 20 steps; `turbo_mode` uses 8 steps at strength 1.0.
  R2V: the 4-step turbo is "faster, weaker reference/audio" — prefer 20–25
  steps when references must hold.
- **Style LoRAs compete with references**: on R2V keep extra LoRAs low (~0.5).
  This applies to the adult catalog too (see ../../docs/ADULT_LORAS.md). Add
  them with a stock **LoraLoaderModelOnly** chained after the turbo loader.

## Models & VAE

Upstream graphs name the int8/nvfp4 home-sized files (int8_convrot video VAE,
qwen3vl int8 or nvfp4 text encoder, pruned int8 models). The copies under
`../tiers/<tier>/official/` are the same graphs with those names (and their
`models` download URLs) switched to the tier's files by `tools/build_tiers.py`
— nothing else is changed. Every file they name is downloaded by
`config/tiers/<tier>.conf`, except the FastH3 checkpoints and Pika Flex
adapters, which still need `H3_MODEL_PROFILES=fasth3` / `pika-flex`.

The image templates upstream name `qwen3vl_32b_minimax_h3_int8_convrot`; the
home PC used them patched to the nvfp4 encoder. Here the upstream file is kept
as is, and tier 16's copy is the nvfp4 one.

## Not included (and why)

- **No local "FL2VA-only" graph exists upstream.** FL2VA is the
  `video_minimax_h3_i2v.json` graph with both frames wired (docs: "Wire images
  to first_frame / last_frame on MiniMaxH3ImageToVideo for FL2VA"). The
  `api_minimax_h3_flf2v*.json` templates are paid **API** (partner-node)
  graphs, not local weights, so they were left out.
- `api_*` H3 Max / Turbo templates: hosted API only.
- Union 2.0 ControlNet weights: the shipped template references the original
  Union file; Union 2.0 (0.38.0+) is not wired in any official template here.

## Integrity (git blob SHA-1 = upstream tree entry)

| File | bytes | git blob sha1 |
|---|---:|---|
| `video_fasth3_ominiref_r2v.json` | 40050 | `649e240ca11a5bab1300b24955c9bedf5a986614` |
| `video_fastvideo_fasth3_i2v.json` | 68384 | `e490d2c665f51997b222aa81b0d9de7468dcefc5` |
| `video_fastvideo_fasth3_t2v.json` | 60008 | `cb9bfdadec6cde34df1f0ff20000c8d1703b73ca` |
| `video_minimax_h3_fun_controlnet_union.json` | 91170 | `dd93bafa261724674832456f0f80cd8bbc907cad` |
| `video_minimax_h3_i2v.json` | 71812 | `bcc680e74537bffa89bff3eb6eb11a7c220e38e9` |
| `video_minimax_h3_i2v_continuation.json` | 62191 | `92d2b0c0c68c751600b8e8bdad88b3a55c2da545` |
| `video_minimax_h3_multiframe_reference.json` | 76309 | `417084805e778aa87c381746585eaef865bbd579` |
| `video_minimax_h3_r2v.json` | 46409 | `8a1ffa8043bbb7ef51cbd53003cec3bdd65719f9` |
| `video_minimax_h3_t2v.json` | 68461 | `b99a270eadd74c371c3c4facd9322da6a99ca4db` |
| `video_pika_h3_flex_fl2va.json` | 65814 | `399d997fda0aa7cf212cc6dc0e325d3ab0ba87c3` |
| `video_pika_h3_flex_ref2va.json` | 40308 | `33b863a2e5ef67308e7de8c07a15d07145c5cbd1` |
