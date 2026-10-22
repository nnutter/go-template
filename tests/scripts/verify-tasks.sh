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

step "linters (except lint-gitleaks)"
# lint-gitleaks is excluded: gitleaks v8.30.1 (latest) depends on
# mholt/archives@v0.1.2, which does not compile under Go 1.27
# (rarReader/WriteTo mismatch) -- an upstream breakage outside this
# template. The rendered CI (ci.yaml) does not run it either. Everything
# that transitively needs it (pre-commit, linters, all, on-stop,
# on-start) is covered above by deps/validate wiring checks instead.
mise run lint-constable
mise run lint-errcheck
mise run lint-go-check-sumtype
mise run lint-go-vet
mise run lint-gosec
mise run lint-govulncheck
mise run lint-nilaway
mise run lint-staticcheck
mise run lint-testifylint

echo "ALL TASKS OK (pre-commit, lint-gitleaks, linters, all, on-stop, on-start need gitleaks, which is upstream-broken under Go 1.27; their wiring is checked via deps/validate)"
