---
name: go-template
description: Set up or adopt the Go repository tooling baseline, mise tasks, Git hooks, and GitHub CI. Use when creating a Go repository or bringing an existing one onto this baseline. Configure Homebrew publishing only when requested.
---

# Go repository tooling

Use this skill to apply the repository tooling baseline without `git-tpl`. This skill does not define Go package or application defaults.

The key words "MUST", "MUST NOT", "REQUIRED", "SHALL", "SHALL NOT", "SHOULD", "SHOULD NOT", "RECOMMENDED", "NOT RECOMMENDED", "MAY", and "OPTIONAL" in this document are to be interpreted as described in BCP 14 [RFC2119] [RFC8174] when, and only when, they appear in all capitals, as shown here.

[RFC2119]: https://www.rfc-editor.org/rfc/rfc2119
[RFC8174]: https://www.rfc-editor.org/rfc/rfc8174

## Workflow

1. Inspect the target repository, its instructions, existing configuration, and working tree. Identify conflicts before changing files. Preserve unrelated changes and merge the baseline into existing files rather than overwriting them.
1. Determine the module path and minimum Go version from the project or ask the user. Do not replace an existing module path or Go version without approval. Determine whether Homebrew publishing is requested.
1. Read the relevant files in `references/` relative to this skill. Adapt their project-specific values and merge their configurations into the target. Do not leave template directives or unresolved placeholders in the target.
1. Configure the required tools, tasks, hooks, and CI below. Do not add `git-tpl` or its refresh task. Do not remove existing `git-tpl` configuration unless the user requests removal.
1. Install or resolve dependencies as appropriate, then verify the result. Report any blocked setup or failed check and its cause.

If a required reference is unavailable, the agent MUST report the missing file and MUST NOT claim that the baseline is complete.

## Required baseline

The agent MUST retain the template's development tools and their capabilities, except `git-tpl`:

- In `mise.toml`, configure Go, `hk`, `mdlint`, and `git-review`, and the baseline development, fix, check, and agent-hook tasks. Use `references/mise.toml` as the task reference.
- In `go.mod`, configure the Go tool dependencies in `references/go.mod`: testifylint, go-check-sumtype, errcheck, constable, gosec, gitleaks, nilaway, goimports, govulncheck, staticcheck, and gofumpt. Preserve the compatibility constraint documented there when it remains necessary. Resolve dependencies with `go mod tidy`.
- Configure the commit-message and pre-commit hooks from `references/hk.pkl`. Keep the staged secret scan and formatting behavior. Configure Markdown linting from `references/mdlint.toml`.
- Configure GitHub CI from `references/.github/workflows/ci.yaml`: run the fix task, race-enabled CI tests, and govulncheck on pull requests and manual dispatch. Preserve its least-privilege permissions and pinned actions. Check current action versions before changing pins.

The agent MUST preserve the full baseline task coverage, including Go and Markdown formatting, static analysis, secret scanning, vulnerability checks, tests, coverage, setup, and `on-start` and `on-stop` hooks. For an existing repository, adapt commands to its structure without removing these capabilities.

## Conditional Homebrew publishing

If the user requests Homebrew publishing, the agent MUST configure `.github/workflows/update-tap.yaml` from `references/.github/workflows/update-tap.yaml` using the agreed formula name, tap owner, and tap repository. The agent MUST identify the required GitHub App client ID and private key, tap access, existing formula, and `bin/update-formula` dependency. The agent MUST report any unmet prerequisite rather than claim publishing is ready. Preserve GitHub Actions expressions when adapting the reference.

If Homebrew publishing is not requested, the agent MUST NOT add the publishing workflow. The agent MUST NOT remove an existing publishing workflow without approval.

## Verification

For a repository with Go packages, run `mise run setup`, `mise run fix`, `mise run test`, `mise run check`, and `mise run ci-test` when their prerequisites are available. `mise run setup` changes Git hooks and can remove Lefthook shims; inspect the existing hooks and obtain approval before replacing them. Inspect changes produced by fix tasks. If the repository has no Go packages or a required tool or service is unavailable, report the commands not run and why. Do not claim CI or Homebrew publishing has been verified without exercising it.
