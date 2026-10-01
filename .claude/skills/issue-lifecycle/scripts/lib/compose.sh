#!/usr/bin/env bash
# Issue-text composition and verification. Sourced by issue.sh.
#
# This half owns what the posted text LOOKS like: the AI-author marker, the
# heading registry, and the round-trip check. The stage state machine lives
# in issue.sh. See ../../references/comment-formats.md for the registry.

BLOCK_MARK='<!-- issue-lifecycle:blocked -->'
UNBLOCK_MARK='<!-- issue-lifecycle:unblocked -->'
AI_MARK='🤖'

# Per-session idempotency marker for cost comments. Unlike the two above it is
# parameterized: several cost comments legitimately coexist on one issue (a
# refine session, then a solve session), so the guard has to identify the
# session, not just the comment kind.
COST_MARK_PREFIX='<!-- issue-lifecycle:cost:'
cost_mark() { printf '%s%s -->' "$COST_MARK_PREFIX" "$1"; }

# 'cost' is in the heading registry so issue.sh's own 'cost' dispatch can look
# it up -- but that also makes it reachable via 'comment', which stamps no
# marker and would post a cost comment both idempotency guards are blind to.
# The registry is this file's, so the refusal belongs here too.
reject_cost_key() {
  [ "$1" != cost ] || {
    echo "key 'cost' is not postable via 'comment'" >&2
    echo "use: issue.sh cost <n> <file> <session-id> -- it stamps the per-session marker" >&2
    exit 1
  }
}

# jq function library for structural marker detection, shared by
# lib/gate.sh's blocker-state predicates. Exact line-position matching, not
# substring search -- a GitHub quote-reply blockquotes every line with
# "> ", which breaks exact equality but would still satisfy a naive
# contains(). Per compose() below: the AI marker is the line directly
# below the heading (or the very first line, when there is no heading --
# an issue body); BLOCK_MARK/UNBLOCK_MARK are a trailing line after the
# body, not directly below the heading.
JQ_MARKER_DEFS='
def nonblank_lines:
  split("\n") | map(gsub("\r$";"") | gsub("[ \t]+$";"")) | map(select(test("\\S")));
def is_ai_line:
  nonblank_lines as $nb | ($nb[0] // "") == "🤖" or ($nb[1] // "") == "🤖";
def has_trailer($mark):
  nonblank_lines as $nb | ($nb[-1] // "") == $mark;
def is_cost_record:
  nonblank_lines as $nb
  | (($nb[-1] // "") | startswith("<!-- issue-lifecycle:cost:"));
'

# How 'brief' renders an issue. Lives here rather than in issue.sh's dispatch
# because it is presentation, this file's half of the split -- and because it
# outgrew being readable inline once cost comments had to be filtered out.
#
# Cost comments are analysis records, not decision log: each carries a fixed
# JSON block, and a flow re-reading an issue has no use for it, so recording a
# run's cost must not inflate the context of the next one. They are matched as
# a trailing line via is_cost_record, never by substring -- a comment that
# merely *discusses* the marker (a design write-up does) has to stay in the
# log. Measured: a naive contains() dropped #83's own refinement comment.
JQ_BRIEF="$JQ_MARKER_DEFS"'
(.comments | map(select(.body | is_cost_record | not))) as $log |
"#\(.number) [\(.state)] \(.title)\n" +
"Labels: " + ([.labels[].name] | join(", ") // "(none)") + "\n\n" +
"=== BODY ===\n" + (.body // "(empty)") + "\n\n" +
"=== COMMENTS (" + ($log | length | tostring) +
  (((.comments | length) - ($log | length)) as $c |
   if $c > 0 then " + \($c) cost, omitted" else "" end) + ") ===\n" +
([$log[] | "--- @\(.author.login) @ \(.createdAt) ---\n\(.body)"]
 | join("\n\n") // "(none)")'

# Fixed headings. This function and the registry table in
# ../../references/comment-formats.md must be changed together.
heading_for() {
  case "$1" in
    exploration)    printf '### 🔍 Exploration' ;;
    refinement)     printf '### 📐 Refinement' ;;
    implementation) printf '### 🛠 Implementation' ;;
    difficulty)     printf '### ⚠️ Difficulty Note' ;;
    observed)       printf '### 🔁 Observed Again' ;;
    rebase)         printf '### 🔀 Rebase Note' ;;
    waiting)        printf '### ⏸ Waiting' ;;
    cost)           printf '### 💰 Cost' ;;
    *) echo "bad heading key: $1 (allowed: exploration refinement implementation difficulty observed rebase waiting cost)" >&2
       exit 1 ;;
  esac
}

# AI-authored text carries the marker directly below its header. For a comment
# that header is the heading; an issue body has none, so the marker leads.
# A caller-typed marker is stripped first, so stamping is idempotent: authors
# copy it from earlier bodies, and verify_posted can't see the duplicate
# (#199). The stripped body goes through a temp file, not $(...), so the
# marker-only refusal exits the calling script instead of a subshell.
compose() {
  local heading="$1" body="$2" trailer="${3:-}" clean
  clean="$(mktemp)"
  strip_leading_marker "$body" > "$clean"
  grep -q '[^[:space:]]' "$clean" || {
    rm -f "$clean"
    echo "body holds only the $AI_MARK marker, no content: $body" >&2
    exit 1
  }
  if [ -n "$heading" ]; then printf '%s\n\n' "$heading"; fi
  printf '%s\n\n' "$AI_MARK"
  cat "$clean"; rm -f "$clean"
  if [ -n "$trailer" ]; then printf '\n%s\n' "$trailer"; fi
}

# Drops leading lines that hold only the marker, plus the blank lines around
# them. Leading blanks with no marker after them are kept as-is. A marker
# further down is content (a write-up may discuss it), so it is kept.
strip_leading_marker() {
  awk -v m="$AI_MARK" '
    !done {
      t = $0; gsub(/^[ \t\r]+|[ \t\r]+$/, "", t)
      if (t == m) { hit = 1; buf = ""; next }
      if (t == "") { if (!hit) buf = buf $0 "\n"; next }
      done = 1; printf "%s", buf
    }
    { print }
    END {
      if (hit) print "note: leading " m " marker stripped -- issue.sh stamps it itself" > "/dev/stderr"
    }' "$1"
}

# A body of nothing but whitespace would post a marker with no content.
require_body() {
  [ -s "$1" ] || { echo "body file is empty: $1" >&2; exit 1; }
  grep -q '[^[:space:]]' "$1" || {
    echo "body file holds only whitespace: $1" >&2; exit 1
  }
}

# Comments take their heading from the registry, never from the caller's
# file. issue.sh always emits the registered heading itself, so a
# caller-supplied one is redundant, not harmful -- it is stripped rather
# than rejected, so a minor formatting slip doesn't force a whole re-run.
# Checked on the first non-blank line only, and only for a real markdown
# heading -- a body legitimately opening with "#42 relates to..." is not
# one. Writes the (possibly unmodified) body to stdout; prints a note to
# stderr when it actually strips something, so the caller still notices.
# Precondition: $f has already passed require_body (at least one
# non-blank line) -- callers must run that first, this does not re-check.
strip_leading_heading() {
  local f="$1" n first
  n="$(grep -n -m1 '[^[:space:]]' "$f" | cut -d: -f1 || true)"
  [ -n "$n" ] || {
    echo "internal error: strip_leading_heading needs require_body run first: $f" >&2
    exit 1
  }
  first="$(sed -n "${n}p" "$f")"
  if [[ "$first" =~ ^#{1,6}[[:space:]] ]]; then
    echo "note: leading heading stripped from $f -- issue.sh emits the registered heading itself" >&2
    tail -n "+$((n + 1))" "$f" | sed '/[^[:space:]]/,$!d'
  else
    cat "$f"
  fi
}

# A stripped body that was nothing but a heading has no content left to
# post -- that is a genuinely empty comment, not a minor slip, so this
# still refuses rather than silently posting a heading-only body.
prepare_comment_body() {
  local f="$1" out="$2"
  strip_leading_heading "$f" > "$out"
  grep -q '[^[:space:]]' "$out" || {
    echo "comment body was only a heading with no content: $f" >&2
    exit 1
  }
}

# Passing a body or a stage label directly would bypass compose() and post
# unmarked, unverified, or wrongly staged text -- the whole point of the seam.
reject_reserved_flags() {
  local a
  for a in ${1+"$@"}; do
    case "$a" in
      --body|--body-file|-b|-F)
        echo "flag not allowed: $a" >&2
        echo "the body comes from the body-file argument, so it is marked and verified" >&2
        exit 1 ;;
      stage:*)
        echo "label not allowed: $a -- 'create' applies stage:fresh itself" >&2
        exit 1 ;;
      approved)
        echo "label not allowed: 'approved' is the human's alone" >&2
        exit 1 ;;
    esac
  done
}

# Strip CR and per-line trailing whitespace: GitHub may normalize either.
norm_text() { tr -d '\r' | sed 's/[[:space:]]*$//'; }

# Re-read what GitHub stored and compare it with what we sent. Catches shell
# escaping that leaked into the text and silent truncation. The composed temp
# file is gone by the time a caller reads this, so name the caller's source.
verify_posted() {
  local kind="$1" n="$2" sent="$3" src="$4" got
  case "$kind" in
    comment) got="$(gh issue view "$n" --json comments --jq '.comments[-1].body')" ;;
    body)    got="$(gh issue view "$n" --json body --jq '.body')" ;;
  esac
  if [ "$(norm_text < "$sent")" != "$(printf '%s\n' "$got" | norm_text)" ]; then
    echo "round-trip check FAILED for issue #$n ($kind)" >&2
    echo "the posted text differs from what was sent" >&2
    echo "correct this file and re-post: $src" >&2
    exit 1
  fi
}
