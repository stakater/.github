# generate-crd-api-reference

Generate a CRD API-reference markdown page from an operator's Go types using
[`crd-ref-docs`](https://github.com/elastic/crd-ref-docs). Repo-agnostic; bundles
its own rendering templates and post-processing fixups.

## Turnkey usage (reusable workflow → PR)

In a docs repo, add `crd-ref-docs.yaml` (your operator's ignore rules) and a thin
caller workflow:

```yaml
name: Generate API Reference
on:
  workflow_dispatch:
    inputs:
      operator_ref:
        description: "Operator git ref to generate from"
        required: false
        default: "main"
jobs:
  generate:
    uses: stakater/.github/.github/workflows/generate-api-reference.yaml@main
    with:
      operator_repo: https://github.com/stakater-ab/<operator>.git
      operator_ref: ${{ github.event.inputs.operator_ref }}
      api_path: api/<group>/<version>
      config_file: crd-ref-docs.yaml
      output_file: content/reference/api.md
    secrets:
      PR_TOKEN: ${{ secrets.PUBLISH_TOKEN }}
```

## Direct action usage (custom triggers / PR policy)

```yaml
- uses: actions/checkout@v5
- uses: stakater/.github/.github/actions/generate-crd-api-reference@main
  with:
    operator_repo: https://github.com/stakater-ab/<operator>.git
    api_path: api/<group>/<version>
    config_file: crd-ref-docs.yaml
    output_file: content/reference/api.md
```

## Private operator repos

The action clones `operator_repo` over HTTPS. For **private** operators, pass a
token-authenticated URL or pre-configure a git credential, e.g.:

```yaml
operator_repo: https://x-access-token:${{ secrets.OPERATOR_TOKEN }}@github.com/stakater-ab/<operator>.git
```

## Notes

- `api_path` may point at a single group (`api/group/v1alpha1`) or a parent
  (`api/`) — `crd-ref-docs` recurses, so multi-group operators work unchanged.
- Two generic post-processing fixups keep output `mkdocs build --strict`-clean:
  broken `map[string]Type` anchors are stripped to plain text, and a
  `<!-- markdownlint-disable -->` line is prepended.
- Scratch (`.work/` locally, `RUNNER_TEMP` in CI) is never committed.
