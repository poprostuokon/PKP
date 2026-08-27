"""
prune.py
--------
Porzadek w ARCHIVE: dla (feed, dzien) zostaw pliki najswiezszego run_ts,
starsze przebiegi tego samego dnia usun. Operations bezpieczny - grupujemy
po run_ts, wiec wszystkie strony _pNNN danego runu zostaja razem.
"""

from collections import defaultdict
from pathlib import Path

from .paths import archive_dir, parse_filename, _TS_RE


def prune_archive(part_date: str) -> None:
    d = archive_dir(part_date)
    if not d.exists():
        return

    # (kategoria, feed) -> { run_ts: [pliki] }
    groups: dict[tuple, dict[str, list[Path]]] = defaultdict(lambda: defaultdict(list))
    for f in d.glob("*.json"):
        m = _TS_RE.search(f.stem)
        if not m:
            continue
        run_ts = m.group(1)
        category, subtype, _ = parse_filename(f.name)
        groups[(category, subtype)][run_ts].append(f)

    removed = 0
    for by_ts in groups.values():
        latest = max(by_ts)                      # najwyzszy run_ts w grupie
        for run_ts, files in by_ts.items():
            if run_ts != latest:
                for f in files:
                    f.unlink()
                    removed += 1
    if removed:
        print(f"prune ARCHIVE {part_date}: usunieto {removed} starszych plikow")


def keep_latest_todo(directory, feed: str) -> None:
    """
    W katalogu TODO zostawia pliki tylko NAJNOWSZEGO run_ts dla danego feedu,
    starsze przebiegi tego samego feedu usuwa. Operations bezpieczny -
    wszystkie strony _pNNN jednego runu maja ten sam run_ts, wiec zostaja razem.
    """
    files = []
    for f in directory.glob("*.json"):
        _, subtype, _ = parse_filename(f.name)   # data->subtype, dict->name
        if subtype == feed:
            m = _TS_RE.search(f.stem)
            if m:
                files.append((m.group(1), f))
    if not files:
        return
    latest = max(ts for ts, _ in files)
    for ts, f in files:
        if ts != latest:
            f.unlink()