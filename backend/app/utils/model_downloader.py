"""
FNGarvin 2026
TODO: INSERT LICENSE
Shared utility for downloading model checkpoints.
"""
import logging
from pathlib import Path
from typing import Tuple

logger = logging.getLogger(__name__)

def ensure_5hz_lm(lm_filename: str, checkpoint_dir: Path) -> Tuple[bool, str]:
    """
    Checks if the 5Hz LM model exists in checkpoint_dir, and downloads it if missing.
    Returns (success, message).
    """
    checkpoint_dir.mkdir(parents=True, exist_ok=True)
    full_path = checkpoint_dir / lm_filename
    
    if full_path.exists():
        return True, "Model already exists"
    
    logger.info("5Hz LM model not found at %s. Attempting auto-download...", full_path)
    try:
        from acestep.model_downloader import download_submodel
        success, msg = download_submodel(lm_filename, checkpoint_dir)
        if not success:
            logger.error("Failed to auto-download 5Hz LM: %s", msg)
            return False, msg
        
        logger.info("5Hz LM model downloaded successfully.")
        return True, "Downloaded successfully"
    except ImportError:
        err = "Could not import acestep.model_downloader"
        logger.error(err)
        return False, err
    except Exception as e:
        err = f"Error during 5Hz LM auto-download: {e}"
        logger.error(err)
        return False, err

#EOF model_downloader.py
