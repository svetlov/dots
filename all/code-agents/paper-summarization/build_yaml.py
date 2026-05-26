#!/usr/bin/env python3
"""
Splice a Zotero Actions & Tags JS source file into its companion YAML backup.

WHY THIS EXISTS
---------------
Zotero's Actions & Tags plugin imports actions from a YAML backup file. The
JavaScript that an action runs is stored inside that YAML as a block scalar
(`data: |`). Editing JavaScript inside a YAML block is painful — bad
indentation, no syntax highlighting, awkward diffs — so we keep the JS in a
plain `.js` file (the editable source of truth) and use this script to
splice it back into the YAML before importing.

WORKFLOW
--------
1. Edit `<name>_action.js`.
2. Run `python3 build_yaml.py <name>_action.js <name>-action.yml`.
3. In Zotero → Tools → Actions & Tags Settings, delete the old action,
   then import the regenerated YAML.

The YAML's metadata (action id, event, operation, menu config, ...) is
preserved untouched — only the `data:` block is replaced.

USAGE
-----
    python3 build_yaml.py SOURCE.js TARGET.yml
"""
from __future__ import annotations

import re
import sys
from pathlib import Path


def splice(yml_text: str, js_text: str) -> str:
    """Return yml_text with the `data: |` block scalar replaced by js_text."""
    m = re.search(r"^(\s+)data:\s*\|\s*\n", yml_text, re.MULTILINE)
    if not m:
        raise SystemExit("could not find `data: |` block in target YAML")

    key_indent = m.group(1)              # spaces before `data:` (e.g. "    ")
    body_indent = key_indent + "  "      # block-scalar children: parent + 2

    start = m.end()
    # Walk forward until we hit a non-blank line whose indent < body_indent.
    rest = yml_text[start:]
    consumed = 0
    for line in rest.splitlines(keepends=True):
        stripped = line.lstrip("\n")
        if stripped.strip() == "":
            consumed += len(line)
            continue
        if not line.startswith(body_indent):
            break
        consumed += len(line)
    end = start + consumed

    indented = "".join(
        (body_indent + line if line.strip() else line) + "\n"
        for line in js_text.splitlines()
    )

    return yml_text[:start] + indented + yml_text[end:]


def main(argv: list[str]) -> int:
    if len(argv) != 3:
        print(f"usage: {argv[0]} SOURCE.js TARGET.yml", file=sys.stderr)
        return 2
    src = Path(argv[1])
    tgt = Path(argv[2])

    js = src.read_text()
    yml = tgt.read_text()
    new_yml = splice(yml, js)
    tgt.write_text(new_yml)
    print(f"updated {tgt} ({len(js)} bytes of JS inserted from {src})")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
