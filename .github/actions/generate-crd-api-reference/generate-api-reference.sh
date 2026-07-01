#!/usr/bin/env bash
set -euo pipefail

# Generic CRD API-reference renderer. Renders markdown from a LOCAL path of Go
# API types using crd-ref-docs, then applies generic post-processing. Checkout
# of any source repos is the caller's responsibility — this script never clones.
# Driven entirely by env vars so it can run from a composite action, a reusable
# workflow, or locally.

# --- Required ---
: "${SOURCE_PATH:?SOURCE_PATH is required (local path to the API types, e.g. api/group.example.com/v1alpha1, or api/ for all groups)}"
: "${OUTPUT_FILE:?OUTPUT_FILE is required (absolute path to the markdown to write)}"
: "${CONFIG_FILE:?CONFIG_FILE is required (absolute path to crd-ref-docs.yaml)}"

# --- Optional (with defaults) ---
CRD_REF_DOCS_VERSION="${CRD_REF_DOCS_VERSION:-v0.3.0}"

# Templates ALWAYS resolved relative to this script so they travel with it.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATES_DIR="${TEMPLATES_DIR:-$SCRIPT_DIR/crd-ref-templates}"

# Scratch area (tool binary only); never committed.
WORK_DIR="${WORK_DIR:-$PWD/.work}"
LOCALBIN="$WORK_DIR/bin"
CRD_REF_DOCS="$LOCALBIN/crd-ref-docs"

mkdir -p "$LOCALBIN" "$(dirname "$OUTPUT_FILE")"

# 1. Install crd-ref-docs (pinned)
if [ ! -x "$CRD_REF_DOCS" ]; then
  echo "Installing crd-ref-docs $CRD_REF_DOCS_VERSION..."
  GOBIN="$LOCALBIN" go install "github.com/elastic/crd-ref-docs@$CRD_REF_DOCS_VERSION"
fi

# 2. Generate the reference from the local source path
"$CRD_REF_DOCS" \
  --source-path="$SOURCE_PATH" \
  --config="$CONFIG_FILE" \
  --templates-dir="$TEMPLATES_DIR" \
  --renderer=markdown \
  --output-path="$OUTPUT_FILE"

# 3. Post-process (generic fixups for mkdocs strict builds)
# 3a. crd-ref-docs renders nested `map[string]Type` values as a link whose
#     anchor contains brackets (`[map[string]X](#map[string]x)`) — an invalid
#     anchor that fails `mkdocs build --strict`. Strip the link, keep the text.
perl -i -pe 's/\[(map\[string\][A-Za-z0-9]+)\]\(#map\[string\][a-z0-9]+\)/$1/g' "$OUTPUT_FILE"
# 3b. Silence markdownlint on the generated file.
sed -i '1i <!-- markdownlint-disable -->' "$OUTPUT_FILE"

echo "Wrote $OUTPUT_FILE (SOURCE_PATH=$SOURCE_PATH)"
