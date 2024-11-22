#!/bin/bash

# Exit on error, undefined variables, and pipe failures
set -euo pipefail

# Enable debug mode if requested
[[ "${DEBUG:-false}" == "true" ]] && set -x

# Script constants
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly POLICIES_DIR="${SCRIPT_DIR}/policies"
readonly BASE_CONSTRAINTS_DIR="${POLICIES_DIR}/constraints"
readonly BASE_TEMPLATES_DIR="${POLICIES_DIR}/templates"

# List of namespaces to exclude
readonly EXCLUDED_NAMESPACES=(
    "amazon-cloudwatch"
    "aws-for-fluent-bit"
    "calico-apiserver"
    "calico-system"
    "gatekeeper-system"
    "karpenter"
    "kube-system"
    "secrets-store-csi-driver"
    "tigera-operator"
    "cert-manager"
    "brupop-bottlerocket-aws"
    "amazon-guardduty"
)

# Color codes for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly NC='\033[0m' # No Color

# Logging functions
log_info() { echo -e "${GREEN}[INFO]${NC} $*"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $*" >&2; }
log_error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }

# Initialize TEMP_DIR early to avoid "unbound variable" errors
TEMP_DIR=$(mktemp -d || { echo "Failed to create temporary directory"; exit 1; })

# Ensure the temporary directory is cleaned up on exit
trap 'rm -rf -- "$TEMP_DIR"' EXIT

# Function to inject excludedNamespaces into constraints using yq
inject_exclusions_into_constraints() {
    local constraint_file="$1"
    log_info "Injecting excludedNamespaces into $constraint_file"

    # Create backup of original file
    cp "$constraint_file" "${constraint_file}.bak"

    # Check if spec.match exists and create it if it doesn't
    if [[ $(yq eval '.spec.match' "$constraint_file") == "null" ]]; then
        yq eval -i '.spec.match = {}' "$constraint_file"
    fi

    # Directly update the excludedNamespaces field
    yq eval -i '.spec.match.excludedNamespaces = []' "$constraint_file"
    for ns in "${EXCLUDED_NAMESPACES[@]}"; do
        yq eval -i ".spec.match.excludedNamespaces += \"$ns\"" "$constraint_file"
    done

    # Clean up
    rm -f "${constraint_file}.bak"
}

# Function to apply kubernetes resources
apply_resources() {
    local resource_type=$1
    local dir=$2

    log_info "Applying ${resource_type}..."
    local failed_resources=()

    for file in "$dir"/*.yaml; do
        if [[ -f "$file" ]]; then
            log_info "Applying $file"
            if ! kubectl apply -f "$file"; then
                failed_resources+=("$file")
                log_warn "Failed to apply $file"
            fi
        fi
    done

    if [[ ${#failed_resources[@]} -gt 0 ]]; then
        log_error "Failed to apply the following $resource_type:"
        printf '%s\n' "${failed_resources[@]}"
        return 1
    fi
}

# Main function
main() {
    # Check prerequisites
    local prerequisites=("kubectl" "yq")
    for cmd in "${prerequisites[@]}"; do
        if ! command -v "$cmd" &> /dev/null; then
            log_error "Required command not found: $cmd"
            exit 1
        fi
    done

    # Verify kubectl can connect to cluster
    if ! kubectl cluster-info &> /dev/null; then
        log_error "Cannot connect to Kubernetes cluster"
        exit 1
    fi

    # Read App_ID from input parameter or prompt
    local APP_ID="${1:-}"
    if [[ -z "$APP_ID" ]]; then
        read -rp "Enter App_ID (or leave blank for baseline policies): " APP_ID
    fi
    log_info "Using App_ID: ${APP_ID:-baseline}"

    # Set up directory structure
    mkdir -p "$TEMP_DIR/templates" "$TEMP_DIR/constraints"

    # Copy and process templates
    cp -r "${BASE_TEMPLATES_DIR}/." "$TEMP_DIR/templates"
    if [[ -n "$APP_ID" ]] && [[ -d "${BASE_TEMPLATES_DIR}/${APP_ID}" ]]; then
        log_info "Overriding baseline templates with App_ID specific ones: ${APP_ID}"
        cp -r "${BASE_TEMPLATES_DIR}/${APP_ID}/." "$TEMP_DIR/templates"
    fi

    # Copy and process constraints
    cp -r "${BASE_CONSTRAINTS_DIR}/." "$TEMP_DIR/constraints"
    if [[ -n "$APP_ID" ]] && [[ -d "${BASE_CONSTRAINTS_DIR}/${APP_ID}" ]]; then
        log_info "Overriding baseline constraints with App_ID specific ones: ${APP_ID}"
        cp -r "${BASE_CONSTRAINTS_DIR}/${APP_ID}/." "$TEMP_DIR/constraints"
    fi

    # Process and apply templates
    log_info "Processing templates..."
    if ! apply_resources "templates" "$TEMP_DIR/templates"; then
        log_error "Failed to apply templates"
        exit 1
    fi

    # Process and inject exclusions into constraints
    log_info "Processing constraints..."
    for file in "$TEMP_DIR"/constraints/*.yaml; do
        if [[ -f "$file" ]]; then
            inject_exclusions_into_constraints "$file"
        fi
    done

    # Apply processed constraints
    if ! apply_resources "constraints" "$TEMP_DIR/constraints"; then
        log_error "Failed to apply constraints"
        exit 1
    fi

    log_info "All policies have been applied successfully."
}

# Execute main function
main "$@"