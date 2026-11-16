#!/usr/bin/env bash
# git pre-push hook body. Args: <remote name> <url>. stdin: "<local ref> <local sha> <remote ref>
# <remote sha>" per ref.
# 1. Every commit being pushed is scanned for secrets.
# 2. On levels standard and full, pushing straight to a protected branch is refused, except the
#    very first push to a remote that has no branches yet: there is nothing to open a PR against.
set -euo pipefail
# shellcheck source=lib.sh
source "$(dirname "$0")/lib.sh"
landspec_cd_root

zero="0000000000000000000000000000000000000000"
status=0
remote="${1:-origin}"
# Under the pre-commit framework the refs don't arrive on stdin: measured with pre-commit 4.7.0 on
# 2026-11-04 (tests/secrets.test.sh shows the variables), args and stdin are empty and the push is
# described by PRE_COMMIT_* variables, one ref only (the last one of a multi-branch push).
if [[ -n "${PRE_COMMIT_TO_REF:-}" ]]; then
  remote="${PRE_COMMIT_REMOTE_NAME:-$remote}"
  exec <<<"${PRE_COMMIT_LOCAL_BRANCH:-HEAD} $PRE_COMMIT_TO_REF ${PRE_COMMIT_REMOTE_BRANCH:-HEAD} ${PRE_COMMIT_FROM_REF:-$zero}"
fi
# An empty remote (a brand-new repository) has no branch a pull request could target.
empty_remote=false
if [[ -z "$(git ls-remote --heads "$remote" 2>/dev/null)" ]] && git ls-remote "$remote" >/dev/null 2>&1; then empty_remote=true; fi
while read -r _local_ref local_sha remote_ref remote_sha; do
  [[ "$local_sha" == "$zero" ]] && continue # deleting a remote branch
  branch="${remote_ref#refs/heads/}"
  if [[ "$(landspec_level)" != lite ]] && is_protected "$branch"; then
    if $empty_remote && [[ "$remote_sha" == "$zero" ]]; then
      echo "landspec: first push to an empty repository: '$branch' allowed once; from now on it only changes through pull requests" >&2
    else
      echo "landspec: refusing to push straight to '$branch'; open a pull request instead" >&2
      status=1; continue
    fi
  fi
  if [[ "$remote_sha" == "$zero" ]] || ! git cat-file -e "$remote_sha^{commit}" 2>/dev/null; then
    # New remote branch: every commit no remote has yet, down to the root on a first push. Also
    # when the remote's tip was never fetched (the remote moved on, or a deliberate --force): a
    # range from it would fail, and git itself still says "fetch first" where it applies.
    from=-
  else
    from="$remote_sha"
  fi
  bash "$(dirname "$0")/secrets.sh" range "$from" "$local_sha" || status=1
done
exit "$status"
