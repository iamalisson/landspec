#!/usr/bin/env bash
# Guard for git commands run by Claude Code (called by the plugin's PreToolUse hook).
# Usage: guard.sh "<bash command>"   — exit 2 (with the reason on stderr) blocks the command.
# Rules: no --no-verify or a prefix of it (or commit/am -n), no hooks disabled with -c
#        core.hooksPath or SKIP=, no `git add -A/--all/.`, no commit on a protected branch, no push
#        to a protected branch (counting every branch a switch/checkout earlier in the chain may
#        have moved to), no `gh pr create` outside pr.sh except a promotion between long-lived branches.
# AWS rules, only when `aws: on` in the repository the command runs in: no terraform/tofu destroy
#        (or apply -destroy), no apply in an aws_prod_paths directory or under a prod AWS_PROFILE=,
#        no aws write verb under a prod --profile/AWS_PROFILE=, no secret reads (secretsmanager,
#        ssm --with-decryption), no printing a .env or Terraform state file. Prod is only what
#        aws_prod_profiles/aws_prod_paths declare; IAM is the real boundary.
# Each git command is checked against the repository it runs in: the hook's directory, moved by a
# `cd`/`pushd` earlier in the chain or by `git -C`, or the one --git-dir/GIT_DIR= names. A
# repository without landspec is not checked.
# Best effort: it catches the usual forms (chains, subshells, $(...) and backquotes (quoted or not), { ...; } and if blocks,
# env/command/VAR=/timeout/nice/xargs/sudo prefixes, sh -c '...', git
# global options, bundled flags), not every possible shell trick. The real boundary is CI plus
# branch protection. People are not affected; their git hooks still apply.
set -uo pipefail
# Byte-wise: under a UTF-8 locale ${s:i:1} is O(i), which makes long commands quadratic and could
# outrun the hook's timeout (a timed-out hook lets the command through).
export LC_ALL=C
# shellcheck source=lib.sh
source "$(dirname "$0")/lib.sh"
# A guard that cannot decide blocks: Claude Code lets the command through on exit 1.
die() { echo "landspec guard: $*" >&2; exit 2; }

block() { echo "landspec guard: $1" >&2; exit 2; }
start="$(pwd -P)"
# Where the next command runs; "" when a cd went somewhere it can't tell ($VAR, cd -).
dir="$start"
# Every branch the chain may be on in repository $btop: a switch/checkout earlier in it adds the
# branch it moves to. Reset when a command targets another repository.
btop="" branches=""

# resolve <base> <path>: the physical directory <path> names from <base>, or "" when it can't tell.
resolve() {
  local p="$2"
  [[ -n "$1" ]] || { echo ""; return; }
  case "$p" in
    *'$'*|*'`'*|*'*'*|*'?'*|-) echo ""; return ;;
    \~) p="$HOME" ;; # a literal ~: the command text was never expanded
    \~/*) p="$HOME/${p#\~/}" ;;
    /*) ;;
    *) p="$1/$p" ;;
  esac
  (cd "$p" 2>/dev/null && pwd -P) || echo ""
}

# enter_repo <dir>: cd to the top of the landspec repository a git command runs in. Fails (the
# command is not checked) when <dir> is not in a repository or the repository has no landspec.
enter_repo() {
  local top
  cd "$1" 2>/dev/null || return 1
  top="$(git rev-parse --show-toplevel 2>/dev/null)" || return 1
  [[ -d "$top/.specify/extensions/landspec" || -d "$top/.specify/extensions/jit" ]] || return 1 # jit: the name before 2.0.0
  landspec_cd_root
  if [[ "$top" != "$btop" ]]; then btop="$top"; branches=" $(git branch --show-current 2>/dev/null || true) "; fi
}

# no_verify <word>: --no-verify or any prefix of it from 3 characters (git takes unique prefixes).
no_verify() { ((${#1} >= 3)) && [[ "--no-verify" == "$1"* ]]; }

# switched <switch|checkout> <args...>: add the branch they may move to. Restoring files
# (`checkout [<tree-ish>] -- <paths>`) adds nothing; a word it cannot tell apart is added.
switched() {
  local cmd="$1" w o found=""; shift
  while (($#)); do
    w="$1"; shift
    o="${w%%=*}"
    case "$w" in
      # checkout -- <paths> restores files; for switch, -- only ends the options and the branch follows.
      --) [[ "$cmd" == switch ]] || return 0; [[ -z "${1:-}" ]] || found+=" $1 "; break ;;
      --*)
        # git takes a unique prefix of a long option, so --cr is --create.
        if ((${#o} >= 4)) && [[ "--create" == "$o"* || "--force-create" == "$o"* || "--orphan" == "$o"* ]]; then
          if [[ "$w" == *=* ]]; then w="${w#*=}"; else w="${1:-}"; fi; branches+=" $w "; return 0
        fi
        [[ "$w" != *=* ]] || found+=" ${w#*=} " ;;
      -?*)
        # Short bundle: a new-branch letter takes the rest of the word, or the next word.
        if [[ "$w" == -*[bBcC]* ]]; then
          w="${w#*[bBcC]}"; [[ -n "$w" ]] || w="${1:-}"; branches+=" $w "; return 0
        fi ;;
      -) found+=" $(git rev-parse --abbrev-ref "@{-1}" 2>/dev/null || echo -) " ;;
      *) found+=" $w " ;;
    esac
  done
  # A switch to [refs/][remotes/]<remote>/<branch> may land on the local <branch>: git creates it
  # with --track, --no-track, or none when only the remote has it. Add that name whatever the flags,
  # so no tracking form is missed; the cost is a refusal git would not need (detached checkouts).
  for w in $found; do w="${w#refs/}"; w="${w#remotes/}"; [[ "$w" != */* ]] || found+=" ${w#*/} "; done
  branches+="$found"
}

# words "<text>": shell-like words, one per line. Quotes group and are removed; nothing is
# expanded or run. Unquoted && || ; and newlines become a "|" word, separating commands; a pipe
# (| or |&) becomes "|>" and a lone & "|&" (subshells); a redirection (>f, 2>&1, &>f) is a word of
# its own. A # at the start of a word starts a comment. In awk, linear in the length (bash's ${s:i:1} is not).
words() {
  awk '
    # A command substitution ($(…) or `…`, quoted or not) runs before the command that holds it, and
    # holding it must not split that command: `git commit -m "$(cat m)" --no-verify` is one commit.
    # So its text is kept aside and checked as its own command, between "|(" and "|)", once the
    # command around it ends. Quoted runs are read whole; single quotes hold no substitution.
    # Both scans jump from match to match: a per-character substr() is O(n) per call in a UTF-8
    # BSD awk, which made a long quoted message quadratic (the 100k-character test hung on macOS).
    function close_paren(t, i,   d, k) { # the ) that closes the ( at i, or 0
      d = 0
      while (match(substr(t, i), /[()]/)) {
        k = i + RSTART - 1; if (substr(t, k, 1) == "(") d++; else if (--d == 0) return k
        i = k + 1
      }
      return 0
    }
    function keep(t, i,   j, n) { # set aside the substitution starting at i ($ or `); returns where it ends
      n = length(t)
      if (substr(t, i, 1) == "`") { j = index(substr(t, i + 1), "`"); j = j ? i + j : n + 1; pend = pend "\001" substr(t, i + 1, j - i - 1); return j }
      j = close_paren(t, i + 1); if (!j) j = n + 1; pend = pend "\001" substr(t, i + 2, j - i - 2); return j
    }
    function subs(part,   i) {
      i = 1
      while (match(substr(part, i), /`|[$][(]/)) i = keep(part, i + RSTART - 1) + 1
    }
    function flush(   p, k, m, parts) {
      if (pend == "") return
      p = pend; pend = ""; m = split(p, parts, "\001")
      for (k = 2; k <= m; k++) { print "|("; tok(parts[k]); print "|)" }
    }
    function tok(text,   n, w, inw, i, c, j, part, d, s) {
      n = length(text); w = ""; inw = 0
      for (i = 1; i <= n; i++) {
        c = substr(text, i, 1)
        if (c == "\047" || c == "\"") {
          # The whole quoted run at once: no per-character work inside long messages.
          j = index(substr(text, i + 1), c); if (j == 0) j = n - i + 1
          part = substr(text, i + 1, j - 1); gsub(/\n/, " ", part)
          if (c == "\"") subs(part)
          w = w part; inw = 1; i += j; continue
        }
        if (c == "#" && !inw) { j = index(substr(text, i + 1), "\n"); i = j ? i + j - 1 : n; continue }
        if (c == "`" || c == "$" && substr(text, i + 1, 1) == "(") { i = keep(text, i); w = w "_"; inw = 1; continue }
        # ( and ) open and close a subshell ("|(" and "|)").
        if (c == "(" || c == ")") {
          if (inw) { print w; w = ""; inw = 0 }
          flush(); print (c == "(" ? "|(" : "|)"); continue
        }
        # A redirection ends the word before it (bash does too) but is not a separator: it becomes
        # its own word, keeping a file descriptor number (2>&1) and the & of >&2 or &>f.
        if (c == "<" || c == ">" || c == "&" && substr(text, i + 1, 1) == ">") {
          if (inw && w !~ /^[0-9]*$/ && w !~ /[<>&]$/) { print w; w = "" }
          w = w c; inw = 1; continue
        }
        if (c == "&" && w ~ /[<>]$/) { w = w c; continue }
        if (c == " " || c == "\t" || c == "\n" || c == ";" || c == "|" || c == "&") {
          if (inw) { print w; w = ""; inw = 0 }
          d = substr(text, i + 1, 1); s = "|"
          if (c == "|" && d == "|" || c == "&" && d == "&") i++
          else if (c == "|") { s = "|>"; if (d == "&") i++ }
          else if (c == "&") s = "|&"
          if (c != " " && c != "\t") { print s; flush() }
          continue
        }
        # The whole run of ordinary characters at once, like a quoted run: one substr() per
        # character is O(n) per call in busybox and BSD awk, so a long unquoted word was quadratic.
        # The slice is bounded so many short words do not copy the rest of the text each time;
        # a longer run just matches again on the next pass.
        if (match(substr(text, i, 256),/^[^ \t\n;|&<>()"\047`$]+/)) { w = w substr(text, i, RLENGTH); i += RLENGTH - 1 }
        else w = w c
        inw = 1
      }
      if (inw) print w
      flush()
    }
    { text = text $0 "\n" }
    END { tok(text) }
  ' <<<"$1"
}

# without_heredocs: drops heredoc bodies (data, not commands), so a quote inside one can't hide the
# commands after it. `<<<` here-strings are left alone.
without_heredocs() {
  awk '
    skip { t = $0; if (strip) sub(/^\t+/, "", t); if (t == delim) skip = 0; next }
    { print }
    match($0, /(^|[^<])<<-?[ \t]*["\047]?[A-Za-z_][A-Za-z0-9_]*/) {
      h = substr($0, RSTART, RLENGTH); sub(/^[^<]?<</, "", h)
      strip = (h ~ /^-/); sub(/^-?[ \t]*["\047]?/, "", h); delim = h; skip = 1
    }
  ' <<<"$1"
}

hookspath() { [[ "$(tr '[:upper:]' '[:lower:]' <<<"$1")" == *core.hookspath* ]]; }
no_hooks() { block "switching git hooks off skips the secret checks"; }

# check_git <args...>: the words after `git`.
check_git() {
  local sub="" w gdir="${dir:-$start}" gd="$git_dir" wt="$work_tree"
  # Global options before the subcommand; -C and -c take a value. Each -C moves on from the last.
  while (($#)); do
    case "$1" in
      -c|--config-env) if hookspath "${2:-}"; then no_hooks; fi; shift 2 || shift ;;
      -c*|--config-env=*) if hookspath "$1"; then no_hooks; fi; shift ;;
      -C) gdir="$(resolve "$gdir" "${2:-}")"; [[ -n "$gdir" ]] || gdir="$start"; shift 2 || shift ;;
      --git-dir) gd="${2:-}"; shift 2 || shift ;;
      --git-dir=*) gd="${1#*=}"; shift ;;
      --work-tree) wt="${2:-}"; shift 2 || shift ;;
      --work-tree=*) wt="${1#*=}"; shift ;;
      --namespace) shift 2 || shift ;;
      -*) shift ;;
      *) sub="$1"; shift; break ;;
    esac
  done
  # A named git dir picks the repository: its work tree, or the folder above it. Git resolves a
  # relative one after every -C. --work-tree alone keeps the repository found from the directory.
  if [[ -n "$gd" ]]; then
    if [[ -n "$wt" ]]; then gdir="$(resolve "$gdir" "$wt")"; else gdir="$(resolve "$gdir" "$gd/..")"; fi
    [[ -n "$gdir" ]] || gdir="$start"
  fi
  enter_repo "$gdir" || return 0
  # pre-commit's SKIP= only matters where hooks run; `SKIP=x git status` is fine.
  case "$sub" in commit|push|merge|rebase|am|cherry-pick|revert)
    if $skip_env; then block "SKIP= turns pre-commit hooks off; fix what the hook reports instead"; fi ;;
  esac
  case "$sub" in
    commit)
      while (($#)); do
        case "$1" in
          -m|-F|-C|-c|-t|--message|--file|--template|--reuse-message|--reedit-message|--author|--date|--fixup|--squash) shift ;;
          --*) if no_verify "$1"; then block "--no-verify skips the secret checks; fix what the hook reports instead"; fi ;;
          -*)
            # Bundled short options: letters up to the first one that takes a value. -nm "x" is
            # -n -m "x"; -mn is the message "n".
            b="${1#-}"; b="${b%%[mFCctuS]*}"
            if [[ "$b" == *n* ]]; then block "commit -n is --no-verify, which skips the secret checks"; fi
            [[ "${1#-}" == "$b"[mFCctuS] ]] && shift ;;
        esac
        shift
      done
      for b in $branches; do
        if is_protected "$b"; then
          block "committing on '$b' is not allowed; start a task with /speckit-implement Tnnn (or /landspec:next); a branch created earlier in the same command does not count: run the switch on its own first"
        fi
      done ;;
    switch|checkout) switched "$sub" "$@" ;;
    config)
      local w2 reading=false keys=0
      for w2 in "$@"; do case "$w2" in --get|--get-all|--get-regexp|--list|-l|get) reading=true ;; esac; done
      # `git config core.hooksPath` (a key and no value, no other action) only reads it.
      for w2 in "$@"; do case "$w2" in --local|--global|--system|--worktree|--show-origin|--show-scope) ;; -*) keys=9 ;; *) keys=$((keys + 1)) ;; esac; done
      ((keys == 1)) && reading=true
      for w2 in "$@"; do
        if hookspath "$w2" && ! $reading; then no_hooks; fi
      done ;;
    merge|rebase|am)
      for w in "$@"; do
        if no_verify "$w"; then block "--no-verify skips the secret checks; fix what the hook reports instead"; fi
        # am -n is --no-verify (merge/rebase -n is --no-stat). Bundles stop at a letter that takes a value.
        if [[ "$sub" == am && "$w" == -[!-]* ]]; then
          b="${w#-}"; b="${b%%[CpS]*}"
          if [[ "$b" == *n* ]]; then block "am -n is --no-verify, which skips the secret checks"; fi
        fi
      done ;;
    cherry-pick|revert)
      for w in "$@"; do
        [[ "$w" == --no-verify ]] && block "--no-verify skips the secret checks; fix what the hook reports instead"
      done ;;
    add|stage)
      # --a and --al are prefixes of --all (git takes them); ./ and :/. name the whole tree too.
      for w in "$@"; do
        case "$w" in -A|--a|--al|--all|.|./|:/|:/.|:/./|-[a-zA-Z]*A*) block "stage files by name (git add path/to/file), not everything at once" ;; esac
      done ;;
    push)
      local targets="" remote_seen=false
      for w in "$@"; do
        case "$w" in
          --all|--mirror) block "push --all/--mirror would push the protected branches too; push your branch by name" ;;
          -*) if no_verify "$w"; then block "--no-verify skips the pre-push secret scan"; fi ;;
          *) if ! $remote_seen && git remote get-url "$w" >/dev/null 2>&1; then remote_seen=true; continue; fi
             w="${w#+}"; w="${w##*:}"
             [[ "$w" == HEAD || "$w" == @ ]] && w="$branches"
             targets+=" $w " ;;
        esac
      done
      [[ -n "$targets" ]] || targets="$branches"
      for b in $(protected_branches); do
        if [[ "$targets" == *" $b "* || "$targets" == *" HEAD:$b "* || "$targets" == *" refs/heads/$b "* ]]; then
          block "pushing to '$b' is not allowed; it only changes through pull requests"
        fi
      done ;;
  esac
}

# check_command <command text> [nested]: every command in it, including ones inside sh -c '...'.
# An env prefix (SKIP=) belongs to one top-level command; inside sh -c it carries over.
check_command() {
  local cmd=() w nested="${2:-}" before="$dir" piped=false saved=""
  while IFS= read -r w; do
    case "$w" in
      "|"|"|>"|"|&"|"|("|"|)")
        [[ -n "$nested" ]] || skip_env=false
        check_words ${cmd[@]+"${cmd[@]}"}; cmd=()
        # A pipeline stage or a background job runs in a subshell: its cd does not last.
        if $piped || [[ "$w" == "|>" || "$w" == "|&" ]]; then dir="$before"; fi
        if [[ "$w" == "|>" ]]; then piped=true; else piped=false; fi
        # Neither does a cd inside ( … ) or $( … ): the directory comes back at the ")".
        if [[ "$w" == "|(" ]]; then saved="$dir"$'\n'"$saved"; fi
        if [[ "$w" == "|)" && -n "$saved" ]]; then dir="${saved%%$'\n'*}"; saved="${saved#*$'\n'}"; fi
        before="$dir" ;;
      *) cmd+=("$w") ;;
    esac
  done < <(words "$(without_heredocs "$1")")
  [[ -n "$nested" ]] || skip_env=false
  check_words ${cmd[@]+"${cmd[@]}"}
}

# check_gh <args...>: the words after `gh`. A PR opens through pr.sh, which refuses it without a
# recorded review, at every level. A promotion (head is a long-lived branch: develop into main)
# carries only PRs that were each reviewed, so it may open directly.
check_gh() {
  local head=""
  while [[ "${1:-}" == -R || "${1:-}" == --repo ]]; do shift; (($#)) && shift; done # a trailing -R must not loop
  while [[ "${1:-}" == --repo=* ]]; do shift; done
  [[ "${1:-}" == pr && "${2:-}" == create ]] || return 0
  enter_repo "${dir:-$start}" || return 0
  # The guard is the plugin's copy, pr.sh the project's: before /landspec:init updates a project,
  # its pr.sh has no fix mode, and blocking would leave a small fix no way to open.
  grep -qF '|fix)' .specify/extensions/landspec/scripts/pr.sh 2>/dev/null || return 0
  shift 2
  while (($#)); do
    case "$1" in
      -H|--head) head="${2:-}"; shift 2 || shift ;;
      --head=*) head="${1#*=}"; shift ;;
      *) shift ;;
    esac
  done
  [[ -n "$head" ]] || head="$(git branch --show-current 2>/dev/null)"
  head="${head##*:}" # owner:branch
  if [[ -n "$head" ]] && is_protected "$head"; then return 0; fi
  block "a PR opens after the independent review, through pr.sh: pr.sh feature \"<title>\" <body-file> for a feature, pr.sh fix \"<title>\" <body-file> for anything else (/speckit-landspec-review first)"
}

# aws_on: the AWS layer is on in the repository the command runs in. Its aws, aws_prod_profiles and
# aws_prod_paths are read once per repository top (one git call per new directory); outside any
# repository the rules are off.
adir="-" atop="-" aon=false aprofiles="" aprod=()
aws_on() {
  local d="${dir:-$start}" top p cf
  if [[ "$d" != "$adir" ]]; then
    adir="$d"
    top="$(git -C "$d" rev-parse --show-toplevel 2>/dev/null)" || top=""
    if [[ "$top" != "$atop" ]]; then
      atop="$top" aon=false aprofiles="" aprod=()
      cf="$top/$LANDSPEC_CONFIG"
      if [[ -n "$top" && "$(LANDSPEC_CONFIG="$cf" cfg aws off)" == on ]]; then
        aon=true
        aprofiles=" $(LANDSPEC_CONFIG="$cf" cfg aws_prod_profiles "" | tr ', ' '  ') "
        local IFS=,
        for p in $(LANDSPEC_CONFIG="$cf" cfg aws_prod_paths ""); do
          p="${p#"${p%%[! ]*}"}"; p="${p%"${p##*[! ]}"}"
          [[ -z "$p" ]] || { p="$(resolve "$top" "$p")"; [[ -z "$p" ]] || aprod+=("$p"); }
        done
      fi
    fi
  fi
  $aon
}
prod_profile() { [[ -n "$1" && "$aprofiles" == *" $1 "* ]]; }
prod_dir() {
  local p
  for p in ${aprod[@]+"${aprod[@]}"}; do [[ "$1" == "$p" || "$1" == "$p"/* ]] && return 0; done
  return 1
}
no_destroy() { block "$1 is refused: destroys go through a reviewed PR and a human"; }
no_prod() { block "$1 aims at prod ($2): prod changes go through a PR; the pipeline applies them"; }
no_secret() { block "$1 is refused: secret values stay out of the conversation"; }

# check_tf <terraform|tofu> <args...>: destroys always; apply in a prod directory or profile;
# reading the state (state pull, show of a state file or of the current state).
check_tf() {
  local tool="$1" sub="" w tfdir="${dir:-$start}" file=""; shift
  while (($#)); do
    case "$1" in
      -chdir=*) tfdir="$(resolve "$tfdir" "${1#*=}")"; shift ;;
      -*) shift ;;
      *) sub="$1"; shift; break ;;
    esac
  done
  case "$sub" in
    destroy) no_destroy "$tool destroy" ;;
    apply)
      for w in "$@"; do
        case "$w" in -destroy|--destroy|-destroy=*|--destroy=*)
          # Go's flag parsing takes -destroy=<bool>; only a false value keeps it off.
          case "${w#*=}" in 0|f|F|false|FALSE|False) ;; *) no_destroy "$tool apply -destroy" ;; esac ;;
        esac
      done
      if prod_profile "$aws_profile"; then no_prod "$tool apply" "AWS_PROFILE=$aws_profile"; fi
      if [[ -n "$tfdir" ]] && prod_dir "$tfdir"; then no_prod "$tool apply" "${tfdir#"$atop"/}"; fi ;;
    state) [[ "${1:-}" != pull ]] || no_secret "$tool state pull" ;;
    show)
      for w in "$@"; do [[ "$w" == -* ]] || file="$w"; done
      # Without a file, show prints the current state.
      [[ -n "$file" && "$file" != *.tfstate* ]] || no_secret "$tool show of the state" ;;
  esac
}

# check_aws <args...>: the words after `aws`. Secret reads always; write verbs under a prod profile.
check_aws() {
  local profile="$aws_profile" svc="" verb="" dec=false
  while (($#)); do
    case "$1" in
      --profile) profile="${2:-}"; shift 2 || shift ;;
      --profile=*) profile="${1#*=}"; shift ;;
      --with-decryption) dec=true; shift ;;
      # Global options that take a value.
      --region|--output|--endpoint-url|--query|--color|--ca-bundle|--cli-read-timeout|--cli-connect-timeout|--cli-binary-format) shift 2 || shift ;;
      -*) shift ;;
      *) if [[ -z "$svc" ]]; then svc="$1"; elif [[ -z "$verb" ]]; then verb="$1"; fi; shift ;;
    esac
  done
  case "$svc:$verb" in
    secretsmanager:get-secret-value|secretsmanager:batch-get-secret-value) no_secret "aws $svc $verb" ;;
    ssm:get-parameter|ssm:get-parameters|ssm:get-parameters-by-path|ssm:get-parameter-history)
      if $dec; then no_secret "aws ssm $verb --with-decryption"; fi ;;
  esac
  prod_profile "$profile" || return 0
  case "$svc:$verb" in
    s3:rm|s3:mv|s3:cp|s3:sync|s3:rb|*:create-*|*:delete-*|*:put-*|*:update-*|*:modify-*|*:terminate-*|*:run-*|*:start-*|*:stop-*|*:attach-*|*:detach-*|*:associate-*|*:disassociate-*|*:register-*|*:deregister-*|*:reboot-*|*:restore-*)
      no_prod "aws $svc $verb" "profile $profile" ;;
  esac
}

# check_read <reader> <args...>: a .env or Terraform state file among its words.
check_read() {
  local tool="$1" w f; shift
  for w in "$@"; do
    # Only the last 256 characters (a file name is shorter): ## over a whole long word is quadratic.
    f="${w: -256}"; [[ ${#w} -gt 256 ]] || f="$w"
    f="${f##*[<>=]}"; f="${f##*/}" # a glued redirection or --file=, then the file name
    case "$f" in
      .env.example|.env.sample|.env.template|.env.dist) ;;
      .[eE][nN][vV]|.[eE][nN][vV].*|*.tfstate|*.tfstate.*) no_secret "$tool $f" ;;
    esac
  done
}

check_words() {
  # GIT_DIR=/GIT_WORK_TREE= belong to this command, and reach the commands inside its sh -c, as
  # does AWS_PROFILE=.
  local w git_dir="${git_dir-}" work_tree="${work_tree-}" aws_profile="${aws_profile-}"
  # Git reads config from the environment too (GIT_CONFIG_PARAMETERS, GIT_CONFIG_KEY_n).
  for w in "$@"; do
    if [[ "$w" == GIT_CONFIG_*=* ]] && hookspath "$w"; then no_hooks; fi
  done
  # Prefixes that still run git: VAR=value, env [VAR=value...], command, exec, time, nohup, the
  # shell's own words ({ ! if then …), and runners with options (timeout 30, nice -n 5, xargs, sudo).
  # SKIP= (pre-commit) is remembered: it also reaches the commands inside a `sh -c '...'`.
  local p
  while (($#)); do
    case "$1" in
      SKIP=*|PRE_COMMIT_ALLOW_NO_CONFIG=*) skip_env=true; shift ;;
      GIT_DIR=*) git_dir="${1#*=}"; shift ;;
      GIT_WORK_TREE=*) work_tree="${1#*=}"; shift ;;
      AWS_PROFILE=*) aws_profile="${1#*=}"; shift ;;
      *=*|env|command|exec|time|nohup|'{'|'}'|'!'|if|then|else|elif|fi|do|done|while|until) shift ;;
      timeout|nice|xargs|stdbuf|sudo|doas)
        p="$1"; shift
        while [[ "${1:-}" == -* ]]; do
          # Options that take the next word as their value.
          case "$p:$1" in timeout:-s|timeout:-k|timeout:--signal|timeout:--kill-after|nice:-n|xargs:-[InLPdsaE]|stdbuf:-[ioe]|sudo:-[ug]|doas:-u) shift ;; esac
          shift
        done
        if [[ "$p" == timeout ]]; then shift; fi ;; # its duration
      *) break ;;
    esac
  done
  (($#)) || return 0
  case "$1" in
    cd|pushd)
      shift
      while [[ "${1:-}" == -?* ]]; do shift; done
      dir="$(resolve "${dir:-$start}" "${1:-~}")" ;;
    git|*/git) shift; check_git "$@" ;;
    gh|*/gh) shift; check_gh "$@" ;;
    terraform|tofu|*/terraform|*/tofu) if aws_on; then check_tf "${1##*/}" "${@:2}"; fi ;;
    aws|*/aws) if aws_on; then shift; check_aws "$@"; fi ;;
    cat|less|more|head|tail|bat|grep|sed|awk|strings|xxd|*/cat|*/less|*/more|*/head|*/tail|*/bat|*/grep|*/sed|*/awk|*/strings|*/xxd)
      if aws_on; then check_read "${1##*/}" "${@:2}"; fi ;;
    sh|bash|zsh|*/sh|*/bash|*/zsh)
      shift
      while (($#)); do
        # A cd inside the child shell does not move the commands after it.
        if [[ "$1" == -*c* && "$1" != --* ]]; then local d="$dir"; check_command "${2:-}" nested; dir="$d"; return; fi
        shift
      done ;;
  esac
}

skip_env=false
check_command "${1:-}"
exit 0
