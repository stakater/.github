##@ Helm

HELM_CHART_NAME ?= 
HELM_CHART_DIR ?= charts/$(HELM_CHART_NAME)
CHART_VERSION ?= $(VERSION)-$(GIT_TAG)
HELM_REGISTRY ?= ghcr.io/stakater/charts
LOCALBIN ?= bin
# Prefer a globally installed helm if available, otherwise use the local bin path
# This resolves to the global helm path when present, else to ./bin/helm
HELM := $(shell command -v helm 2>/dev/null || echo $(LOCALBIN)/helm)

##@ Required variables check
.PHONY: check-helm-reqs
check-helm-reqs:
	@missing=0; \
	if [ -z "$(HELM_CHART_NAME)" ]; then echo "ERROR: HELM_CHART_NAME is not set"; missing=1; fi; \
	if [ -z "$(CHART_VERSION)" ]; then echo "ERROR: CHART_VERSION is not set"; missing=1; fi; \
	if [ -z "$(GIT_USER)" ]; then echo "ERROR: GIT_USER is not set"; missing=1; fi; \
	if [ -z "$(GIT_TOKEN)" ]; then echo "ERROR: GIT_TOKEN is not set"; missing=1; fi; \
	if [ "$${missing}" -ne 0 ]; then echo "One or more required variables are missing. Aborting."; exit 1; fi

.PHONY: install-helm
install-helm:
	@echo "Checking for helm..."
	@if command -v helm >/dev/null 2>&1; then \
		echo "helm found at $$(command -v helm) - skipping install"; \
	elif [ -x "$(LOCALBIN)/helm" ]; then \
		echo "helm already installed at $(LOCALBIN)/helm - skipping install"; \
	else \
		echo "Installing helm to $(LOCALBIN)..."; \
		mkdir -p $(LOCALBIN); \
		curl -sSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | HELM_INSTALL_DIR=$(LOCALBIN) bash; \
	fi

.PHONY: helmify
helmify: ## Generate Helm chart from Kustomize manifests
	@echo "Checking for helmify..."
	@command -v helmify >/dev/null 2>&1 || { echo "helmify not found. Installing..."; go install github.com/arttor/helmify/cmd/helmify@latest; }
	@echo "Generating Helm chart from Kustomize manifests..."
	@rm -rf $(HELM_CHART_DIR)
	@mkdir -p $(HELM_CHART_DIR)
	$(KUSTOMIZE) build config/default | helmify -crd-dir $(HELM_CHART_DIR)
	@echo "✓ Helm chart generated at $(HELM_CHART_DIR)"

.PHONY: helm-lint
helm-lint: helmify install-helm ## Lint the Helm chart
	@echo "Linting Helm chart..."
	@command -v $(HELM) >/dev/null 2>&1 || { echo "ERROR: $(HELM) not found. Install it: https://helm.sh/docs/intro/install/"; exit 1; }
	$(HELM) lint $(HELM_CHART_DIR) --strict
	@echo "✓ Helm chart linting passed!"

.PHONY: helm-package
helm-package: helm-lint check-helm-reqs ## Package the Helm chart
	@echo "Packaging Helm chart..."
	@mkdir -p dist
	$(HELM) package $(HELM_CHART_DIR) -d dist --version $(CHART_VERSION)
	@echo "✓ Chart packaged: dist/$(HELM_CHART_NAME)-$(CHART_VERSION).tgz"

.PHONY: helm-release
helm-release: helm-package check-helm-reqs ## Release Helm chart to OCI registry
	@echo "Releasing Helm chart to OCI registry..."
	@command -v $(HELM) >/dev/null 2>&1 || { echo "ERROR: $(HELM) not found"; exit 1; }
	@if [ -z "$(GIT_TOKEN)" ]; then \
		echo "ERROR: GIT_TOKEN not set."; \
		echo "For local dev, export GIT_TOKEN with your GitHub PAT:"; \
		echo "  export GIT_TOKEN=ghp_xxxxxxxxxxxx"; \
		echo ""; \
		echo "Attempting to use existing Docker credentials..."; \
	else \
		echo "Logging in to GitHub Container Registry..."; \
		echo "$(GIT_TOKEN)" | $(HELM) registry login ghcr.io -u $(GIT_USER) --password-stdin; \
	fi
	@echo "Pushing chart to oci://$(HELM_REGISTRY)/$(HELM_CHART_NAME):$(CHART_VERSION)"
	$(HELM) push dist/$(HELM_CHART_NAME)-$(CHART_VERSION).tgz oci://$(HELM_REGISTRY)
	@echo "✓ Chart released to: oci://$(HELM_REGISTRY)/$(HELM_CHART_NAME):$(CHART_VERSION)"

