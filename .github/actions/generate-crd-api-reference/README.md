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

The action clones `operator_repo` over HTTPS. For **private** `stakater-ab`
operators, set `ENABLE_STAKATER_AB_GIT_AUTH: true` and pass the
`STAKATER_AB_REPOS` token secret — the reusable workflow then configures git
(`url.insteadOf`) so the plain `https://github.com/stakater-ab/<operator>.git`
URL clones with auth. This matches the pattern used by the operator
build/push workflows.

```yaml
jobs:
  generate:
    uses: stakater/.github/.github/workflows/generate-api-reference.yaml@main
    with:
      operator_repo: https://github.com/stakater-ab/<operator>.git
      api_path: api/<group>/<version>
      ENABLE_STAKATER_AB_GIT_AUTH: true
    secrets:
      PR_TOKEN: ${{ secrets.PUBLISH_TOKEN }}
      STAKATER_AB_REPOS: ${{ secrets.STAKATER_AB_REPOS }}
```

When calling the **action** directly (not via the reusable workflow), add the
equivalent git-config step before the action in your own workflow:

```yaml
- name: Configure private repo
  run: |
    git config --global url."https://${{ secrets.STAKATER_AB_REPOS }}:x-oauth-basic@github.com/stakater-ab".insteadOf "https://github.com/stakater-ab"
```

## Notes

- `api_path` may point at a single group (`api/group/v1alpha1`) or a parent
  (`api/`) — `crd-ref-docs` recurses, so multi-group operators work unchanged.
- Two generic post-processing fixups keep output `mkdocs build --strict`-clean:
  broken `map[string]Type` anchors are stripped to plain text, and a
  `<!-- markdownlint-disable -->` line is prepended.
- Scratch (`.work/` locally, `RUNNER_TEMP` in CI) is never committed.
