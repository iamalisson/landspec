#!/usr/bin/env bash
# Record that /speckit-analyze ran on the current tasks.md (checked by branch.sh on level "full").
# Usage: analyzed.sh <report-file>  (the report, saved as it came; kept next to the marker)
# The marker lives in .git, so it never dirties the working tree.
set -euo pipefail
# shellcheck source=lib.sh
source "$(dirname "$0")/lib.sh"

report="${1:-}"
[[ -n "$report" && -f "$report" ]] || die "usage: analyzed.sh <report-file> (the /speckit-analyze report, saved as it came)"
grep -qF "Specification Analysis Report" "$report" && grep -qF "Coverage Summary Table" "$report" \
  || die "$report is not a /speckit-analyze report (no \"Specification Analysis Report\" or \"Coverage Summary Table\")"
report="$(cd "$(dirname "$report")" && pwd)/$(basename "$report")" # landspec_cd_root changes the directory

landspec_cd_root
fdir="$(feature_dir)"
dir="$(git rev-parse --git-common-dir)/landspec-analyzed"
mkdir -p "$dir"
cp "$report" "$dir/$(basename "$fdir").report.md"
# ticks and the issue line left out, as implement.sh status reads it: landing a task never needs a new analysis
plain_tasks "$fdir/tasks.md" | sha256 > "$dir/$(basename "$fdir")"
echo "ANALYZED=$(basename "$fdir")"
