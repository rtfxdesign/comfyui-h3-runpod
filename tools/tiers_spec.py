"""Single source of truth for the GPU tiers.

tools/build_tiers.py turns this into config/tiers/<tier>.conf (what provision.sh
downloads) and workflows/tiers/<tier>/ (workflow copies whose loader file names
point at that tier's files). Every file name below was read from the Hugging
Face tree API or the CivitAI model-version API — none is guessed.
"""
HF = "https://huggingface.co"
H3 = f"{HF}/Comfy-Org/MiniMax-H3/resolve/main"
IMG = f"{HF}/Comfy-Org/MiniMax-H3-Image/resolve/main"
Q35 = f"{HF}/Comfy-Org/Qwen3.5/resolve/main"
LX = f"{HF}/lightx2v/Minimax-h3-Turbo/resolve/main"
PDMD = f"{HF}/akhaliq/minimax-h3-image-pdmd-2step/resolve/main"
SDP = f"{HF}/Comfy-Org/SDPose/resolve/main"

# role -> (models/ subfolder, url)  — or civitai-version:<id> with an exact file name
def hf(cat, url):
    return {"cat": cat, "url": url, "name": url.rsplit("/", 1)[1]}

def civ(cat, vid, name):
    return {"cat": cat, "url": f"civitai-version:{vid}", "name": name, "civitai": vid}

EROS = 3429412  # H3 Eros Max beta7 (fl2va-based NSFW 8-step merge) on CivitAI

# Files every tier gets unchanged.
COMMON = {
    "audio_vae": hf("vae", f"{H3}/vae/minimax_h3_audio_vae_fp32.safetensors"),
    "image_vae": hf("vae", f"{IMG}/vae/minimax_h3_image_vae_fp16.safetensors"),
    "turbo_ref2v": hf("loras", f"{H3}/loras/minimax_h3_ref2v_turbo_4step_v0.1_comfyui_bf16.safetensors"),
    "turbo_fl2v": hf("loras", f"{LX}/minimax_h3_fl2v_turbo_8step_v1.0_comfyui_bf16.safetensors"),
    "pdmd_lora": hf("loras", f"{PDMD}/minimax_h3_pdmd_2nfe_comfyui.safetensors"),
    "sdpose": hf("checkpoints", f"{SDP}/checkpoints/sdpose_wholebody_fp16.safetensors"),
    "sdpose_det": hf("diffusion_models", f"{SDP}/diffusion_models/rt_detr_v4-x-hgnet_fp16.safetensors"),
}

TIERS = {
    "16": {
        "label": "16-23 GB - same files as the home PC (RTX 5070 Ti)",
        "gpus": "RTX 4080 / 5080 / 5070 Ti, RTX A4000/A4500, RTX 4000 Ada",
        "vram_min_mib": 0,
        "roles": {
            "image": hf("diffusion_models", f"{IMG}/diffusion_models/minimax_h3_image_pruned_int8_convrot.safetensors"),
            "ref2va": hf("diffusion_models", f"{H3}/diffusion_models/minimax_h3_ref2va_pruned_int8_convrot.safetensors"),
            "fl2va": hf("diffusion_models", f"{H3}/diffusion_models/minimax_h3_fl2va_pruned_int8_convrot.safetensors"),
            "te": hf("text_encoders", f"{H3}/text_encoders/qwen3vl_32b_minimax_h3_nvfp4_awq.safetensors"),
            "te9b": hf("text_encoders", f"{IMG}/text_encoders/qwen3.5_9b_w4a8_gptq.safetensors"),
            "video_vae": hf("vae", f"{H3}/vae/minimax_h3_video_vae_int8_convrot.safetensors"),
            "controlnet": hf("model_patches", f"{H3}/model_patches/minimax_h3_fun_controlnet_union_pruned_int8_convrot.safetensors"),
            "eros": civ("diffusion_models", EROS, "10Eros_Max_h3_8stepTURBO_beta7_fix1_int8.safetensors"),
        },
    },
    "24": {
        "label": "24-47 GB - int8 models, int8 text encoder, fp16 video VAE",
        "gpus": "RTX 4090 (24), RTX 5090 (32), L4 (24), A100 40GB, RTX A5000",
        "vram_min_mib": 22000,
        "roles": {
            "image": hf("diffusion_models", f"{IMG}/diffusion_models/minimax_h3_image_pruned_int8_convrot.safetensors"),
            "ref2va": hf("diffusion_models", f"{H3}/diffusion_models/minimax_h3_ref2va_pruned_int8_convrot.safetensors"),
            "fl2va": hf("diffusion_models", f"{H3}/diffusion_models/minimax_h3_fl2va_pruned_int8_convrot.safetensors"),
            "te": hf("text_encoders", f"{H3}/text_encoders/qwen3vl_32b_minimax_h3_int8_convrot.safetensors"),
            "te9b": hf("text_encoders", f"{Q35}/text_encoders/qwen3.5_9b_int8_convrot.safetensors"),
            "video_vae": hf("vae", f"{H3}/vae/minimax_h3_video_vae_fp16.safetensors"),
            "controlnet": hf("model_patches", f"{H3}/model_patches/minimax_h3_fun_controlnet_union_pruned_int8_convrot.safetensors"),
            "eros": civ("diffusion_models", EROS, "10Eros_Max_h3_8stepTURBO_beta7_int8HQ.safetensors"),
        },
    },
    "48": {
        "label": "48-79 GB - bf16 image model, int8 video models",
        "gpus": "L40S, RTX 6000 Ada, A6000 / A40 (48), RTX PRO 5000 (48)",
        "vram_min_mib": 44000,
        "roles": {
            "image": hf("diffusion_models", f"{IMG}/diffusion_models/minimax_h3_image_pruned_bf16.safetensors"),
            "ref2va": hf("diffusion_models", f"{H3}/diffusion_models/minimax_h3_ref2va_pruned_int8_convrot.safetensors"),
            "fl2va": hf("diffusion_models", f"{H3}/diffusion_models/minimax_h3_fl2va_pruned_int8_convrot.safetensors"),
            "te": hf("text_encoders", f"{H3}/text_encoders/qwen3vl_32b_minimax_h3_int8_convrot.safetensors"),
            "te9b": hf("text_encoders", f"{Q35}/text_encoders/qwen3.5_9b_int8_convrot.safetensors"),
            "video_vae": hf("vae", f"{H3}/vae/minimax_h3_video_vae_fp16.safetensors"),
            "controlnet": hf("model_patches", f"{H3}/model_patches/minimax_h3_fun_controlnet_union_pruned_int8_convrot.safetensors"),
            "eros": civ("diffusion_models", EROS, "10Eros_Max_h3_8stepTURBO_beta7_int8HQ.safetensors"),
        },
    },
    "80": {
        "label": "80-92 GB - everything bf16, int8 text encoder stays loaded next to it",
        "gpus": "H100 80GB (SXM/PCIe), A100 80GB, H800",
        "vram_min_mib": 75000,
        "roles": {
            "image": hf("diffusion_models", f"{IMG}/diffusion_models/minimax_h3_image_pruned_bf16.safetensors"),
            "ref2va": hf("diffusion_models", f"{H3}/diffusion_models/minimax_h3_ref2va_pruned_bf16.safetensors"),
            "fl2va": hf("diffusion_models", f"{H3}/diffusion_models/minimax_h3_fl2va_pruned_bf16.safetensors"),
            "te": hf("text_encoders", f"{H3}/text_encoders/qwen3vl_32b_minimax_h3_int8_convrot.safetensors"),
            "te9b": hf("text_encoders", f"{Q35}/text_encoders/qwen3.5_9b_bf16.safetensors"),
            "video_vae": hf("vae", f"{H3}/vae/minimax_h3_video_vae_fp16.safetensors"),
            "controlnet": hf("model_patches", f"{H3}/model_patches/minimax_h3_fun_controlnet_union_pruned_bf16.safetensors"),
            "eros": civ("diffusion_models", EROS, "10Eros_Max_h3_8stepTURBO_beta7.safetensors"),
        },
    },
    "96": {
        "label": "93 GB+ - everything bf16 including the 51 GB bf16 text encoder",
        "gpus": "RTX PRO 6000 Blackwell (96), H100 NVL (94), H200 (141), B200 (180)",
        "vram_min_mib": 92000,
        "roles": {
            "image": hf("diffusion_models", f"{IMG}/diffusion_models/minimax_h3_image_pruned_bf16.safetensors"),
            "ref2va": hf("diffusion_models", f"{H3}/diffusion_models/minimax_h3_ref2va_pruned_bf16.safetensors"),
            "fl2va": hf("diffusion_models", f"{H3}/diffusion_models/minimax_h3_fl2va_pruned_bf16.safetensors"),
            "te": hf("text_encoders", f"{H3}/text_encoders/qwen3vl_32b_minimax_h3_bf16.safetensors"),
            "te9b": hf("text_encoders", f"{Q35}/text_encoders/qwen3.5_9b_bf16.safetensors"),
            "video_vae": hf("vae", f"{H3}/vae/minimax_h3_video_vae_fp16.safetensors"),
            "controlnet": hf("model_patches", f"{H3}/model_patches/minimax_h3_fun_controlnet_union_pruned_bf16.safetensors"),
            "eros": civ("diffusion_models", EROS, "10Eros_Max_h3_8stepTURBO_beta7.safetensors"),
        },
    },
}

# File names that appear in the bundled workflows -> the role they play.
# (GGUF names come from the upstream Multishot workflows; H3ModelLoaderAny /
#  H3ClipLoaderAny load safetensors too, so the tier copies point them at the
#  tier's safetensors files.)
WORKFLOW_NAMES = {
    "minimax_h3_image_pruned_int8_convrot.safetensors": "image",
    "minimax_h3_ref2va_pruned_int8_convrot.safetensors": "ref2va",
    "MiniMax-H3-ref2va-curve-Q5_1.gguf": "ref2va",
    "minimax_h3_fl2va_pruned_int8_convrot.safetensors": "fl2va",
    "MiniMax-H3-fl2va-curve-Q5_1.gguf": "fl2va",
    "qwen3vl_32b_minimax_h3_nvfp4_awq.safetensors": "te",
    "qwen3vl_32b_minimax_h3_int8_convrot.safetensors": "te",
    "MiniMax-H3-encoder-Q4_K_M.gguf": "te",
    "qwen3.5_9b_w4a8_gptq.safetensors": "te9b",
    "minimax_h3_video_vae_int8_convrot.safetensors": "video_vae",
    "minimax_h3_video_vae_fp16.safetensors": "video_vae",
    "minimax_h3_fun_controlnet_union_pruned_int8_convrot.safetensors": "controlnet",
}
