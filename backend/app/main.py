from __future__ import annotations

import os

# Robust initialization of LD_LIBRARY_PATH for AI libraries (torchaudio, torch, nvidia)
def init_ld_library_path():
    venv_base = "/workspace/backend/.venv/lib/python3.11/site-packages"
    extra_paths = [
        f"{venv_base}/torch/lib",
        f"{venv_base}/nvidia/cublas/lib",
        f"{venv_base}/nvidia/cuda_cupti/lib",
        f"{venv_base}/nvidia/cuda_nvrtc/lib",
        f"{venv_base}/nvidia/cuda_runtime/lib",
        f"{venv_base}/nvidia/cudnn/lib",
        f"{venv_base}/nvidia/cufft/lib",
        f"{venv_base}/nvidia/curand/lib",
        f"{venv_base}/nvidia/cusolver/lib",
        f"{venv_base}/nvidia/cusparse/lib",
        f"{venv_base}/nvidia/nccl/lib",
        f"{venv_base}/nvidia/nvjitlink/lib",
        f"{venv_base}/nvidia/nvtx/lib",
        "/usr/local/nvidia/lib",
        "/usr/local/nvidia/lib64"
    ]
    current = os.environ.get("LD_LIBRARY_PATH", "")
    new_path = ":".join(extra_paths)
    if current:
        new_path = f"{new_path}:{current}"
    os.environ["LD_LIBRARY_PATH"] = new_path

init_ld_library_path()

import asyncio
import logging
from contextlib import asynccontextmanager

# Setup logging earliest to catch all logger inits
log_level = logging.INFO
if os.getenv("ACE_STEP_QUIET") == "true":
    log_level = logging.INFO
elif os.getenv("ACE_STEP_VERBOSE") == "true":
    log_level = logging.DEBUG

logging.basicConfig(
    level=log_level,
    format="%(asctime)s %(levelname)s: [%(name)s] %(message)s",
)

# Refined logging: Suppress repetitive polling noise
class PollingFilter(logging.Filter):
    def filter(self, record: logging.LogRecord) -> bool:
        # record.getMessage() contains the log line, e.g., "127.0.0.1:port - GET /path HTTP/1.1 200 OK"
        msg = record.getMessage()
        if "GET /api/history" in msg or "GET /api/models" in msg or "GET /api/config" in msg or "GET /health" in msg:
            return False
        return True

logging.getLogger("uvicorn.access").addFilter(PollingFilter())

logger = logging.getLogger(__name__)
logger.info("ACE-Step Studio backend initialized with log level: %s", logging.getLevelName(log_level))

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from .config import settings
from .database import Base, engine
from .migrations import run_migrations
from .routers import config as config_router
from .routers import generate, history, llm, models


@asynccontextmanager
async def lifespan(app: FastAPI):
    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.create_all)
        await run_migrations(conn)
    yield


app = FastAPI(title=settings.app_name, debug=settings.debug, lifespan=lifespan)

app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.cors_origins,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

app.include_router(config_router.router)
app.include_router(generate.router)
app.include_router(history.router)
app.include_router(llm.router)
app.include_router(models.router)


@app.get("/health")
async def health() -> dict[str, str]:
    return {"status": "ok"}
