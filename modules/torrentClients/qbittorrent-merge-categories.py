#!/usr/bin/env python3
import json
import os
import sys
import tempfile
from pathlib import Path


def fail(message):
    raise SystemExit(f"qbittorrent-merge-categories: {message}")


def load_json(path, *, missing_default=None):
    if not path.exists():
        if missing_default is not None:
            return missing_default
        fail(f"{path} does not exist")
    try:
        with path.open() as handle:
            return json.load(handle)
    except json.JSONDecodeError as exc:
        fail(f"{path} is not valid JSON: {exc}")


def main():
    if len(sys.argv) != 3:
        fail("usage: qbittorrent-merge-categories.py CATEGORIES_JSON DECLARED_JSON")

    categories_path = Path(sys.argv[1])
    declared_path = Path(sys.argv[2])

    current = load_json(categories_path, missing_default={})
    declared = load_json(declared_path)

    if not isinstance(current, dict):
        fail("existing categories JSON must be an object")
    if not isinstance(declared, dict):
        fail("declared categories JSON must be an object")

    merged = dict(current)
    for name, value in declared.items():
        if not isinstance(value, dict):
            fail(f"declared category {name!r} must be an object")
        save_path = value.get("save_path")
        if not isinstance(save_path, str) or save_path == "":
            fail(f"declared category {name!r} must have a non-empty save_path")

        existing = merged.get(name)
        if existing is not None and not isinstance(existing, dict):
            fail(f"existing category {name!r} must be an object")
        updated = dict(existing or {})
        updated["save_path"] = save_path
        merged[name] = updated

    categories_path.parent.mkdir(parents=True, exist_ok=True)
    fd, temp_name = tempfile.mkstemp(
        prefix=f".{categories_path.name}.",
        dir=str(categories_path.parent),
        text=True,
    )
    try:
        with os.fdopen(fd, "w") as handle:
            json.dump(merged, handle, indent=2, sort_keys=True)
            handle.write("\n")
        os.replace(temp_name, categories_path)
    finally:
        if os.path.exists(temp_name):
            os.unlink(temp_name)


if __name__ == "__main__":
    main()
