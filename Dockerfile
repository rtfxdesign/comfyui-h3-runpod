# =============================================================================
#  ComfyUI for RunPod — MiniMax H3 video stack
#
#  CUDA 12.8 + PyTorch cu128. 12.8 is the floor for Blackwell (sm_120 — RTX
#  50-series, B200); it also covers Ada and Ampere, so one image runs on
#  whatever RunPod has capacity for. Do not drop below 12.8 unless you have
#  stopped caring about 50-series pods.
# =============================================================================
FROM nvidia/cuda:12.8.1-cudnn-runtime-ubuntu22.04

ENV DEBIAN_FRONTEND=noninteractive \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1 \
    COMFY_DIR=/workspace/ComfyUI \
    COMFY_PORT=8188

# ffmpeg is NOT optional: every video-export path (SaveVideo, CreateVideo,
# VideoHelperSuite) shells out to it, and its absence shows up as a confusing
# node error rather than a missing-binary message.
RUN apt-get update && apt-get install -y --no-install-recommends \
        python3.11 python3.11-venv python3.11-dev python3-pip \
        git git-lfs curl wget ca-certificates \
        ffmpeg libgl1 libglib2.0-0 \
        openssh-server \
    && ln -sf /usr/bin/python3.11 /usr/bin/python \
    && rm -rf /var/lib/apt/lists/*

RUN python -m pip install --upgrade pip setuptools wheel

# Torch first and pinned, from the cu128 index. If a custom node's
# requirements.txt later pulls a plain `torch`, pip would otherwise fetch the
# default CUDA build and silently break GPU support.
RUN pip install --no-cache-dir \
        torch torchvision torchaudio \
        --index-url https://download.pytorch.org/whl/cu128

# JupyterLab: the pod's file manager — upload LoRAs, download rendered videos,
# poke around /workspace from the browser. Started by start.sh on :8888 only
# when JUPYTER_PASSWORD is set.
RUN pip install --no-cache-dir jupyterlab

# Build ComfyUI at /opt so an empty RunPod volume mounted at /workspace cannot
# shadow it; start.sh copies it into place on first boot.
ARG COMFYUI_REF=master
RUN git clone https://github.com/comfyanonymous/ComfyUI.git /opt/ComfyUI \
    && cd /opt/ComfyUI \
    && git checkout "$COMFYUI_REF" \
    && pip install --no-cache-dir -r requirements.txt

# ComfyUI-Manager, so you can install nodes from the running pod's UI too.
RUN git clone --depth 1 https://github.com/ltdrdata/ComfyUI-Manager.git \
        /opt/ComfyUI/custom_nodes/ComfyUI-Manager \
    && pip install --no-cache-dir \
        -r /opt/ComfyUI/custom_nodes/ComfyUI-Manager/requirements.txt

# Provisioning config + scripts live outside /workspace so a mounted volume
# never hides them.
COPY config/    /opt/provision/config/
COPY scripts/   /opt/provision/scripts/
COPY workflows/ /opt/provision/workflows/
RUN chmod +x /opt/provision/scripts/*.sh \
    && mkdir -p /var/run/sshd

EXPOSE 8188 8888 22

# A pod that answers TCP but whose ComfyUI died is worse than one that reports
# unhealthy — probe the actual API.
HEALTHCHECK --interval=30s --timeout=10s --start-period=180s --retries=3 \
    CMD curl -fsS "http://127.0.0.1:${COMFY_PORT}/system_stats" || exit 1

ENTRYPOINT ["/opt/provision/scripts/start.sh"]
