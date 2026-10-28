#!/usr/bin/env bash
# Exercise the reference tasks in a disposable project. Requires mise, Git,
# network access, and the tools specified by references/mise.toml.
set -euo pipefail

step() { printf '\n=== %s ===\n' "$*"; }

main() {
  local root var hooks_dir msg fake_key
  root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
  project=$(mktemp -d)
  trap 'rm -rf -- "$project"' EXIT

  # Git's rebase environment can redirect commands away from the fixture.
  while IFS='=' read -r var _; do
    case "$var" in GIT_CONFIG_*) ;; GIT_*) unset "$var" ;; esac
  done < <(env)
  export GOSUMDB=off
  cd -- "$project"
  cp "$root/references/"{go.mod,mise.toml,hk.pkl,mdlint.toml,LICENSE} .
  # Use a supported Go version and a real module path in the copied reference.
  python3 -c 'from pathlib import Path; p=Path("go.mod"); s=p.read_text().replace("MODULE_PATH", "example.org/integration").replace("GO_VERSION", "1.26.0"); p.write_text(s)'
  git init -q
  git config user.name 'Integration Test'
  git config user.email integration@example.invalid
  mise trust -q
  mise install

  step 'tidy module and create fixtures'
  mise run fix-go-mod-tidy
  mkdir sub
  printf 'package main\n\nfunc main() {}\n' > main.go
  printf 'package sub\n\nfunc Hi() {}\n' > sub/sub.go
  printf 'package main\n\nimport "testing"\n\nfunc TestMain(t *testing.T) {}\n' > main_test.go
  printf '# demo\n' > README.md

  step 'Markdown checks report errors without writing'
  printf '#  Title\n' > dirty.md
  cp dirty.md dirty.md.bak
  if mise run check-mdlint dirty.md; then
    printf 'check-mdlint did not report a format diff\n' >&2; return 1
  fi
  cmp dirty.md dirty.md.bak
  mise run fix-mdlint dirty.md
  mise run check-mdlint dirty.md
  printf '# Title\n\n### Skipped\n' > dirty.md
  cp dirty.md dirty.md.bak
  if mise run check-mdlint dirty.md; then
    printf 'check-mdlint did not report a lint violation\n' >&2; return 1
  fi
  cmp dirty.md dirty.md.bak
  mise run fix-mdlint main.go
  mise run check-mdlint main.go
  rm dirty.md dirty.md.bak

  step 'Go tasks handle single files, multiple directories, and non-Go files'
  mise run fix-go-fix ./main.go
  mise run fix-go-fix ./main.go ./sub/sub.go
  for task in fix-gofumpt fix-goimports fix-go-fix fix-testifylint check-gofumpt check-goimports check-go-fix check-testifylint; do
    mise run "$task" README.md
  done

  step 'Go checks report changes without writing'
  printf 'package  main\n\nfunc   G( ) {}\n' > dirty_fmt.go
  cp dirty_fmt.go dirty_fmt.go.bak
  if mise run check-gofumpt ./dirty_fmt.go; then
    printf 'check-gofumpt did not report a diff with a failing status\n' >&2; return 1
  fi
  cmp dirty_fmt.go dirty_fmt.go.bak
  rm dirty_fmt.go dirty_fmt.go.bak
  printf 'package main\n\nimport (\n\t"fmt"\n\t"os"\n)\n\nfunc H() { fmt.Println("x") }\n' > dirty_imp.go
  cp dirty_imp.go dirty_imp.go.bak
  if mise run check-goimports ./dirty_imp.go; then
    printf 'check-goimports did not report a diff\n' >&2; return 1
  fi
  cmp dirty_imp.go dirty_imp.go.bak
  rm dirty_imp.go dirty_imp.go.bak
  mkdir fixdir
  printf 'package fixdir\n\nvar y interface{}\n\nfunc use() { _ = y }\n' > fixdir/dirty_fix.go
  cp fixdir/dirty_fix.go fixdir/dirty_fix.go.bak
  if mise run check-go-fix ./fixdir/dirty_fix.go; then
    printf 'check-go-fix did not report a diff\n' >&2; return 1
  fi
  cmp fixdir/dirty_fix.go fixdir/dirty_fix.go.bak
  rm -r fixdir

  step 'fix and test tasks'
  mise run fix README.md main.go
  for task in fix-gofumpt fix-goimports fix-go-fix fix-testifylint fix test ci-test coverage; do
    mise run "$task"
  done

  step 'setup preserves existing hooks'
  hooks_dir=$(git rev-parse --git-path hooks)
  mkdir -p "$hooks_dir"
  printf '#!/bin/sh\n# LEFTHOOK\n' > "$hooks_dir/pre-commit"
  if ! mise run setup; then
    printf 'setup refused an existing hook; checking that it was preserved\n'
  fi
  if ! grep -qs LEFTHOOK "$hooks_dir/pre-commit"; then
    printf 'setup changed the existing hook\n' >&2; return 1
  fi
  # Simulate an approved migration in this disposable repository.
  rm "$hooks_dir/pre-commit"
  mise run setup
  mise tasks ls
  for task in all on-start on-stop check fix; do mise tasks deps "$task"; done

  step 'commit message hook adds a Change-Id'
  msg="$project/message"
  printf 'Subject\n' > "$msg"
  mise exec -- hk run commit-msg "$msg"
  grep -q '^Change-Id: ' "$msg"
  rm "$msg"

  step 'pre-commit blocks staged secrets'
  fake_key="AKIA""Q7M3XNB5TRW2KHLD"
  printf 'aws = "%s"\n' "$fake_key" > secret.txt
  git add secret.txt
  if mise run pre-commit secret.txt; then
    printf 'pre-commit did not block a staged secret\n' >&2; return 1
  fi
  git rm -q --cached secret.txt
  rm secret.txt

  step 'pre-commit formats staged Go and Markdown files'
  printf 'package  main\n\nfunc   F( ) {}\n' > fmt_me.go
  git add fmt_me.go main.go sub/sub.go main_test.go
  mise run pre-commit fmt_me.go main.go sub/sub.go main_test.go
  grep -qx 'func F() {}' fmt_me.go
  printf '#  Markdown\n' > staged.md
  printf '#  Untouched\n' > unstaged.md
  git add staged.md
  mise exec -- hk run pre-commit
  grep -qx '# Markdown' staged.md
  git show :staged.md | grep -qx '# Markdown'
  grep -qx '#  Untouched' unstaged.md
  git rm -q --cached staged.md
  rm staged.md unstaged.md

  step 'aggregate and agent-hook tasks'
  for task in check all on-start; do mise run "$task"; done
  mise run on-stop main.go
  printf '\nALL TASKS OK\n'
}

main "$@"
