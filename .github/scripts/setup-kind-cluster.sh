#!/usr/bin/env bash
set -euo pipefail

# =============================================================================
# Kind Cluster Setup Script
# =============================================================================
# This script provides common functionality for setting up Kind clusters
# across multiple repositories. It handles:
# - Kind cluster creation
# - Loading local Docker images into Kind
# - Creating pull secrets for private registries
#
# Usage:
#   ./setup-kind-cluster.sh [action] [options]
#
# Actions:
#   cluster     - Create Kind cluster (if it doesn't exist)
#   load-image  - Load local Docker image into Kind cluster
#   pull-secret - Create pull secret in specified namespace
#   all         - Run all actions in sequence
#
# Environment Variables:
#   TEST_CLUSTER_NAME     - Name of the Kind cluster (default: e2e-test-cluster)
#   IMG                   - Docker image to load (required for load-image action)
#   CONTAINER_TOOL        - Container tool to use (default: docker)
#   OPERATOR_NAMESPACE    - Namespace for pull secret (required for pull-secret action)
#   PULL_SECRET_NAME      - Name of the pull secret (default: saap-dockerconfigjson)
#   GHCR_USERNAME         - GitHub Container Registry username (required for pull-secret)
#   GHCR_TOKEN            - GitHub Container Registry token (required for pull-secret)
#   KIND_VERSION          - Kind version to use (default: v0.30.0)
#   LOCALBIN              - Local bin directory (default: ./bin)
# =============================================================================

# Default values
TEST_CLUSTER_NAME=${TEST_CLUSTER_NAME:-e2e-test-cluster}
CONTAINER_TOOL=${CONTAINER_TOOL:-docker}
KIND_VERSION=${KIND_VERSION:-v0.30.0}
LOCALBIN=${LOCALBIN:-./bin}
KIND=${KIND:-${LOCALBIN}/kind}
PULL_SECRET_NAME=${PULL_SECRET_NAME:-saap-dockerconfigjson}

# Check for required tools
check_prerequisites() {
    if ! command -v kubectl &> /dev/null; then
        log_error "kubectl is required but not found in PATH"
        exit 1
    fi
}

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Install Kind if not available
install_kind() {
    if [[ -f "${KIND}" ]]; then
        log_info "Kind already installed at ${KIND}"
        return 0
    fi
    
    log_info "Installing Kind ${KIND_VERSION}..."
    mkdir -p "${LOCALBIN}"
    
    OS=$(go env GOOS 2>/dev/null || echo "linux")
    ARCH=$(go env GOARCH 2>/dev/null || echo "amd64")
    
    # Download and install kind
    curl -sSLo "${KIND}" "https://kind.sigs.k8s.io/dl/${KIND_VERSION}/kind-${OS}-${ARCH}"
    chmod +x "${KIND}"
    
    log_success "Kind ${KIND_VERSION} installed successfully"
}

# Create Kind cluster
create_cluster() {
    log_info "Setting up Kind cluster '${TEST_CLUSTER_NAME}'"
    
    # Install Kind if needed
    install_kind
    
    # Check if cluster already exists
    if ${KIND} get clusters | grep -q "^${TEST_CLUSTER_NAME}$"; then
        log_success "Kind cluster '${TEST_CLUSTER_NAME}' already exists"
        return 0
    fi
    
    log_info "Creating Kind cluster '${TEST_CLUSTER_NAME}'"
    ${KIND} create cluster --name "${TEST_CLUSTER_NAME}"
    log_success "Kind cluster '${TEST_CLUSTER_NAME}' created successfully"
}

# Load Docker image into Kind cluster
load_image() {
    if [[ -z "${IMG:-}" ]]; then
        log_error "IMG environment variable is required for load-image action"
        exit 1
    fi
    
    log_info "Checking for local image: ${IMG}"
    
    # Check if image exists locally
    if ${CONTAINER_TOOL} images --format "table {{.Repository}}:{{.Tag}}" | grep -q "^${IMG}$"; then
        log_info "Found local image ${IMG}, loading into Kind cluster ${TEST_CLUSTER_NAME}"
        
        # Install Kind if needed
        install_kind
        
        ${KIND} load docker-image "${IMG}" --name "${TEST_CLUSTER_NAME}"
        log_success "Image ${IMG} loaded into Kind cluster successfully"
    else
        log_warning "Local image ${IMG} not found, cluster will pull from registry"
    fi
}

# Create pull secret for private registry
create_pull_secret() {
    if [[ -z "${OPERATOR_NAMESPACE:-}" ]]; then
        log_error "OPERATOR_NAMESPACE environment variable is required for pull-secret action"
        exit 1
    fi
    
    if [[ -z "${GHCR_USERNAME:-}" ]]; then
        log_error "GHCR_USERNAME environment variable is required for pull-secret action"
        exit 1
    fi
    
    if [[ -z "${GHCR_TOKEN:-}" ]]; then
        log_error "GHCR_TOKEN environment variable is required for pull-secret action"
        exit 1
    fi
    
    log_info "Creating pull secret in namespace '${OPERATOR_NAMESPACE}'"
    
    # Create namespace if it doesn't exist
    kubectl create namespace "${OPERATOR_NAMESPACE}" --dry-run=client -o yaml | kubectl apply -f -
    
    # Create docker registry secret
    kubectl -n "${OPERATOR_NAMESPACE}" create secret docker-registry "${PULL_SECRET_NAME}" \
        --docker-server=ghcr.io \
        --docker-username="${GHCR_USERNAME}" \
        --docker-password="${GHCR_TOKEN}" \
        --dry-run=client -o yaml | kubectl apply -f -
    
    log_success "Pull secret '${PULL_SECRET_NAME}' created successfully in namespace '${OPERATOR_NAMESPACE}'"
}

# Display usage information
usage() {
    cat << EOF
Usage: $0 [action] [options]

Actions:
  cluster      Create Kind cluster (if it doesn't exist)
  load-image   Load local Docker image into Kind cluster
  pull-secret  Create pull secret in specified namespace
  all          Run all actions in sequence
  help         Show this help message

Environment Variables:
  TEST_CLUSTER_NAME     Name of the Kind cluster (default: e2e-test-cluster)
  IMG                   Docker image to load (required for load-image action)
  CONTAINER_TOOL        Container tool to use (default: docker)
  OPERATOR_NAMESPACE    Namespace for pull secret (required for pull-secret action)
  PULL_SECRET_NAME      Name of the pull secret (default: saap-dockerconfigjson)
  GHCR_USERNAME         GitHub Container Registry username (required for pull-secret)
  GHCR_TOKEN            GitHub Container Registry token (required for pull-secret)
  KIND_VERSION          Kind version to use (default: v0.30.0)
  LOCALBIN              Local bin directory (default: ./bin)

Examples:
  # Create cluster only
  $0 cluster

  # Load image into cluster
  IMG=myregistry/myapp:latest $0 load-image

  # Create pull secret
  OPERATOR_NAMESPACE=my-system GHCR_USERNAME=user GHCR_TOKEN=token $0 pull-secret

  # Create pull secret with custom name
  OPERATOR_NAMESPACE=my-system PULL_SECRET_NAME=my-custom-secret GHCR_USERNAME=user GHCR_TOKEN=token $0 pull-secret

  # Run all actions
  IMG=myregistry/myapp:latest OPERATOR_NAMESPACE=my-system GHCR_USERNAME=user GHCR_TOKEN=token $0 all

EOF
}

# Display current configuration
show_config() {
    log_info "Current configuration:"
    echo "  TEST_CLUSTER_NAME: ${TEST_CLUSTER_NAME}"
    echo "  IMG: ${IMG:-<not set>}"
    echo "  CONTAINER_TOOL: ${CONTAINER_TOOL}"
    echo "  OPERATOR_NAMESPACE: ${OPERATOR_NAMESPACE:-<not set>}"
    echo "  PULL_SECRET_NAME: ${PULL_SECRET_NAME}"
    echo "  KIND_VERSION: ${KIND_VERSION}"
    echo "  LOCALBIN: ${LOCALBIN}"
    
    # Show masked credentials
    if [[ -n "${GHCR_USERNAME:-}" ]]; then
        echo "  GHCR_USERNAME: ${GHCR_USERNAME}"
    else
        echo "  GHCR_USERNAME: <not set>"
    fi
    
    if [[ -n "${GHCR_TOKEN:-}" ]]; then
        echo "  GHCR_TOKEN: ****"
    else
        echo "  GHCR_TOKEN: <not set>"
    fi
    echo ""
}

# Main execution
main() {
    local action="${1:-help}"
    
    # Check prerequisites for all actions
    check_prerequisites
    
    # Show configuration for all actions except help
    if [[ "${action}" != "help" && "${action}" != "--help" && "${action}" != "-h" ]]; then
        show_config
    fi
    
    case "${action}" in
        cluster)
            create_cluster
            ;;
        load-image)
            load_image
            ;;
        pull-secret)
            create_pull_secret
            ;;
        all)
            create_cluster
            load_image
            create_pull_secret
            ;;
        help|--help|-h)
            usage
            ;;
        *)
            log_error "Unknown action: ${action}"
            usage
            exit 1
            ;;
    esac
}

# Run main function with all arguments
main "$@"