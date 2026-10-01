"""Token-bucket summation and USD pricing for the session-cost skill.

Split out of cost.py because this is the half that goes stale: rates.json's
numbers are transcribed by hand from Anthropic's published price list, so the
staleness policy and the unknown-model degradation belong next to the
arithmetic that depends on them rather than next to the transcript plumbing.

Nothing here raises on bad data. Every failure mode returns a *degradation
reason* instead, because the caller runs inside a SessionEnd hook: a crash
there would surface as a broken session teardown, and a wrong dollar figure is
worse than no dollar figure.
"""

from __future__ import annotations

import json
from datetime import date, datetime, timedelta

# The five priced dimensions. Cache *writes* split by TTL because a 1h write
# costs 2x base input and a 5m write only 1.25x -- collapsing them into one
# "cache_creation" number (as usage.cache_creation_input_tokens does) misprices
# any session that mixes them, and Claude Code mixes them routinely.
BUCKETS = ("input", "output", "cache_write_1h", "cache_write_5m", "cache_read")

# Rates are quoted per 1M tokens.
PER = 1_000_000


def zero_buckets() -> dict[str, int]:
    return dict.fromkeys(BUCKETS, 0)


def entry_usage(entry: dict) -> tuple[str, str, dict[str, int]] | None:
    """Extract (message_id, model, buckets) from one transcript entry.

    Returns None for any entry that carries no usage block (user turns, tool
    results, meta records) or whose shape doesn't match -- the transcript
    format is undocumented and may change, so an unrecognized entry is
    skipped, never fatal.
    """
    msg = entry.get("message")
    if not isinstance(msg, dict):
        return None
    usage = msg.get("usage")
    if not isinstance(usage, dict):
        return None
    mid = msg.get("id")
    model = msg.get("model")
    if not isinstance(mid, str) or not isinstance(model, str):
        return None

    creation = usage.get("cache_creation")
    if isinstance(creation, dict):
        write_1h = _int(creation.get("ephemeral_1h_input_tokens"))
        write_5m = _int(creation.get("ephemeral_5m_input_tokens"))
    else:
        # Older/leaner shape: only the collapsed total is present. Bill it at
        # the 5m rate -- that is the API default TTL, so it is the assumption
        # that under- rather than over-states cost when the split is unknown.
        write_1h = 0
        write_5m = _int(usage.get("cache_creation_input_tokens"))

    return mid, model, {
        "input": _int(usage.get("input_tokens")),
        "output": _int(usage.get("output_tokens")),
        "cache_write_1h": write_1h,
        "cache_write_5m": write_5m,
        "cache_read": _int(usage.get("cache_read_input_tokens")),
    }


def _int(value) -> int:
    return value if isinstance(value, int) and value >= 0 else 0


def summarize(entries) -> dict[str, dict[str, int]]:
    """Sum token buckets per model over `entries`, deduplicated by message id.

    Deduplication is not an optimization, it is a correctness requirement.
    One assistant response whose content spans several blocks (thinking, then
    text, then a tool_use) is written to the transcript as several JSONL lines
    that each repeat the *same* usage block. Measured on a real /solve
    transcript: 151 usage-bearing lines for 80 distinct message ids, so naive
    summation overstates spend by ~1.9x.
    """
    per_model: dict[str, dict[str, int]] = {}
    seen: set[str] = set()
    for entry in entries:
        got = entry_usage(entry)
        if got is None:
            continue
        mid, model, buckets = got
        if mid in seen:
            continue
        seen.add(mid)
        target = per_model.setdefault(model, zero_buckets())
        for key, value in buckets.items():
            target[key] += value
    return per_model


def totals(per_model: dict[str, dict[str, int]]) -> dict[str, int]:
    out = zero_buckets()
    for buckets in per_model.values():
        for key, value in buckets.items():
            out[key] += value
    return out


def load_rates(path) -> dict | None:
    """Read rates.json. Returns None if it is missing or unparseable."""
    try:
        with open(path, encoding="utf-8") as handle:
            rates = json.load(handle)
    except (OSError, ValueError):
        return None
    if not isinstance(rates.get("models"), dict):
        return None
    return rates


def staleness(rates: dict, today: date) -> str | None:
    """Return a degradation reason if the rate table is too old to trust.

    Rates are copied in by hand and nothing in the repo verifies them against
    Anthropic's price list, so an unbounded table would silently keep quoting
    dollar figures years after a price change. Past the window the comment
    still reports token counts -- those are measured, not transcribed -- and
    simply omits the dollar figure.
    """
    as_of = rates.get("as_of")
    window = rates.get("staleness_days")
    if not isinstance(as_of, str) or not isinstance(window, int):
        return "rates_undated"
    try:
        stamped = date.fromisoformat(as_of)
    except ValueError:
        return "rates_undated"
    if today - stamped > timedelta(days=window):
        return f"rates_stale_since_{as_of}"
    return None


def price(per_model: dict[str, dict[str, int]], rates: dict, today: date):
    """Cost `per_model` in USD.

    Returns (total_usd, priced_per_model, degraded_reason). `total_usd` is None
    when nothing could be priced; `degraded_reason` is None on a clean run.
    Models missing from the table are reported by name rather than guessed at:
    a new model release must show up as a visible degradation, not as a
    silently-too-low number.
    """
    stale = staleness(rates, today)
    if stale:
        return None, {model: dict(b) for model, b in per_model.items()}, stale

    multipliers = rates.get("cache_multipliers") or {}
    table = rates["models"]
    priced: dict[str, dict] = {}
    total = 0.0
    unknown: list[str] = []

    for model, buckets in sorted(per_model.items()):
        entry = dict(buckets)
        model_rates = table.get(model)
        if not isinstance(model_rates, dict):
            unknown.append(model)
            entry["usd"] = None
        else:
            usd = _model_usd(buckets, model_rates, multipliers)
            entry["usd"] = round(usd, 4) if usd is not None else None
            if usd is not None:
                total += usd
        priced[model] = entry

    if unknown and len(unknown) == len(per_model):
        return None, priced, "unpriced_models:" + ",".join(sorted(unknown))
    reason = "unpriced_models:" + ",".join(sorted(unknown)) if unknown else None
    return round(total, 4), priced, reason


def _model_usd(buckets, model_rates, multipliers) -> float | None:
    try:
        base_in = float(model_rates["input"])
        base_out = float(model_rates["output"])
    except (KeyError, TypeError, ValueError):
        return None
    rate = {
        "input": base_in,
        "output": base_out,
        "cache_write_1h": base_in * float(multipliers.get("cache_write_1h", 2.0)),
        "cache_write_5m": base_in * float(multipliers.get("cache_write_5m", 1.25)),
        "cache_read": base_in * float(multipliers.get("cache_read", 0.1)),
    }
    return sum(buckets[key] * rate[key] for key in BUCKETS) / PER


def window(entries) -> tuple[str | None, str | None]:
    """Earliest and latest timestamp across `entries`, as ISO strings."""
    stamps = []
    for entry in entries:
        ts = entry.get("timestamp")
        if isinstance(ts, str):
            stamps.append(ts)
    if not stamps:
        return None, None
    return min(stamps), max(stamps)


def parse_ts(value) -> datetime | None:
    if not isinstance(value, str):
        return None
    try:
        return datetime.fromisoformat(value.replace("Z", "+00:00"))
    except ValueError:
        return None
