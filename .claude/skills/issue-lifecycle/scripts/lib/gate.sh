#!/usr/bin/env bash
# Gate signal computation: the blocker-state predicates and the full `gate`
# command body. This is a third seam alongside issue.sh (stage mutation) and
# compose.sh (text/marker composition) -- it only ever reads and prints,
# never mutates a label or posts text, so it belongs in neither of those.
# Sourced by issue.sh, after compose.sh (uses $JQ_MARKER_DEFS, $BLOCK_MARK,
# $UNBLOCK_MARK from it).

# True when at least one comment carries a structurally-valid block
# trailer, regardless of whether it was since resolved. Used by `unblock`
# -- it may still post its structured acknowledgment even after a bare
# human reply already resolved the block.
block_marker_exists() {
  gh issue view "$1" --json comments --jq "
    $JQ_MARKER_DEFS
    [.comments[].body] as \$b
    | ([\$b[] | select(has_trailer(\"$BLOCK_MARK\"))] | length) > 0"
}

# Unresolved when the LATEST block-trailer comment has no comment after it
# that is either the unblock marker or simply not AI-authored (a plain
# human reply resolves a block just as well as the structured path).
# "none" covers both "never blocked" and "blocked, then resolved" -- the
# gate's own refusal only needs that binary; which of the two applies is
# what the `blocked` label (checked separately, in run_gate) is for.
blocker_state() {
  gh issue view "$1" --json comments --jq "
    $JQ_MARKER_DEFS
    [.comments[].body] as \$b
    | (\$b | to_entries) as \$entries
    | ([\$entries[] | select(.value | has_trailer(\"$BLOCK_MARK\")) | .key] | max) as \$i
    | if \$i == null then \"none\"
      else
        ([\$entries[] | select(.key > \$i) | select(
            (.value | has_trailer(\"$UNBLOCK_MARK\")) or (.value | (is_ai_line | not))
          )] | length) as \$resolvers
        | if \$resolvers > 0 then \"none\" else \"unresolved\" end
      end"
}

# Open issues <n> is blocked by, via GitHub's native dependencies (#52), as
# "#12, #34" -- or "none". A closed blocker simply drops out: that is the whole
# resolution path, so no label or comment ever has to be cleared by hand.
open_blockers() {
  gh api graphql -F owner='{owner}' -F repo='{repo}' -F n="$1" -f query='
    query($owner: String!, $repo: String!, $n: Int!) {
      repository(owner: $owner, name: $repo) {
        issue(number: $n) { blockedBy(first: 50) { nodes { number state } } }
      }
    }' --jq '[.data.repository.issue.blockedBy.nodes[]
             | select(.state == "OPEN") | "#\(.number)"]
           | if length == 0 then "none" else join(", ") end'
}

# The branch state the refinement built on (#206): the sha from the latest
# `**Builds on:** issue-<n> @ <sha>` line, or "none". Computed here rather than
# read by eye, because only two authors count: the refinement's own readiness
# stamp, and a human. A blocker quoting the line is neither, and must never
# turn a refusal into an adoption. `**Builds on:** none` is a record too, so a
# later one cancels an earlier sha. A line naming another issue is ignored.
JQ_BUILDS_ON='
def stamp: (nonblank_lines[0] // "") == "### 📐 Refinement — readiness stamp";
def value:
  capture("^\\s*(?:[-*]|[0-9]+\\.)?\\s*\\*\\*Builds on:\\*\\*\\s*(?<v>.*)$").v
  | if test("^`?none\\b"; "i") then "none"
    else (capture("^`?issue-(?<n>[0-9]+)`?\\s*@\\s*`?(?<s>[0-9a-f]{7,40})`?")
          | select(.n == issue_n) | .s) // empty
    end;
[.comments[].body | select(stamp or (is_ai_line | not))
 | [nonblank_lines[] | value] | last // empty] | last // "none"'

builds_on() {
  gh issue view "$1" --json comments \
    --jq "$JQ_MARKER_DEFS def issue_n: \"$1\"; $JQ_BUILDS_ON"
}

# issue.sh's `gate <n> <refine|solve>` command body, kept out of issue.sh to
# stay inside its line budget -- pure signal computation, never a label or
# text mutation. `blocked` is label-based (cheap, one query) and orthogonal
# to `blocker` (comment-log-based, authoritative): a resumed run checks
# `blocked: yes` to know a block preceded this invocation and its reply
# needs mapping against the original questions -- see the /refine command's
# Blocking Protocol section 4, and the /solve command, Step 2.
run_gate() {
  n="${1:?issue number}"; flow="${2:?refine|solve}"
  case "$flow" in refine|solve) ;; *) echo "bad flow: $flow" >&2; exit 1;; esac
  IFS='|' read -r st s apr ai blk_label <<<"$(gh issue view "$n" --json state,labels --jq "
    [.labels[].name] as \$L
    | ((\$L | map(select(startswith(\"stage:\"))) | .[0]) // \"\" | sub(\"^stage:\";\"\")) as \$s
    | (\$L | index(\"approved\") != null) as \$apr
    | (\$L | index(\"ai\") != null) as \$ai
    | (\$L | index(\"blocked\") != null) as \$blk
    | \"\(.state)|\(\$s)|\(\$apr)|\(\$ai)|\(\$blk)\"
  ")"

  # Closed first, before any signal is computed. `issue.sh close` strips the
  # stage label, so a closed issue reaches the `s=fresh` default below and
  # would otherwise print a synthetic `stage: stage:fresh` + `verdict: OK` --
  # that default exists for a genuinely-fresh OPEN issue that lost its label.
  # Closed-ness is therefore read from the issue's own `state` field (free:
  # it rides the labels query above), never inferred from labels. Refuse
  # early and skip the signal lines: on a refusal nothing parses them, and
  # printing a fabricated stage is the defect itself.
  # Anything that is not a confirmed OPEN refuses. CLOSED gets its own reason;
  # an empty $st means the query itself failed (bad number, auth, network) --
  # that already exits non-zero one call later, but only via a raw `gh` error
  # with no `verdict:`/`reason:` pair, which is the contract every flow reads.
  if [ "$st" = "CLOSED" ]; then
    echo "verdict: REFUSE"
    echo "reason: issue #$n is closed; a closed issue is finished and no flow may run against it"
    exit 1
  elif [ "$st" != "OPEN" ]; then
    echo "verdict: REFUSE"
    echo "reason: could not read the state of issue #$n (it may not exist, or the gh query failed); no flow may run on an unverified issue"
    exit 1
  fi

  [ -n "$s" ] || s="fresh"
  if [ "$apr" = "true" ]; then apr=yes; else apr=no; fi
  if [ "$ai" = "true" ]; then ai=yes; else ai=no; fi
  if [ "$blk_label" = "true" ]; then blk_label=yes; else blk_label=no; fi
  blk="$(blocker_state "$n")"
  # Only solve reads dependencies, so only solve pays for (and depends on) the
  # query -- refine keeps working even if it fails. Solve fails closed.
  waiting="n/a"
  bon="n/a"
  if [ "$flow" = solve ]; then
    bon="$(builds_on "$n")" || {
      echo "verdict: REFUSE"
      echo "reason: could not read the Builds-on record of issue #$n; solve may not pick a branch on an unverified record"
      exit 1
    }
    waiting="$(open_blockers "$n")" || {
      echo "verdict: REFUSE"
      echo "reason: could not read the blocked-by dependencies of issue #$n; solve may not run on an unverified issue"
      exit 1
    }
  fi

  refused=""
  if [ "$ai" = "yes" ]; then
    refused="issue is labeled 'ai'; AI-asset changes are processed by their own interactive flow, not /refine or /solve"
  elif [ "$blk" = "unresolved" ]; then
    refused="an unresolved blocker is recorded in the comment log; a human must answer it (a plain reply resolves it, or 'issue.sh unblock' for a structured one) -- clearing the 'blocked' label alone does not"
  elif [ "$flow" = solve ] && [ "$waiting" != none ]; then
    # waiting is "n/a" for refine, so this row only ever fires for solve.
    # Solve only: refining needs no green main, so it may proceed meanwhile.
    refused="issue is blocked by open issue(s) $waiting; it becomes solvable on its own once they close"
  else
    case "$s:$flow" in
      decomposed:*)          refused="issue is a tracking parent; work its sub-issues instead" ;;
      in-refinement:solve)   refused="a refinement run is in progress or crashed; its spec is not trustworthy yet" ;;
      in-implementation:refine)
                              refused="an implementation is in progress against the current spec; finish or block it first" ;;
    esac
  fi

  resume=no
  case "$s:$flow" in in-refinement:refine|in-implementation:solve) resume=yes ;; esac
  refd=no
  case "$s" in refined|in-implementation) refd=yes ;; esac

  echo "stage: stage:$s"
  echo "approved: $apr"
  echo "refined: $refd"
  echo "blocker: $blk"
  echo "blocked: $blk_label"
  echo "waiting: $waiting"
  echo "builds-on: $bon"
  echo "resume: $resume"
  echo "ai: $ai"
  if [ -n "$refused" ]; then
    echo "verdict: REFUSE"
    echo "reason: $refused"
    exit 1
  fi
  echo "verdict: OK"
}
