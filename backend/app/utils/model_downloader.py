"""
FNGarvin 2026
TODO: INSERT LICENSE
Shared utility for downloading model checkpoints.
"""
import logging
from pathlib import Path
from typing import Tuple

logger = logging.getLogger(__name__)

def ensure_5hz_lm(lm_filename: str, checkpoint_dir: Path) -> None:
    """
    Checks if the 5Hz LM model exists in checkpoint_dir, and downloads it if missing.
    Raises RuntimeError on failure.
    """
    checkpoint_dir.mkdir(parents=True, exist_ok=True)
    full_path = checkpoint_dir / lm_filename
    
    if full_path.exists():
        logger.debug("5Hz LM model already exists at %s", full_path)
        return
    
    logger.info("5Hz LM model not found at %s. Attempting auto-download...", full_path)
    try:
        from acestep.model_downloader import download_submodel
        success, msg = download_submodel(lm_filename, checkpoint_dir)
        if not success:
            err = f"Failed to auto-download 5Hz LM: {msg}"
            logger.error(err)
            raise RuntimeError(err)
        
        logger.info("5Hz LM model downloaded successfully.")
    except ImportError as e:
        err = "Could not import acestep.model_downloader"
        logger.error(err)
        raise RuntimeError(err) from e
    except Exception as e:
        err = f"Error during 5Hz LM auto-download: {e}"
        logger.error(err)
        raise RuntimeError(err) from e

#EOF model_downloader.py
