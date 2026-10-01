# Shared helpers for branch.sh and lib/sync.sh, plus the start-time
# `preflight` command body. Sourced, never executed. Split out of branch.sh
# when the Sync-with-main subcommands (#196) pushed it past the 300-line
# script cap; every caller sees the same guards.

# Single declaration point for the remote and base branch: every fetch, push,
# remote ref and merge-base in these scripts derives from these two.
REMOTE=happy-bank-demo
MAIN=demo

die() { echo "branch.sh: $*" >&2; exit 1; }

require_repo() {
  git rev-parse --git-dir >/dev/null 2>&1 || die "not a git repository"
}

require_num() {
  case "${1:-}" in
    '' | *[!0-9]*) die "issue number must be numeric, got '${1:-}'" ;;
  esac
}

require_file() {
  [ -f "$1" ] || die "message file not found: $1"
  [ -n "$(awk 'NF {print; exit}' "$1")" ] || die "message file is empty: $1"
}

# A dirty tree at a checkout boundary is someone else's uncommitted work (or a
# crashed run's). Switching branches under it would silently carry it across,
# which is #88's failure mode -- refuse instead of guessing whose it is.
require_clean() {
  [ -z "$(git status --porcelain)" ] ||
    die "working tree is dirty -- commit or stash before switching branches:
$(git status --short)"
}

require_on() {
  [ "$(current_branch)" = "$1" ] || die "not on $1 (on $(current_branch)) -- run 'start ${1#issue-}' first"
}

fetch_remote() {
  git fetch --quiet "$REMOTE" || die "git fetch $REMOTE failed -- cannot establish the branch base"
}

local_exists() { git rev-parse --verify --quiet "refs/heads/$1" >/dev/null; }
remote_exists() { git rev-parse --verify --quiet "refs/remotes/$REMOTE/$1" >/dev/null; }

current_branch() { git rev-parse --abbrev-ref HEAD; }

git_dir() { git rev-parse --git-dir; }

rebase_in_progress() {
  [ -d "$(git_dir)/rebase-merge" ] || [ -d "$(git_dir)/rebase-apply" ]
}

# Publish an issue branch. A plain push when the remote copy is an ancestor (the
# normal case); --force-with-lease only when a Sync rebase rewrote the branch
# (#196). Force is scoped to issue-* branches -- main is never force-pushed.
# The lease names the remote's last-fetched sha, so a push someone else made since
# is refused rather than destroyed. Returns the push's exit status.
push_branch() {
  local branch="$1"
  case "$branch" in issue-*) ;; *) die "push_branch refuses non-issue branch '$branch'" ;; esac
  if ! remote_exists "$branch" ||
    git merge-base --is-ancestor "refs/remotes/$REMOTE/$branch" "refs/heads/$branch"; then
    git push -q -u "$REMOTE" "$branch"
  else
    git push -q -u --force-with-lease="$branch:$(git rev-parse "refs/remotes/$REMOTE/$branch")" \
      "$REMOTE" "$branch"
  fi
}

# Compose "<prefix><summary>" + the file's remaining lines as the body, then
# commit. Everything staged with -A: .tmp/ and the session scratchpad are both
# outside what git tracks here, so there is nothing stray to pick up.
commit_with_prefix() {
  local prefix="$1" file="$2" msg
  msg="$(mktemp)"
  awk -v p="$prefix" '
    !done && NF { print p $0; done = 1; next }
    done { print }
  ' "$file" >"$msg"
  git add -A
  if [ -z "$(git diff --cached --name-only)" ]; then
    rm -f "$msg"
    die "nothing to commit -- the step that should have produced changes did not"
  fi
  git commit -q -F "$msg"
  rm -f "$msg"
  echo "committed: $(git log -1 --pretty=%h) $(git log -1 --pretty=%s)"
}

# /solve's start-time check (#52): is REMOTE/MAIN -- the tip `start` forks
# from -- green? Runs the full suite there detached, then returns to where it
# was. Red is an answer, not a failure: both verdicts exit 0, only refusals
# die. One red run is the verdict by design -- the repo must never be red, so
# a flaky failure is a real defect to track, never something to retry away.
preflight() {
  local back sha out rc=0
  require_clean
  fetch_remote
  back="$(current_branch)"
  [ "$back" != HEAD ] || back="$(git rev-parse HEAD)"
  sha="$(git rev-parse --short "$REMOTE/$MAIN")"
  out="$(mktemp)"
  git checkout -q --detach "$REMOTE/$MAIN"
  uv run pytest -q -rfE >"$out" 2>&1 || rc=$?
  # A suite that writes tracked (or unignored) files would make the checkout
  # back carry them, or fail. Refuse loudly instead of discarding someone's changes -- this
  # routes to the same escape `start` row as the other refusals.
  [ -z "$(git status --porcelain)" ] || { rm -f "$out"; die "the suite left the tree dirty on $REMOTE/$MAIN -- still detached there; a human cleans it and runs 'git checkout $back':
$(git status --short)"; }
  git checkout -q "$back"
  if [ "$rc" -eq 0 ]; then
    printf 'preflight: green\nsha: %s\n' "$sha"
  else
    printf 'preflight: red\nsha: %s\nfailed:\n' "$sha"
    grep -E '^(FAILED|ERROR) ' "$out" | sed 's/^/  /' ||
      echo "  UNPARSED pytest-exit-$rc"
    echo "summary: $(tail -n 1 "$out")"
  fi
  rm -f "$out"
}
