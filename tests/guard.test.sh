#!/usr/bin/env bash
# shellcheck disable=SC2016,SC2034  # checks are strings evaluated by check()
# shellcheck source=helpers.sh
source "$(dirname "$0")/helpers.sh"
g="$SCRIPTS/guard.sh"
blocked() { local rc=0; "$g" "$1" 2>/dev/null || rc=$?; [[ $rc == 2 ]]; }

new_repo standard
git switch --quiet -c feat/001-t001-thing

check "when Claude commits with --no-verify, then it is blocked" 'blocked "git commit --no-verify -m x"'
check "when Claude commits with -n, then it is blocked" 'blocked "git commit -n -m x"'
check "when Claude pushes with --no-verify, then it is blocked" 'blocked "git push --no-verify"'
check "when Claude runs git add -A or git add ., then it is blocked" 'blocked "git add -A" && blocked "git add ." && blocked "git add --all"'
check "when Claude stages files by name, then it is allowed" '"$g" "git add src/a.ts src/b.ts"'
check "when Claude commits on a task branch, then it is allowed" '"$g" "git commit -m \"feat: x\""'
check "when Claude pushes its task branch, then it is allowed" '"$g" "git push -u origin feat/001-t001-thing"'
check "when the remote's default branch is develop, then pushing to main is still blocked" \
  'git remote set-head origin develop >/dev/null 2>&1 || git symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/develop; blocked "git push origin main"; rc=$?; git remote set-head origin main >/dev/null 2>&1 || git symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/main; exit $rc'
check "when Claude pushes to develop or main explicitly, then it is blocked" \
  'blocked "git push origin develop" && blocked "git push origin HEAD:main" && blocked "git push --force origin main"'
check "when the push hides in a chain or uses -C, then it is still blocked" \
  'blocked "npm test && git -C . push origin develop"'
check "when Claude opens a PR with gh pr create, then it is blocked at every level (pr.sh checks the review)" \
  'blocked "gh pr create --base develop --title x --body y" && blocked "cd . && gh -R o/r pr create -t x" && blocked "bash -c \"gh pr create --fill\""'
check "when the PR is a promotion from a long-lived branch, then gh pr create is allowed" \
  '"$g" "gh pr create --base main --head develop --title x" && "$g" "gh pr create -B main -H develop -t x"'
check "when gh ends in -R or uses --repo=, then the guard ends (a loop hangs the job) and still blocks the PR" \
  '"$g" "gh -R" && "$g" "gh --repo" && blocked "gh --repo=o/r pr create -t x"'
check "when the project's pr.sh predates pr.sh fix (not updated by init yet), then gh pr create is allowed" \
  'rm .specify/extensions/landspec/scripts && mkdir .specify/extensions/landspec/scripts && echo "  task)" > .specify/extensions/landspec/scripts/pr.sh \
   && "$g" "gh pr create --head feat/001-t001-thing --fill"; rc=$?; rm -r .specify/extensions/landspec/scripts; ln -s "$ROOT/extension/scripts" .specify/extensions/landspec/scripts; exit $rc'
check "when gh only reads PRs, then it is allowed" '"$g" "gh pr list" && "$g" "gh pr view 3 --json body" && "$g" "gh pr edit 3 --body x"'

check "when no-verify hides in a bundled flag, a global option or a wrapper, then it is blocked" \
  'blocked "git commit -nm x" && blocked "git --no-pager commit -n -m x" && blocked "env git commit --no-verify -m x" && blocked "GIT_X=1 command git push --no-verify"'
check "when the command sits in a subshell, braces, an if block or a \$(…), then it is still blocked" \
  'blocked "(git commit --no-verify -m x)" && blocked "{ git commit --no-verify -m x; }" && blocked "if true; then git push origin main; fi" && blocked "URL=\$(gh pr create --title x)" && blocked "URL=\`gh pr create --title x\`"'
check "when a \$(…) or backquote sits inside double quotes, then the command inside is still checked" \
  'blocked "URL=\"\$(gh pr create --title x)\"" && blocked "x=\"\$(git push origin main)\"" && blocked "echo \"\`git commit --no-verify -m x\`\""'
check "when a \$(…) sits inside a command, then the rest of that command is still checked" \
  'blocked "git commit -m \"\$(cat m)\" --no-verify" && blocked "git commit -m \$(cat m) --no-verify" && blocked "git commit -m \`cat m\` --no-verify" && blocked "x=\$(cd /tmp); git push origin main"'
check "when single quotes hold a \$(…), then it is text and allowed" \
  '"$g" "echo '"'"'literal \$(git push origin main)'"'"'" && "$g" "echo \$((1+2))" && "$g" "git commit -m \"\$(cat m)\""'
check "when timeout, nice, xargs or sudo run git, with their own options, then it is still blocked" \
  'blocked "timeout 30 git push origin main" && blocked "timeout -s KILL 30 git commit --no-verify -m x" && blocked "nice -n 5 git commit --no-verify -m x" && blocked "xargs -n 1 git push origin main" && blocked "sudo git push origin main" && blocked "sudo -u me git push origin main"'
check "when a cd happens inside ( … ), then the commands after it are checked where they really run" \
  'blocked "(cd /tmp && git status); git push origin main"'
check "when parentheses or braces are only inside a quoted message or format, then it is allowed" \
  '"$g" "git commit -m \"fix (parser) and {braces}\"" && "$g" "git log --format=\"(%h)\" -n 3" && "$g" "echo \"\$(date)\"; git status"'
check "when everything is staged through git stage, --al or ./, then it is blocked" \
  'blocked "git stage -A" && blocked "git add --al" && blocked "git add ./" && blocked "git add :/."'
check "when hooks are switched off with -c core.hooksPath, then it is blocked" \
  'blocked "git -c core.hooksPath=/dev/null commit -m x" && blocked "git -c core.hooksPath /dev/null commit -m x"'
check "when pre-commit hooks are skipped with SKIP=, then it is blocked" \
  'blocked "SKIP=blue git commit -m x" && blocked "SKIP=a,b env git push" && blocked "npm test && SKIP=x git commit -m y"'
check "when SKIP= wraps an sh -c, then the commit inside is still blocked" 'blocked "SKIP=x bash -c \"git commit -m y\""'
check "when SKIP= prefixes a read-only git command, then it is allowed" '"$g" "SKIP=x git status" && "$g" "SKIP=lint git diff" && "$g" "SKIP=1 git log -1"'
check "when SKIP= was on an earlier command in the chain, then a later plain commit is allowed" '"$g" "SKIP=x pre-commit run && git commit -m y"'
check "when SKIP= only appears in the message, then it is allowed" '"$g" "git commit -m \"docs: SKIP=blue explained\""'
check "when a commit message merely contains -n or --no-verify, then it is allowed" \
  '"$g" "git commit -m \"docs: explain -n and --no-verify\""'
check "when merge or rebase use -n (no-stat, not no-verify), then they are allowed" '"$g" "git merge -n main" && "$g" "git rebase -n main"'
check "when the git command is wrapped in sh -c or bash -lc, then it is still checked" \
  'blocked "sh -c \"git push origin develop\"" && blocked "bash -lc '"'"'git add -A'"'"'"'
check "when a force refspec +main or a bundled add -A is used, then it is blocked" \
  'blocked "git push origin +main" && blocked "git add -vA"'
check "when the remote has an unusual name, then it is not mistaken for the target branch" \
  'git remote add fork "$TMP/origin.git" && "$g" "git push fork feat/001-t001-thing" && blocked "git push fork develop"'

check "when hooks are switched off any other way (case, env, --config-env, git config), then it is blocked" \
  'blocked "git -c CORE.HOOKSPATH=/x commit -m x" && blocked "GIT_CONFIG_PARAMETERS=\"'"'"'core.hooksPath=/x'"'"'\" git commit -m x" && blocked "GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=core.hooksPath GIT_CONFIG_VALUE_0=/x git commit -m x" && blocked "git --config-env=core.hooksPath=X commit -m x" && blocked "git config core.hooksPath /dev/null" && blocked "git config --unset core.hooksPath"'
check "when the hooks path is only read, then it is allowed" '"$g" "git config --get core.hooksPath"'
check "when an apostrophe sits in a comment or a heredoc, then the commands after it are still checked" \
  'blocked "# don'"'"'t forget
git push origin develop" && blocked "cat > notes.md <<EOF
it'"'"'s fine
EOF
git push origin develop"'
check "when pushing everything or HEAD/@ while on a protected branch, then it is blocked" \
  'blocked "git push --all origin" && blocked "git push --mirror origin"'
check "when the message is bundled after -m (-mn is the message n), then it is allowed; -nm is not" \
  '"$g" "git commit -mn" && "$g" "git commit -am \"fix -n handling\"" && blocked "git commit -anm x"'
check "when other git commands use -n (git log -n 5), then they are allowed" '"$g" "git log -n 5 --oneline"'
long="git commit -m \"$(head -c 100000 /dev/zero | tr '\0' 'a')\""
check "when a 100 KB command is checked under a UTF-8 locale, then it takes under 3 seconds (the hook allows 10)" \
  'start=$(date +%s); LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8 "$g" "$long"; (( $(date +%s) - start < 3 ))'
long2="git commit -m \"$(head -c 100000 /dev/zero | tr '\0' 'a') \$(date) \$(echo (\""
check "when that command also holds a \$(…) and an unclosed one in quotes, then it still takes under 3 seconds" \
  'start=$(date +%s); LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8 "$g" "$long2"; (( $(date +%s) - start < 3 ))'

# F2.3: git accepts a unique prefix of a long option, so every cut of the option is refused. The
# cuts are made here at run time; the file holds no list of them.
nv="--no-verify"; takes="commit push merge rebase am"
check "when commit, push, merge, rebase or am use an abbreviation of --no-verify (3 to 10 characters), then it is blocked" \
  'for c in $takes; do for n in 3 4 5 6 7 8 9 10; do blocked "git $c ${nv:0:$n} x" || exit 1; done; done'
check "when git am uses -n, alone or bundled, then it is blocked like commit -n" 'blocked "git am -n x.patch" && blocked "git am -3n x.patch"'
check "when options only look like it (--verify, --no-edit, --no-ff, --no-stat, --no-tags, a message), then they are allowed" \
  '"$g" "git commit --verify -m x" && "$g" "git merge --no-edit --no-ff main" && "$g" "git rebase --no-stat main" && "$g" "git push --no-tags origin feat/001-t001-thing" && "$g" "git commit -m \"${nv:0:6}\""'
check "when git -h is asked, then exactly commit, push, merge, rebase and am take --no-verify (cherry-pick and revert do not)" \
  'for c in $takes; do { git $c -h 2>&1 || true; } | grep -qF -- "$nv" || exit 1; done; for c in cherry-pick revert; do if { git $c -h 2>&1 || true; } | grep -qF -- "$nv"; then exit 1; fi; done'
check "when a chain switches to main and then commits or pushes HEAD, then it is blocked" \
  'blocked "git switch main && git commit -m x" && blocked "git checkout main && git push origin HEAD" && blocked "git switch --quiet main; git push" && blocked "git checkout -q develop && git commit -m x"'
check "when a chain creates a branch named like a protected one, then a later commit is blocked" \
  'blocked "git switch -c main && git commit -m x" && blocked "git checkout -bmain && git commit -m x"'
check "when a chain tracks a protected remote branch (--track or -t, alone or bundled), then a later commit is blocked" \
  'blocked "git switch --track origin/develop && git commit -m x" && blocked "git checkout -t origin/develop && git commit -m x" && blocked "git checkout -qt origin/main && git commit -m x" && blocked "git switch --track=direct origin/develop && git commit -m x"'
check "when a chain tracks a protected branch by its full remote ref (remotes/ or refs/remotes/), then a later commit is blocked" \
  'blocked "git switch --track remotes/origin/develop && git commit -m x" && blocked "git checkout -t refs/remotes/origin/main && git commit -m x"'
# switch has no other long option starting --t, so git takes --t for --track; -h proves it here.
tr="--track"
check "when git switch tracks with the shortest unique prefix of --track (3 characters), then a later commit is blocked" \
  '[[ "$({ git switch -h 2>&1 || true; } | grep -oE -- "--(\[no-\])?t[a-z-]*")" == "--[no-]track" ]] && blocked "git switch ${tr:0:3} origin/develop && git commit -m x"'
# Built at run time: the tracking flag does not matter, git lands on the local branch either way.
nt="--no-track"
check "when a chain switches to a protected branch's remote ref without tracking, then a later commit is blocked" \
  'blocked "git switch $nt origin/develop && git commit -m x" && blocked "git checkout ${nt:0:6} origin/main && git commit -m x" && blocked "git switch origin/develop && git commit -m x"'
# For switch, "--" ends the options and the branch still follows; built at run time.
dd="--"
check "when a chain switches to a protected branch after the end-of-options marker, then a later commit is blocked" \
  'blocked "git switch $dd develop && git commit -m x" && blocked "git switch -q $dd main && git commit -m x" && "$g" "git checkout $dd main && git commit -m x"'
# The abbreviations are cut at run time too.
cr="--create"; orph="--orphan"; fc="--force-create"
check "when a chain creates a protected branch with an abbreviated long option, then a later commit is blocked" \
  'blocked "git switch ${cr:0:4}=main && git commit -m x" && blocked "git switch ${cr:0:5} main && git commit -m x" && blocked "git checkout ${orph:0:6}=main && git commit -m x" && blocked "git switch ${fc:0:9}=main && git commit -m x"'
check "when a chain creates or tracks a task branch with a long or abbreviated option, then the commit is allowed" \
  '"$g" "git switch --create=feat/001-t002-other main && git commit -m x" && "$g" "git switch ${cr:0:4} feat/001-t002-other main && git commit -m x" && "$g" "git switch --track origin/feat/001-t001-thing && git commit -m x"'
check "when a chain only restores files or creates a task branch from main, then the commit is allowed" \
  '"$g" "git checkout main -- README.md && git commit -m x" && "$g" "git checkout -- README.md && git commit -m x" && "$g" "git switch -c feat/001-t002-other main && git commit -m x" && "$g" "git checkout -b feat/001-t002-other main && git push -u origin HEAD"'

git switch --quiet main
check "when Claude commits on main, then it is blocked" 'blocked "git commit -m x"'
check "when a chain creates a branch from main and commits, then the refusal says to run the switch on its own" \
  'fails_with "run the switch on its own first" "$g" "git switch -c chore/x && git commit -m x"'
check "when Claude pushes with no refspec while on main, then it is blocked" 'blocked "git push"'
check "when pushing HEAD or @ while on main, then it is blocked" 'blocked "git push origin HEAD" && blocked "git push origin @"'
check "when the command is not git, then it is allowed" '"$g" "ls -la && echo done"'

# Commands aimed at another repository (cd / pushd / git -C) are checked there, not here.
mkdir -p "$TMP/other" && git -C "$TMP/other" init --quiet -b main
cp -R "$TMP/repo" "$TMP/second" && git -C "$TMP/second" switch --quiet -c feat/001-t009-other
check "when the commit goes to a repository without landspec through cd or -C, then it is allowed" \
  '"$g" "cd $TMP/other && git commit -m x" && "$g" "git -C $TMP/other commit -m x" && "$g" "pushd $TMP/other && git push origin main"'
check "when the commit goes to another landspec repository on a task branch, then it is allowed" \
  '"$g" "cd $TMP/second && git commit -m x" && "$g" "git -C $TMP/second commit -m x" && "$g" "cd .. && cd second && git commit -m x"'
check "when the chain moves back into this repository on main, then the commit is blocked again" \
  'blocked "cd $TMP/other && cd $TMP/repo && git commit -m x" && blocked "git -C $TMP/other -C ../repo commit -m x"'
git -C "$TMP/repo" worktree add --quiet -b feat/001-t010-wt "$TMP/wt" 2>/dev/null
check "when the commit goes into a worktree of this repository on a task branch, then it is allowed" \
  '"$g" "cd $TMP/wt && git commit -m x" && "$g" "git -C $TMP/wt commit -m x"'
check "when git config only reads core.hooksPath, then it is allowed; setting or unsetting it is not" \
  '"$g" "git config core.hooksPath" && "$g" "git config --local core.hooksPath" && blocked "git config core.hooksPath /dev/null" && blocked "git config --unset core.hooksPath"'
check "when the cd target can not be told (a variable, cd -), then it is checked here" \
  'blocked "cd \$X && git commit -m x" && blocked "cd - && git commit -m x"'
# #103: a cd in a child process (sh -c, a pipeline stage, a background job) does not move the rest.
check "when a cd or pushd runs inside sh -c, then the commands after it are still checked here" \
  'blocked "bash -c '"'"'cd /tmp'"'"'; git commit --no-verify -m x" && blocked "sh -c '"'"'cd /tmp'"'"'; git commit -m x" && blocked "zsh -c '"'"'cd /tmp'"'"' && git commit --no-verify -m x" && blocked "env bash -c '"'"'cd /tmp'"'"'; git commit --no-verify -m x" && blocked "bash -c '"'"'pushd /tmp'"'"'; git commit --no-verify -m x" && blocked "bash -c '"'"'cd /tmp'"'"'; git add -A" && blocked "bash -c '"'"'cd /tmp'"'"'; git push origin main"'
check "when a cd runs in a pipeline stage or before a lone &, then the commands after it are still checked here" \
  'blocked "cd /tmp | true; git commit --no-verify -m x" && blocked "true | cd /tmp; git commit -m x" && blocked "cd /tmp |& true; git commit -m x" && blocked "cd /tmp & git commit --no-verify -m x" && blocked "(cd /tmp); git commit --no-verify -m x"'
check "when a redirection is glued to a blocked word (&>, >&, >, <), then it is still blocked" \
  'blocked "git commit --no-verify&>/dev/null -m x" && blocked "git push --no-verify&>/dev/null" && blocked "git commit -m x --no-verify&>/dev/null" && blocked "git push origin main&>/dev/null" && blocked "git add .&>/dev/null" && blocked "git commit --no-verify>&2 -m x" && blocked "git commit --no-verify>/dev/null -m x" && blocked "git add -A</dev/null" && blocked "git commit -m x --no-verify|&cat"'
check "when a redirection is spaced or 2>&1, then the commit is checked as usual" \
  'blocked "git commit --no-verify &> /dev/null -m x" && blocked "git commit --no-verify 2>&1 -m x" && blocked "git commit -m x 2>&1" && "$g" "git -C $TMP/other commit -m x 2>&1 >/dev/null" && "$g" "git -C $TMP/other commit -m x &>/dev/null" && "$g" "git -C $TMP/other commit -m x >&2"'
check "when the commit runs inside the same sh -c as the cd, or after a cd with a redirection, then it is checked there" \
  '"$g" "bash -c '"'"'cd $TMP/other; git commit -m x'"'"'" && "$g" "cd $TMP/other 2>&1 && git commit -m x" && "$g" "cd $TMP/other && git commit -m x | cat"'

# The plugin hook shim: JSON in, guard decision out; silent outside landspec projects.
shim="$ROOT/hooks/guard-git.sh"
json() { printf '{"tool_name":"Bash","cwd":"%s","tool_input":{"command":"%s"}}' "$1" "$2"; }
check "when the hook gets a blocked command inside a landspec project, then it exits 2" \
  'rc=0; json "$PWD" "git push origin develop" | bash "$shim" 2>/dev/null || rc=$?; [[ $rc == 2 ]]'
check "when the hook gets gh pr create (no 'git' in it) inside a landspec project, then it exits 2" \
  'rc=0; json "$PWD" "gh pr create --head feat/001-t001-thing --fill" | bash "$shim" 2>/dev/null || rc=$?; [[ $rc == 2 ]]'
mkdir -p "$TMP/oldname/.specify/extensions/jit" && git -C "$TMP/oldname" init --quiet
check "when a project still has the old jit folder, then the hook still guards it" \
  'rc=0; json "$TMP/oldname" "git add -A" | bash "$shim" 2>/dev/null || rc=$?; [[ $rc == 2 ]]'
mkdir -p "$TMP/plain" && git -C "$TMP/plain" init --quiet
check "when the project does not use landspec, then the hook allows everything" \
  'json "$TMP/plain" "git push origin main" | bash "$shim"'
check "when the session is outside landspec but the command cds into a landspec repo on main, then it exits 2" \
  'rc=0; json "$TMP/plain" "cd $TMP/repo && git commit -m x" | bash "$shim" 2>/dev/null || rc=$?; [[ $rc == 2 ]]'
check "when the session is in a landspec repo on main but the commit targets another repo, then the hook allows it" \
  'json "$TMP/repo" "git -C $TMP/other commit -m x" | bash "$shim"'
# #104: --git-dir / GIT_DIR= name the repository git writes to; --work-tree alone does not.
check "when the session is outside landspec but --git-dir or GIT_DIR= names a landspec repo on main, then it is blocked" \
  '(cd "$TMP/plain" && blocked "git --git-dir=$TMP/repo/.git --work-tree=$TMP/repo commit --no-verify -m x" && blocked "GIT_DIR=$TMP/repo/.git GIT_WORK_TREE=$TMP/repo git commit --no-verify -m x" && blocked "git --git-dir $TMP/repo/.git commit -m x" && blocked "GIT_DIR=$TMP/repo/.git bash -c \"git commit -m x\"")'
check "when the hook gets --git-dir or GIT_DIR= from outside landspec, then it still runs the guard and exits 2" \
  'a=0 b=0; json "$TMP/plain" "GIT_DIR=$TMP/repo/.git git commit --no-verify -m x" | bash "$shim" 2>/dev/null || a=$?; json "$TMP/plain" "git --git-dir=$TMP/repo/.git --work-tree=$TMP/repo commit --no-verify -m x" | bash "$shim" 2>/dev/null || b=$?; [[ $a == 2 && $b == 2 ]]'
check "when the session is in a landspec repo on main but --git-dir or GIT_DIR= names another repo, then it is allowed" \
  '"$g" "git --git-dir=$TMP/plain/.git commit -m x" && "$g" "GIT_DIR=$TMP/plain/.git git commit -m x"'
check "when only --work-tree names another repo, or GIT_DIR= was on an earlier command, then the commit is still checked here" \
  'blocked "git --work-tree=$TMP/plain commit -m x" && blocked "GIT_WORK_TREE=$TMP/plain git commit -m x" && blocked "GIT_DIR=$TMP/plain/.git true; git commit -m x" && blocked "GIT_DIR=$TMP/plain/.git; git commit -m x"'
check "when a git or gh option that takes a value ends the command, then the guard ends (a loop hangs the hook)" \
  '"$g" "git --git-dir" && "$g" "git -C" && "$g" "git -c" && "$g" "git --namespace" && "$g" "gh pr create --base main -H"'


mkdir -p "$TMP/plain/.specify/extensions/landspec/scripts"; echo 'exit 0' > "$TMP/plain/.specify/extensions/landspec/scripts/guard.sh"
printf 'level: lite\n' > "$TMP/plain/.specify/extensions/landspec/landspec-config.yml"
check "when the repo ships its own guard (stale or tampered), then the plugin's copy decides, not the repo's" \
  'rc=0; json "$TMP/plain" "git add -A" | bash "$shim" 2>/dev/null || rc=$?; [[ $rc == 2 ]]'
mkdir -p "$TMP/plain/sub/.specify"
check "when the guard cannot decide (spec-kit in a subfolder), then it blocks instead of letting the command through" \
  'rc=0; (cd "$TMP/plain/sub" && "$g" "git status") 2>/dev/null || rc=$?; [[ $rc == 2 ]]'

exit "$FAIL"
