#!/usr/bin/env bash
#
# Verify every mise task in a freshly rendered Go project.
#
# Invoked by tests/tasks.toml as:
#   {{ env.TEMPLATE_ROOT }}/tests/scripts/verify-tasks.sh
# so the working directory is the sandbox holding the rendering, and
# TEMPLATE_ROOT points at this template's checkout.
#
# Rebase safety: `git tpl test` inherits the full environment, and an
# interactive rebase leaks GIT_* (GIT_DIR, GIT_INDEX_FILE, GIT_WORK_TREE,
# GIT_PREFIX, ...) into every child process. Those break the `go` and `git`
# invocations below -- Go shells out to Git for module/VCS info -- so drop
# them up front. Keep GIT_CONFIG_*, which is how git-tpl itself isolates
# the sandbox (GIT_CONFIG_NOSYSTEM, GIT_CONFIG_GLOBAL).
set -eo pipefail

git_vars=$(env | cut -d= -f1 | grep '^GIT_' || true)
# shellcheck disable=SC2086
for var in $git_vars; do
  case "$var" in
    GIT_CONFIG_*) ;;
    *) unset "$var" ;;
  esac
done

step() { echo "=== $* ==="; }

# The checksum DB caches a `latest` timestamp file under GOMODCACHE; on
# some macOS hosts that file carries a restrictive provenance xattr that
# makes it unwritable even for its owner, breaking `go mod tidy` for
# pseudo-versions. The sandbox is throwaway and go.sum still pins hashes,
# so skip third-party witnessing here.
export GOSUMDB=off

step "tidy module (fetch tool deps)"
mise run fix-go-mod-tidy

step "fixtures: Go files in two dirs plus a non-Go file"
mkdir -p sub
printf 'package main\n\nfunc main() {}\n' > main.go
printf 'package sub\n\nfunc Hi() {}\n' > sub/sub.go
printf 'package main\n\nimport "testing"\n\nfunc TestMain(t *testing.T) {}\n' > main_test.go
printf '# demo\n' > README.md

step "regression: single file to go fix"
mise run fix-go-fix ./main.go

step "regression: files in different dirs to go fix"
mise run fix-go-fix ./main.go ./sub/sub.go

step "regression: non-Go files are a no-op for Go fixers"
mise run fix-gofumpt README.md
mise run fix-goimports README.md
mise run fix-go-fix README.md
mise run fix-testifylint README.md

step "regression: mixed Go and non-Go files"
mise run fixers README.md main.go

step "fixers"
mise run fix-gofumpt
mise run fix-goimports
mise run fix-go-fix
mise run fix-testifylint
mise run fixers

step "tests"
mise run tests
mise run ci-tests
mise run coverage

step "regression: install-hooks replaces a pre-existing Lefthook hook"
hooks_dir=$(git rev-parse --git-path hooks)
mkdir -p "$hooks_dir"
printf '#!/bin/sh\n# LEFTHOOK\n' > "$hooks_dir/pre-commit"
mise run install-hooks
if grep -qs LEFTHOOK "$hooks_dir/pre-commit"; then
  echo "lefthook hook survived install-hooks" >&2
  exit 1
fi

step "hooks and task wiring"
# install-hooks runs hk; the rest of this section proves every task
# is defined and wired without executing the gitleaks chain (see below).
mise run install-hooks
mise tasks ls
# (Not `mise tasks validate`: it flags the pre-existing shared `test`
# alias on ci-tests/tests, which is out of scope for this suite.)
mise tasks deps all
mise tasks deps on-start
mise tasks deps on-stop
mise tasks deps linters
mise tasks deps fixers

step "commit-msg hook adds a Change-Id"
msg=$(mktemp)
printf 'Subject\n' > "$msg"
mise exec -- hk run commit-msg "$msg"
grep -q '^Change-Id: ' "$msg"
rm -f "$msg"

step "pre-commit blocks staged secrets"
# Split the key so this script does not contain a literal secret that the
# template's own pre-commit hook would flag.
fake_key="AKIA""Q7M3XNB5TRW2KHLD"
printf 'aws = "%s"\n' "$fake_key" > secret.txt
git add secret.txt
if mise run pre-commit secret.txt; then
  echo "pre-commit did not block a staged secret" >&2
  exit 1
fi
git rm -q --cached secret.txt
rm -f secret.txt

step "pre-commit formats staged Go files"
printf 'package  main\n\nfunc   F( ) {}\n' > fmt_me.go
git add fmt_me.go main.go sub/sub.go main_test.go
mise run pre-commit fmt_me.go main.go sub/sub.go main_test.go
grep -qx 'func F() {}' fmt_me.go

step "linters"
# Runs every lint-* task through the aggregate, so each one is exercised.
mise run linters

step "aggregate and agent-hook tasks"
mise run all
mise run on-start
mise run on-stop main.go

step "refresh-template pulls and merges a template change"
# Use a throwaway clone of the template so the probe commit never touches
# TEMPLATE_ROOT. git-tpl refuses to commit unless user.name and user.email
# are set in git config; environment variables such as GIT_AUTHOR_NAME do
# not satisfy that check, and CI runners have no global identity. Set the
# identity in both repos' local config.
refresh_dir=$(mktemp -d)
git clone -q "$TEMPLATE_ROOT" "$refresh_dir/template"
git -C "$refresh_dir/template" config user.name test
git -C "$refresh_dir/template" config user.email test@example.invalid
mkdir "$refresh_dir/project"
(
  cd "$refresh_dir/project"
  git init -q
  git config user.name test
  git config user.email test@example.invalid
  git commit -q --allow-empty -m init
  git tpl init --defaults --answer project_name=demo "$refresh_dir/template" .
  mise trust -q
  echo "# refreshed" >> "$refresh_dir/template/template/LICENSE.jinja"
  git -C "$refresh_dir/template" commit -qam "probe: change LICENSE"
  mise run refresh-template
  grep -qx '# refreshed' LICENSE
)
rm -rf "$refresh_dir"

echo "ALL TASKS OK"
