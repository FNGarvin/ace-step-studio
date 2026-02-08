#!/bin/bash
# FNGarvin - ACE-Step Studio Runner (Container)
# MIT License 2026

set -e

# Defaults
HOST="0.0.0.0"
BACKEND_PORT=8788
FRONTEND_PORT=5175
QUIET=true
VERBOSE=false

# Simple Flag Parsing
while [[ "$#" -gt 0 ]]; do
    case $1 in
        -q|--quiet) QUIET=true; shift ;;
        -v|--verbose) VERBOSE=true; shift ;;
        /bin/bash|*/run.sh) shift ;; # Ignore entrypoint noise
        *) echo "[WARNING] Unknown parameter passed: $1"; shift ;;
    esac
done

# Ensure Symlink (Insurance for in-place or rebuild)
if [ ! -L "/ACE-Step-1.5" ]; then
    echo "[INFO] Setting up /ACE-Step-1.5 symlink..."
    if [ -d "/workspace/ACE-Step-1.5" ] && [ ! -d "/ACE-Step-1.5" ]; then
        ln -s /workspace/ACE-Step-1.5 /ACE-Step-1.5
    fi
fi

# Activate Environment
if [ -f "backend/.venv/bin/activate" ]; then
    source backend/.venv/bin/activate
elif [ -f ".venv/bin/activate" ]; then
    source .venv/bin/activate
fi

# Fix LD_LIBRARY_PATH for torchaudio and other libs (Using absolute paths)
VENV_LIB=/workspace/backend/.venv/lib/python3.11/site-packages
export LD_LIBRARY_PATH=$LD_LIBRARY_PATH:$VENV_LIB/torch/lib:$VENV_LIB/nvidia/cublas/lib:$VENV_LIB/nvidia/cuda_cupti/lib:$VENV_LIB/nvidia/cuda_nvrtc/lib:$VENV_LIB/nvidia/cuda_runtime/lib:$VENV_LIB/nvidia/cudnn/lib:$VENV_LIB/nvidia/cufft/lib:$VENV_LIB/nvidia/curand/lib:$VENV_LIB/nvidia/cusolver/lib:$VENV_LIB/nvidia/cusparse/lib:$VENV_LIB/nvidia/nccl/lib:$VENV_LIB/nvidia/nvjitlink/lib:$VENV_LIB/nvidia/nvtx/lib
export NVIDIA_VISIBLE_DEVICES=all
echo "[DEBUG] Final LD_LIBRARY_PATH: $LD_LIBRARY_PATH"
echo "[DEBUG] NVIDIA_VISIBLE_DEVICES: $NVIDIA_VISIBLE_DEVICES"

# Ensure Runtime Config Exists
if [ ! -f "data/runtime_config.json" ]; then
    echo "[INFO] Seeding default runtime config..."
    python -c 'from backend.app.runtime_config import update_runtime_config; update_runtime_config(lm_enabled=True)'
fi

echo "======================================================================"
echo "Starting ACE-Step Studio Container"
echo "======================================================================"

# Start Backend
echo "[DEBUG] Starting Backend on $HOST:$BACKEND_PORT..."
export PYTHONPATH=$PYTHONPATH:$(pwd)

# Logging configuration
UVICORN_ARGS=""
if [ "$QUIET" = "true" ] || [ "$QUIET_LOGS" = "true" ]; then
    echo "[INFO] Quiet mode enabled: Filtering chatty polling logs."
    UVICORN_ARGS="--log-level info"
    export ACE_STEP_QUIET=true
elif [ "$VERBOSE" = "true" ]; then
    echo "[INFO] Verbose mode enabled."
    UVICORN_ARGS="--log-level debug"
    export ACE_STEP_VERBOSE=true
fi

# Use env to ensure variables are passed to the background process
env LD_LIBRARY_PATH="$LD_LIBRARY_PATH" \
    NVIDIA_VISIBLE_DEVICES="$NVIDIA_VISIBLE_DEVICES" \
    PYTHONPATH="$PYTHONPATH" \
    python -m uvicorn backend.app.main:app --host "$HOST" --port "$BACKEND_PORT" $UVICORN_ARGS &
BACKEND_PID=$!

# Start Frontend
echo "[INFO] Starting Frontend on $HOST:$FRONTEND_PORT..."
cd frontend
npm run dev -- --host "$HOST" --port "$FRONTEND_PORT" &
FRONTEND_PID=$!

# Trap for graceful shutdown
# Start SSHD
echo "[INFO] Starting SSHD..."
if [ ! -d "/var/run/sshd" ]; then
    mkdir -p /var/run/sshd
fi
# Generate host keys if missing
if [ ! -f "/etc/ssh/ssh_host_rsa_key" ]; then
    ssh-keygen -A
fi
/usr/sbin/sshd -D &
SSHD_PID=$!

# Start Filebrowser
echo "[INFO] Starting Filebrowser on port 8080..."
filebrowser -r /workspace -p 8080 -a 0.0.0.0 --noauth & # --noauth for simplicity in runpod, adjust if needed
FILEBROWSER_PID=$!

# Trap for graceful shutdown
trap "kill $BACKEND_PID $FRONTEND_PID $SSHD_PID $FILEBROWSER_PID; exit" SIGINT SIGTERM

wait
#EOF run.sh
