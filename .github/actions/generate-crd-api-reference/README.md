# generate-crd-api-reference

Render a CRD API-reference markdown page from a **local** path of an operator's
Go types using [`crd-ref-docs`](https://github.com/elastic/crd-ref-docs).
Repo-agnostic; bundles its own rendering templates and post-processing fixups.
It does **not** clone — checking out sources is the caller's job.

## Model

The generator runs in the **operator** repo's CI: it reads the operator's own
Go types locally (no cross-repo read of private operator code), renders the
reference, and opens a PR in the **docs** repo. The only cross-repo access
needed is **write** to the docs repo, via `DOCS_TOKEN` (the operator's existing
broad-access token, e.g. `STAKATER_AB_REPOS`).

## Turnkey usage (reusable workflow → PR in the docs repo)

Add `crd-ref-docs.yaml` (your operator's ignore rules) to the **operator** repo
and a caller workflow:

```yaml
name: Generate API Reference
on:
  release:
    types: [published]
  workflow_dispatch:
jobs:
  generate:
    uses: stakater/.github/.github/workflows/generate-api-reference.yaml@main
    with:
      docs_repo: stakater/<operator>-docs
      source_path: api/<group>/<version>
      config_file: crd-ref-docs.yaml
      output_file: content/reference/api.md
    secrets:
      DOCS_TOKEN: ${{ secrets.STAKATER_AB_REPOS }}
```

## Direct action usage (render only, custom delivery)

Check out whatever you need, then point the action at a local `source_path`:

```yaml
- uses: actions/checkout@v5   # the operator repo — has the Go types + config
- uses: stakater/.github/.github/actions/generate-crd-api-reference@main
  with:
    source_path: api/<group>/<version>
    config_file: crd-ref-docs.yaml
    output_file: content/reference/api.md
```

The action renders `output_file` from the local `source_path`; committing,
pushing, and PR policy are up to your workflow.

## Run locally

```bash
git clone --depth 1 https://github.com/stakater/.github /tmp/stakater-github
ACTION=/tmp/stakater-github/.github/actions/generate-crd-api-reference

# from your operator repo root
SOURCE_PATH="$PWD/api/<group>/<version>" \
CONFIG_FILE="$PWD/crd-ref-docs.yaml" \
OUTPUT_FILE="$PWD/api.md" \
bash "$ACTION/generate-api-reference.sh"
```

Needs `go` and `perl` on PATH. Templates resolve automatically (sibling of the
script).

## Notes

- `source_path` may point at a single group (`api/group/v1alpha1`) or a parent
  (`api/`) — `crd-ref-docs` recurses, so multi-group operators work unchanged.
- Two generic post-processing fixups keep output `mkdocs build --strict`-clean:
  broken `map[string]Type` anchors are stripped to plain text, and a
  `<!-- markdownlint-disable -->` line is prepended.
- Scratch (`.work/` locally, `RUNNER_TEMP` in CI) is never committed.
