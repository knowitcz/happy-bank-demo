#!/usr/bin/env python3
"""Post an estimated per-session token/dollar cost onto the issue a session worked.

Two entry points, one costing core:

  --hook    read a SessionEnd hook payload on stdin and cost that session now
  --sweep   cost every finished session in this project that the hook missed

The sweep exists because a killed or crashed session never fires SessionEnd,
and a cost record that silently disappears whenever a session dies is not a
record. It is registered with the OS scheduler (cron/launchd) by whoever wants
it; only that registration is external -- the logic is this same file, so the
two paths can never drift apart.

Degradation is the standing contract: this runs during session teardown, so
every failure path prints to stderr and exits 0. No cost comment is a nuisance;
a broken teardown, or a confidently wrong dollar figure, is a defect.
"""

from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
import tempfile
from datetime import datetime, timedelta, timezone
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from lib import attribution, pricing  # noqa: E402

SCRIPTS = Path(__file__).resolve().parent
SKILLS = SCRIPTS.parents[1]
REPO_ROOT = SCRIPTS.parents[3]
ISSUE_SH = SKILLS / "issue-lifecycle" / "scripts" / "issue.sh"
RATES = SCRIPTS / "rates.json"

# A transcript touched this recently is assumed to belong to a live session:
# summing it now would report a partial total and burn the .done marker that
# would have stopped the real SessionEnd hook from posting the full one.
ACTIVE_GRACE = timedelta(minutes=30)

# SessionEnd hooks are hard-capped at 60s of wall clock by Claude Code, so
# these two must sum to less than that (settings.json asks for the full 60).
# A hook killed at the cap has not written its .done marker, so the sweep --
# which runs under no such budget -- posts it on the next pass. That is the
# designed recovery, not a lost record.
READ_TIMEOUT = 15
POST_TIMEOUT = 40

# A resumed session fires SessionEnd with reason "resume" *before* it carries
# on under the same session id. Costing it there would report a partial total
# and burn the one-shot marker, so settings.json's matcher excludes it; this
# is the belt-and-braces check for a hand-edited or matcher-less registration.
SKIP_REASONS = frozenset({"resume"})


def warn(message: str) -> None:
    print(f"session-cost: {message}", file=sys.stderr)


def state_dir() -> Path:
    override = os.environ.get("SESSION_COST_STATE_DIR")
    path = Path(override) if override else Path.home() / ".claude" / "session-cost"
    path.mkdir(parents=True, exist_ok=True)
    return path


def marker_text(session_id: str) -> str:
    return f"<!-- issue-lifecycle:cost:{session_id} -->"


def already_posted(issue: int, session_id: str) -> bool:
    """Secondary guard: has this session's cost comment already landed?

    The .done marker on disk is the primary guard. This one covers the case it
    cannot -- state directory wiped, a different machine -- at the price of one
    read per post. A read, so it stays outside issue.sh's sole-writer rule.
    """
    try:
        result = subprocess.run(
            ["gh", "issue", "view", str(issue), "--json", "comments",
             "--jq", ".comments[].body"],
            cwd=REPO_ROOT, capture_output=True, text=True,
            timeout=READ_TIMEOUT, check=True,
        )
    except (OSError, subprocess.SubprocessError):
        return False
    return marker_text(session_id) in result.stdout


def post(issue: int, session_id: str, body: str, dry_run: bool) -> bool:
    if dry_run:
        print(f"--- would post to #{issue} ---\n{body}")
        return True
    with tempfile.NamedTemporaryFile("w", suffix=".md", delete=False,
                                     encoding="utf-8") as handle:
        handle.write(body)
        path = handle.name
    try:
        subprocess.run(
            ["bash", str(ISSUE_SH), "cost", str(issue), path, session_id],
            cwd=REPO_ROOT, check=True, timeout=POST_TIMEOUT,
        )
        return True
    except (OSError, subprocess.SubprocessError) as exc:
        warn(f"could not post cost for #{issue}: {exc!r}")
        return False
    finally:
        os.unlink(path)


def compose(session_id: str, issue: int, trigger: str, rows: list[dict],
            rates: dict | None) -> str:
    """Build the comment body: one human line, then a fixed machine-readable block.

    The block is the point of the comment. "Compare cost across issues" -- the
    reason #83 was filed -- is not something a reader can do over prose, so the
    schema is fixed and identical in every cost comment, and the human sentence
    above it is the convenience, not the record.
    """
    per_model = pricing.summarize(rows)
    totals = pricing.totals(per_model)
    first, last = pricing.window(rows)

    if rates is None:
        usd, priced, degraded = None, per_model, "rates_unreadable"
        as_of = None
    else:
        usd, priced, degraded = pricing.price(per_model, rates,
                                              datetime.now(timezone.utc).date())
        as_of = rates.get("as_of")

    record = {
        "session_id": session_id,
        "issue": issue,
        "trigger": trigger,
        "from": first,
        "to": last,
        "tokens": totals,
        "per_model": priced,
        "usd": usd,
        "rates_as_of": as_of,
        "degraded": degraded,
    }

    token_total = sum(totals.values())
    if usd is None:
        headline = (f"Estimated cost unavailable (`{degraded}`) — "
                    f"{token_total:,} tokens recorded for this session.")
    else:
        headline = (f"Estimated **${usd:,.2f}** — {token_total:,} tokens across "
                    f"{len(priced)} model(s).")
        if degraded:
            headline += f" Partial: `{degraded}`."

    block = json.dumps(record, indent=2, sort_keys=True)
    return f"{headline}\n\n```json\n{block}\n```\n"


def process(session_id: str, transcript: Path, trigger: str,
            rates: dict | None, dry_run: bool) -> None:
    done = state_dir() / f"{session_id}.done"
    if done.exists() and not dry_run:
        return

    entries = attribution.load_session(transcript)
    claims = attribution.find_claims(entries)
    parts = attribution.partition(entries, claims)
    if not parts:
        # A session that never claimed an issue (exploration, a chat, a flow
        # that refused at the gate) has nowhere to post. Mark it done anyway,
        # or every sweep re-reads it forever.
        done.touch()
        return

    posted_all = True
    for issue, rows in sorted(parts.items()):
        if not dry_run and already_posted(issue, session_id):
            continue
        body = compose(session_id, issue, trigger, rows, rates)
        posted_all = post(issue, session_id, body, dry_run) and posted_all

    if posted_all and not dry_run:
        done.touch()


def run_hook(args) -> int:
    try:
        payload = json.load(sys.stdin)
    except ValueError as exc:
        warn(f"unreadable hook payload: {exc!r}")
        return 0
    session_id = payload.get("session_id")
    transcript = payload.get("transcript_path")
    reason = payload.get("reason", "?")
    if not isinstance(session_id, str) or not isinstance(transcript, str):
        warn("hook payload carries no session_id/transcript_path")
        return 0
    if reason in SKIP_REASONS:
        return 0
    process(session_id, Path(transcript), f"hook:{reason}",
            pricing.load_rates(RATES), args.dry_run)
    return 0


def watermark_path() -> Path:
    return state_dir() / "sweep-watermark"


def read_watermark() -> datetime | None:
    try:
        return pricing.parse_ts(watermark_path().read_text(encoding="utf-8").strip())
    except OSError:
        return None


def run_sweep(args) -> int:
    """Cost every finished, unposted session in this project's transcript dir."""
    # Anchored on the repo this script lives in, not on cwd: a cron entry whose
    # `cd` lands in a subdirectory (or fails outright) would otherwise resolve a
    # slug that does not exist and no-op silently, forever.
    project = (Path(args.project_dir) if args.project_dir
               else attribution.project_dir_for_cwd(REPO_ROOT))
    if not project.is_dir():
        warn(f"no transcript directory at {project}")
        return 0

    now = datetime.now(timezone.utc)
    watermark = read_watermark()
    if watermark is None:
        # First ever sweep. Every transcript ever recorded predates it, and
        # posting them all would mass-comment the entire backlog's history --
        # so the first run only sets the line and reports nothing.
        _write_watermark(now - ACTIVE_GRACE)
        warn("first sweep: watermark initialized, nothing posted")
        return 0

    rates = pricing.load_rates(RATES)
    for transcript in sorted(project.glob("*.jsonl")):
        try:
            touched = datetime.fromtimestamp(transcript.stat().st_mtime, timezone.utc)
        except OSError:
            continue
        if touched <= watermark or now - touched < ACTIVE_GRACE:
            continue
        process(transcript.stem, transcript, "sweep", rates, args.dry_run)

    if not args.dry_run:
        _write_watermark(now - ACTIVE_GRACE)
    return 0


def _write_watermark(when: datetime) -> None:
    watermark_path().write_text(when.isoformat(), encoding="utf-8")


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument("--hook", action="store_true",
                      help="read a SessionEnd payload on stdin")
    mode.add_argument("--sweep", action="store_true",
                      help="cost finished sessions the hook missed")
    parser.add_argument("--project-dir",
                        help="override the transcript directory (--sweep only)")
    parser.add_argument("--dry-run", action="store_true",
                        help="print what would be posted; write no state")
    args = parser.parse_args(argv)

    # The blanket catch is the degradation contract, not laziness: this runs
    # inside session teardown against an undocumented file format, and no
    # parsing surprise there is worth failing a session over.
    try:
        return run_hook(args) if args.hook else run_sweep(args)
    except Exception as exc:  # noqa: BLE001
        warn(f"skipped: {exc!r}")
        return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
