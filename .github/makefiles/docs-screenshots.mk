##@ Docs screenshots

# Captures a docs repo's console screenshots with browser-runner, and checks that
# every {{ screenshot: name }} directive in the docs resolves to a captured image.
#
# A caller downloads this fragment and runs it as a sub-make:
#
#   DOCS_SS_REF ?= v0.0.199
#   DOCS_SS_MK_URL ?= https://raw.githubusercontent.com/stakater/.github/$(DOCS_SS_REF)/.github/makefiles/docs-screenshots.mk
#   DOCS_SS_MK := makefiles/docs-screenshots.mk
#
#   capture: $(DOCS_SS_MK)
#       $(MAKE) -f $(DOCS_SS_MK) capture DOCS_SS_REF=$(DOCS_SS_REF)
#
# Pass the same DOCS_SS_REF, so this fragment and the script it downloads are one
# version. Gitignore the directory you download into.

# Ref of stakater/.github to take capture.sh from. Pin it in the caller.
DOCS_SS_REF ?= main
DOCS_SS_BASE_URL ?= https://raw.githubusercontent.com/stakater/.github/$(DOCS_SS_REF)/.github/scripts/docs-screenshots

# Where the docs repo keeps flows/, config.env, .env and captured/.
SCREENSHOTS_DIR ?= screenshots

# The directive checker stays in the docs repo, because the mkdocs hook imports it.
INJECT ?= $(SCREENSHOTS_DIR)/inject.py

# capture.sh lands beside this fragment, so one gitignored directory holds both.
DOCS_SS_DIR := $(dir $(firstword $(MAKEFILE_LIST)))
CAPTURE_SH := $(DOCS_SS_DIR)capture.sh

# Flow name for capture-one.
FLOW ?=

# Downloaded only when missing, so a run does not depend on the network. Delete the
# directory to take a newer copy.
$(CAPTURE_SH):
	@mkdir -p $(dir $@)
	@echo "Downloading $(DOCS_SS_BASE_URL)/capture.sh -> $@"
	@curl -H 'Cache-Control: no-cache' -fsSL "$(DOCS_SS_BASE_URL)/capture.sh" -o "$@" \
	  || { echo "ERROR: failed to download capture.sh from $(DOCS_SS_BASE_URL)"; exit 1; }
	@chmod +x "$@"

.PHONY: capture
capture: $(CAPTURE_SH) ## Capture every flow into $(SCREENSHOTS_DIR)/captured
	SCREENSHOTS_DIR=$(SCREENSHOTS_DIR) bash $(CAPTURE_SH)

.PHONY: capture-one
capture-one: $(CAPTURE_SH) ## Capture one flow: make capture-one FLOW=<name>
	@test -n "$(FLOW)" || { echo "ERROR: FLOW is not set (make capture-one FLOW=<name>)"; exit 1; }
	SCREENSHOTS_DIR=$(SCREENSHOTS_DIR) bash $(CAPTURE_SH) $(FLOW)

.PHONY: check
check: ## Report any directive with no captured image, and any capture no page uses
	python3 $(INJECT) --check

.PHONY: docs-screenshots-clean
docs-screenshots-clean: ## Delete the downloaded capture.sh
	rm -f $(CAPTURE_SH)
