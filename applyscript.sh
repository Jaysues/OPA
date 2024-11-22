#!/bin/bash

# Exit immediately if a command exits with a non-zero status
set -e

# List of namespaces to exclude
EXCLUDED_NAMESPACES=(
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

# Function to inject excludedNamespaces into constraints using awk
inject_exclusions_into_constraints() {
    local constraint_file="$1"
    echo "Injecting excludedNamespaces into $constraint_file"

    # Prepare the excludedNamespaces YAML block
    local excluded_namespaces_yaml
    excluded_namespaces_yaml=$(printf "    - %s\n" "${EXCLUDED_NAMESPACES[@]}")

    # Use awk to insert the excludedNamespaces block
    awk -v exclusions="$excluded_namespaces_yaml" '
    BEGIN { match_found=0; added=0 }
    {
        print $0
        if ($0 ~ /^\s*spec:/) {
            spec_indent = match($0, /[^ ]/) - 1
        }
        if ($0 ~ /^\s*match:/ && match_found==0) {
            match_indent = match($0, /[^ ]/) - 1
            match_found=1
        }
        if (match_found==1 && added==0) {
            if ($0 ~ /^\s*excludedNamespaces:/) {
                # Skip existing excludedNamespaces block
                while (getline next_line) {
                    if (next_line !~ /^\s*-/) {
                        # Insert new excludedNamespaces block
                        print_excluded_namespaces()
                        print next_line
                        added=1
                        break
                    }
                }
            } else {
                # Insert excludedNamespaces after match:
                print_excluded_namespaces()
                added=1
            }
        }
    }
    function print_excluded_namespaces() {
        print "  excludedNamespaces:"
        print exclusions
    }
    ' "$constraint_file" > "${constraint_file}.tmp" && mv "${constraint_file}.tmp" "$constraint_file"
}

# Read App_ID from input parameter or prompt
if [ -z "$1" ]; then
    read -p "Enter App_ID (or leave blank for baseline policies): " APP_ID
else
    APP_ID="$1"
fi

echo "Using App_ID: ${APP_ID:-baseline}"

# Set the base directories
BASE_CONSTRAINTS_DIR="policies/constraints"
BASE_TEMPLATES_DIR="policies/templates"

# Create a temporary directory to avoid modifying original files
TEMP_DIR=$(mktemp -d)
trap 'rm -rf -- "$TEMP_DIR"' EXIT

# Copy baseline constraint templates to temporary directory
mkdir -p "$TEMP_DIR/templates"
cp -r "${BASE_TEMPLATES_DIR}/." "$TEMP_DIR/templates"

# If App_ID-specific templates exist, override the baseline ones
if [ -n "$APP_ID" ] && [ -d "${BASE_TEMPLATES_DIR}/${APP_ID}" ]; then
    echo "Overriding baseline constraint templates with those from App_ID: ${APP_ID}"
    cp -r "${BASE_TEMPLATES_DIR}/${APP_ID}/." "$TEMP_DIR/templates"
fi

# Apply constraint templates
echo "Applying Constraint Templates..."
for file in "$TEMP_DIR"/templates/*.yaml; do
    echo "Applying $file"
    kubectl apply -f "$file"
done

# Copy baseline constraints to temporary directory
mkdir -p "$TEMP_DIR/constraints"
cp -r "${BASE_CONSTRAINTS_DIR}/." "$TEMP_DIR/constraints"

# If App_ID-specific constraints exist, override the baseline ones
if [ -n "$APP_ID" ] && [ -d "${BASE_CONSTRAINTS_DIR}/${APP_ID}" ]; then
    echo "Overriding baseline constraints with those from App_ID: ${APP_ID}"
    cp -r "${BASE_CONSTRAINTS_DIR}/${APP_ID}/." "$TEMP_DIR/constraints"
fi

# Inject excludedNamespaces into constraints
echo "Processing Constraints..."
for file in "$TEMP_DIR"/constraints/*.yaml; do
    inject_exclusions_into_constraints "$file"
done

# Apply constraints
echo "Applying Constraints..."
for file in "$TEMP_DIR"/constraints/*.yaml; do
    echo "Applying $file"
    kubectl apply -f "$file"
done

echo "All policies have been applied successfully."
