import re

def sanitize_filename(name: str, fallback: str = "untitled") -> str:
    """Sanitizes a string for use as a filename."""
    base = re.sub(r"[^A-Za-z0-9 _-]+", "", name).strip()
    if not base:
        base = fallback
    return base[:64].strip() or fallback
