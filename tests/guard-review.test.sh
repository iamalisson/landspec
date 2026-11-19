#!/usr/bin/env bash
# shellcheck disable=SC2016  # checks are strings evaluated by check()
# hooks/guard-review.sh: the PreToolUse hook on the subagent tool (Agent, and Task on older clients).
# A review launch must run on opus, in a fresh agent, never on the session's model.
# shellcheck source=helpers.sh
source "$(dirname "$0")/helpers.sh"
hook="$ROOT/hooks/guard-review.sh"
# shellcheck disable=SC2034  # used inside the check strings
S="landspec review: independent reviewer"

# launch <tool> <subagent_type> <model or ""> <prompt> [<isolation>]: the hook's input, as JSON on stdin.
launch() {
  local m="" i=""; [[ -z "$3" ]] || m=",\"model\":\"$3\""; [[ -z "${5:-}" ]] || i=",\"isolation\":\"$5\""
  printf '{"session_id":"s","cwd":"%s","hook_event_name":"PreToolUse","tool_name":"%s","tool_input":{"description":"review","subagent_type":"%s","prompt":"%s"%s%s}}' \
    "$TMP" "$1" "$2" "$4" "$m" "$i"
}
# shellcheck disable=SC2034  # used inside the check strings
OPUS='landspec: reviews run on Opus only (model: opus)'
# shellcheck disable=SC2034  # used inside the check strings
ISO='landspec: the review must run in its own copy of the repository: pass isolation: "worktree" (an older landspec copy in this project? run /landspec:init; Claude Code too old to take it? update it)'
# rc_of <json>: the hook's exit code; its stderr goes to $TMP/err.
rc_of() { local rc=0; bash "$hook" <<<"$1" 2>"$TMP/err" || rc=$?; echo "$rc"; }
blocked() { [[ "$(rc_of "$1")" == 2 ]] && grep -qF "$2" "$TMP/err"; }
allowed() { [[ "$(rc_of "$1")" == 0 ]]; }

for tool in Agent Task; do
  for m in haiku sonnet fable; do
    check "when $tool launches landspec:reviewer with model $m, then it is blocked with the Opus line" \
      'blocked "$(launch $tool landspec:reviewer $m "Review the branch." worktree)" "$OPUS"'
    check "when $tool launches general-purpose with the sentinel and model $m, then it is blocked with the Opus line" \
      'blocked "$(launch $tool general-purpose $m "Do this.\\n$S\\nReview the branch." worktree)" "$OPUS"'
  done
  check "when $tool launches landspec:reviewer with no model, then it is blocked with the Opus line" \
    'blocked "$(launch $tool landspec:reviewer "" "Review the branch." worktree)" "$OPUS"'
  check "when $tool launches general-purpose with the sentinel and no model, then it is blocked" \
    'blocked "$(launch $tool general-purpose "" "$S\\nReview the branch." worktree)" "$OPUS"'
  check "when $tool launches a fork carrying the sentinel on opus, then it is blocked with the fork line" \
    'blocked "$(launch $tool fork opus "$S\\nReview the branch.")" "landspec: the review must run in a fresh agent, not a fork of this session"'
  check "when $tool launches landspec:reviewer on opus, then it is allowed" \
    'allowed "$(launch $tool landspec:reviewer opus "$S\\nReview the branch." worktree)"'
  check "when $tool launches general-purpose with the sentinel on opus, then it is allowed" \
    'allowed "$(launch $tool general-purpose opus "$S" worktree)"'
  check "when $tool launches general-purpose without the sentinel, on haiku or no model, then it is allowed" \
    'allowed "$(launch $tool general-purpose haiku "Find the config.")" && allowed "$(launch $tool general-purpose "" "Find the config.")"'
  check "when $tool launches landspec:reviewer on opus without isolation, then it is blocked with the isolation line" \
    'blocked "$(launch $tool landspec:reviewer opus "x")" "$ISO"'
  check "when $tool launches landspec:reviewer on opus with isolation remote, then it is blocked with the isolation line" \
    'blocked "$(launch $tool landspec:reviewer opus "x" remote)" "$ISO"'
  check "when $tool launches landspec:reviewer on opus with isolation worktree, then it is allowed" \
    'allowed "$(launch $tool landspec:reviewer opus "x" worktree)"'
  check "when $tool launches a fork carrying the sentinel with isolation worktree, then it is still blocked with the fork line" \
    'blocked "$(launch $tool fork opus "$S" worktree)" "not a fork of this session"'
  check "when $tool launches an agent that is not a review, without isolation, then it is allowed" \
    'allowed "$(launch $tool general-purpose sonnet "Find the config.")"'
done

check "when CLAUDE_CODE_SUBAGENT_MODEL_FORCE is set, then a reviewer launch with no model and no isolation is blocked with the isolation line, and allowed with isolation worktree" \
  'export CLAUDE_CODE_SUBAGENT_MODEL_FORCE=opus; blocked "$(launch Agent landspec:reviewer "" "x")" "$ISO" && allowed "$(launch Agent landspec:reviewer "" "x" worktree)"'

check "when CLAUDE_CODE_SUBAGENT_MODEL_FORCE is set, then a reviewer launch with no model is allowed, and one on haiku still blocked" \
  'export CLAUDE_CODE_SUBAGENT_MODEL_FORCE=opus; allowed "$(launch Agent landspec:reviewer "" "x" worktree)" && blocked "$(launch Agent landspec:reviewer haiku "x" worktree)" "$OPUS"'

check "when CLAUDE_CODE_SUBAGENT_MODEL_FORCE names an Opus model id, then a reviewer launch with no model is allowed" \
  'export CLAUDE_CODE_SUBAGENT_MODEL_FORCE=claude-opus-4-8; allowed "$(launch Agent landspec:reviewer "" "x" worktree)"'

check "when CLAUDE_CODE_SUBAGENT_MODEL_FORCE names sonnet, then a reviewer launch with no model is blocked with the Opus line" \
  'export CLAUDE_CODE_SUBAGENT_MODEL_FORCE=sonnet; blocked "$(launch Agent landspec:reviewer "" "x" worktree)" "$OPUS"'

# A prompt bigger than the pipe buffer (64 KB) is still read whole: the sentinel launch on haiku is blocked.
# shellcheck disable=SC2034  # used inside the check string
big="$(head -c 400000 /dev/zero | tr '\0' x)"
check "when general-purpose carries the sentinel in a 400 KB prompt with model haiku or none, then it is blocked" \
  'blocked "$(launch Agent general-purpose haiku "$S\\n$big" worktree)" "$OPUS" && blocked "$(launch Agent general-purpose "" "$S\\n$big" worktree)" "$OPUS"'

# Without python3 the hook reads the fields with sed: the same decisions.
mkdir -p "$TMP/nopy"
for t in bash cat sed grep; do ln -sf "$(command -v "$t")" "$TMP/nopy/$t"; done
check "when python3 is not on PATH, then a reviewer launch on sonnet is still blocked and one on opus allowed" \
  'rc=0; launch Agent landspec:reviewer sonnet "x" worktree | PATH="$TMP/nopy" bash "$hook" 2>"$TMP/err" || rc=$?; [[ $rc == 2 ]] && grep -qF "$OPUS" "$TMP/err" && launch Agent landspec:reviewer opus "x" worktree | PATH="$TMP/nopy" bash "$hook"'
check "when python3 is not on PATH, then a reviewer launch on opus without isolation is blocked with the isolation line, and a fork with isolation still blocked" \
  'rc=0; launch Agent landspec:reviewer opus "x" | PATH="$TMP/nopy" bash "$hook" 2>"$TMP/err" || rc=$?; [[ $rc == 2 ]] && grep -qF "$ISO" "$TMP/err" && ! launch Agent fork opus "$S" worktree | PATH="$TMP/nopy" bash "$hook" 2>/dev/null && launch Agent general-purpose sonnet "Find it." | PATH="$TMP/nopy" bash "$hook"'

# The bash 3.2 job has no python3: there, the entry from the Agent|Task matcher to its onFailure is read with sed.
check "when hooks.json is read, then it runs guard-review.sh on the Agent and Task tools with onFailure block" \
  'if ! command -v python3 >/dev/null; then e="$(sed -n "/\"matcher\": *\"Agent|Task\"/,/\"onFailure\"/p" "$ROOT/hooks/hooks.json")"; [[ "$e" == *guard-review.sh* && "$e" == *"\"onFailure\": \"block\""* ]]; exit; fi
  python3 -c "import json,sys; h=[e for e in json.load(open(sys.argv[1]))[\"hooks\"][\"PreToolUse\"] if \"guard-review.sh\" in e[\"hooks\"][0][\"command\"]]; m=h[0][\"matcher\"].split(\"|\"); sys.exit(0 if \"Agent\" in m and \"Task\" in m and h[0][\"hooks\"][0][\"onFailure\"]==\"block\" else 1)" "$ROOT/hooks/hooks.json"'

exit "$FAIL"
