#!/usr/bin/env bash
set -euo pipefail

# Generic CRD API-reference generator. Driven entirely by env vars so it can be
# invoked from a composite action, a reusable workflow, or locally. No
# operator-specific defaults — required values must be set by the caller.

# --- Required ---
: "${OPERATOR_REPO:?OPERATOR_REPO is required (e.g. https://github.com/org/operator.git)}"
: "${API_PATH:?API_PATH is required (e.g. api/group.example.com/v1alpha1, or api/ for all groups)}"
: "${OUTPUT_FILE:?OUTPUT_FILE is required (absolute path to the markdown to write)}"
: "${CONFIG_FILE:?CONFIG_FILE is required (absolute path to crd-ref-docs.yaml)}"

# --- Optional (with defaults) ---
OPERATOR_REF="${OPERATOR_REF:-main}"
CRD_REF_DOCS_VERSION="${CRD_REF_DOCS_VERSION:-v0.3.0}"

# Templates ALWAYS resolved relative to this script so they travel with it.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATES_DIR="${TEMPLATES_DIR:-$SCRIPT_DIR/crd-ref-templates}"

# Scratch area (tool binary + operator clone); never committed.
WORK_DIR="${WORK_DIR:-$PWD/.work}"
LOCALBIN="$WORK_DIR/bin"
CRD_REF_DOCS="$LOCALBIN/crd-ref-docs"

mkdir -p "$LOCALBIN" "$(dirname "$OUTPUT_FILE")"

# 1. Install crd-ref-docs (pinned)
if [ ! -x "$CRD_REF_DOCS" ]; then
  echo "Installing crd-ref-docs $CRD_REF_DOCS_VERSION..."
  GOBIN="$LOCALBIN" go install "github.com/elastic/crd-ref-docs@$CRD_REF_DOCS_VERSION"
fi

# 2. Clone / update the operator repo at the requested ref
if [ -d "$WORK_DIR/operator/.git" ]; then
  git -C "$WORK_DIR/operator" fetch origin "$OPERATOR_REF"
  git -C "$WORK_DIR/operator" checkout "$OPERATOR_REF"
  git -C "$WORK_DIR/operator" reset --hard "origin/$OPERATOR_REF"
else
  git clone --depth=20 --branch "$OPERATOR_REF" "$OPERATOR_REPO" "$WORK_DIR/operator"
fi

# 3. Generate the reference
"$CRD_REF_DOCS" \
  --source-path="$WORK_DIR/operator/$API_PATH" \
  --config="$CONFIG_FILE" \
  --templates-dir="$TEMPLATES_DIR" \
  --renderer=markdown \
  --output-path="$OUTPUT_FILE"

# 4. Post-process (generic fixups for mkdocs strict builds)
# 4a. crd-ref-docs renders nested `map[string]Type` values as a link whose
#     anchor contains brackets (`[map[string]X](#map[string]x)`) — an invalid
#     anchor that fails `mkdocs build --strict`. Strip the link, keep the text.
perl -i -pe 's/\[(map\[string\][A-Za-z0-9]+)\]\(#map\[string\][a-z0-9]+\)/$1/g' "$OUTPUT_FILE"
# 4b. Silence markdownlint on the generated file.
sed -i '1i <!-- markdownlint-disable -->' "$OUTPUT_FILE"

echo "Wrote $OUTPUT_FILE (OPERATOR_REPO=$OPERATOR_REPO, OPERATOR_REF=$OPERATOR_REF, API_PATH=$API_PATH)"
