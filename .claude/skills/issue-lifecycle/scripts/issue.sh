#!/usr/bin/env bash
# Thin gh wrapper enforcing the issue-lifecycle stage contract.
# The stage:* label names the state the issue IS IN, never the next action.
#
# This script is the ONLY writer of issue text. It owns the stage state
# machine; lib/compose.sh owns the heading registry, the AI-author marker and
# the round-trip check, so neither can be forgotten or reworded by a caller.
# See ../references/states.md for the vocabulary, transitions and refusal rules.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/compose.sh
. "$SCRIPT_DIR/lib/compose.sh"
# shellcheck source=lib/gate.sh
. "$SCRIPT_DIR/lib/gate.sh"
# shellcheck source=lib/ai.sh
. "$SCRIPT_DIR/lib/ai.sh"

STAGES=(fresh explored in-refinement refined decomposed in-implementation)
# Superseded stage values -- no flow sets these any more (a single,
# flow-agnostic `blocked` label replaced them; see states.md). Kept only so
# clear_stage() can still strip one off an issue that predates this change,
# rather than leaving two stage:* labels coexisting.
LEGACY_STAGES=(blocked-refinement blocked-implementation)

usage() {
  cat >&2 <<'EOF'
usage: issue.sh <command> [args]
  brief <n>                     Title, state, stage, body, comment log
                                (cost comments omitted -- see comment-formats.md)
  stage <n>                     Print current stage:* label (empty if none)
  gate <n> <refine|solve>       Refuse (exit 1) if the flow may not run; print signals
  set-stage <n> <stage>         Move to a stage from the vocabulary; also clears 'blocked'
  create <title> <file> [gh flags...]
                                Open an issue from a body file (adds stage:fresh)
  comment <n> <key> <file> [suffix]
                                Append a comment under a registered heading
                                key: see comment-formats.md (e.g. exploration, waiting)
  block <n> refinement <file>
                                Post blocker comment + add 'blocked' (stage unchanged --
                                a refinement block always resumes in place)
  block <n> implementation <file> <target-stage>
                                Post blocker comment + add 'blocked' + move to
                                <target-stage> now (refined in Standard Mode, fresh in
                                Trivial Mode -- /solve decides which)
  cost <n> <file> <session-id>  Post a session cost comment, stamped with a
                                per-session idempotency marker (session-cost skill)
  unblock <n> <file>             Post resolution comment + remove 'blocked'
                                (optional -- a bare human reply resolves a block too;
                                stage is already correct from block time)
  set-body <n> <file>           Replace the issue body from a markdown file
  close <n>                     Strip the stage label, then close
  depend <n> <m>                Record that <n> is blocked by open issue <m> (GitHub
                                native dependency; idempotent; the solve gate reads it)
  ai-start <n>                  Add ai-in-progress (refuses if not 'ai' or already in progress)
  ai-finish <n>                 Remove ai-in-progress (refuses if not present)
  list                          List open issues with their stage and parent/sub-issue relations
  init-labels                   Create the canonical label set

Body files carry the body ONLY. The script emits the registered heading and
stamps the AI marker directly beneath it, then verifies the round trip.
EOF
  exit 1
}

require_stage() {
  case " ${STAGES[*]} " in *" $1 "*) ;; *)
    echo "bad stage: $1 (allowed: ${STAGES[*]})" >&2; exit 1;;
  esac
}

current_stage() {
  gh issue view "$1" --json labels \
    --jq '[.labels[].name | select(startswith("stage:"))] | .[0] // "" | sub("^stage:";"")'
}

clear_stage() {
  for st in "${STAGES[@]}" "${LEGACY_STAGES[@]}"; do
    gh issue edit "$1" --remove-label "stage:$st" >/dev/null 2>&1 || true
  done
}

cmd="${1:-}"; shift || usage
case "$cmd" in
  brief)
    n="${1:?issue number}"
    gh issue view "$n" --json number,title,state,labels,body,comments --jq "$JQ_BRIEF"
    ;;

  stage)
    n="${1:?issue number}"
    s="$(current_stage "$n")"; if [ -n "$s" ]; then echo "stage:$s"; fi
    ;;

  gate)
    run_gate "$@"
    ;;

  set-stage)
    n="${1:?issue number}"; s="${2:?stage}"
    require_stage "$s"
    clear_stage "$n"
    gh issue edit "$n" --add-label "stage:$s" >/dev/null
    # Claiming any stage means "acting on the latest information" -- if a
    # block had been resolved (by reply or by 'unblock'), this is the point
    # the flow acts on that resolution, so 'blocked' is stale from here on.
    # A separate call, guarded: unlike an unattached-but-defined label,
    # --remove-label on a name gh doesn't recognize in the repo at all
    # fails the whole command under 'set -euo pipefail' -- a fresh repo
    # (or one mid-migration) may not have run 'init-labels' to define
    # 'blocked' yet.
    gh issue edit "$n" --remove-label "blocked" >/dev/null 2>&1 || true
    echo "issue #$n -> stage:$s"
    ;;

  create)
    t="${1:?title}"; shift
    f="${1:?body file}"; shift
    require_body "$f"
    reject_reserved_flags ${1+"$@"}
    tmp="$(mktemp)"; trap 'rm -f "$tmp"' EXIT
    compose "" "$f" > "$tmp"
    url="$(gh issue create --title "$t" --body-file "$tmp" \
             --label "stage:fresh" ${1+"$@"})"
    verify_posted body "${url##*/}" "$tmp" "$f"
    echo "$url"
    ;;

  comment)
    n="${1:?issue number}"; k="${2:?heading key}"; f="${3:?body file}"; sfx="${4:-}"
    reject_cost_key "$k"
    require_body "$f"
    stripped="$(mktemp)"; tmp="$(mktemp)"; trap 'rm -f "$stripped" "$tmp"' EXIT
    prepare_comment_body "$f" "$stripped"
    h="$(heading_for "$k")"
    if [ -n "$sfx" ]; then h="$h — $sfx"; fi
    compose "$h" "$stripped" > "$tmp"
    gh issue comment "$n" --body-file "$tmp" >/dev/null
    verify_posted comment "$n" "$tmp" "$f"
    gh issue view "$n" --json comments --jq '.comments[-1].url'
    ;;

  block)
    n="${1:?issue number}"; flow="${2:?refinement|implementation}"; f="${3:?body file}"
    case "$flow" in
      refinement)
        [ $# -le 3 ] || { echo "block refinement takes no target-stage arg -- it always resumes in place" >&2; exit 1; } ;;
      implementation)
        ts="${4:?an implementation block needs a target stage: refined (Standard Mode) or fresh (Trivial Mode)}"
        case "$ts" in
          refined|fresh) ;;
          *) echo "implementation block target must be 'refined' (Standard Mode) or 'fresh' (Trivial Mode): $ts" >&2; exit 1;;
        esac ;;
      *) echo "bad flow: $flow" >&2; exit 1;;
    esac
    require_body "$f"
    tmp="$(mktemp)"; trap 'rm -f "$tmp"' EXIT
    compose "### ⛔ Blocked — $flow" "$f" "$BLOCK_MARK" > "$tmp"
    gh issue comment "$n" --body-file "$tmp" >/dev/null
    verify_posted comment "$n" "$tmp" "$f"
    gh issue edit "$n" --add-label "blocked" >/dev/null
    if [ "$flow" = "implementation" ]; then
      # Move now, not at resolution. The stage is not what a resumed solve
      # run reads -- its issue-<n> branch is (see ../references/states.md
      # section 2) -- so the label is free to record where the issue stands
      # for a human. Standing at the mode-appropriate target the whole time
      # the block is open also means no separate stage transition is needed
      # on resolution. Back to fresh = no approvable spec: drop `approved` (#196).
      clear_stage "$n"
      gh issue edit "$n" --add-label "stage:$ts" >/dev/null
      if [ "$ts" = fresh ]; then gh issue edit "$n" --remove-label approved >/dev/null 2>&1 || true; fi
      echo "issue #$n -> stage:$ts +blocked (blocker recorded)"
    else
      echo "issue #$n -> +blocked, stage unchanged (blocker recorded)"
    fi
    ;;

  # Mirrors block/unblock rather than reusing 'comment': the marker is what
  # makes a cost post idempotent, and composing it here keeps this script the
  # sole owner of every marker in the issue text. A caller hand-writing the
  # marker into its body file would move that ownership out of the seam.
  cost)
    n="${1:?issue number}"; f="${2:?body file}"; sid="${3:?session id}"
    case "$sid" in
      *[!A-Za-z0-9._-]*|"") echo "bad session id: $sid" >&2; exit 1;;
    esac
    require_body "$f"
    tmp="$(mktemp)"; trap 'rm -f "$tmp"' EXIT
    compose "$(heading_for cost)" "$f" "$(cost_mark "$sid")" > "$tmp"
    gh issue comment "$n" --body-file "$tmp" >/dev/null
    verify_posted comment "$n" "$tmp" "$f"
    gh issue view "$n" --json comments --jq '.comments[-1].url'
    ;;

  unblock)
    n="${1:?issue number}"; f="${2:?answers file}"
    require_body "$f"
    # A block marker existing is enough -- not "still unresolved": a bare
    # human reply may have already resolved it, and this structured path
    # stays usable regardless. Stage is already correct from block time.
    [ "$(block_marker_exists "$n")" = "true" ] || { echo "issue #$n has no block marker in its comment log" >&2; exit 1; }
    tmp="$(mktemp)"; trap 'rm -f "$tmp"' EXIT
    compose "### ✅ Unblocked" "$f" "$UNBLOCK_MARK" > "$tmp"
    gh issue comment "$n" --body-file "$tmp" >/dev/null
    verify_posted comment "$n" "$tmp" "$f"
    gh issue edit "$n" --remove-label "blocked" >/dev/null
    echo "issue #$n -> blocked cleared (resolution recorded)"
    ;;

  set-body)
    n="${1:?issue number}"; f="${2:?body file}"
    require_body "$f"
    tmp="$(mktemp)"; trap 'rm -f "$tmp"' EXIT
    compose "" "$f" > "$tmp"
    gh issue edit "$n" --body-file "$tmp" >/dev/null
    verify_posted body "$n" "$tmp" "$f"
    echo "issue #$n body updated"
    ;;

  close)
    n="${1:?issue number}"
    clear_stage "$n"
    gh issue close "$n"
    ;;

  # GitHub's native "blocked by" (#52): the dependency itself is the only
  # record of what <n> waits on -- no label mirrors it, so nothing can drift.
  # The REST endpoint wants <m>'s database id, not its number. An edge that
  # already exists is a no-op, so a re-run after a crash is safe.
  depend)
    n="${1:?issue number}"; m="${2:?blocking issue number}"
    [ "$n" != "$m" ] || { echo "issue #$n cannot be blocked by itself" >&2; exit 1; }
    IFS='|' read -r mst mid <<<"$(gh api "repos/{owner}/{repo}/issues/$m" --jq '"\(.state)|\(.id)"')"
    [ "$mst" = "open" ] || { echo "issue #$m is not open -- it cannot block anything" >&2; exit 1; }
    ep="repos/{owner}/{repo}/issues/$n/dependencies/blocked_by"
    if gh api "$ep" --jq '.[].number' | grep -qx "$m"; then
      echo "issue #$n already blocked by #$m"
    else
      gh api -X POST "$ep" -F issue_id="$mid" >/dev/null
      echo "issue #$n -> blocked by #$m"
    fi
    ;;

  ai-start)  run_ai_start "$@" ;;
  ai-finish) run_ai_finish "$@" ;;

  list)
    # Read-only backlog snapshot -- not an issue fetch. parent/subIssues come
    # free from gh's --json (one gh call; jq runs locally after). Only OPEN
    # sub-issues are named; an all-closed child set still gets a marker so it
    # doesn't look childless; a full 200-item page warns instead of hiding items.
    json="$(gh issue list --state open --limit 200 --json number,title,labels,parent,subIssues)"
    echo "$json" | jq -r '
      .[] | "#\(.number)  " +
      ([.labels[].name | select(startswith("stage:"))] | .[0] // "stage:fresh") +
      (if ([.labels[].name] | index("approved")) then " +approved" else "" end) +
      (if ([.labels[].name] | index("blocked")) then " +blocked" else "" end) +
      (if ([.labels[].name] | index("ai")) then " [ai]" else "" end) +
      (if ([.labels[].name] | index("ai-in-progress")) then " [processing]" else "" end) +
      "  \(.title)" +
      ([
        (if (.subIssues.nodes | map(select(.state=="OPEN")) | length) > 0
         then "parent of " + ([.subIssues.nodes[] | select(.state=="OPEN") | "#\(.number)"] | join(", "))
         elif (.subIssues.nodes | length) > 0
         then "parent of — all closed"
         else empty end),
        (if .parent != null then "part of #\(.parent.number)" else empty end)
      ] | if length > 0 then "  (" + join("; ") + ")" else "" end)'
    if [ "$(echo "$json" | jq 'length')" -ge 200 ]; then
      echo "(200-item page limit reached -- backlog may be truncated)"
    fi
    ;;

  init-labels)
    create() { gh label create "$1" --color "$2" --description "$3" --force >/dev/null && echo "label: $1"; }
    create "stage:fresh"                  1d76db "Filed; not yet refined"
    create "stage:explored"               1d76db "Explored; ready for refinement"
    create "stage:in-refinement"          fef2c0 "Refinement in progress"
    create "stage:refined"                0e8a16 "Refined; awaiting human approval"
    create "stage:decomposed"             5319e7 "Split into sub-issues; tracking only"
    create "stage:in-implementation"      fef2c0 "Implementation in progress"
    create "approved"                     fbca04 "Human-approved; ready to implement"
    create "blocked"                      b60205 "A human decision is required; see the ⛔ Blocked comment"
    create "ai"                           7057ff "AI assets: skills, agents, commands, prompts"
    create "ai-in-progress"               fef2c0 "AI-asset processing in progress (process-ai concurrency guard)"
    # Superseded by the single 'blocked' label above -- delete rather than
    # leave stale definitions around. No open or closed issue carried either
    # at the time of this change (verified via 'gh issue list --state all').
    gh label delete "stage:blocked-refinement" --yes >/dev/null 2>&1 || true
    gh label delete "stage:blocked-implementation" --yes >/dev/null 2>&1 || true
    ;;

  *) usage ;;
esac
