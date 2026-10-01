# Sync-with-main subcommands for branch.sh (#196): bring issue-<n> onto the
# current REMOTE/MAIN before ship squashes it. Sourced, never executed; needs
# lib/git.sh. /solve's "Sync with main" step owns the judgement (staleness,
# intent conflict, who fixes what) -- this file owns only the git mechanics,
# for the same one-allow-list-entry reason as the rest of branch.sh.
#
# Exit codes: 0 done, 1 refused (die), 2 rebase stopped on a conflict and is
# left in progress for the flow to resolve.

EXIT_CONFLICT=2

# What the flow needs to judge distance and intent before rebasing: how far
# REMOTE/MAIN moved since the branch base, which issues those commits belong
# to, and whether their files overlap ours. Read-only apart from the fetch.
sync_behind() {
  local branch="$1" base count
  local_exists "$branch" || die "branch $branch does not exist"
  fetch_remote
  base="$(git merge-base "$branch" "$REMOTE/$MAIN")"
  count="$(git rev-list --count "$base..$REMOTE/$MAIN")"
  echo "behind: $count"
  echo "base: $(git log -1 --pretty='%h %cs' "$base")"
  [ "$count" -gt 0 ] || return 0
  echo "new commits:"
  git log --oneline --no-decorate "$base..$REMOTE/$MAIN" | sed 's/^/  /'
  echo "issues: $(git log --pretty=%s "$base..$REMOTE/$MAIN" |
    grep -o '^\[#[0-9]*\]' | tr -d '[]' | sort -u | tr '\n' ' ')"
  git diff --name-only "$base" "$REMOTE/$MAIN" | sort >"$(git_dir)/sync-theirs"
  git diff --name-only "$base" "$branch" | sort >"$(git_dir)/sync-ours"
  echo "overlap:"
  comm -12 "$(git_dir)/sync-theirs" "$(git_dir)/sync-ours" | sed 's/^/  /'
  rm -f "$(git_dir)/sync-theirs" "$(git_dir)/sync-ours"
}

# Shared by rebase and rebase-continue: either the rebase finished, or it
# stopped on a commit whose conflicts the flow must resolve.
report_rebase_state() {
  local branch="$1"
  if rebase_in_progress; then
    echo "rebase: conflict"
    echo "commit: $(git log -1 --pretty='%h %s' REBASE_HEAD 2>/dev/null || echo '<unknown>')"
    echo "files:"
    git diff --name-only --diff-filter=U | sed 's/^/  /'
    exit "$EXIT_CONFLICT"
  fi
  # Not in progress and not on REMOTE/MAIN means git refused outright (not a
  # conflict) -- never report that as done.
  git merge-base --is-ancestor "$REMOTE/$MAIN" HEAD ||
    die "rebase of $branch failed without leaving a conflict -- $branch is unchanged"
  echo "rebase: done -- $branch now on $REMOTE/$MAIN @ $(git rev-parse --short "$REMOTE/$MAIN")"
  echo "next: publish, before anything else can escape -- $REMOTE still holds the pre-rebase branch"
}

sync_rebase() {
  local branch="$1"
  require_on "$branch"
  require_clean
  rebase_in_progress && die "a rebase is already in progress -- rebase-continue or rebase-abort"
  fetch_remote
  # GIT_EDITOR=true: nothing may wait on an editor in an unattended run.
  GIT_EDITOR=true git rebase -q "$REMOTE/$MAIN" >/dev/null 2>&1 || true
  report_rebase_state "$branch"
}

# The implementor edits the conflicted files; it cannot stage them. This stages
# and continues -- but only once no conflict marker survives, so a half-done
# resolution can never be folded into the replayed commit.
sync_continue() {
  local branch="$1" files left
  rebase_in_progress || die "no rebase in progress for $branch"
  files="$(git diff --name-only --diff-filter=U)"
  if [ -n "$files" ]; then
    # shellcheck disable=SC2086
    left="$(grep -l -E '^(<<<<<<<|>>>>>>>)( |$)' $files 2>/dev/null || true)"
    [ -z "$left" ] || die "conflict markers remain in: $(echo "$left" | tr '\n' ' ')"
  fi
  git add -A
  GIT_EDITOR=true git rebase --continue >/dev/null 2>&1 || true
  report_rebase_state "$branch"
}

sync_abort() {
  local branch="$1"
  rebase_in_progress || { echo "rebase: none in progress"; return 0; }
  git rebase --abort
  echo "rebase: aborted -- $branch restored @ $(git rev-parse --short HEAD)"
}

# Bisect the rebased branch for the first commit that turns the suite red. A
# HINT, not proof: chunk commits were only ever targeted-test green, so a
# mid-branch commit may fail on its own. pytest exit >=2 (collection/usage
# errors) is "skip", not "bad" -- it says nothing about the regression.
sync_bisect() {
  local branch="$1" base out first
  require_on "$branch"
  require_clean
  rebase_in_progress && die "a rebase is in progress -- finish it before bisecting"
  base="$(git merge-base HEAD "$REMOTE/$MAIN")"
  git checkout -q --detach "$base"
  if ! uv run pytest -q -x >/dev/null 2>&1; then
    git checkout -q "$branch"
    echo "first-bad: base-red -- $REMOTE/$MAIN itself fails; not this branch's doing"
    return 0
  fi
  git checkout -q "$branch"
  git bisect start "$branch" "$base" >/dev/null
  out="$(git bisect run sh -c 'uv run pytest -q -x >/dev/null 2>&1; c=$?
    [ "$c" -le 1 ] && exit "$c"; exit 125' 2>&1 || true)"
  first="$(echo "$out" | awk '/is the first bad commit/ {print $1; exit}')"
  git bisect reset -q >/dev/null 2>&1 || true
  git checkout -q "$branch"
  if [ -n "$first" ]; then
    echo "first-bad: $(git log -1 --pretty='%h %s' "$first")"
    echo "files:"
    git diff-tree --no-commit-id --name-only -r "$first" | sed 's/^/  /'
  else
    echo "first-bad: inconclusive -- hand the whole rebased diff to the owners"
  fi
}

# Publish the rebased branch. No fetch here: the lease is the remote's sha as last
# fetched by 'rebase', so a push someone made since then is refused, not lost.
sync_publish() {
  local branch="$1" sha
  require_on "$branch"
  require_clean
  rebase_in_progress && die "a rebase is in progress -- finish or abort it first"
  sha="$(git rev-parse --short HEAD)"
  if push_branch "$branch"; then
    echo "**Branch:** \`$branch\` @ \`$sha\` (pushed to $REMOTE)"
  else
    echo "**Branch:** \`$branch\` @ \`$sha\` (NOT pushed -- local only)"
  fi
}

# Stale path: the issue goes back to /refine, and the next /solve makes a fresh
# 'start', which refuses an existing issue-<n>. Rename rather than delete --
# branches are never deleted (#148) -- and push the new name before dropping
# the old one from the remote, so no push failure can lose the history.
sync_retire() {
  local branch="$1" stale
  local_exists "$branch" || die "branch $branch does not exist -- nothing to retire"
  rebase_in_progress && die "a rebase is in progress -- rebase-abort first"
  require_clean
  stale="$branch-stale-$(date +%Y%m%d-%H%M)"
  [ "$(current_branch)" = "$branch" ] && git checkout -q "$MAIN"
  git branch -m "$branch" "$stale"
  if push_branch "$stale"; then
    remote_exists "$branch" && { git push -q "$REMOTE" --delete "$branch" ||
      echo "warning: could not drop $branch from $REMOTE -- a fresh start will refuse" >&2; }
    echo "**Branch:** \`$stale\` (retired from \`$branch\`, pushed to $REMOTE)"
  else
    echo "**Branch:** \`$stale\` (retired from \`$branch\`, NOT pushed -- local only; $REMOTE keeps $branch)"
  fi
  echo "on $(current_branch)"
}
