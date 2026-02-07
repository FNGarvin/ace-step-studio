#!/bin/bash
# FNGarvin - ACE-Step Studio Runner (Container)
# MIT License 2026

set -e

# Defaults
HOST="0.0.0.0"
BACKEND_PORT=8788
FRONTEND_PORT=5175

# Activate Environment
if [ -f "backend/.venv/bin/activate" ]; then
    source backend/.venv/bin/activate
elif [ -f ".venv/bin/activate" ]; then
    source .venv/bin/activate
fi

# Ensure Runtime Config Exists
if [ ! -f "data/runtime_config.json" ]; then
    echo "[INFO] Seeding default runtime config..."
    python -c 'from backend.app.runtime_config import update_runtime_config; update_runtime_config(lm_enabled=True)'
fi

echo "======================================================================"
echo "Starting ACE-Step Studio Container"
echo "======================================================================"

# Start Backend
echo "[INFO] Starting Backend on $HOST:$BACKEND_PORT..."
export PYTHONPATH=$PYTHONPATH:$(pwd)
python -m uvicorn backend.app.main:app --host "$HOST" --port "$BACKEND_PORT" &
BACKEND_PID=$!

# Start Frontend
echo "[INFO] Starting Frontend on $HOST:$FRONTEND_PORT..."
cd frontend
# In production container, we might serve static files, but for now we follow "dev" mode as per plan?
# Actually, Dockerfile installs npm deps. Let's run dev server for flexibility as requested in plan "Starts Vite frontend (in dev mode or served build)"
# "dev" mode is easier for now.
npm run dev -- --host "$HOST" --port "$FRONTEND_PORT" &
FRONTEND_PID=$!

# Trap for graceful shutdown
trap "kill $BACKEND_PID $FRONTEND_PID; exit" SIGINT SIGTERM

wait
