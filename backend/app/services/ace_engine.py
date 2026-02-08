from __future__ import annotations

import asyncio
import logging
import os
import re
import sys
import time
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Literal, Optional, TYPE_CHECKING

from ..config import settings
from ..hardware import mps_available
from ..runtime_config import get_runtime_config
from ..utils.filename_utils import sanitize_filename
from ..utils.model_downloader import ensure_5hz_lm

try:
    from mutagen.id3 import ID3, TIT2, TPE1, COMM
    HAS_MUTAGEN = True
except ImportError:
    HAS_MUTAGEN = False

class _NullLLMHandler:
    llm_initialized = False

if TYPE_CHECKING:  # pragma: no cover
    from ..models.generation import Generation

logger = logging.getLogger(__name__)


@dataclass
class GenerationJob:
    id: str
    title: Optional[str]
    task_type: Literal["text2music", "cover", "repaint"]
    mode: Literal["simple", "custom"]
    model_variant: str
    prompt: Optional[str]
    lyrics: Optional[str]
    instrumental: bool
    bpm: Optional[int]
    duration_seconds: Optional[int]
    key: Optional[str]
    time_signature: Optional[str]
    metadata: dict[str, Any]
    cover_strength: Optional[int]
    source_audio_path: Optional[str]
    reference_audio_path: Optional[str]
    output_dir: Optional[str]

    @classmethod
    def from_orm(cls, generation: "Generation", output_dir: Optional[str] = None) -> "GenerationJob":  # type: ignore[name-defined]
        return cls(
            id=generation.id,
            title=generation.title,
            task_type=generation.task_type,
            mode=generation.mode,
            model_variant=generation.model_variant,
            prompt=generation.prompt,
            lyrics=generation.lyrics,
            instrumental=bool(generation.instrumental),
            bpm=generation.bpm,
            duration_seconds=generation.duration_seconds,
            key=generation.key,
            time_signature=generation.time_signature,
            metadata=generation.metadata_json or {},
            cover_strength=generation.cover_strength,
            source_audio_path=getattr(generation, "source_audio_path", None),
            reference_audio_path=getattr(generation, "reference_audio_path", None),
            output_dir=output_dir,
        )


@dataclass
class EngineResult:
    audio_path: Path
    prompt: str
    lyrics: str
    metadata: dict[str, Any]
    bpm: Optional[int]
    duration_seconds: Optional[float]
    key: Optional[str]
    time_signature: Optional[str]
    seed_value: str


class ACEEngine:
    def __init__(self, repo_path: Path | None = None) -> None:
        self.repo_path = settings.resolve_path(repo_path or settings.ace_repo_path)
        self.checkpoints_path = settings.resolve_path(settings.checkpoints_path)
        self.handler = None
        self.llm_handler = None
        self.initialized = False
        self.llm_ready = False
        self.generation_params_cls = None
        self.generation_config_cls = None
        self.generate_music_fn = None
        self._imports_ready = False
        self._cache_root = settings.resolve_path(Path("data/.acestep_cache"))
        self.active_variant: str | None = None

    def _prepare_environment(self) -> None:
        self._cache_root.mkdir(parents=True, exist_ok=True)
        tmp_dir = self._cache_root / "tmp"
        tmp_dir.mkdir(parents=True, exist_ok=True)
        os.environ.setdefault("ACESTEP_TMPDIR", str(tmp_dir))
        os.environ.setdefault("TMPDIR", str(tmp_dir))
        os.environ.setdefault("TEMP", str(tmp_dir))
        os.environ.setdefault("TMP", str(tmp_dir))
        os.environ.setdefault("HF_HOME", str(self._cache_root / "hf"))

    def _import_modules(self) -> None:
        if self._imports_ready:
            return
        if not self.repo_path.exists():
            raise FileNotFoundError(f"ACE-Step repo not found at {self.repo_path}")
        repo_str = str(self.repo_path)
        if repo_str not in sys.path:
            logger.info("Adding %s to sys.path", repo_str)
            sys.path.insert(0, repo_str)
        logger.info("Importing acestep modules...")
        try:
            logger.info("Importing AceStepHandler...")
            from acestep.handler import AceStepHandler  # type: ignore
            logger.info("Importing LLMHandler...")
            from acestep.llm_inference import LLMHandler  # type: ignore
            logger.info("Importing inference functions...")
            from acestep.inference import (  # type: ignore
                GenerationConfig as ACEGenerationConfig,
                GenerationParams as ACEGenerationParams,
                generate_music,
            )
            logger.info("Importing gpu_config...")
            from acestep.gpu_config import get_gpu_config, set_global_gpu_config  # type: ignore

            self.AceStepHandler = AceStepHandler
            self.LLMHandler = LLMHandler
            self.generation_params_cls = ACEGenerationParams
            self.generation_config_cls = ACEGenerationConfig
            self.generate_music_fn = generate_music

            # Detect GPU info once to help LM constraints
            gpu_config = get_gpu_config()
            set_global_gpu_config(gpu_config)
            self.gpu_config = gpu_config
        except Exception as exc:  # pragma: no cover - surfaces import errors clearly
            raise RuntimeError(f"Failed to import ACE-Step modules: {exc}") from exc
        self._imports_ready = True

    def initialize(self, model_config: Optional[str] = None, variant: Optional[str] = None) -> None:
        if self.initialized and not model_config and not variant:
            return
        target_variant = variant or settings.default_model_variant
        logger.info("Initializing ACEEngine for variant: %s", target_variant)
        self._prepare_environment()
        logger.info("Engine environment prepared")
        self._import_modules()
        logger.info("Engine modules imported")

        self._load_model(target_variant, model_config=model_config)

    def _load_model(self, variant: str, model_config: Optional[str] = None) -> None:
        model_config_map = settings.model_config_map or {}
        config_name = model_config or model_config_map.get(variant) or settings.default_model_config
        self.handler = self.AceStepHandler()
        logger.info("Loading ACE-Step DiT model '%s' for variant '%s'", config_name, variant)
        status_msg, ok = self.handler.initialize_service(
            project_root=str(self.repo_path),
            config_path=config_name,
            device=settings.device,
            use_flash_attention=settings.use_flash_attention,
            compile_model=settings.compile_model,
            offload_to_cpu=settings.offload_to_cpu,
            offload_dit_to_cpu=settings.offload_dit_to_cpu,
        )
        if not ok:
            raise RuntimeError(f"ACE-Step model init failed: {status_msg}")
        self.initialized = True
        self.active_variant = variant
        logger.info("ACE-Step DiT ready (%s)", config_name)

        self.llm_handler = self.LLMHandler()
        runtime_config = get_runtime_config()
        if runtime_config.lm_enabled and settings.lm_init_on_start:
            self._initialize_llm()

    def _initialize_llm(self) -> None:
        if not self.llm_handler or self.llm_ready:
            return
        checkpoint_dir = self.checkpoints_path
        checkpoint_dir.mkdir(parents=True, exist_ok=True)
        runtime_config = get_runtime_config()

        # Auto-Download Logic
        lm_filename = runtime_config.lm_checkpoint
        ensure_5hz_lm(lm_filename, checkpoint_dir)

        logger.info(
            "Loading ACE-Step 5Hz LM '%s' using backend=%s", runtime_config.lm_checkpoint, runtime_config.lm_backend
        )
        status, ok = self.llm_handler.initialize(
            checkpoint_dir=str(checkpoint_dir),
            lm_model_path=runtime_config.lm_checkpoint,
            backend=runtime_config.lm_backend,
            device=runtime_config.lm_device,
            offload_to_cpu=runtime_config.lm_offload_to_cpu,
            dtype=getattr(self.handler, "dtype", None),
        )
        if ok:
            self.llm_ready = True
            logger.info("ACE-Step LM ready")
        else:
            logger.warning("ACE-Step LM init skipped: %s", status)
    def ensure_variant(self, variant: str) -> None:
        if not self.initialized or self.active_variant != variant:
            self.initialize(variant=variant)

    def _build_params(self, job: GenerationJob) -> tuple[Any, Any, dict[str, Any]]:
        metadata = job.metadata or {}
        params_cls = self.generation_params_cls
        config_cls = self.generation_config_cls
        if not params_cls or not config_cls:
            raise RuntimeError("ACE-Step modules not imported")

        def _get_float(key: str, default: Optional[float] = None) -> Optional[float]:
            value = metadata.get(key, default)
            if value in (None, "", "N/A"):
                return default
            try:
                return float(value)
            except (TypeError, ValueError):
                return default

        def _get_int(key: str, default: Optional[int] = None) -> Optional[int]:
            value = metadata.get(key, default)
            if value in (None, "", "N/A"):
                return default
            try:
                return int(value)
            except (TypeError, ValueError):
                return default

        def _get_bool(key: str, default: bool) -> bool:
            value = metadata.get(key, default)
            if isinstance(value, bool):
                return value
            if isinstance(value, str):
                return value.lower() in {"1", "true", "yes", "on"}
            return bool(value)

        runtime_config = get_runtime_config()
        variant_steps_map = {
            "base": runtime_config.base_inference_steps,
            "turbo": runtime_config.turbo_inference_steps,
            "shift": runtime_config.shift_inference_steps,
        }
        default_steps = variant_steps_map.get(job.model_variant, runtime_config.turbo_inference_steps)

        duration = job.duration_seconds or _get_int("duration") or _get_int("audio_duration")
        duration = float(duration) if duration else -1.0
        keyscale = job.key or metadata.get("keyscale") or metadata.get("key_scale") or ""
        timesig = job.time_signature or metadata.get("time_signature") or metadata.get("timesignature") or ""
        thinking_default = (
            runtime_config.thinking_simple_mode if job.mode == "simple" else runtime_config.thinking_custom_mode
        )

        timesteps = metadata.get("timesteps")
        if isinstance(timesteps, str):
            try:
                timesteps = [float(x.strip()) for x in timesteps.split(",") if x.strip()]
            except ValueError:
                timesteps = None

        use_adg = _get_bool("use_adg", runtime_config.use_adg)
        if use_adg and mps_available():
            # ACE ADG currently casts to float64 internally, which MPS does not support.
            use_adg = False

        params = params_cls(
            task_type=job.task_type,
            caption=job.prompt or metadata.get("caption", ""),
            lyrics=job.lyrics or metadata.get("lyrics", ""),
            instrumental=job.instrumental,
            bpm=job.bpm or _get_int("bpm"),
            keyscale=keyscale,
            timesignature=timesig,
            duration=duration,
            inference_steps=_get_int("inference_steps", default_steps) or default_steps,
            guidance_scale=_get_float("guidance_scale", 7.0) or 7.0,
            seed=_get_int("seed", -1) or -1,
            use_adg=use_adg,
            cfg_interval_start=_get_float("cfg_interval_start", runtime_config.cfg_interval_start)
            or runtime_config.cfg_interval_start,
            cfg_interval_end=_get_float("cfg_interval_end", runtime_config.cfg_interval_end)
            or runtime_config.cfg_interval_end,
            shift=_get_float("shift", 1.0) or 1.0,
            infer_method=metadata.get("infer_method", runtime_config.infer_method),
            timesteps=timesteps,
            repainting_start=_get_float("repainting_start", 0.0) or 0.0,
            repainting_end=_get_float("repainting_end", -1.0) or -1.0,
            audio_cover_strength=_get_float(
                "audio_cover_strength", (job.cover_strength or 100) / 100.0
            )
            or 1.0,
            thinking=_get_bool("thinking", thinking_default),
            use_cot_caption=_get_bool("use_cot_caption", runtime_config.use_cot_caption),
            use_cot_language=_get_bool("use_cot_language", runtime_config.use_cot_language),
            use_cot_metas=_get_bool("use_cot_metas", runtime_config.use_cot_metas),
            lm_temperature=_get_float("lm_temperature", 0.85) or 0.85,
            lm_cfg_scale=_get_float("lm_cfg_scale", 2.0) or 2.0,
            lm_top_k=_get_int("lm_top_k", 0) or 0,
            lm_top_p=_get_float("lm_top_p", 0.9) or 0.9,
            lm_negative_prompt=metadata.get("lm_negative_prompt", "NO USER INPUT"),
            reference_audio=job.reference_audio_path,
            src_audio=job.source_audio_path,
            audio_codes=metadata.get("audio_codes", ""),
            vocal_language=metadata.get("vocal_language", "unknown"),
            instruction=metadata.get("instruction", "Fill the audio semantic mask based on the given conditions:"),
        )

        seeds = metadata.get("seeds")
        if isinstance(seeds, str):
            seeds = [int(s.strip()) for s in seeds.split(",") if s.strip().isdigit()]

        config = config_cls(
            batch_size=_get_int("batch_size", 2) or 2,
            allow_lm_batch=_get_bool("allow_lm_batch", runtime_config.allow_lm_batch),
            use_random_seed=_get_bool("use_random_seed", True),
            seeds=seeds,
            audio_format=metadata.get("audio_format", "mp3"),
            constrained_decoding_debug=_get_bool("constrained_decoding_debug", False),
        )

        return params, config, metadata

    def _normalize_metas(self, metas: dict[str, Any]) -> dict[str, Any]:
        normalized = dict(metas or {})
        if "keyscale" not in normalized and "key_scale" in normalized:
            normalized["keyscale"] = normalized.get("key_scale")
        if "timesignature" not in normalized and "time_signature" in normalized:
            normalized["timesignature"] = normalized.get("time_signature")
        for key in ["bpm", "duration", "genres", "keyscale", "timesignature"]:
            if normalized.get(key) in (None, ""):
                normalized[key] = "N/A"
        return normalized

    def _ensure_llm_ready(self) -> None:
        runtime_config = get_runtime_config()
        if not runtime_config.lm_enabled:
            return
        if not self.llm_handler:
            self.llm_handler = self.LLMHandler()
        if not self.llm_ready:
            self._initialize_llm()

    def _run_generation(self, job: GenerationJob) -> EngineResult:
        if not self.initialized or not self.handler:
            raise RuntimeError("ACE-Step engine not initialized")
        
        job_title = job.title or "Untitled"
        logger.info("Starting generation for '%s' (ID: %s) using variant %s", job_title, job.id, job.model_variant)
        start_time_perf = time.perf_counter()

        params, config, existing_metadata = self._build_params(job)
        self._ensure_llm_ready()

        llm = self.llm_handler or _NullLLMHandler()

        if job.output_dir:
            output_dir = Path(job.output_dir)
        else:
            output_dir = settings.resolve_path(settings.generations_dir) / job.id
        output_dir.mkdir(parents=True, exist_ok=True)

        result = self.generate_music_fn(
            dit_handler=self.handler,
            llm_handler=llm,
            params=params,
            config=config,
            save_dir=str(output_dir),
            progress=None,
        )
        if not result.success:
            raise RuntimeError(result.error or result.status_message or "Generation failed")

        audio_entries = [audio for audio in result.audios if audio.get("path")]
        if not audio_entries:
            raise RuntimeError("Generation succeeded but no audio paths returned")
        
        # Multiple Audio Outputs Handling
        processed_audio_files = []
        primary_audio_path = None
        
        safe_title = sanitize_filename(job_title)
        
        for i, audio in enumerate(audio_entries):
            raw_path = Path(audio["path"]).resolve()
            
            # Create a unique friendly filename for each output
            suffix = f"-{i}" if i > 0 else ""
            new_filename = f"{safe_title}-{job.id}{suffix}{raw_path.suffix}"
            friendly_path = raw_path.parent / new_filename
            
            try:
                os.rename(raw_path, friendly_path)
                current_audio_path = friendly_path
            except Exception as e:
                logger.warning("Failed to rename %s to friendly filename: %s", raw_path, e)
                current_audio_path = raw_path

            if i == 0:
                primary_audio_path = current_audio_path

            # ID3 Tagging & Metadata Embedding (only for supported formats)
            if HAS_MUTAGEN and current_audio_path.suffix.lower() in {".mp3", ".wav"}:
                try:
                    try:
                        audio_tags = ID3(str(current_audio_path))
                    except Exception:
                        audio_tags = ID3()
                        
                    audio_tags.add(TIT2(encoding=3, text=job_title))
                    audio_tags.add(TPE1(encoding=3, text="ACE-Step Studio"))
                    
                    # Build parameters string
                    extra = result.extra_outputs or {}
                    meta = extra.get("lm_metadata") or {}
                    params_str = f"Prompt: {job.prompt or ''}\n"
                    params_str += f"Steps: {params.inference_steps}, Guidance: {params.guidance_scale}, Seed: {params.seed}\n"
                    params_str += f"BPM: {meta.get('bpm', 'N/A')}, Key: {meta.get('keyscale', 'N/A')}, Time: {meta.get('timesignature', 'N/A')}\n"
                    params_str += f"Model: {job.model_variant}\n"
                    
                    audio_tags.add(COMM(encoding=3, lang='eng', desc='parameters', text=params_str))
                    audio_tags.save(str(current_audio_path))
                except Exception as e:
                    logger.warning("Failed to write ID3 tags to %s: %s", current_audio_path, e)

            processed_audio_files.append(str(current_audio_path))

        lm_metadata = result.extra_outputs.get("lm_metadata", {})
        metas = self._normalize_metas(lm_metadata)
        metas.setdefault("prompt", job.prompt or "")
        metas.setdefault("lyrics", job.lyrics or "")

        seed_values = []
        for audio in audio_entries:
            seed_val = audio.get("params", {}).get("seed")
            if seed_val is not None:
                seed_values.append(str(seed_val))
        seed_value = ",".join(seed_values)

        merged_metadata = {
            **existing_metadata,
            "metas": metas,
            "lm_metadata": lm_metadata,
            "time_costs": result.extra_outputs.get("time_costs", {}),
            "seed_value": seed_value,
            "audio_files": processed_audio_files,
            "primary_audio_file": str(primary_audio_path),
            "final_prompt": result.extra_outputs.get("final_prompt", params.caption),
            "final_lyrics": result.extra_outputs.get("final_lyrics", params.lyrics),
        }

        bpm = metas.get("bpm")
        bpm_value = bpm if isinstance(bpm, int) else None
        duration = metas.get("duration")
        duration_value = None
        try:
            if isinstance(duration, (int, float)):
                duration_value = float(duration)
            elif isinstance(duration, str) and duration not in {"", "N/A"}:
                duration_value = float(duration)
        except (TypeError, ValueError):
            duration_value = None

        keyscale = metas.get("keyscale")
        if isinstance(keyscale, str) and keyscale in {"", "N/A"}:
            keyscale = None
        timesig = metas.get("timesignature")
        if isinstance(timesig, str) and timesig in {"", "N/A"}:
            timesig = None

        elapsed = time.perf_counter() - start_time_perf
        logger.info("Generation complete for '%s' in %.2fs (Audio length: %ss)", 
                    job_title, elapsed, duration_value or "unknown")

        return EngineResult(
            audio_path=primary_audio_path,
            prompt=result.extra_outputs.get("final_prompt", params.caption) or params.caption,
            lyrics=result.extra_outputs.get("final_lyrics", params.lyrics) or params.lyrics,
            metadata=merged_metadata,
            bpm=bpm_value,
            duration_seconds=duration_value,
            key=keyscale,
            time_signature=timesig,
            seed_value=seed_value,
        )

    async def generate_async(self, job: GenerationJob) -> EngineResult:
        loop = asyncio.get_running_loop()
        return await loop.run_in_executor(None, lambda: self._run_generation(job))

    def handle_runtime_config_change(self) -> None:
        runtime_config = get_runtime_config()
        if not runtime_config.lm_enabled:
            self.llm_ready = False
        else:
            # Reinitialize with new settings on next request
            self.llm_ready = False


def create_job_from_model(generation: "Generation", output_dir: Optional[str] = None) -> GenerationJob:  # type: ignore[name-defined]
    return GenerationJob.from_orm(generation, output_dir=output_dir)


engine = ACEEngine()
