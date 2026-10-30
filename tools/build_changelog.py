"""Collects docs/releases/v*.md into game/data/changelog.json for the About page.

docs/ does not ship with the game, so run this before a release:
    python tools/build_changelog.py
"""
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent


def version_key(path: Path) -> tuple:
    return tuple(int(part) for part in path.stem[1:].split("."))


def notes_of(text: str) -> list:
    section = re.search(r"^### Что нового\s*$(.*?)(?=^#{1,3} |\Z)", text, re.M | re.S)
    body = section.group(1) if section else text
    return [line[2:].strip() for line in body.splitlines() if line.startswith("- ")]


def main() -> None:
    releases = sorted((ROOT / "docs" / "releases").glob("v*.md"), key=version_key, reverse=True)
    entries = [{"version": path.stem[1:], "notes": notes_of(path.read_text(encoding="utf-8"))} for path in releases]
    target = ROOT / "game" / "data" / "changelog.json"
    target.write_text(json.dumps(entries, ensure_ascii=False, indent="\t") + "\n", encoding="utf-8")
    print(f"{target}: {len(entries)} versions")


if __name__ == "__main__":
    main()
