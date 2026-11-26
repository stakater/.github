#!/usr/bin/env bash
# Capture docs screenshots with browser-runner.
#   capture.sh            -> every flow
#   capture.sh <name>     -> only flows/<name>.yaml
#
# The screenshots directory holds the input and the output:
#   flows/       one browser-runner YAML per docs page
#   config.env   checked-in config (console URL, resource names)
#   .env         credentials, gitignored. CI sets them in the environment instead.
#   captured/    the PNGs this writes
#
# SCREENSHOTS_DIR names that directory. It defaults to the directory of this script,
# so a copy inside the docs repo needs no variable.
#
# A failing flow does not stop the run, so one broken page still leaves the rest
# captured. The exit code is non-zero if any flow failed.
#
# A flow that fails is run again, because one slow page or one failed reachability
# probe against a live console should not fail the whole capture. CAPTURE_ATTEMPTS
# sets the number of tries per flow (default 3, 1 turns retrying off) and
# CAPTURE_RETRY_DELAY the seconds between them (default 10).
set -u

if [ -n "${SCREENSHOTS_DIR:-}" ]; then
    DIR="$(cd "$SCREENSHOTS_DIR" && pwd)"
else
    DIR="$(cd "$(dirname "$0")" && pwd)"
fi

IMAGE="${RUNNER_IMAGE:-ghcr.io/stakater/browser-runner:latest}"
OUT="$DIR/captured"
CONFIG_FILE="$DIR/config.env"
ENV_FILE="$DIR/.env"

# Point RUNNER_PACKS at a browser-runner checkout's src/packs to mount them over the
# image's copy. This is for pack development only.
PACKS="${RUNNER_PACKS:-}"

ATTEMPTS="${CAPTURE_ATTEMPTS:-3}"
RETRY_DELAY="${CAPTURE_RETRY_DELAY:-10}"

if [ ! -f "$CONFIG_FILE" ]; then
    echo "FAIL: $CONFIG_FILE not found" >&2
    exit 1
fi

# Credentials come from .env locally; CI sets them in the environment instead.
creds=()
if [ -f "$ENV_FILE" ]; then
    creds=(--env-file "$ENV_FILE")
elif [ -n "${CONSOLE_USER:-}" ] && [ -n "${CONSOLE_PASSWORD:-}" ]; then
    creds=(-e CONSOLE_USER -e CONSOLE_PASSWORD)
else
    echo "FAIL: no credentials - copy .env.example to $ENV_FILE, or set" >&2
    echo "      CONSOLE_USER and CONSOLE_PASSWORD in the environment" >&2
    exit 1
fi

mkdir -p "$OUT"
# The runner writes as pwuser (uid 1000), which does not own the checkout on a CI runner.
chmod 0777 "$OUT"

if [ $# -ge 1 ]; then
    flows="$DIR/flows/$1.yaml"
    if [ ! -f "$flows" ]; then
        echo "FAIL: no such flow: $flows" >&2
        exit 1
    fi
    # Single-flow run: drop only this flow's own outputs, so a partial run cannot
    # leave a stale shot of a later step behind.
    grep -oE 'path: *[A-Za-z0-9._-]+\.png' "$flows" | awk '{print $NF}' \
        | while read -r p; do rm -f "$OUT/$p"; done
else
    # An underscore marks a flow whose position is fixed: _seed sets up state and runs
    # first, _teardown removes it and runs last. Both are optional. A repo whose flows
    # create nothing has neither, and every flow is a capture flow.
    flows=""
    [ -f "$DIR/flows/_seed.yaml" ] && flows="$DIR/flows/_seed.yaml"
    flows="$flows
$(ls "$DIR"/flows/*.yaml | grep -v '/flows/_')"
    [ -f "$DIR/flows/_teardown.yaml" ] && flows="$flows
$DIR/flows/_teardown.yaml"
    # Start clean so review never sees stale images from a past run.
    rm -f "$OUT"/*.png
fi

packs_mount=()
if [ -n "$PACKS" ]; then
    packs_mount=(-v "$PACKS:/runner/packs:ro")
    echo "packs: $PACKS (mounted over the image's copy)"
fi

# One capture of one flow. Returns the runner's exit code.
run_flow() {
    docker run --rm \
        --env-file "$CONFIG_FILE" \
        "${creds[@]}" \
        -e E2E_ARTIFACTS_DIR=/out \
        -v "$OUT:/out" \
        "${packs_mount[@]}" \
        -v "$1:/etc/e2e/test.yaml:ro" \
        "$IMAGE" /etc/e2e/test.yaml
}

# Run a flow up to ATTEMPTS times. Before a retry, the images the failed attempt wrote
# are deleted, so its on-failure shot is not left behind once the flow passes.
run_with_retry() {
    local flow="$1" tries="$2" rc=0 attempt marker
    marker="$(mktemp)"
    for attempt in $(seq 1 "$tries"); do
        touch "$marker"
        run_flow "$flow" && rc=0 && break
        rc=$?
        [ "$attempt" -lt "$tries" ] || break
        echo "RETRY: $(basename "$flow" .yaml) (exit $rc, attempt $attempt of $tries)"
        find "$OUT" -name '*.png' -newer "$marker" -delete
        sleep "$RETRY_DELAY"
    done
    rm -f "$marker"
    return $rc
}

failed=0
for flow in $flows; do
    name="$(basename "$flow" .yaml)"
    echo "RUN: $name"
    # _seed and _teardown change state, so they run once: a retry could repeat a create.
    tries="$ATTEMPTS"
    case "$name" in _*) tries=1 ;; esac
    if run_with_retry "$flow" "$tries"; then
        echo "PASS: $name"
    else
        echo "FAIL: $name (exit $?)"
        failed=1
    fi
done

exit $failed
