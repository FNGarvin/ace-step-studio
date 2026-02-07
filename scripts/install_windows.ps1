# FNGarvin - ACE-Step Studio Installer (Windows)
# MIT License 2026

$ErrorActionPreference = "Stop"
$ROOT = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Definition)
$pyEnv = Join-Path $ROOT "backend/.venv"
$defaultAce = [System.IO.Path]::GetFullPath((Join-Path $ROOT "..\ACE-Step-1.5"))
$aceRepo = if ($env:ACE_STEP_REPO_PATH) { $env:ACE_STEP_REPO_PATH } else { $defaultAce }
$nodeDir = Join-Path $ROOT "frontend"

Write-Host "======================================================================"
Write-Host "         ACE-STEP STUDIO - INSTALLER (Windows)"
Write-Host "======================================================================"

# Check/Install uv
if (-not (Get-Command "uv" -ErrorAction SilentlyContinue)) {
    Write-Host "[INFO] Installing uv..."
    powershell -ExecutionPolicy ByPass -c "irm https://astral.sh/uv/install.ps1 | iex"
}

Write-Host "[STEP 1/5] Preparing Python Environment..."
# uv handles python download and venv creation
uv venv $pyEnv --python 3.11 --seed --managed-python
if (-not (Test-Path "$pyEnv\Scripts\Activate.ps1")) {
  throw "Virtual environment was not created successfully."
}
& "$pyEnv/Scripts/Activate.ps1"

Write-Host "[STEP 2/5] Installing PyTorch..."
Write-Host "Select Accelerator:"
Write-Host "   1) CPU (Default)"
Write-Host "   2) NVIDIA CUDA 12.1"
$choice = Read-Host "Choose option [1/2]"
if ([string]::IsNullOrWhiteSpace($choice)) { $choice = "1" }

switch ($choice) {
  "2" { uv pip install torch==2.1.2+cu121 torchvision==0.16.2+cu121 torchaudio==2.1.2+cu121 --index-url https://download.pytorch.org/whl/cu121 }
  default { uv pip install torch==2.1.2 torchvision==0.16.2 torchaudio==2.1.2 --index-url https://download.pytorch.org/whl/cpu }
}

Write-Host "[STEP 3/5] Setup ACE-Step Repository..."
if (-not (Test-Path $aceRepo)) {
  $reply = Read-Host "ACE-Step repo not found at $aceRepo. Clone now? [Y/n]"
  if ([string]::IsNullOrWhiteSpace($reply) -or $reply -match "^[Yy]") {
    git clone https://github.com/ace-step/ACE-Step-1.5 $aceRepo
  } else {
    Write-Error "ACE-Step repo required. Set ACE_STEP_REPO_PATH or clone manually."
    exit 1
  }
}

Write-Host "[STEP 4/5] Installing Application..."
Write-Host "[INFO] Installing backend..."
uv pip install -e "$ROOT/backend" --link-mode hardlink

Write-Host "[INFO] Installing ACE-Step dependencies..."
$aceCoreDeps = @(
  "transformers>=4.51.0,<4.58.0",
  "diffusers",
  "gradio",
  "matplotlib>=3.7.5",
  "scipy>=1.10.1",
  "soundfile>=0.13.1",
  "loguru>=0.7.3",
  "einops>=0.8.1",
  "accelerate>=1.12.0",
  "diskcache",
  "numba>=0.63.1",
  "vector-quantize-pytorch>=1.27.15",
  "torchao",
  "modelscope"
)
uv pip install @aceCoreDeps --link-mode hardlink

Write-Host "[INFO] Installing ACE-Step in editable mode..."
uv pip install -e "$aceRepo" --no-deps --link-mode hardlink

Write-Host "[INFO] Seeding runtime config..."
$runtimeScript = @'
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
'@
python -c $runtimeScript

Write-Host "[STEP 5/5] Installing Frontend..."
Set-Location $nodeDir
if (Get-Command "npm" -ErrorAction SilentlyContinue) {
    npm install
} else {
    Write-Warning "npm not found. Skipping frontend installation."
}

Write-Host "Installation complete. Run scripts/start.bat to launch."
