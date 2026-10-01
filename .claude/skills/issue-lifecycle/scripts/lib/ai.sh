#!/usr/bin/env bash
# The process-ai concurrency guard: ai-labeled issues skip stage:* entirely,
# so they need their own transient in-progress marker rather than a stage
# transition. Moved out of issue.sh to keep it inside its line budget when
# `depend` (#52) was added. Sourced by issue.sh; mutates only the
# 'ai-in-progress' label.

run_ai_start() {
  n="${1:?issue number}"
  IFS='|' read -r ai prog <<<"$(gh issue view "$n" --json labels --jq '
    [.labels[].name] as $L
    | ($L | index("ai") != null) as $ai
    | ($L | index("ai-in-progress") != null) as $prog
    | "\($ai)|\($prog)"
  ')"
  [ "$ai" = "true" ] || { echo "issue #$n is not labeled 'ai'" >&2; exit 1; }
  [ "$prog" = "false" ] || {
    echo "issue #$n already has 'ai-in-progress' -- another session may be active," >&2
    echo "or a prior run died mid-phase; 'issue.sh ai-finish $n' clears it" >&2
    exit 1
  }
  gh issue edit "$n" --add-label "ai-in-progress" >/dev/null
  echo "issue #$n -> ai-in-progress"
}

run_ai_finish() {
  n="${1:?issue number}"
  prog="$(gh issue view "$n" --json labels --jq '[.labels[].name] | index("ai-in-progress") != null')"
  [ "$prog" = "true" ] || { echo "issue #$n has no 'ai-in-progress' label" >&2; exit 1; }
  gh issue edit "$n" --remove-label "ai-in-progress" >/dev/null
  echo "issue #$n -> ai-in-progress cleared"
}
