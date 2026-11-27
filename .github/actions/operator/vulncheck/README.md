# vulncheck

Run [`govulncheck`](https://pkg.go.dev/golang.org/x/vuln/cmd/govulncheck) against
a Go module and write a findings table to the job summary. Supports an ignore
list and, by default, fails only on vulnerabilities your code actually calls.

The caller must set up Go first (e.g. `actions/setup-go`). `jq` must be on
PATH (it is on GitHub-hosted runners).

## Usage

```yaml
- uses: actions/checkout@v5
- uses: actions/setup-go@v5
  with:
    go-version-file: go.mod
- uses: stakater/.github/.github/actions/operator/vulncheck@main
```

With all inputs:

```yaml
- uses: stakater/.github/.github/actions/operator/vulncheck@main
  with:
    GOVULNCHECK_VERSION: v1.1.4
    IGNORE_FILE: .govulncheck-ignore
    CALLED_ONLY: "true"
    WORKING_DIRECTORY: .
    SCAN_PATTERN: ./...
```

## Inputs

| Input | Default | Description |
|---|---|---|
| `GOVULNCHECK_VERSION` | `latest` | Version for `go install golang.org/x/vuln/cmd/govulncheck@<version>`. Skipped if `govulncheck` is already on PATH. |
| `IGNORE_FILE` | `.govulncheck-ignore` | Ignore list, relative to `WORKING_DIRECTORY`. A missing file means nothing is ignored. |
| `CALLED_ONLY` | `true` | `true`: only called vulnerabilities fail. `false`: imported-only ones fail too. |
| `WORKING_DIRECTORY` | `.` | Directory containing `go.mod`. |
| `SCAN_PATTERN` | `./...` | Package pattern passed to `govulncheck`. |

## How findings are classified

Each advisory gets one status:

| Status | When | Fails the build |
|---|---|---|
| `FAIL` | Called by your code, or imported-only with `CALLED_ONLY: "false"` | yes |
| `informational (imported only)` | Imported but never called, with `CALLED_ONLY: "true"` | no |
| `ignored` | ID is in the ignore file | no |

Example summary:

| ID | Module | Called | Ignored | Status |
|---|---|---|---|---|
| [GO-2025-3521](https://pkg.go.dev/vuln/GO-2025-3521) | golang.org/x/net | yes | no | FAIL |
| [GO-2025-3547](https://pkg.go.dev/vuln/GO-2025-3547) | github.com/foo/bar | no | no | informational (imported only) |

A `govulncheck` tool error (bad module, network failure) also fails the step.

## Ignore file

One advisory ID per line, `#` starts a comment. Add a note on why each is
ignored. See [govulncheck-ignore-example](govulncheck-ignore-example):

```text
# https://pkg.go.dev/vuln/GO-2025-3521 No fix available yet
GO-2025-3521
```

## Run locally

```bash
git clone --depth 1 https://github.com/stakater/.github /tmp/stakater-github

# from your Go module root
bash /tmp/stakater-github/.github/scripts/run-govulncheck.sh
```

Same inputs work as env vars (e.g. `CALLED_ONLY=false`). Needs `go` and `jq`.
