# FNGarvin - ACE-Step Studio Installer (Windows)
# MIT License 2026

$ErrorActionPreference = "Stop"
$ROOT = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Definition)

# Parse versions.env for centralized version management
$versionsFile = Join-Path (Join-Path $ROOT "scripts") "versions.env"
$versions = @{}
if (Test-Path $versionsFile) {
    Get-Content $versionsFile | ForEach-Object {
        if ($_ -match "^(?<key>[A-Z0-9_]+)=\"(?<value>.*)\"") {
            $versions[$Matches.key] = $Matches.value
        }
    }
}

$PYTHON_VERSION = if ($versions.PYTHON_VERSION) { $versions.PYTHON_VERSION } else { "3.12" }
$TORCH_VERSION = if ($versions.TORCH_VERSION) { $versions.TORCH_VERSION } else { "2.10.0+cu128" }
$TORCHVISION_VERSION = if ($versions.TORCHVISION_VERSION) { $versions.TORCHVISION_VERSION } else { "0.17.0+cu128" }
$TORCHAUDIO_VERSION = if ($versions.TORCHAUDIO_VERSION) { $versions.TORCHAUDIO_VERSION } else { "2.10.0+cu128" }
$CUDA_INDEX_URL = if ($versions.CUDA_INDEX_URL) { $versions.CUDA_INDEX_URL } else { "https://download.pytorch.org/whl/cu128" }
$CPU_INDEX_URL = if ($versions.CPU_INDEX_URL) { $versions.CPU_INDEX_URL } else { "https://download.pytorch.org/whl/cpu" }
$pyEnv = Join-Path $ROOT "backend/.venv"
$defaultAce = [System.IO.Path]::GetFullPath((Join-Path $ROOT "ACE-Step-1.5"))
$aceRepo = if ($env:ACE_STEP_REPO_PATH) { $env:ACE_STEP_REPO_PATH } else { $defaultAce }
$nodeDir = Join-Path $ROOT "frontend"

Write-Host "======================================================================"
Write-Host "         ACE-STEP STUDIO - INSTALLER (Windows)"
Write-Host "======================================================================"

# UV Configuration
$env:UV_LINK_MODE = "copy"
$env:UV_CACHE_DIR = Join-Path $env:LOCALAPPDATA "uv\cache"
if (-not (Test-Path $env:UV_CACHE_DIR)) {
    New-Item -ItemType Directory -Force -Path $env:UV_CACHE_DIR | Out-Null
}

# Check/Install uv
if (-not (Get-Command "uv" -ErrorAction SilentlyContinue)) {
    Write-Host "[INFO] Installing uv..."
    powershell -ExecutionPolicy ByPass -c "irm https://astral.sh/uv/install.ps1 | iex"
    $env:Path = "$env:USERPROFILE\.local\bin;$env:Path"
}

Write-Host "[STEP 1/5] Preparing Python Environment..."
# uv handles python download and venv creation
uv venv $pyEnv --python $PYTHON_VERSION --seed --managed-python --clear
if (-not (Test-Path "$pyEnv\Scripts\Activate.ps1")) {
  throw "Virtual environment was not created successfully."
}
& "$pyEnv/Scripts/Activate.ps1"

Write-Host "[STEP 2/5] Installing PyTorch..."
Write-Host "Select Accelerator:"
Write-Host "   1) CPU (Default)"
Write-Host "   2) NVIDIA CUDA 12.8"
$choice = Read-Host "Choose option [1/2]"
if ([string]::IsNullOrWhiteSpace($choice)) { $choice = "1" }

switch ($choice) {
  "2" { uv pip install torch==$TORCH_VERSION torchvision==$TORCHVISION_VERSION torchaudio==$TORCHAUDIO_VERSION --index-url $CUDA_INDEX_URL }
  default { 
    $pureTorch = $TORCH_VERSION -replace '\+.*$', ''
    $pureVision = $TORCHVISION_VERSION -replace '\+.*$', ''
    $pureAudio = $TORCHAUDIO_VERSION -replace '\+.*$', ''
    uv pip install torch==$pureTorch torchvision==$pureVision torchaudio==$pureAudio --index-url $CPU_INDEX_URL 
  }
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
$tempScript = Join-Path $ROOT "seed_config.py"
$runtimeScript | Out-File -FilePath $tempScript -Encoding UTF8
python $tempScript
Remove-Item $tempScript

# Pre-flight Check for VC++ Redistributables (Greenlet/SQLAlchemy)
Write-Host "[INFO] Checking for Visual C++ Redistributables..."
$vcppCheckScript = "try:`n    import greenlet`nexcept ImportError as e:`n    if 'DLL load failed' in str(e): print('MISSING_VC_REDIST')`n    else: print(e)"
$tempCheck = Join-Path $ROOT "check_vcpp.py"
$vcppCheckScript | Out-File -FilePath $tempCheck -Encoding UTF8

try {
    $checkResult = & "$pyEnv/Scripts/python.exe" $tempCheck 2>&1
    if ($checkResult -match "MISSING_VC_REDIST") {
        Write-Warning "Visual C++ Redistributable is missing (required for Greenlet/SQLAlchemy)."
        if (Get-Command "winget" -ErrorAction SilentlyContinue) {
             Write-Host "Installing Microsoft Visual C++ Redistributable (2015-2022) via winget..."
             winget install -e --id Microsoft.VCRedist.2015+.x64 --accept-source-agreements --accept-package-agreements
             Write-Warning "VC++ Runtime installed. A system reboot might be required."
        } else {
             Write-Error "Please install the Microsoft Visual C++ Redistributable manually."
        }
    }
} finally {
    if (Test-Path $tempCheck) { Remove-Item $tempCheck }
}
Write-Host "[STEP 5/5] Installing Frontend..."
Push-Location $nodeDir
try {
    if (Get-Command "npm" -ErrorAction SilentlyContinue) {
        npm install
    } else {
        Write-Host "[INFO] npm not found. Checking for winget..."
        if (Get-Command "winget" -ErrorAction SilentlyContinue) {
            Write-Host "Installing Node.js LTS via winget..."
            winget install -e --id OpenJS.NodeJS.LTS --accept-source-agreements --accept-package-agreements
            
            # Refresh env path from registry to avoid restart if possible
            $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")
            
            if (Get-Command "npm" -ErrorAction SilentlyContinue) {
                 npm install
            } else {
                 Write-Warning "Node.js installed, but a shell restart is required to use 'npm'. Please restart this script."
            }
        } else {
            Write-Warning "npm not found and winget is unavailable. Please install Node.js manually."
        }
    }
} finally {
    Pop-Location
}

Write-Host "Installation complete. Run scripts/start.bat to launch."
