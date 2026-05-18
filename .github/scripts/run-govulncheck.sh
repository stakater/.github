#!/usr/bin/env bash
set -uo pipefail

# =============================================================================
# govulncheck Runner
# =============================================================================
# Runs govulncheck against a Go module and renders a condensed Markdown
# summary table. Supports a plain-text ignore file and an option to fail
# only on called (reachable) vulnerabilities.
#
# Usage:
#   ./run-govulncheck.sh
#
# Environment Variables:
#   GOVULNCHECK_VERSION   govulncheck version for 'go install' (default: latest)
#   IGNORE_FILE           Path to ignore file, relative to WORKING_DIRECTORY
#                         (default: .govulncheck-ignore). Missing file is OK.
#   CALLED_ONLY           When "true", only called vulnerabilities fail the
#                         script. Imported-only findings appear in the summary
#                         but don't cause a non-zero exit. (default: true)
#   WORKING_DIRECTORY     Directory containing go.mod (default: .)
#   SCAN_PATTERN          Package pattern passed to govulncheck (default: ./...)
#
# Outputs:
#   - Markdown table to $GITHUB_STEP_SUMMARY if set, else stdout-only.
#   - Same table echoed to stdout.
#
# Exit codes:
#   0   No unignored, non-informational findings.
#   1   At least one unignored finding qualifies as FAIL (or a tool error).
#
# Prerequisites: a working Go toolchain on PATH (for installing govulncheck if
# missing), plus jq.
# =============================================================================

GOVULNCHECK_VERSION=${GOVULNCHECK_VERSION:-latest}
IGNORE_FILE=${IGNORE_FILE:-.govulncheck-ignore}
CALLED_ONLY=${CALLED_ONLY:-true}
WORKING_DIRECTORY=${WORKING_DIRECTORY:-.}
SCAN_PATTERN=${SCAN_PATTERN:-./...}

# Colors (only emit ANSI when stdout is a TTY).
if [ -t 1 ]; then
  RED=$'\033[0;31m'
  GREEN=$'\033[0;32m'
  YELLOW=$'\033[1;33m'
  BLUE=$'\033[0;34m'
  NC=$'\033[0m'
else
  RED=""; GREEN=""; YELLOW=""; BLUE=""; NC=""
fi

log_info()    { echo "${BLUE}[INFO]${NC} $1"; }
log_success() { echo "${GREEN}[SUCCESS]${NC} $1"; }
log_warning() { echo "${YELLOW}[WARNING]${NC} $1" >&2; }
log_error()   { echo "${RED}[ERROR]${NC} $1" >&2; }

check_prerequisites() {
  if ! command -v jq &> /dev/null; then
    log_error "jq is required but not found in PATH"
    exit 1
  fi
  if ! command -v go &> /dev/null; then
    log_error "go is required but not found in PATH"
    exit 1
  fi
}

install_govulncheck_if_missing() {
  if command -v govulncheck &> /dev/null; then
    log_info "govulncheck already on PATH ($(command -v govulncheck))"
    return 0
  fi
  log_info "Installing govulncheck@${GOVULNCHECK_VERSION}"
  go install "golang.org/x/vuln/cmd/govulncheck@${GOVULNCHECK_VERSION}"
  # 'go install' places binaries in $GOBIN or $GOPATH/bin; ensure it's on PATH.
  GOBIN_DIR=$(go env GOBIN)
  if [ -z "$GOBIN_DIR" ]; then
    GOBIN_DIR="$(go env GOPATH)/bin"
  fi
  export PATH="$GOBIN_DIR:$PATH"
  if ! command -v govulncheck &> /dev/null; then
    log_error "govulncheck not found on PATH after install (expected in $GOBIN_DIR)"
    exit 1
  fi
}

main() {
  check_prerequisites
  install_govulncheck_if_missing

  cd "$WORKING_DIRECTORY"

  local json_file err_file summary
  json_file="${RUNNER_TEMP:-/tmp}/govulncheck.json"
  err_file="${RUNNER_TEMP:-/tmp}/govulncheck.err"
  summary="${GITHUB_STEP_SUMMARY:-/dev/null}"

  log_info "Running govulncheck (scan=symbol, pattern=${SCAN_PATTERN}) in $(pwd)"

  # govulncheck exits 3 when vulns are present; treat as expected.
  set +e
  govulncheck -format=json -scan symbol "$SCAN_PATTERN" > "$json_file" 2> "$err_file"
  local gvc_exit=$?
  set -e

  case "$gvc_exit" in
    0)
      log_success "No vulnerabilities found."
      {
        echo "## govulncheck"
        echo
        echo "No vulnerabilities found."
      } >> "$summary"
      exit 0
      ;;
    3)
      ;;
    *)
      log_error "govulncheck failed with exit code $gvc_exit"
      cat "$err_file" >&2
      exit 1
      ;;
  esac

  # Load ignore list: strip '#' comments and blank lines; trim whitespace.
  local ignore_list=""
  if [ -f "$IGNORE_FILE" ]; then
    ignore_list=$(sed -E 's/#.*$//; s/^[[:space:]]+//; s/[[:space:]]+$//' "$IGNORE_FILE" | grep -v '^$' || true)
    log_info "Loaded ignore file: $IGNORE_FILE"
  else
    log_info "Ignore file '$IGNORE_FILE' not found; using empty ignore list."
  fi

  local rows_json
  if ! rows_json=$(jq -s \
    --arg ignore_list "$ignore_list" \
    --arg called_only "$CALLED_ONLY" '
    ($ignore_list | split("\n") | map(select(length > 0))) as $ignored
    | (map(select(.finding != null)) | map(.finding)) as $findings
    | ($findings | group_by(.osv)) as $by_id
    | $by_id
    | map({
        id: .[0].osv,
        module: (
          [ .[] | (.trace // [])[] | .module ]
          | map(select(. != null and . != ""))
          | (if length > 0 then .[0] else "(unknown)" end)
        ),
        called: (any(.[]; ((.trace // [])[0].function // "") != "")),
        ignored: ((.[0].osv) as $oid | ($ignored | index($oid)) != null),
      }
      | .status = (
          if .ignored then "ignored"
          elif .called then "FAIL"
          elif ($called_only == "true") then "informational (imported only)"
          else "FAIL"
          end
        )
    )
    | sort_by(
        if .status == "FAIL" then 0
        elif (.status | startswith("informational")) then 1
        else 2
        end
      )
  ' "$json_file"); then
    log_error "Failed to parse govulncheck JSON output."
    echo "--- first 50 lines of raw output ---" >&2
    head -n 50 "$json_file" >&2
    exit 1
  fi

  local table_head table_body
  table_head=$'| ID | Module | Called | Ignored | Status |\n|---|---|---|---|---|'
  table_body=$(printf '%s' "$rows_json" | jq -r '
    .[] | "| [\(.id)](https://pkg.go.dev/vuln/\(.id)) | \(.module) | \(if .called then "yes" else "no" end) | \(if .ignored then "yes" else "no" end) | \(.status) |"
  ')

  {
    echo "## govulncheck"
    echo
    echo "$table_head"
    echo "$table_body"
  } >> "$summary"

  echo "$table_head"
  echo "$table_body"

  local fail_count
  fail_count=$(printf '%s' "$rows_json" | jq '[.[] | select(.status == "FAIL")] | length')
  if [ "$fail_count" -gt 0 ]; then
    log_error "govulncheck found $fail_count unignored vulnerability/vulnerabilities"
    # Also emit the GitHub Actions ::error:: annotation when running in CI.
    if [ -n "${GITHUB_ACTIONS:-}" ]; then
      echo "::error::govulncheck found $fail_count unignored vulnerability/vulnerabilities"
    fi
    exit 1
  fi

  log_success "All findings are either ignored or informational."
  exit 0
}

main "$@"
