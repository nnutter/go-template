---

## name: go-template description: Set up or adopt the Go repository tooling baseline, mise tasks, Git hooks, and GitHub CI. Use when creating a Go repository or bringing an existing one onto this baseline. Configure Homebrew publishing only when requested.

# Go repository tooling

Use this skill to apply the repository tooling baseline without `git-tpl`.
This skill does not define Go package or application defaults.

The key words "MUST", "MUST NOT", "REQUIRED", "SHALL", "SHALL NOT", "SHOULD", "SHOULD NOT", "RECOMMENDED", "NOT RECOMMENDED", "MAY", and "OPTIONAL" in this document are to be interpreted as described in BCP 14 [RFC2119] [RFC8174] when, and only when, they appear in all capitals, as shown here.

[RFC2119]: https://www.rfc-editor.org/rfc/rfc2119
[RFC8174]: https://www.rfc-editor.org/rfc/rfc8174

## Workflow

1. Inspect the target repository, its instructions, existing configuration, and working tree.
   Identify conflicts before changing files.
   Preserve unrelated changes and merge the baseline into existing files rather than overwriting them.
1. Determine the module path and minimum Go version from the project or ask the user.
   Do not replace an existing module path or Go version without approval.
   Determine whether Homebrew publishing is requested.
1. Read the relevant files in `references/` relative to this skill.
   Adapt their project-specific values and merge their configurations into the target.
   Do not leave template directives or unresolved placeholders in the target.
1. Configure the required tools, tasks, hooks, and CI below.
   Do not add `git-tpl` or its refresh task.
   Do not remove existing `git-tpl` configuration unless the user requests removal.
1. Install or resolve dependencies as appropriate, then verify the result.
   Report any blocked setup or failed check and its cause.

If a required reference is unavailable, the agent MUST report the missing file and MUST NOT claim that the baseline is complete.

## Required baseline

The agent MUST configure `mise` to install the required tools and `hk` to run formatters and linters.
The agent MUST use suitable `hk` built-ins when available and MUST use custom `hk` steps for the remaining required tools.
Use `references/mise.toml` and `references/hk.pkl` as the configuration references.

- Go: configure `go-fumpt`, `go-imports`, `go-sec`, `go-vet`, `go-vuln-check`, `go-fix`, `staticcheck`, and `gomod-tidy`.
- Pkl: configure `pkl` and `pkl-format`.
- TOML: configure `tombi` and `tombi-format`.
- YAML: configure `yamlfmt`.
- Preserve the existing `testifylint`, `go-check-sumtype`, `errcheck`, `constable`, `gitleaks`, `nilaway`, Markdown linting, and Change-Id capabilities.
- Configure GitHub CI from `references/.github/workflows/ci.yaml` and run the same checks in CI as in the local workflow.
  Preserve its least-privilege permissions and pinned actions.
  Check current action versions before changing pins.

The agent MUST preserve tests, coverage, setup, and the `on-start` and `on-stop` hooks.
The pre-commit hook MUST scan staged content for secrets regardless of file type.
For an existing repository, adapt commands to its structure without removing these capabilities.
Some `hk` Go built-ins operate on a whole module even when given selected files.
The agent MUST account for these effects and MUST NOT silently overwrite unrelated or unstaged changes.
The `go-fix` built-in requires Go 1.26 or later; use a compatible toolchain without silently changing an existing module's minimum Go version.

## Git hook migration

Before installing `hk`, the agent MUST inspect the effective hooks directory and any configured `core.hooksPath`:

```sh
git config --show-origin --show-scope --get-all core.hooksPath
git config --show-origin --show-scope --get-regexp '^hook\.'
git rev-parse --git-path hooks
```

The first 2 commands can exit with status 1 when no matching configuration exists.
Inspect active hooks, symlinks and their targets, and repository configuration and dependencies for existing managers such as Lefthook, Husky, pre-commit, and `hk`.
The agent MUST identify existing hook behavior and preserve nonduplicate behavior in `hk` before removing its previous implementation.
The agent MUST treat hooks as duplicates only when their behavior is demonstrably equivalent.
If equivalence or preservation is uncertain, the agent MUST ask the user before removing either implementation.
The agent MUST obtain approval before removing or replacing hooks or uninstalling a hook manager.

For each manager to remove, consult the uninstall instructions for the installed version and inspect their effects before running them.
For Lefthook, consult `lefthook uninstall --help` or its documentation and use its documented uninstall process after approval.
Do not assume a manager's uninstall command affects only its own files or handles every hooks directory.
After uninstalling, inspect the effective hooks directory again, resolve remaining conflicts, install `hk`, and verify that the preserved behavior runs.
Report any behavior that could not be preserved.

## Conditional Homebrew publishing

If the user requests Homebrew publishing, the agent MUST configure `.github/workflows/update-tap.yaml` from `references/.github/workflows/update-tap.yaml` using the agreed formula name, tap owner, and tap repository.
The agent MUST identify the required GitHub App client ID and private key, tap access, existing formula, and `bin/update-formula` dependency.
The agent MUST report any unmet prerequisite rather than claim publishing is ready.
Preserve GitHub Actions expressions when adapting the reference.

If Homebrew publishing is not requested, the agent MUST NOT add the publishing workflow.
The agent MUST NOT remove an existing publishing workflow without approval.

## Verification

For a repository with Go packages, run `mise run setup`, `mise run fix`, `mise run test`, `mise run check`, and `mise run ci-test` when their prerequisites are available. `mise run setup` changes Git hooks; follow the Git hook migration procedure before running it.
Inspect changes produced by fix tasks.
If the repository has no Go packages or a required tool or service is unavailable, report the commands not run and why.
Do not claim CI or Homebrew publishing has been verified without exercising it.
