#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-or-later
# Every bundled-script flag cited in the skill's documents must exist in that script's --help.
"""Usage: check-flags.py

Scans inline code spans in SKILL.md, agents/, references/ and scripts/README.md of every skill for
"<script>.py ... --flag" and checks each flag against "python3 scripts/<script>.py --help".
Exit 0 when all citations are valid, 1 otherwise.
"""

import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SPAN = re.compile(r"`([^`]+)`")
CALL = re.compile(r"(?:python3 )?(?:<skill>/)?(?:scripts/)?([A-Za-z_-]+\.py)\b(.*)")
FLAG = re.compile(r"(?<![\w-])(--[a-z][a-z0-9-]+)")


def main():
    problems, checked = [], 0
    for skill in sorted(
        p for p in (ROOT / "skills").iterdir() if (p / "SKILL.md").exists()
    ):
        scripts = {p.name: p for p in (skill / "scripts").glob("*.py")}
        helps = {}
        docs = [skill / "SKILL.md", skill / "scripts" / "README.md"]
        docs += sorted((skill / "agents").glob("*.md")) + sorted(
            (skill / "references").glob("*.md")
        )
        for doc in (d for d in docs if d.exists()):
            text = doc.read_text(encoding="utf-8")
            rel = doc.relative_to(ROOT).as_posix()
            for name in set(re.findall(r"scripts/([A-Za-z_-]+\.py)", text)) - set(
                scripts
            ):
                problems.append(f"flags: {rel}: mentions missing script {name}")
            fenced = False
            for num, line in enumerate(text.splitlines(), 1):
                if line.lstrip().startswith(("```", "~~~")):
                    fenced = not fenced
                    continue
                for span in [line.strip()] if fenced else SPAN.findall(line):
                    call = CALL.match(span)
                    if not call or call.group(1) not in scripts:
                        continue
                    name = call.group(1)
                    if name not in helps:
                        helps[name] = subprocess.run(
                            [sys.executable, str(scripts[name]), "--help"],
                            capture_output=True,
                            text=True,
                            timeout=60,
                            check=False,
                        ).stdout
                    for flag in FLAG.findall(call.group(2)):
                        checked += 1
                        if not re.search(
                            rf"(?<![\w-]){re.escape(flag)}(?![\w-])", helps[name]
                        ):
                            problems.append(f"flags: {rel}:{num}: {name} has no {flag}")
    print(
        "\n".join(problems)
        if problems
        else f"ok - {checked} flag citations match --help"
    )
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
