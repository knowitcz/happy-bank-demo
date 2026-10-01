"""Transcript discovery and issue attribution for the session-cost skill.

Answers two questions cost.py cannot answer from its hook payload alone:
which files hold this session's usage records, and which GitHub issue that
usage belongs to.

Like pricing.py, nothing here raises on malformed input -- the transcript
format is undocumented and version-fragile, so an unrecognized line is skipped
and an unattributable session simply yields no issue.
"""

from __future__ import annotations

import json
import re
from pathlib import Path

# A *claim*, never a bare mention. Solve sessions routinely reference a
# parent issue's number in prose and in `gh` reads without working it, so
# matching plain "#83" over-attributes; these three subcommands are the only
# points at which a flow declares "I am now working issue N":
#   /refine  -> set-stage <N> in-refinement
#   /solve   -> set-stage <N> in-implementation
#   /process-ai -> ai-start <N>   (ai issues skip stage:* entirely)
# Any invocation prefix matches, since the pattern anchors on the script name.
#
# Deliberately NOT claims: set-stage <N> refined|fresh. /refine Step 8b
# stamps a demoted sub-issue child that way, never in-refinement -- that is
# what keeps a decomposition run's cost wholly on the parent (see SKILL.md
# and docs/ai/session-cost.md). Adding either stage here would silently
# split the parent's total onto its children.
CLAIM_RE = re.compile(
    r"issue\.sh\s+(?:"
    r"set-stage\s+(?P<staged>\d+)\s+in-(?:refinement|implementation)"
    r"|ai-start\s+(?P<ai>\d+)"
    r")"
)


def iter_entries(path: Path):
    """Yield parsed JSONL records from `path`, skipping unparseable lines.

    A transcript being written to concurrently can end in a partial line; that
    is a normal read, not an error.
    """
    try:
        with open(path, encoding="utf-8", errors="replace") as handle:
            for line in handle:
                line = line.strip()
                if not line:
                    continue
                try:
                    entry = json.loads(line)
                except ValueError:
                    continue
                if isinstance(entry, dict):
                    yield entry
    except OSError:
        return


def session_files(transcript: Path) -> list[Path]:
    """The main transcript plus every subagent transcript it spawned.

    Subagent spend has to be included or a /solve run reports a fraction of
    its real cost -- the specialist subagents do much of the work. They live
    in a sibling directory named after the session, which is why attribution
    is session-scoped rather than a time sweep over the whole project
    directory: that directory is shared, and a concurrent session working a
    *different* issue would otherwise be absorbed into this total.
    """
    files = [transcript] if transcript.is_file() else []
    subagents = transcript.parent / transcript.stem / "subagents"
    if subagents.is_dir():
        files.extend(sorted(subagents.glob("agent-*.jsonl")))
    return files


def load_session(transcript: Path) -> list[dict]:
    entries: list[dict] = []
    for path in session_files(transcript):
        entries.extend(iter_entries(path))
    return entries


def find_claims(entries: list[dict]) -> list[tuple[str, int]]:
    """Every issue claim in the session, as (timestamp, issue number).

    Ordered by timestamp and collapsed so a repeated claim on the same issue
    (a /solve run re-claiming after a block) does not open a new window. A
    claim that *failed* still matches -- the tool_use input is read, not its
    result -- which is accepted: set-stage failing is rare, and the fallback
    (cost attributed to an issue the session did touch) beats dropping it.
    """
    found: list[tuple[str, int]] = []
    for entry in entries:
        ts = entry.get("timestamp")
        if not isinstance(ts, str):
            continue
        for command in _bash_commands(entry):
            for match in CLAIM_RE.finditer(command):
                number = match.group("staged") or match.group("ai")
                found.append((ts, int(number)))
    found.sort(key=lambda pair: pair[0])

    collapsed: list[tuple[str, int]] = []
    for ts, number in found:
        if collapsed and collapsed[-1][1] == number:
            continue
        collapsed.append((ts, number))
    return collapsed


def _bash_commands(entry: dict):
    message = entry.get("message")
    if not isinstance(message, dict):
        return
    content = message.get("content")
    if not isinstance(content, list):
        return
    for block in content:
        if not isinstance(block, dict) or block.get("type") != "tool_use":
            continue
        if block.get("name") != "Bash":
            continue
        command = (block.get("input") or {}).get("command")
        if isinstance(command, str):
            yield command


def partition(entries: list[dict], claims: list[tuple[str, int]]) -> dict[int, list[dict]]:
    """Group `entries` by the issue they are attributed to.

    One claim -- the overwhelmingly common case, since a session works one
    issue at a time -- attributes the *whole* session, including the gate,
    fetch and planning turns that precede the claim. Those are real cost of
    working that issue, and a claim-anchored partial sum would drop them.

    Several claims fall back to splitting at claim boundaries: entries before
    the first claim join the first issue, and each later claim opens a window
    that runs until the next one. Coarser than tracking each subagent to its
    spawning turn, but it keeps a two-issue session from reporting one issue's
    cost twice.
    """
    if not claims:
        return {}
    if len({number for _, number in claims}) == 1:
        return {claims[0][1]: list(entries)}

    buckets: dict[int, list[dict]] = {number: [] for _, number in claims}
    boundaries = [ts for ts, _ in claims]
    for entry in entries:
        ts = entry.get("timestamp")
        index = 0
        if isinstance(ts, str):
            while index + 1 < len(boundaries) and ts >= boundaries[index + 1]:
                index += 1
        buckets[claims[index][1]].append(entry)
    return {number: rows for number, rows in buckets.items() if rows}


def project_dir_for(transcript: Path) -> Path:
    return transcript.parent


def project_dir_for_cwd(cwd: Path, root: Path | None = None) -> Path:
    """The ~/.claude/projects/<slug> directory Claude Code uses for `cwd`.

    Needed only by --sweep, which has no hook payload to read a transcript
    path from. The slug is the absolute path with every non-alphanumeric
    character replaced by a dash.
    """
    base = root or (Path.home() / ".claude" / "projects")
    slug = re.sub(r"[^a-zA-Z0-9]", "-", str(cwd.resolve()))
    return base / slug
