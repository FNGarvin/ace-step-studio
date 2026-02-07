from __future__ import annotations

import uuid
from datetime import datetime
from typing import Optional

from sqlalchemy import Boolean, DateTime, Float, Index, Integer, String, Text, JSON
from sqlalchemy.orm import Mapped, mapped_column
from sqlalchemy.sql import func

from .database import Base


def generate_uuid() -> str:
    return str(uuid.uuid4())


class Generation(Base):
    __tablename__ = "generations"

    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=generate_uuid)
    created_at: Mapped[datetime] = mapped_column(DateTime, server_default=func.now())
    updated_at: Mapped[datetime] = mapped_column(
        DateTime, server_default=func.now(), onupdate=func.now()
    )

    title: Mapped[Optional[str]] = mapped_column(String(255), nullable=True)
    task_type: Mapped[str] = mapped_column(String(32), default="text2music")
    mode: Mapped[str] = mapped_column(String(32), default="simple")
    model_variant: Mapped[str] = mapped_column(String(32), default="turbo")
    status: Mapped[str] = mapped_column(String(32), default="queued")
    error_message: Mapped[Optional[str]] = mapped_column(Text, nullable=True)

    # Inputs
    prompt: Mapped[Optional[str]] = mapped_column(Text, nullable=True)
    lyrics: Mapped[Optional[str]] = mapped_column(Text, nullable=True)
    instrumental: Mapped[bool] = mapped_column(Boolean, default=False)
    bpm: Mapped[Optional[int]] = mapped_column(Integer, nullable=True)
    duration_seconds: Mapped[Optional[float]] = mapped_column(Float, nullable=True)
    key: Mapped[Optional[str]] = mapped_column(String(16), nullable=True)
    time_signature: Mapped[Optional[str]] = mapped_column(String(16), nullable=True)
    cover_strength: Mapped[Optional[int]] = mapped_column(Integer, nullable=True)

    # Outputs
    output_audio_path: Mapped[Optional[str]] = mapped_column(String(1024), nullable=True)
    cover_image_path: Mapped[Optional[str]] = mapped_column(String(1024), nullable=True)
    metadata_json: Mapped[Optional[dict]] = mapped_column(JSON, nullable=True)

    # Theme
    cover_color: Mapped[Optional[str]] = mapped_column(String(32), nullable=True)
    cover_icon: Mapped[Optional[str]] = mapped_column(String(32), nullable=True)

    __table_args__ = (Index("ix_generations_created_at", "created_at"),)
