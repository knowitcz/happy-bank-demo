#!/usr/bin/env bash
# Git branch workflow for /solve: one `issue-<n>` branch per issue, a commit
# per reviewed chunk on it, squash-merge onto main at ship time.
#
# Every git verb this flow needs lives here rather than inline in solve.md:
# /solve runs unattended, and each raw verb (fetch, branch, push, merge) would
# otherwise raise its own permission prompt. One script, one allow-list entry --
# the same reason issue.sh exists. It also owns the commit-subject
# contract (chunk / fix / rebase fix / WIP blocked), so a resuming run can tell reviewed work
# from WIP. See ../references/branching.md and branch-exits.md for the contract.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/git.sh
. "$SCRIPT_DIR/lib/git.sh"
# shellcheck source=lib/sync.sh
. "$SCRIPT_DIR/lib/sync.sh"
# shellcheck source=lib/start.sh
. "$SCRIPT_DIR/lib/start.sh"

usage() {
  cat >&2 <<'EOF'
usage: branch.sh <command> [args]
  preflight              Run the full suite on REMOTE/MAIN: "preflight: green|red"
  start <n> [--resume | --base <sha> | --adopt <sha>]
                         Claim issue-<n> off main (or the preflight sha), resume
                         it, or adopt a human-prepared branch at the recorded sha
  chunk <n> <k> <total> <file>   Commit a reviewed chunk: [#n] chunk <k>/<total>:
  fix <n> <file>         Commit a post-review fix: [#n] fix:
  rebase-fix <n> <file>  Commit a fix after a Sync rebase: [#n] rebase fix:
  wip <n> <file>         Commit work an escape interrupted: [#n] WIP blocked:
  escape <n>             Push issue-<n>, return to main; print its branch+sha line
  ship <n> <file>        Push issue-<n>, squash onto main, commit, push main
  log <n>                issue-<n>'s tip sha(s) and commits; "branch: none" if none
  where                  Print the current branch
Sync with main (/solve, before ship -- lib/sync.sh):
  behind <n>             Fetch; how far REMOTE/MAIN moved, its issues, file overlap
  rebase <n>             Rebase issue-<n> onto REMOTE/MAIN; exit 2 = stopped on conflict
  rebase-continue <n>    Stage the resolution and continue; refuses while markers remain
  rebase-abort <n>       Abort an in-progress rebase, restoring the branch
  bisect <n>             First commit turning the suite red (a hint, not proof)
  publish <n>            Push issue-<n>, --force-with-lease only if it was rebased
  retire <n>             Rename issue-<n> to issue-<n>-stale-<date>, push, drop the old name

<file> is a commit-message file: first non-blank line is the summary, rest is
the body. The script composes every subject prefix -- never write one yourself.
Messages go via a file because inline -m corrupts backticks and $ (CLAUDE.md).
Full contract: ../references/branching.md and branch-exits.md.
EOF
  exit 1
}

cmd="${1:-}"
[ -n "$cmd" ] || usage
require_repo

case "$cmd" in

  start)
    shift
    start_cmd "$@"
    ;;

  chunk)
    require_num "${2:-}"
    n="$2"
    k="${3:-}"
    total="${4:-}"
    file="${5:-}"
    [ -n "$k" ] && [ -n "$total" ] && [ -n "$file" ] || usage
    require_file "$file"
    require_on "issue-$n"
    commit_with_prefix "[#$n] chunk $k/$total: " "$file"
    ;;

  fix | wip | rebase-fix)
    require_num "${2:-}"
    n="$2"
    file="${3:-}"
    [ -n "$file" ] || usage
    require_file "$file"
    require_on "issue-$n"
    case "$cmd" in
      fix) prefix="[#$n] fix: " ;;
      rebase-fix) prefix="[#$n] rebase fix: " ;;
      *) prefix="[#$n] WIP blocked: " ;;
    esac
    commit_with_prefix "$prefix" "$file"
    ;;

  escape)
    require_num "${2:-}"
    n="$2"
    branch="issue-$n"
    [ "$(current_branch)" = "$branch" ] || die "not on $branch (on $(current_branch)) -- nothing to escape from"
    # Same guard as start/ship: the checkout back to main below would otherwise
    # carry surviving edits onto main. If the caller misjudged "nothing is
    # uncommitted", 'wip <n>' is the fix -- never a silent ride-along.
    [ -z "$(git status --porcelain)" ] ||
      die "uncommitted changes on $branch -- run 'wip $n <file>' first, then escape:
$(git status --short)"
    sha="$(git log -1 --pretty=%h)"
    rebase_in_progress && die "a rebase is in progress on $branch -- run 'rebase-abort $n' first"
    # push_branch force-pushes (with lease) only a branch a Sync rebase
    # rewrote; a plain push there would be rejected and strand the resume.
    if push_branch "$branch"; then
      echo "**Branch:** \`$branch\` @ \`$sha\` (pushed to $REMOTE)"
    else
      echo "**Branch:** \`$branch\` @ \`$sha\` (NOT pushed -- local only)"
    fi
    # Leave no flow parked on an issue-* branch: the next run must start from
    # main, or its own 'start' would misread the state it is in.
    git checkout -q "$MAIN"
    echo "returned to $MAIN"
    ;;

  ship)
    require_num "${2:-}"
    n="$2"
    file="${3:-}"
    branch="issue-$n"
    [ -n "$file" ] || usage
    require_file "$file"
    require_clean
    local_exists "$branch" || die "branch $branch does not exist -- nothing to ship"
    fetch_remote
    # Sync guard (#196): the branch must already sit on REMOTE/MAIN, so the
    # squash below ships exactly what the Sync step tested. Exit 3 is not a
    # block: /solve routes it back into Sync (main moved again meanwhile).
    git merge-base --is-ancestor "$REMOTE/$MAIN" "$branch" || {
      echo "branch.sh: not-synced -- $REMOTE/$MAIN has commits $branch lacks; run the Sync step" >&2
      exit 3
    }

    # Push the branch BEFORE squashing onto main. A squash leaves the branch's
    # own commits off main's ancestry, so the push is the only thing that makes
    # them survive -- which the issue asks for. The branch is never deleted.
    git checkout -q "$branch"
    sha="$(git log -1 --pretty=%h)"
    # The branch line ends up in a blocker body, telling a human where to look.
    # It must state what is actually true, so it is composed from the push's
    # real outcome -- never assumed, the same way 'escape' does it.
    if push_branch "$branch"; then
      pushed_note="pushed to $REMOTE"
    else
      echo "warning: could not push $branch to $REMOTE -- its per-chunk history stays local only" >&2
      pushed_note="NOT pushed -- local only"
    fi
    branch_line="**Branch:** \`$branch\` @ \`$sha\` ($pushed_note)"

    git checkout -q "$MAIN"
    # Local main carrying commits REMOTE/MAIN lacks means someone committed
    # straight to this clone's main. Squashing on top would publish it as part
    # of this issue. Refuse; automatic recovery is forbidden here as in ship.md.
    # The branch line comes first so the resulting blocker can carry it.
    git merge-base --is-ancestor "$MAIN" "$REMOTE/$MAIN" || die "$branch_line
local $MAIN has diverged from $REMOTE/$MAIN:
$(git log --oneline "$REMOTE/$MAIN..$MAIN")
Refusing to squash onto it. $branch is intact and pushed; a human reconciles $MAIN."

    # Local main is now provably an ancestor of REMOTE/MAIN, so this can only
    # fast-forward -- it never merges and never creates a merge commit. It is
    # required, not cosmetic: the branch was cut from REMOTE/MAIN, so squashing
    # onto a *behind* main would fold REMOTE/MAIN's intervening commits into
    # this issue's commit and then be rejected as non-fast-forward anyway.
    git merge --ff-only "$REMOTE/$MAIN" >/dev/null

    # The other permitted merge form: --squash stages the branch's net change
    # without recording a merge commit, so history stays linear.
    if ! git merge --squash "$branch" >/dev/null; then
      # Name the files before wiping the index -- the blocker this produces is
      # all the human gets, and the flow may not run git itself to find out.
      conflicts="$(git diff --name-only --diff-filter=U | tr '\n' ' ')"
      # Leave no conflicted index behind: the next run's clean-tree guard would
      # refuse everything, with main half-merged and nothing saying why.
      # --squash writes no MERGE_HEAD, so 'abort' is a no-op net, not the
      # cleanup -- the reset is, safe because require_clean ran above.
      git merge --abort 2>/dev/null || true
      git reset -q --hard HEAD
      die "$branch_line
squash of $branch onto $MAIN conflicts in: ${conflicts:-<none reported>}
$MAIN moved under this issue's work. Nothing was committed and $MAIN is
untouched. $branch is intact and pushed; a human resolves the conflict."
    fi
    commit_with_prefix "[#$n]: " "$file"
    ship_sha="$(git rev-parse --short HEAD)"
    if git push -q "$REMOTE" "$MAIN"; then
      echo "Pushed: $ship_sha"
    else
      echo "NOT pushed: git push was rejected -- recover with: git pull --rebase $REMOTE $MAIN && git push $REMOTE $MAIN"
    fi
    echo "branch $branch kept ($pushed_note); on $MAIN"
    ;;

  log)
    # Exits zero whether or not the branch exists: this is also how a flow asks
    # "is there a branch for this issue?" when the issue's own signals cannot be
    # trusted -- e.g. after a block that fired before any branch was created.
    # The fetch is best-effort: a stale remote ref only risks a recorded sha
    # that `start --adopt` later refuses, never a wrong adoption.
    require_num "${2:-}"
    git fetch --quiet "$REMOTE" 2>/dev/null || true
    n="$2"
    branch="issue-$n"
    if local_exists "$branch"; then
      ref="$branch"
    elif remote_exists "$branch"; then
      ref="$REMOTE/$branch"
    else
      echo "branch: none -- $branch exists neither locally nor on $REMOTE"
      exit 0
    fi
    echo "branch: $ref"
    # Full shas, for /refine's Builds-on line: `start --adopt` compares it to
    # every tip, so a short or local-only one would only end in a refusal.
    echo "tip: $(git rev-parse "$ref")"
    if local_exists "$branch" && remote_exists "$branch" &&
      [ "$(git rev-parse "$branch")" != "$(git rev-parse "$REMOTE/$branch")" ]; then
      echo "origin-tip: $(git rev-parse "$REMOTE/$branch")"
    fi
    git log --oneline --no-decorate "$REMOTE/$MAIN..$ref"
    ;;

  where)
    current_branch
    ;;

  preflight)
    preflight
    ;;

  behind | rebase | rebase-continue | rebase-abort | bisect | publish | retire)
    require_num "${2:-}"
    fn="sync_${cmd//-/_}"
    [ "$cmd" = rebase-continue ] && fn=sync_continue
    [ "$cmd" = rebase-abort ] && fn=sync_abort
    "$fn" "issue-$2"
    ;;

  *) usage ;;
esac
