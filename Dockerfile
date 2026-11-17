# =============================================================================
#  ComfyUI for RunPod — MiniMax H3 image + video stack, scaled by GPU tier
#
#  CUDA 13.0 + PyTorch 2.14.1+cu130 — the same torch build as the home PC.
#  Checked 2026-11-15:
#   * nvidia/cuda:13.0.3-cudnn-runtime-ubuntu24.04 exists on Docker Hub
#     (amd64 digest sha256:af851538a2bb05f587f27b660d61de3643d964e75ef5c04f4086ff2b36f2a12a,
#     CUDA_VERSION=13.0.3, cuDNN 9.14, NVIDIA_REQUIRE_CUDA=cuda>=13.0).
#   * torch-2.14.1+cu130, torchvision-0.29.1+cu130 and torchaudio-2.11.0+cu130
#     cp312 manylinux x86_64 wheels exist on download.pytorch.org/whl/cu130.
#   * That torch wheel carries GPU kernels for sm_75, sm_80, sm_86, sm_90,
#     sm_100 and sm_120 (read out of libtorch_cuda.so). So one image covers
#     A100 (sm_80), A6000/A40 (sm_86), L40S/4090/6000 Ada (sm_89, runs the
#     sm_86 kernels), H100/H200 (sm_90), B200 (sm_100) and RTX 5090 /
#     RTX PRO 6000 Blackwell (sm_120).
#   * Comfy-Org recommends int8_convrot models "if you are able to use pytorch
#     with cu130" — that is why the tiers use int8_convrot, not fp8.
#
#  HOST DRIVER: CUDA 13.x needs an NVIDIA driver >= 580 on the host. On RunPod
#  set the pod/template filter "CUDA Version" to 13.0 (or newer). A host on a
#  570/575 driver (CUDA 12.8/12.9) refuses to start this container.
#  There is no cu128 build of torch 2.14.1, so there is no 12.8 fallback tag.
# =============================================================================
FROM nvidia/cuda:13.0.3-cudnn-runtime-ubuntu24.04

ENV DEBIAN_FRONTEND=noninteractive \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1 \
    VIRTUAL_ENV=/opt/venv \
    PATH=/opt/venv/bin:$PATH \
    COMFY_DIR=/workspace/ComfyUI \
    COMFY_PORT=8188

# Python 3.12 is Ubuntu 24.04's own python3 (home PC: 3.12.10).
# jq resolves CivitAI model-version metadata at provision time.
# ffmpeg is NOT optional: every video-export path shells out to it.
RUN apt-get update && apt-get install -y --no-install-recommends \
        python3 python3-venv python3-dev python3-pip \
        build-essential \
        git git-lfs curl wget ca-certificates jq \
        ffmpeg libgl1 libglib2.0-0 \
        openssh-server \
    && rm -rf /var/lib/apt/lists/* \
    && python3 -m venv /opt/venv \
    && ln -sf /opt/venv/bin/python /usr/local/bin/python \
    && python -m pip install --upgrade pip setuptools wheel

# The same versions as the home PC. PIP_CONSTRAINT (set below) makes every
# later `pip install` — including custom-node requirements.txt at boot — keep
# these, so no node can swap torch for a CPU or wrong-CUDA build.
RUN mkdir -p /opt/provision && printf '%s\n' \
        'torch==2.14.1+cu130' \
        'torchvision==0.29.1+cu130' \
        'torchaudio==2.11.0+cu130' \
        'transformers==5.23.0' \
        'safetensors==0.8.0' \
        > /opt/provision/constraints.txt
ENV PIP_CONSTRAINT=/opt/provision/constraints.txt

RUN pip install \
        torch==2.14.1+cu130 torchvision==0.29.1+cu130 torchaudio==2.11.0+cu130 \
        --index-url https://download.pytorch.org/whl/cu130

# JupyterLab: the pod's file manager. Started by start.sh on :8888 only when
# JUPYTER_PASSWORD is set.
RUN pip install jupyterlab

# Build ComfyUI at /opt so an empty RunPod volume mounted at /workspace cannot
# shadow it; start.sh copies it into place on first boot.
# v0.45.0 = commit 989d93d0d968e704c589ce0146bb18c77f6b50cc, the exact build on
# the home PC, and the minimum the official MiniMax H3 Image templates need
# (templates/index.json: image_minimax_h3_image_edit / _t2i minComfyUIVersion
# 0.45.0). Its requirements.txt pins comfy-kitchen 0.2.41, comfy-aimdo 0.6.0
# and frontend 1.58.5 (same as home). Newer: v0.45.3 — override with
# --build-arg COMFYUI_REF=v0.45.3 if you want it.
ARG COMFYUI_REF=v0.45.0
RUN git clone https://github.com/comfyanonymous/ComfyUI.git /opt/ComfyUI \
    && cd /opt/ComfyUI \
    && git checkout "$COMFYUI_REF" \
    && pip install -r requirements.txt \
    && pip install -r manager_requirements.txt

# ComfyUI-Manager is the pip package from manager_requirements.txt
# (comfyui_manager==4.2.2 at v0.45.0, as on the home PC). start.sh adds
# --enable-manager. The old git clone of ltdrdata/ComfyUI-Manager is gone.

# Sanity check at build time: the wheel really is the CUDA 13.0 build.
RUN python -c "import torch, sys; v=torch.__version__; c=torch.version.cuda; print('torch', v, 'cuda', c, 'archs', torch.cuda.get_arch_list()); sys.exit(0 if v.startswith('2.14.1') and c and c.startswith('13.0') else 1)"

# Provisioning config + scripts live outside /workspace so a mounted volume
# never hides them.
COPY config/    /opt/provision/config/
COPY scripts/   /opt/provision/scripts/
COPY workflows/ /opt/provision/workflows/
RUN chmod +x /opt/provision/scripts/*.sh \
    && mkdir -p /var/run/sshd

EXPOSE 8188 8888 22

# A pod that answers TCP but whose ComfyUI died is worse than one that reports
# unhealthy — probe the actual API. First boot downloads 120-250 GB, so the
# start period is long.
HEALTHCHECK --interval=30s --timeout=10s --start-period=3600s --retries=3 \
    CMD curl -fsS "http://127.0.0.1:${COMFY_PORT}/system_stats" || exit 1

ENTRYPOINT ["/opt/provision/scripts/start.sh"]
