#!/bin/bash
# FNGarvin - ACE-Step Studio Runner (Container)
# MIT License 2026
set -e

echo "======================================================================"
echo "Starting ACE-Step Studio Container"
echo "======================================================================"

# Defaults
HOST="0.0.0.0"
BACKEND_PORT=8788
FRONTEND_PORT=5175
QUIET=true
VERBOSE=false

# Simple Flag Parsing
while [[ "$#" -gt 0 ]]; do
    case $1 in
        -q|--quiet) QUIET=true; VERBOSE=false; shift ;;
        -v|--verbose) VERBOSE=true; QUIET=false; shift ;;
        /bin/bash|*/run.sh) shift ;; # Ignore entrypoint noise
        *) echo "[WARNING] Unknown parameter passed: $1"; shift ;;
    esac
done

# Activate Environment (if exists)
if [ -f "backend/.venv/bin/activate" ]; then
    source backend/.venv/bin/activate
elif [ -f ".venv/bin/activate" ]; then
    source .venv/bin/activate
fi

# Fix LD_LIBRARY_PATH for torchaudio and other libs
if [ -d "backend/.venv" ]; then
    VENV_LIB="$(pwd)/backend/.venv/lib/python3.12/site-packages"
else
    # Try to find site-packages dynamically (useful for system/docker installs)
    VENV_LIB=$(python3 -c 'import site; print(site.getsitepackages()[0])' 2>/dev/null || echo "/usr/local/lib/python3.12/dist-packages")
fi

# We append to the existing path to avoid breaking hard-won local configurations
export LD_LIBRARY_PATH=$LD_LIBRARY_PATH:$VENV_LIB/torch/lib:$VENV_LIB/nvidia/cublas/lib:$VENV_LIB/nvidia/cuda_cupti/lib:$VENV_LIB/nvidia/cuda_nvrtc/lib:$VENV_LIB/nvidia/cuda_runtime/lib:$VENV_LIB/nvidia/cudnn/lib:$VENV_LIB/nvidia/cufft/lib:$VENV_LIB/nvidia/curand/lib:$VENV_LIB/nvidia/cusolver/lib:$VENV_LIB/nvidia/cusparse/lib:$VENV_LIB/nvidia/nccl/lib:$VENV_LIB/nvidia/nvjitlink/lib:$VENV_LIB/nvidia/nvtx/lib
export NVIDIA_VISIBLE_DEVICES=all

# Ensure Runtime Config Exists (Handles volume mounts)
if [ ! -f "data/runtime_config.json" ]; then
    echo "[INFO] Seeding default runtime config..."
    python3 -c 'from backend.app.runtime_config import update_runtime_config; update_runtime_config(lm_enabled=True)'
fi

# Start Backend
echo "[INFO] Starting Backend on ${HOST}:${BACKEND_PORT}..."
export PYTHONPATH=$PYTHONPATH:$(pwd)

UVICORN_ARGS=""
if [ "$QUIET" = "true" ] || [ "$QUIET_LOGS" = "true" ]; then
    UVICORN_ARGS="--log-level info"
    export ACE_STEP_QUIET=true
elif [ "$VERBOSE" = "true" ]; then
    UVICORN_ARGS="--log-level debug"
    export ACE_STEP_VERBOSE=true
fi

python3 -m uvicorn backend.app.main:app --host "${HOST}" --port "${BACKEND_PORT}" ${UVICORN_ARGS} &
BACKEND_PID=$!

# Start Frontend
echo "[INFO] Starting Frontend on ${HOST}:${FRONTEND_PORT}..."
if [ -d "frontend" ]; then
    cd frontend
    npm run dev -- --host "${HOST}" --port "${FRONTEND_PORT}" &
    FRONTEND_PID=$!
    cd ..
else
    echo "[WARNING] frontend directory not found. Skipping frontend start."
fi

# Start Filebrowser
echo "[INFO] Starting Filebrowser on port 8080..."
filebrowser -r /workspace/data -p 8080 -a 0.0.0.0 --noauth &
FILEBROWSER_PID=$!

# Start SSHD
echo "[INFO] Starting SSHD..."
mkdir -p /run/sshd
if [ ! -L "/var/run/sshd" ] && [ ! -d "/var/run/sshd" ]; then
    ln -s /run/sshd /var/run/sshd
fi

# Generate host keys if missing (guard for local non-RunPod runs)
if [ ! -f "/etc/ssh/ssh_host_rsa_key" ]; then
    ssh-keygen -A
fi

/usr/sbin/sshd -D &
SSHD_PID=$!

# Trap for graceful shutdown
trap "kill $BACKEND_PID $FRONTEND_PID $FILEBROWSER_PID $SSHD_PID; exit" SIGINT SIGTERM

echo "[SUCCESS] All services started. Waiting..."
wait
#EOF run.sh
