# Reference files

Copy these files to the matching paths in the target project.
Replace these placeholders before you use the files:

- `MODULE_PATH`: the Go module path.
- `GO_VERSION`: the minimum Go version, such as `1.27.3`.
- `COPYRIGHT_YEAR`: the copyright year.
- `COPYRIGHT_HOLDER`: the copyright holder.

Copy `.github/workflows/update-tap.yaml` only when the project publishes a Homebrew formula.
Replace `FORMULA_NAME_PLACEHOLDER`, `TAP_OWNER_PLACEHOLDER`, and `TAP_REPOSITORY_PLACEHOLDER` with the formula name, tap owner, and tap repository.
The tap must provide `bin/update-formula`.
Configure the `APP_CLIENT_ID` repository variable and `APP_PRIVATE_KEY` secret for a GitHub App that can write to the tap and open pull requests.

Keep GitHub Actions expressions such as `${{ github.ref }}` and hk placeholders such as `{{files}}` unchanged.
Run `go mod tidy` to resolve the Go tool dependencies.
Run `mise run setup` to install the Git hooks.
