#!/usr/bin/env bash
# Krea2 / DesireX fresh-Pod bootstrap. Runs after RunPod initializes ComfyUI's cu128 venv.
set -Eeuo pipefail
umask 077

LOG="/workspace/setup.log"
mkdir -p /workspace
exec > >(tee -a "$LOG") 2>&1
CIVITAI_CFG=""
cleanup() { [[ -z "${CIVITAI_CFG:-}" ]] || rm -f "$CIVITAI_CFG"; }
trap cleanup EXIT
trap 'rc=$?; echo "ERROR: setup failed at line ${LINENO} (exit ${rc}). See ${LOG}"; exit "$rc"' ERR

COMFY="${COMFY_DIR:-/workspace/runpod-slim/ComfyUI}"
PY="${COMFY}/.venv-cu128/bin/python"
TOKEN="${CIVITAI_TOKEN:-}"

DESIREX_URL="https://civitai.red/api/download/models/3411639?fileId=3303945"
SNOFS_URL="https://civitai.red/api/download/models/3220691?fileId=3102670"
NICE_URL="https://civitai.red/api/download/models/3075498?fileId=2954554"
REALISM_URL="https://civitai.red/api/download/models/3109006?fileId=2988982"
LENOVO_URL="https://civitai.red/api/download/models/3075606?fileId=2954661"

log() { printf '[%s] %s\n' "$(date '+%F %T')" "$*"; }
die() { log "FATAL: $*"; exit 1; }

[[ -n "$TOKEN" ]] || die "CIVITAI_TOKEN is missing. Add it as a RunPod Secret."
for tool in curl git stat tee date sleep seq mktemp chmod rm mv mkdir basename dirname df; do
  command -v "$tool" >/dev/null 2>&1 || die "Required command not found: $tool"
done
[[ -d "$COMFY/custom_nodes" ]] || die "ComfyUI is not initialized at $COMFY"
[[ -x "$PY" ]] || die "ComfyUI CUDA 12.8 Python is missing: $PY"

"$PY" - <<'PY'
import sys, torch
assert torch.version.cuda and torch.version.cuda.startswith("12.8"), f"Expected CUDA 12.8, got {torch.version.cuda!r}"
print("Python:", sys.version.split()[0], "| PyTorch:", torch.__version__, "| CUDA:", torch.version.cuda)
PY

if [[ -f /opt/comfyui-runtime-constraints.txt ]]; then
  export PIP_CONSTRAINT=/opt/comfyui-runtime-constraints.txt
fi

verify_safetensors() {
  local f="$1" min_bytes="$2"
  [[ -s "$f" ]] || return 1
  local size
  size=$(stat -c '%s' "$f") || return 1
  (( size >= min_bytes )) || return 1
  "$PY" - "$f" <<'PY'
import json, struct, sys
with open(sys.argv[1], "rb") as f:
    raw=f.read(8)
    if len(raw)!=8: raise SystemExit(1)
    n=struct.unpack("<Q",raw)[0]
    if n<2 or n>100_000_000: raise SystemExit(1)
    h=f.read(n)
    if len(h)!=n: raise SystemExit(1)
    obj=json.loads(h)
    if not isinstance(obj,dict) or not obj: raise SystemExit(1)
PY
}

download_file() {
  local url="$1" dest="$2" min_bytes="$3" kind="${4:-public}"
  mkdir -p "$(dirname "$dest")"
  if [[ -s "$dest" ]]; then
    if [[ "$dest" == *.safetensors ]]; then
      if verify_safetensors "$dest" "$min_bytes" >/dev/null 2>&1; then
        log "Verified existing $(basename "$dest")"; return 0
      fi
    else
      local size; size=$(stat -c '%s' "$dest")
      if (( size >= min_bytes )); then log "Existing $(basename "$dest") present"; return 0; fi
    fi
    log "Removing incomplete/invalid file: $dest"; rm -f "$dest"
  fi
  local tmp="${dest}.part"
  rm -f "$tmp"
  log "Downloading $(basename "$dest")"
  if [[ "$kind" == "civitai" ]]; then
    CIVITAI_CFG="$(mktemp /workspace/.civitai-curl.XXXXXX)"
    chmod 600 "$CIVITAI_CFG"
    "$PY" - "$url" "$tmp" > "$CIVITAI_CFG" <<'PY'
import json, os, sys
url, output_path = sys.argv[1], sys.argv[2]
print("url = " + json.dumps(url))
print("get")
print("data-urlencode = " + json.dumps("token=" + os.environ["CIVITAI_TOKEN"]))
print("fail")
print("location")
print("retry = 5")
print("retry-delay = 5")
print("connect-timeout = 30")
print("output = " + json.dumps(output_path))
PY
    curl --config "$CIVITAI_CFG"
    rm -f "$CIVITAI_CFG"; CIVITAI_CFG=""
  else
    curl --fail --location --retry 5 --retry-delay 3 --connect-timeout 30 --output "$tmp" "$url"
  fi
  [[ -s "$tmp" ]] || die "Download produced an empty file: $dest"
  local size; size=$(stat -c '%s' "$tmp")
  (( size >= min_bytes )) || die "Downloaded file is too small: $dest ($size bytes)"
  if [[ "$dest" == *.safetensors ]]; then
    verify_safetensors "$tmp" "$min_bytes" || die "Safetensors header validation failed: $dest"
  fi
  mv "$tmp" "$dest"
  log "Download verified: $(basename "$dest") ($size bytes)"
}

install_node() {
  local repo="$1" dir="$2"
  if [[ -d "$dir/.git" ]]; then
    log "Updating custom node $(basename "$dir")"
    git -C "$dir" fetch --depth 1 origin
    git -C "$dir" reset --hard FETCH_HEAD
  elif [[ -e "$dir" ]]; then
    die "Custom node directory exists but is not a Git checkout: $dir"
  else
    log "Cloning $(basename "$dir")"
    git clone --depth 1 "$repo" "$dir"
  fi
  [[ -f "$dir/__init__.py" ]] || die "Missing custom-node __init__.py in $dir"
  if [[ -f "$dir/requirements.txt" ]]; then
    log "Installing requirements.txt for $(basename "$dir")"
    "$PY" -m pip install --disable-pip-version-check -r "$dir/requirements.txt"
  fi
  if [[ -f "$dir/install.py" ]]; then
    log "Running install.py for $(basename "$dir")"
    "$PY" "$dir/install.py"
  fi
}

N="$COMFY/custom_nodes"
install_node "https://github.com/lbouaraba/comfyui-krea2edit" "$N/comfyui-krea2edit"
install_node "https://github.com/lonecatone23/ComfyUI_LC123_nodes" "$N/ComfyUI_LC123_nodes"
install_node "https://github.com/lonecatone23/ComfyUI_LC_MaskMaker_nodes" "$N/ComfyUI_LC_MaskMaker_nodes"
install_node "https://github.com/rgthree/rgthree-comfy" "$N/rgthree-comfy"

# MaskMaker's Touch Mask documentation calls out cv2 as a prerequisite.
if ! "$PY" -c 'import cv2' >/dev/null 2>&1; then
  log "OpenCV missing; installing headless OpenCV"
  "$PY" -m pip install --disable-pip-version-check opencv-python-headless
fi
"$PY" - <<'PY'
import cv2, transformers, huggingface_hub, timm
print("Verified MaskMaker Python dependencies:", cv2.__version__, transformers.__version__, huggingface_hub.__version__, timm.__version__)
PY

M="$COMFY/models"
download_file "https://huggingface.co/Comfy-Org/Krea-2/resolve/main/text_encoders/qwen3vl_4b_fp8_scaled.safetensors" "$M/text_encoders/qwen3vl_4b_fp8_scaled.safetensors" 100000000
download_file "https://huggingface.co/Comfy-Org/Krea-2/resolve/main/vae/qwen_image_vae.safetensors" "$M/vae/qwen_image_vae.safetensors" 100000000
download_file "https://huggingface.co/conradlocke/krea2-identity-edit/resolve/main/krea2_identity_edit_v2_r128.safetensors?download=true" "$M/loras/krea2_identity_edit_v2.safetensors" 1000000
download_file "$DESIREX_URL" "$M/diffusion_models/BSS_DesireX3_INT8_ConvRot.safetensors" 1000000000 civitai
download_file "$LENOVO_URL" "$M/loras/lenovo_krea2.safetensors" 1000000 civitai
download_file "$SNOFS_URL" "$M/loras/snofs_krea2.safetensors" 1000000 civitai
download_file "$NICE_URL" "$M/loras/nicegirls_krea2.safetensors" 1000000 civitai
download_file "$REALISM_URL" "$M/loras/realism_engine_krea2.safetensors" 1000000 civitai

# Workflow-specific LCRemBG settings: BiRefNet general + local ViTMatte refine.
# ComfyUI core's LoadBackgroundRemovalModel expects this exact filename/path.
download_file "https://huggingface.co/Comfy-Org/BiRefNet/resolve/main/background_removal/birefnet.safetensors" "$M/background_removal/birefnet.safetensors" 400000000
# LC MaskMaker's local ViTMatte choice expects the model snapshot under models/vitmatte.
download_file "https://huggingface.co/hustvl/vitmatte-small-composition-1k/resolve/main/model.safetensors" "$M/vitmatte/vitmatte-small-composition-1k/model.safetensors" 50000000
download_file "https://huggingface.co/hustvl/vitmatte-small-composition-1k/resolve/main/config.json" "$M/vitmatte/vitmatte-small-composition-1k/config.json" 100
download_file "https://huggingface.co/hustvl/vitmatte-small-composition-1k/resolve/main/preprocessor_config.json" "$M/vitmatte/vitmatte-small-composition-1k/preprocessor_config.json" 100

# Fail before ComfyUI launch if any workflow-critical file is missing or invalid.
verify_safetensors "$M/diffusion_models/BSS_DesireX3_INT8_ConvRot.safetensors" 1000000000 || die "DesireX model invalid"
verify_safetensors "$M/text_encoders/qwen3vl_4b_fp8_scaled.safetensors" 100000000 || die "Qwen text encoder invalid"
verify_safetensors "$M/vae/qwen_image_vae.safetensors" 100000000 || die "Qwen VAE invalid"
verify_safetensors "$M/loras/krea2_identity_edit_v2.safetensors" 1000000 || die "Krea2 identity LoRA invalid"
verify_safetensors "$M/background_removal/birefnet.safetensors" 400000000 || die "BiRefNet model invalid"
verify_safetensors "$M/vitmatte/vitmatte-small-composition-1k/model.safetensors" 50000000 || die "ViTMatte model invalid"

for f in lenovo_krea2.safetensors snofs_krea2.safetensors nicegirls_krea2.safetensors realism_engine_krea2.safetensors; do
  verify_safetensors "$M/loras/$f" 1000000 || die "Optional LoRA invalid: $f"
done

log "All workflow model files downloaded and safetensors headers validated."
log "All four custom-node repositories cloned; requirements/install.py processing completed."
log "SETUP COMPLETE. The official RunPod start.sh will now launch ComfyUI."
