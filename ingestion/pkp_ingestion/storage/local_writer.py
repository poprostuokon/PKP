"""
local_writer.py
---------------
Zapis surowego JSON lokalnie do struktury Data (TODO).
To jest "pelna historia" wg naszej zasady bronze = pliki, nie DB.
Tresc zapisywana bit w bit - zero parsowania.
"""

from pathlib import Path


def write_raw(directory: Path, filename: str, content: str) -> Path:
    """
    Tworzy katalog (jesli brak) i zapisuje surowy tekst do pliku.
    Zwraca pelna sciezke zapisanego pliku.
    """
    directory.mkdir(parents=True, exist_ok=True)
    out_path = directory / filename
    out_path.write_text(content, encoding="utf-8")
    return out_path