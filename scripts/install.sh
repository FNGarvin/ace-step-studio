#!/bin/bash
# FNGarvin - ACE-Step Studio Installer (Linux/macOS)
# MIT License 2026

set -e

# UV Configuration
export UV_LINK_MODE="copy"
export UV_CACHE_DIR="${HOME}/.cache/uv"
# Load centralized versions
source "$(dirname "$0")/versions.env"

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
ACE_REPO="${ACE_STEP_REPO_PATH:-$ROOT_DIR/ACE-Step-1.5}"

echo "======================================================================"
echo "         ACE-STEP STUDIO - INSTALLER (Linux/macOS)"
echo "======================================================================"

# Check/Install uv
if ! command -v uv &> /dev/null; then
    echo "[INFO] Installing uv..."
    curl -LsSf https://astral.sh/uv/install.sh | sh
    export PATH="$HOME/.local/bin:$HOME/.cargo/bin:$PATH"
fi

# Check for --system flag
USE_SYSTEM=false
INSTALL_ARGS=""
if [[ "$*" == *"--system"* ]]; then
    USE_SYSTEM=true
    INSTALL_ARGS="--system --break-system-packages"
fi

echo "[STEP 1/5] Preparing Python Environment..."
if [ "$USE_SYSTEM" = true ]; then
    echo "[INFO] Using system Python environment (Skipping venv creation)..."
    VENV_PYTHON="python3"
else
    # Create venv with specific python version
    # Using --seed to ensure pip/setuptools/wheel presence if needed, though uv handles most things
    uv venv "$ROOT_DIR/backend/.venv" --python $PYTHON_VERSION --seed --managed-python --clear
    source "$ROOT_DIR/backend/.venv/bin/activate"
    VENV_PYTHON="python"
fi

echo "[STEP 2/5] Installing PyTorch..."
# Skip PyTorch installation if using system and torch matches requirements (roughly)
# For Docker images where torch is pre-installed
if [ "$USE_SYSTEM" = true ] && pip show torch &> /dev/null; then
    echo "[INFO] System Torch detected. Skipping explicit Torch installation."
else
    echo "Select Accelerator:"
    echo "   1) Apple Silicon (MPS) / CPU (Default)"
    echo "   2) NVIDIA CUDA (Linux)"
    echo "   3) CPU Only"
    if [ -z "$ACC_CHOICE" ]; then
        read -r -p "Choose [1/2/3]: " ACC_CHOICE
    fi
    ACC_CHOICE=${ACC_CHOICE:-1}


    case "$ACC_CHOICE" in
      2)
        echo "[INFO] Installing Torch (CUDA 12.8)..."
        uv pip install $INSTALL_ARGS torch==${TORCH_VERSION} torchvision==${TORCHVISION_VERSION} torchaudio==${TORCHAUDIO_VERSION} --index-url ${CUDA_INDEX_URL}
        ;;
      *)
        # Defaulting to standard PyPI for Mac/CPU which usually has wheels for MPS
        echo "[INFO] Installing Torch..."
        pure_torch="${TORCH_VERSION%+*}"
        pure_vision="${TORCHVISION_VERSION%+*}"
        pure_audio="${TORCHAUDIO_VERSION%+*}"
        uv pip install $INSTALL_ARGS torch==${pure_torch} torchvision==${pure_vision} torchaudio==${pure_audio} --index-url ${CPU_INDEX_URL}
        ;;
    esac
fi

echo "[STEP 3/5] Setup ACE-Step Repository..."
if [ ! -d "$ACE_REPO" ]; then
    if [ -z "$CLONE_REPLY" ]; then
    read -r -p "ACE-Step repo not found at $ACE_REPO. Clone now? [Y/n] " CLONE_REPLY
fi
CLONE_REPLY=${CLONE_REPLY:-Y}
    if [[ "$CLONE_REPLY" =~ ^[Yy]$ ]]; then
        git clone --depth 1 https://github.com/ace-step/ACE-Step-1.5 "$ACE_REPO"
    else
        echo "ACE-Step repo is required. Set ACE_STEP_REPO_PATH or clone manually."
        exit 1
    fi
fi

echo "[STEP 4/5] Installing Application..."
echo "[INFO] Installing backend dependencies..."
uv pip install $INSTALL_ARGS -e "$ROOT_DIR/backend"

echo "[INFO] Installing ACE-Step dependencies..."
# We install these explicitly to ensure uv handles them efficiently
uv pip install $INSTALL_ARGS "transformers>=4.51.0,<4.58.0" "diffusers" "gradio" "matplotlib>=3.7.5" \
    "scipy>=1.10.1" "soundfile>=0.13.1" "loguru>=0.7.3" "einops>=0.8.1" \
    "accelerate>=1.12.0" "diskcache" "numba>=0.63.1" "vector-quantize-pytorch>=1.27.15" \
    "torchao" "modelscope"

echo "[INFO] Installing ACE-Step in editable mode..."
uv pip install $INSTALL_ARGS -e "$ACE_REPO" --no-deps

echo "[INFO] Seeding runtime config..."
$VENV_PYTHON <<'PY'
from backend.app.runtime_config import update_runtime_config
update_runtime_config(
    lm_enabled=True,
    default_model_variant="turbo",
    base_inference_steps=32,
    turbo_inference_steps=8,
    shift_inference_steps=8,
    image_generation_provider="none",
    a1111_base_url="http://127.0.0.1:7860",
)
print("Runtime config initialized at data/runtime_config.json")
PY


echo "[STEP 5/5] Installing Frontend..."
pushd "$ROOT_DIR/frontend" > /dev/null
if command -v npm &> /dev/null; then
    npm install
else
    echo "[INFO] npm not found. Installing fnm and Node.js LTS..."
    # Install fnm
    curl -fsSL https://fnm.vercel.app/install | bash -s -- --install-dir "$HOME/.local/bin" --skip-shell
    export PATH="$HOME/.local/bin:$PATH"
    eval "$(fnm env)"
    
    # Install Node LTS
    fnm install --lts
    fnm use --lts
    
    if command -v npm &> /dev/null; then
        echo "[INFO] Node.js $(node -v) installed successfully."
        npm install
    else
        echo "[WARNING] Automatic Node.js installation failed. Please install manually."
    fi
fi
popd > /dev/null

echo "======================================================================"
echo "Installation complete!"
echo "Run the app with: ./scripts/start.sh"
