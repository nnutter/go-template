# go-template

An agent skill for standardizing Go repository development tools and CI/CD.
The skill replaces the former `git-tpl` template.

## Use

Install this repository as an agent skill, or make its directory available to your agent's skill loader.
Ask the agent to set up or standardize a Go repository with the `go-template` skill.

Start with [`SKILL.md`](SKILL.md).
Reusable configuration examples are in [`references/`](references/README.md).

## Develop

```sh
mise run check
mise run test
# Uses a disposable repository and downloads Go tool dependencies.
mise run test-integration
```

The skill's requirements apply to target Go repositories, not to this skill repository itself.
