# go-template

A [git-tpl](https://noirbizarre.github.io/git-tpl/) template for Go apps.
Only `template/` is rendered into projects; this README, `tests/`, and the
Git history are the template author's side.

## What projects get

| File | How |
|---|---|
| `mise.toml` | Templated (`go` version) — fix/test/lint task graph |
| `lefthook.toml` | Verbatim — pre-commit formatting hook |
| `go.mod` | Templated (`module`, `go`) — tool dependencies only |
| `.github/workflows/ci.yml` | Verbatim — fixers, tests, govulncheck |
| `LICENSE` | Templated (MIT holder + year) |
| `.github/workflows/update-tap.yml` | Only when `with_homebrew` is true — templated formula/tap names, Actions `${{ }}` kept intact via `{% raw %}` |

## Use

```sh
# New project
git tpl init git@github.com:nnutter/go-template.git my-app --init

# Existing project (adopts git-tpl, merges by content)
cd my-app
git tpl init git@github.com:nnutter/go-template.git

# After init in the new project
go mod tidy
mise run install-hooks
```

```sh
# Later, when this template moves on
git tpl status
git tpl update
git tpl diff
git tpl merge
```

## Develop

```sh
mise run lint   # manifest + rendering diagnostics
mise run test   # tests/*.toml cases
```

## Publish

```sh
git remote add origin git@github.com:nnutter/go-template.git
git push -u origin main
gh repo edit --add-topic git-tpl
```
