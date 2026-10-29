#!/usr/bin/env bash
# Exercise the reference hk entry points in disposable projects. Requires mise,
# Git, network access, and the tools specified by references/mise.toml.
set -euo pipefail

step() { printf '\n=== %s ===\n' "$*"; }

main() {
  local root var
  root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
  project=$(mktemp -d)
  trap 'rm -rf -- "$project"' EXIT

  # Git's rebase environment can redirect commands away from the fixture.
  while IFS='=' read -r var _; do
    case "$var" in GIT_*) unset "$var" ;; esac
  done < <(env)
  export GOSUMDB=off
  export MISE_TRUSTED_CONFIG_PATHS="$project"
  cd -- "$project"
  cp "$root/references/"{go.mod,mise.toml,hk.pkl,mdlint.toml,LICENSE} .
  python3 -c 'from pathlib import Path; p=Path("go.mod"); s=p.read_text().replace("MODULE_PATH", "example.org/integration").replace("GO_VERSION", "1.26.0"); p.write_text(s)'
  git init -q
  git config user.name 'Integration Test'
  git config user.email integration@example.invalid
  mise install

  step 'prepare a complete Go module and clean baseline'
  printf 'package main\n\nfunc main() {}\n' > main.go
  printf 'package main\n\nimport "testing"\n\nfunc TestExample(t *testing.T) {}\n' > main_test.go
  printf '# Demo\n' > README.md
  mise exec -- go mod tidy
  mise exec -- hk validate
  mise exec -- hk fix hk.pkl mise.toml mdlint.toml README.md
  git add .
  git -c core.hooksPath=/dev/null commit -qm Baseline

  step 'behavioral hk integration tests'
  GO_TEMPLATE_TEST_PROJECT="$project" python3 -B "$root/skill-tests/test_references.py" -v

  step 'test and coverage tasks'
  for task in test ci-test coverage; do mise run "$task"; done
  # Coverage output is not source input for the aggregate checks.
  rm -f coverage.out

  step 'aggregate and agent-hook tasks'
  for task in check all on-start on-stop; do mise run "$task"; done
  printf '\nALL ENTRY POINTS OK\n'
}

main "$@"
