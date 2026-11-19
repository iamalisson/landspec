#!/usr/bin/env bash
# shellcheck disable=SC2016,SC2034  # checks are strings evaluated by check()
# shellcheck source=helpers.sh
source "$(dirname "$0")/helpers.sh"
fake_gh
fake_terraform
t="$SCRIPTS/tfplan.sh"
# later <file>: its mtime 2 seconds from now (bash 3.2's -nt compares whole seconds). GNU, then BSD touch.
later() { local s=$(($(date +%s) + 2)); touch -d "@$s" "$1" 2>/dev/null || touch -t "$(date -r "$s" +%Y%m%d%H%M.%S)" "$1"; }
rec() { (source "$SCRIPTS/lib.sh"; diff_record landspec-tfplan); }
# record <root> [args]: plan in <root> and record it from there, as the refusal tells the user to.
record() { echo plan > "$1/tfplan"; later "$1/tfplan"; (cd "$1" && bash "$t" record tfplan "${@:2}"); }
# nopy: every system tool but python, plus the fakes.
mkdir -p "$TMP/nopy"
for f in /usr/local/bin/* /usr/bin/* /bin/*; do
  n="${f##*/}"; case "$n" in python*) continue ;; esac
  [[ -e "$TMP/nopy/$n" || -L "$TMP/nopy/$n" ]] || ln -s "$f" "$TMP/nopy/$n"
done
NOPY="$TMP/bin:$TMP/nopy"

cat > "$TMP/plan.json" <<'EOF'
{"format_version": "1.2", "planned_values": {}, "variables": {"db_password": {"value": "hunter2hunter2"}},
 "resource_changes": [
  {"address": "aws_instance.web", "type": "aws_instance", "change": {"actions": ["create"], "after": {"user_data": "hunter2hunter2"}}},
  {"address": "aws_security_group.web", "type": "aws_security_group", "change": {"actions": ["update"]}},
  {"address": "aws_db_instance.main", "type": "aws_db_instance", "change": {"actions": ["delete", "create"], "after": {"master_pw": "hunter2hunter2"}, "after_sensitive": {"master_pw": true}}},
  {"address": "aws_s3_bucket.logs", "type": "aws_s3_bucket", "change": {"actions": ["delete"]}},
  {"address": "aws_iam_role.kept", "type": "aws_iam_role", "change": {"actions": ["forget"]}},
  {"address": "aws_instance.same", "type": "aws_instance", "change": {"actions": ["no-op"]}}
 ]}
EOF
cat > "$TMP/plan.txt" <<'EOF'
Terraform will perform the following actions:

  # aws_db_instance.main must be replaced
-/+ resource "aws_db_instance" "main" {
      ~ password  = (sensitive value)
      + user_data = <<-EOT
            hunter2hunter2
            # aws_kms_key.not_a_header will be destroyed
        EOT
    }

  # aws_instance.web will be created
  + resource "aws_instance" "web" {
      + user_data = "hunter2hunter2"
    }

  # aws_s3_bucket.logs will be destroyed
  - resource "aws_s3_bucket" "logs" {}

  # aws_security_group.web will be updated in-place
  ~ resource "aws_security_group" "web" {}

Plan: 2 to add, 1 to change, 2 to destroy.
EOF
export TF_PLAN_JSON="$TMP/plan.json" TF_PLAN_TEXT="$TMP/plan.txt"
want='PLAN=create 2 change 1 destroy 2
STATEFUL=replace aws_db_instance.main
STATEFUL=destroy aws_s3_bucket.logs'

new_repo standard
printf 'tfplan\n' >> .gitignore # the planfile is never committed
mkdir -p infra/envs/dev infra/envs/prod infra/modules/db infra/modules/net
printf 'module "db" {\n  source = "../../modules/db"\n}\n' > infra/envs/dev/main.tf
printf 'module "db" {\n  source  = "../../modules/db/"\n  version = "x"\n}\nmodule "vpc" {\n  source = "terraform-aws-modules/vpc/aws"\n}\n' > infra/envs/prod/main.tf
printf 'module "net" {\n  source = "../net"\n}\n' > infra/modules/db/main.tf
echo 'resource "aws_vpc" "main" {}' > infra/modules/net/main.tf
commit_tasks '- [ ] T001 Add infra in `infra/main.tf`'
"$SCRIPTS/branch.sh" 001 >/dev/null
echo 'resource "aws_db_instance" "main" {}' >> infra/modules/db/main.tf; git commit --quiet -am "feat: db"

out="$(record infra/envs/dev)"
check "when a JSON plan has a create, an update, a replace and a destroy, then it prints the counts as Terraform's Plan: line and the stateful lines" \
  '[[ "$out" == "$want" ]]'
check "then the record holds the root's section with the addresses only" \
  '[[ "$(cat "$(rec)")" == "$(printf "[infra/envs/dev]\ncreate 2\nchange 1\ndestroy 2\nreplace aws_db_instance.main\ndestroy aws_s3_bucket.logs")" ]]'
here="$(pwd -P)" # macOS: $TMP is under a symlink (/var -> /private/var), and the script logs the physical path
# python3 is optional (the busybox image has none): the checks of the JSON reader alone run where it is.
if command -v python3 >/dev/null; then
  check "then it read the JSON form, in the root's folder" 'grep -qx "show -json $here/infra/envs/dev/tfplan" "$TF_LOG"'
fi
check "then the sensitive value is in neither the record nor the output" '! grep -rq hunter2hunter2 "$(dirname "$(rec)")" && [[ "$out" != *hunter2* ]]'
: > "$TF_LOG"
out="$(PATH="$NOPY" record infra/envs/dev)"
check "when python3 is missing, then the text form gives the same lines, a value deeper in never passing for a header" '[[ "$out" == "$want" ]]'
check "then it read the text form, and the record is the same, with the sensitive value nowhere" \
  'grep -qx "show -no-color $here/infra/envs/dev/tfplan" "$TF_LOG" && ! grep -q -- -json "$TF_LOG" && [[ "$(grep -c . "$(rec)")" == 6 ]] && ! grep -rq hunter2hunter2 "$(dirname "$(rec)")"'

record infra/envs/prod >/dev/null
record infra/envs/dev >/dev/null
check "when a second root is recorded, then it adds a section; recording the first again replaces its section, not adds one" \
  '[[ "$(grep -c "^\[" "$(rec)")" == 2 && "$(grep -c "^\[infra/envs/dev\]$" "$(rec)")" == 1 && "$(grep -c "^replace aws_db_instance.main$" "$(rec)")" == 2 ]]'
record infra/envs/dev --chdir ../prod >/dev/null
check "when --chdir names the root, then that root's section is the one written" '[[ "$(grep -c "^\[" "$(rec)")" == 2 && "$(grep -c "^\[infra/envs/prod\]$" "$(rec)")" == 1 ]]'

if command -v python3 >/dev/null; then
printf '{"format_version": "1.2", "planned_values": {}, "resource_changes": [{"address": "aws_instance.tmp", "type": "aws_instance", "change": {"actions": ["delete"]}}, {"address": "aws_iam_role.r", "type": "aws_iam_role", "change": {"actions": ["create", "delete"]}}]}\n' > "$TMP/plain.json"
out="$(TF_PLAN_JSON="$TMP/plain.json" record infra/envs/dev)"
check "when only stateless resources are destroyed or replaced, then no STATEFUL line, and create-then-delete counts as a replace" '[[ "$out" == "PLAN=create 1 change 0 destroy 2" ]]'
fi
printf 'No changes. Your infrastructure matches the configuration.\n' > "$TMP/none.txt"
out="$(PATH="$NOPY" TF_PLAN_TEXT="$TMP/none.txt" record infra/envs/dev)"
check "when the text plan says No changes., then it records the root with no counts" \
  '[[ "$out" == "PLAN=create 0 change 0 destroy 0" ]] && sed -n "/^\[infra\/envs\/dev\]$/,/^\[/p" "$(rec)" | gq -vE "^(create|change|destroy)"'
printf 'Plan: 1 to import, 3 to add, 0 to change, 1 to destroy, 2 to forget.\n' > "$TMP/import.txt"
check "when the Plan: line also has import and forget counts, then only add, change and destroy are read" \
  '[[ "$(PATH="$NOPY" TF_PLAN_TEXT="$TMP/import.txt" record infra/envs/dev)" == "PLAN=create 3 change 0 destroy 1" ]]'

rm -f "$(rec)"
check "when the text output has neither a Plan: line nor No changes., then it refuses and writes no record" \
  'echo "Error: nothing" > "$TMP/bad.txt"; ! PATH="$NOPY" TF_PLAN_TEXT="$TMP/bad.txt" record infra/envs/dev && [[ ! -f "$(rec)" ]]'
if command -v python3 >/dev/null; then
check "when the JSON is not a plan, then it refuses and writes no record" \
  'echo "{}" > "$TMP/bad.json"; ! TF_PLAN_JSON="$TMP/bad.json" record infra/envs/dev && [[ ! -f "$(rec)" ]]'
check "when the JSON is a state file (format_version, no planned_values), then it refuses and writes no record" \
  'echo "{\"format_version\": \"1.0\", \"values\": {}}" > "$TMP/state.json"; ! TF_PLAN_JSON="$TMP/state.json" record infra/envs/dev && [[ ! -f "$(rec)" ]]'
fi
printf '  # aws_rds_cluster.main is tainted, so must be replaced\n  # aws_kms_key.k will be replaced, as requested\n\nPlan: 2 to add, 0 to change, 2 to destroy.\n' > "$TMP/taint.txt"
check "when the text plan has a tainted and a requested replace, then both are STATEFUL=replace lines with the bare address" \
  '[[ "$(PATH="$NOPY" TF_PLAN_TEXT="$TMP/taint.txt" record infra/envs/dev)" == "$(printf "PLAN=create 2 change 0 destroy 2\nSTATEFUL=replace aws_rds_cluster.main\nSTATEFUL=replace aws_kms_key.k")" ]]'
rm -f "$(rec)"
echo corrupt > infra/envs/dev/tfplan; later infra/envs/dev/tfplan
check "when terraform cannot read the plan file, then it exits 1 and writes no record" \
  'set +e; (cd infra/envs/dev && bash "$t" record tfplan); rc=$?; set -e; ((rc == 1)) && [[ ! -f "$(rec)" ]]'
check "when the plan file does not exist, then it refuses naming it" 'fails_with "cannot read the plan file nosuch" bash "$t" record nosuch'
echo plan > infra/envs/dev/tfplan; touch -t 200001010000 infra/envs/dev/tfplan
check "when the plan file is older than the last commit, then it exits 1 saying to plan again, and writes no record" \
  '(cd infra/envs/dev && fails_with "plan again after the last commit, checkout or rebase" bash "$t" record tfplan) && [[ ! -f "$(rec)" ]]'
later infra/envs/dev/tfplan; echo '# edit' >> infra/envs/dev/main.tf
check "when a .tf file is uncommitted, then it exits 1 saying to plan again" \
  '(cd infra/envs/dev && fails_with "plan again after the last commit, checkout or rebase" bash "$t" record tfplan) && [[ ! -f "$(rec)" ]]'
git checkout --quiet -- infra/envs/dev/main.tf
check "when the plan file is newer than the last commit and every .tf is committed, then it records" '(cd infra/envs/dev && bash "$t" record tfplan) && [[ -f "$(rec)" ]]'
check "when the root is outside the repository, then it refuses" 'fails_with "outside the repository" bash "$t" record infra/envs/dev/tfplan --chdir "$TMP"'

# ── The gate pr.sh runs: aws_prod_paths and the modules a root uses ──
rm -f "$(rec)"
printf 'aws: on\naws_prod_paths: infra/envs/prod\n' >> .specify/extensions/landspec/landspec-config.yml
check "when aws is on and the diff touches a .tf file with no record, then the gate refuses naming infra_dir" \
  'one_refusal "no Terraform plan recorded for this diff; run terraform plan -out=tfplan in infra, then bash .specify/extensions/landspec/scripts/tfplan.sh record tfplan" bash "$t" gate'
record infra/envs/dev >/dev/null
check "when a module used by the prod root changed and only dev was recorded, then the gate refuses naming infra/envs/prod" \
  'one_refusal "run terraform plan -out=tfplan in infra/envs/prod, then" bash "$t" gate'
record infra/envs/prod >/dev/null; record infra/envs/dev >/dev/null
out="$(bash "$t" gate)"
check "when both roots are recorded, then the section has one block per root, stateful lines first" \
  '[[ "$(head -1 <<<"$out")" == "## Terraform plan" && "$(grep -c "^### " <<<"$out")" == 2 ]] && grep -qx "### infra/envs/dev" <<<"$out" && grep -qx "### infra/envs/prod" <<<"$out" \
   && [[ "$(grep -A6 -x "### infra/envs/dev" <<<"$out" | tail -6)" == "$(printf "\n**Destroys or replaces stateful resources:**\n- replace \`aws_db_instance.main\`\n- destroy \`aws_s3_bucket.logs\`\n\ncreate 2 · change 1 · destroy 2")" ]]'
git switch --quiet -c tmp-net origin/develop
echo '# net' >> infra/modules/net/main.tf; git commit --quiet -am "feat: net"
record infra/envs/dev >/dev/null
check "when only a module used through another module changes (prod uses db, db uses net), then the prod root still needs its own section" \
  'one_refusal "in infra/envs/prod, then" bash "$t" gate'
git switch --quiet -c tmp-dev-only origin/develop
echo '# dev only' >> infra/envs/dev/main.tf; git commit --quiet -am "feat: dev"
check "when the diff touches only the dev root, then a dev record is enough: prod's section is not needed" \
  'record infra/envs/dev >/dev/null && bash "$t" gate | gq -x "### infra/envs/dev"'
git switch --quiet -c tmp-rm origin/develop
git rm --quiet infra/envs/prod/main.tf; git commit --quiet -m "chore: drop prod"; rmdir infra/envs/prod 2>/dev/null || true
set_cfg aws_prod_paths "infra/envs/none, ./infra/envs/prod/"
check "when the diff deletes a prod root (listed with a space and ./), then the gate still wants its section" \
  'record infra/envs/dev >/dev/null && one_refusal "in infra/envs/prod, then" bash "$t" gate'
set_cfg aws_prod_paths infra/envs/prod
git switch --quiet -c tmp-mv origin/develop
mkdir -p infra/old; git mv infra/envs/prod/main.tf infra/old/main.tf; git commit --quiet -m "chore: move prod"
check "when a commit moves a prod .tf file elsewhere and only another root is recorded, then the gate refuses naming infra/envs/prod" \
  'record infra/envs/dev >/dev/null && one_refusal "in infra/envs/prod, then" bash "$t" gate'
set_cfg aws off
check "when aws is off, then the gate prints nothing and lets it through, record or not" 'rm -f "$(rec)"; [[ -z "$(bash "$t" gate)" ]]'
set_cfg aws on; set_cfg level lite
check "when the level is lite, then the gate prints nothing and lets it through" '[[ -z "$(bash "$t" gate)" ]]'
set_cfg level standard
git switch --quiet -c tmp-no-tf "$(git merge-base HEAD origin/develop)"; echo doc > README.txt; git add README.txt; git commit --quiet -m "docs: readme"
check "when the diff touches no .tf file, then the gate prints nothing and lets it through" '[[ -z "$(bash "$t" gate)" ]]'

# ── Spec 006 T009: infrastructure code that is not Terraform gets a Skipped line ──
base="$(git merge-base HEAD origin/develop)"
# only <branch> <path>...: a branch from the base whose diff is exactly these new files.
only() { git switch --quiet -c "$1" "$base"; shift; local f; for f; do mkdir -p "$(dirname "$f")"; echo x > "$f"; done; git add -- "$@"; git commit --quiet -m "chore: $1"; }
skipped() { printf '## Terraform plan\n\nSkipped: this diff changes infrastructure code that is not Terraform (%s); the plan gate covers Terraform only.' "$1"; }
only tmp-cdk cdk/cdk.json
check "when the diff has only cdk/cdk.json, then the gate prints the section with the Skipped line naming it" '[[ "$(bash "$t" gate)" == "$(skipped cdk/cdk.json)" ]]'
only tmp-pulumi stack/Pulumi.dev.yaml
check "when the diff has only stack/Pulumi.dev.yaml, then the Skipped line names it" '[[ "$(bash "$t" gate)" == "$(skipped stack/Pulumi.dev.yaml)" ]]'
only tmp-cfn deploy/app.template.yaml
check "when the diff has only deploy/app.template.yaml, then the Skipped line names it" '[[ "$(bash "$t" gate)" == "$(skipped deploy/app.template.yaml)" ]]'
only tmp-three cdk.json Pulumi.yaml a/b.template.json
check "when three files match, then the Skipped line names all three in git diff order with no \"more\"" \
  '[[ "$(bash "$t" gate)" == "$(skipped "Pulumi.yaml, a/b.template.json, cdk.json")" ]]'
only tmp-four cdk.json Pulumi.yaml a/b.template.json c/Pulumi.prod.yml
check "when four files match, then the Skipped line names the first 3, then and 1 more" \
  '[[ "$(bash "$t" gate)" == "$(skipped "Pulumi.yaml, a/b.template.json, c/Pulumi.prod.yml and 1 more")" ]]'
only tmp-five cdk.json Pulumi.yaml a/b.template.json c/Pulumi.prod.yml d/e.template.yml src/notcdk.json
check "when five files match, then the Skipped line names the first 3 in git diff order, then and 2 more" \
  '[[ "$(bash "$t" gate)" == "$(skipped "Pulumi.yaml, a/b.template.json, c/Pulumi.prod.yml and 2 more")" ]]'
only tmp-tf-cdk infra/main.tf cdk.json
check "when the diff has a .tf file and cdk.json with no plan recorded, then the gate still refuses, with no Skipped line" \
  'rm -f "$(rec)"; one_refusal "no Terraform plan recorded for this diff" bash "$t" gate && ! bash "$t" gate 2>&1 | gq Skipped'
printf 'infra_dir: .\n' >> .specify/extensions/landspec/landspec-config.yml
only tmp-app src/app.py
check "when the diff has only src/app.py, with infra_dir ., then the gate prints nothing" '[[ -z "$(bash "$t" gate)" ]]'
set_cfg infra_dir infra
only tmp-tfvars infra/terraform.tfvars infra/.terraform.lock.hcl infra/x.tf.json
check "when the diff has only Terraform companions (tfvars, lock file, .tf.json), then the gate prints nothing" '[[ -z "$(bash "$t" gate)" ]]'
git switch --quiet tmp-cdk
set_cfg aws off
check "when aws is off and the diff has cdk.json, then the gate prints nothing" '[[ -z "$(bash "$t" gate)" ]]'
set_cfg aws on; set_cfg level lite
check "when the level is lite and the diff has cdk.json, then the gate prints nothing" '[[ -z "$(bash "$t" gate)" ]]'
set_cfg level standard
check "when tfplan.sh gets no subcommand, then it prints its usage" 'fails_with "usage: tfplan.sh record" bash "$t"'

exit "$FAIL"
