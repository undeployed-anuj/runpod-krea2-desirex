# Krea2 / DesireX — fresh RunPod Pod bootstrap

This package creates a custom image based on the exact CUDA 12.8 image in the existing RunPod template. It preserves the official `/start.sh` and runs the bootstrap **after** the official script creates/activates `.venv-cu128` and **before** `python main.py` launches.

## What is verified from the supplied workflow

The uploaded `Krea2_ID_Edit_DesireX_ready.json` was parsed directly: **80 nodes**. It contains two `LCRemBG` nodes, both selecting:
- `BiRefNet general (MIT)`
- `models/vitmatte (local)`

Required custom node families in that graph:
- `comfyui-krea2edit`
- `ComfyUI_LC123_nodes`
- `ComfyUI_LC_MaskMaker_nodes`
- `rgthree-comfy`

Required workflow model files:
- `models/diffusion_models/BSS_DesireX3_INT8_ConvRot.safetensors`
- `models/text_encoders/qwen3vl_4b_fp8_scaled.safetensors`
- `models/vae/qwen_image_vae.safetensors`
- `models/loras/krea2_identity_edit_v2.safetensors`
- `models/background_removal/birefnet.safetensors`
- `models/vitmatte/vitmatte-small-composition-1k/{model.safetensors,config.json,preprocessor_config.json}`

Four additional optional LoRAs from the original setup are also retained: Lenovo, SNOFS, NiceGirls and Realism Engine.

The MaskMaker repo documentation says model-backed nodes fetch models on first use and reuse local copies. However, the workflow explicitly selects `models/vitmatte (local)`, which requires a local ViTMatte snapshot; it must not be left to lazy-download behavior. The bootstrap therefore preloads it.
The ComfyUI core BiRefNet loader requires the exact lowercase path `models/background_removal/birefnet.safetensors`; this is the official Comfy-Org repackaged model file. The previous package incorrectly used a different filename and source.
The MaskMaker `install.py` handles missing Python dependencies; the bootstrap executes it and checks OpenCV (`cv2`) as well.

## Build once (no GPU required)

1. Create a GitHub repository named `runpod-krea2-desirex`.
2. Extract this ZIP and upload all files/folders to the repository root, including `.github/workflows/build.yml`.
3. Open the repository's **Actions** tab and enable Actions if GitHub asks.
4. Run **Build and publish RunPod Krea2 image** (or push to `main`).
5. Wait for the build to finish. Then set the GHCR package visibility to **Public** if it is private.

Image name:
`ghcr.io/YOUR-LOWERCASE-GITHUB-USERNAME/runpod-krea2-desirex:latest`

The GitHub Actions build creates and publishes the image. It does not download model weights; those are fetched on every new Pod start.

## RunPod template

- Container Image: `ghcr.io/YOUR-LOWERCASE-GITHUB-USERNAME/runpod-krea2-desirex:latest`
- Container Start Command: leave blank
- GPU: RTX 4090 24 GB
- Container Disk: 150 GB
- Pod Volume Disk: 60 GB mounted at `/workspace` (temporary Pod disk, not Network Volume)
- Keep ports 8188, 8080, 8888, 22
- Keep `CIVITAI_TOKEN` as a RunPod Secret environment variable
- Do not attach a Network Volume

## Every fresh deployment

1. RunPod's original startup configures SSH, JupyterLab, FileBrowser and the ComfyUI workspace.
2. It activates the CUDA 12.8 venv.
3. The inserted bootstrap clones the four node repositories, installs requirements, executes each repo's `install.py` if present, verifies dependencies, downloads all workflow model files and the optional LoRAs.
4. If any required download or model-header validation fails, startup stops before ComfyUI launches, instead of presenting a half-installed UI.

No JupyterLab/terminal setup is needed per deployment. Because the Pod is fresh, the models are downloaded again each time. Download your outputs locally before terminating the Pod.

## Important verification boundary

Verified in this package preparation:
- Workflow JSON parsed; 80 nodes counted; two `LCRemBG` nodes and their exact widget selections read.
- Upstream RunPod startup script source shows `.venv-cu128` activation occurs before the exact marker used by the Dockerfile, and `python main.py` follows that marker.
- MaskMaker documentation identifies BiRefNet / ViTMatte and its install.py dependencies.
- Shell script syntax and package structure are checked locally.

Not verified here:
- A Docker daemon build against the remote base image was not run.
- GitHub Actions has not been executed, so no GHCR image has been published.
- No RTX 4090 RunPod Pod has been launched; model URLs, download sizes, Python node imports and full workflow execution still require that first remote test.

Do not treat this ZIP as a published Docker image. It is the corrected build source package.
