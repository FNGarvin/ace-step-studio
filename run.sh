#!/bin/bash
set -e

echo "======================================================================"
echo "Starting ACE-Step Studio Container"
echo "======================================================================"

# Defaults
HOST="0.0.0.0"
BACKEND_PORT=8788
FRONTEND_PORT=5175

# Start Backend
echo "[INFO] Starting Backend on ${HOST}:${BACKEND_PORT}..."
export PYTHONPATH=$PYTHONPATH:$(pwd)
python3 -m uvicorn backend.app.main:app --host "${HOST}" --port "${BACKEND_PORT}" --log-level info &
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
/usr/sbin/sshd -D &
SSHD_PID=$!

# Trap for graceful shutdown
trap "kill $BACKEND_PID $FRONTEND_PID $FILEBROWSER_PID $SSHD_PID; exit" SIGINT SIGTERM

echo "[SUCCESS] All services started. Waiting..."
wait
