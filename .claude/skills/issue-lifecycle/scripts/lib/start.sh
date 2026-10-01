# `start` command body for branch.sh: put a /solve run on issue-<n>. Sourced,
# never executed; needs lib/git.sh. Split out of branch.sh when adoption (#206)
# would have pushed it past the 300-line script cap.
#
# Three ways onto the branch:
#   fresh    -- create issue-<n> off REMOTE/MAIN (or the preflight --base sha)
#   --resume -- check out the branch an interrupted /solve run left behind
#   --adopt  -- check out a branch a human prepared and the refinement recorded
#               as its base (`**Builds on:** issue-<n> @ <sha>`), at exactly
#               that sha
# Every refusal happens before any checkout, so it leaves the run on main.

start_cmd() {
  require_num "${1:-}"
  local n="$1" branch="issue-$1" mode="${2:-}" base="$REMOTE/$MAIN" want=""
  case "$mode" in
    '' | --resume) ;;
    # --base <sha>: fork from the exact tip `preflight` proved green (#52), not
    # whatever REMOTE/MAIN moved to while the suite ran; Sync catches up later.
    --base) base="${3:?--base needs the preflight sha}" ;;
    --adopt) want="${3:?--adopt needs the sha the Builds-on line recorded}" ;;
    *) die "unknown start option '$mode' (allowed: --resume, --base <sha>, --adopt <sha>)" ;;
  esac
  require_clean
  fetch_remote
  git merge-base --is-ancestor "$base" "$REMOTE/$MAIN" 2>/dev/null ||
    die "base $base is not on $REMOTE/$MAIN -- re-run preflight"

  case "$mode" in
    --resume) start_resume "$n" "$branch" ;;
    --adopt) start_adopt "$n" "$branch" "$want" ;;
    *) start_fresh "$branch" "$base" ;;
  esac
}

start_fresh() {
  local branch="$1" base="$2"
  if local_exists "$branch" || remote_exists "$branch"; then
    die "fresh claim, but branch $branch already exists.
Either a prior run left it behind, the issue's resume/blocked signal was missed,
or a human prepared it and no Builds-on line records it.
Refusing to overwrite -- a human decides: record '**Builds on:** $branch @ <sha>'
on the issue so the next run adopts it, resume it, or delete it."
  fi
  git checkout -q -b "$branch" "$base"
  echo "branch: $branch (created off $base at $(git log -1 --pretty=%h))"
  echo "wip: no"
}

start_resume() {
  local n="$1" branch="$2"
  if local_exists "$branch"; then
    # Reconcile local with the remote BEFORE the checkout, so a refusal leaves
    # the run on main rather than parked on an issue-* branch.
    # Local ahead is normal -- the branch is pushed only by escape/ship, so
    # any commit since the last of those puts it ahead. Local behind happens
    # when another clone pushed. Only true divergence is a refusal, and it
    # is never auto-resolved: a fast-forward is the one move allowed here.
    if ! remote_exists "$branch" ||
      git merge-base --is-ancestor "refs/remotes/$REMOTE/$branch" "refs/heads/$branch"; then
      git checkout -q "$branch"
    elif git merge-base --is-ancestor "refs/heads/$branch" "refs/remotes/$REMOTE/$branch"; then
      git checkout -q "$branch"
      git merge --ff-only "$REMOTE/$branch" >/dev/null
    else
      die "local $branch and $REMOTE/$branch have diverged:
  local only:  $(git log --oneline "$REMOTE/$branch..$branch" | tr '\n' ' ')
  $REMOTE only: $(git log --oneline "$branch..$REMOTE/$branch" | tr '\n' ' ')
A human reconciles them before this issue resumes."
    fi
  elif remote_exists "$branch"; then
    git checkout -q -b "$branch" "$REMOTE/$branch"
  else
    die "resume asked for but branch $branch exists neither locally nor on $REMOTE.
The issue's block/resume signal and the git state disagree -- a human must reconcile them."
  fi
  echo "branch: $branch"
  print_landed
  # A "WIP blocked" HEAD marks work committed only because an escape fired
  # mid-chunk. It was never reviewed, so the chunk it belongs to must be
  # re-run rather than counted as landed.
  if git log -1 --pretty=%s | grep -q "^\[#$n\] WIP blocked:"; then
    echo "wip: yes -- re-run the chunk this commit belongs to; it was never reviewed"
  else
    echo "wip: no"
  fi
}

# Exact tip, not ancestry: the refinement analysed the tree at the recorded
# sha, so anything pushed after it was never analysed and must not ride along.
# And no /solve-authored commits: those make it an interrupted run, whose
# chunks --resume must account for -- adopting would read them as a base.
start_adopt() {
  local n="$1" branch="$2" want="$3" sha ref tip ours
  sha="$(git rev-parse --verify --quiet "$want^{commit}")" ||
    die "adopt: the recorded sha $want is not a known commit, even after fetching $REMOTE.
A human re-records the Builds-on line with the branch's real tip."
  local_exists "$branch" || remote_exists "$branch" ||
    die "adopt: the Builds-on line names $branch, but it exists neither locally nor on $REMOTE.
A human pushes it, or posts '**Builds on:** none' so the next run claims fresh."
  for ref in "refs/heads/$branch" "refs/remotes/$REMOTE/$branch"; do
    tip="$(git rev-parse --verify --quiet "$ref")" || continue
    [ "$tip" = "$sha" ] || die "adopt: ${ref#refs/} is at $(git rev-parse --short "$tip"), not the recorded $(git rev-parse --short "$sha").
It moved after the refinement recorded it, so nobody analysed the difference.
A human reconciles the branch and re-records '**Builds on:** $branch @ <tip>' (re-refining if the new commits change the plan)."
  done
  ours="$(git log --format=%s "$REMOTE/$MAIN..$sha" |
    grep -E "^\[#$n\] (chunk [0-9]+/[0-9]+|fix|rebase fix|WIP blocked):" || true)"
  [ -z "$ours" ] || die "adopt: $branch already holds /solve commits -- it is an interrupted run, not a prepared base:
$ours
A human posts '**Builds on:** none' so the next run resumes it (--resume), or deletes the branch."
  if local_exists "$branch"; then
    git checkout -q "$branch"
  else
    git checkout -q -b "$branch" "$REMOTE/$branch"
  fi
  echo "branch: $branch (adopted at $(git rev-parse --short "$sha"))"
  print_landed
  echo "wip: no"
}

print_landed() {
  echo "landed:"
  git log --oneline --no-decorate "$REMOTE/$MAIN..HEAD" | sed 's/^/  /'
}
