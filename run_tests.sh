#!/bin/bash

# Set variables
POLICY_DIR="./policies"
TEMPLATE_DIR="$POLICY_DIR/templates"
CONSTRAINT_DIR="$POLICY_DIR/constraints"
TEST_DIR="./tests"
VIOLATING_DIR="$TEST_DIR/violating-resources"
COMPLIANT_DIR="$TEST_DIR/compliant-resources"

# Check if directories exist
if [ ! -d "$TEMPLATE_DIR" ]; then
  echo "Error: The path '$TEMPLATE_DIR' does not exist."
  exit 1
fi

if [ ! -d "$CONSTRAINT_DIR" ]; then
  echo "Error: The path '$CONSTRAINT_DIR' does not exist."
  exit 1
fi

# Function to apply all ConstraintTemplates and Constraints
apply_policies() {
  echo "Applying ConstraintTemplates..."
  kubectl apply -f "$TEMPLATE_DIR/"

  echo "Waiting for CRDs to be registered..."
  sleep 30

  echo "Applying Constraints..."
  kubectl apply -f "$CONSTRAINT_DIR/"
}

# Function to apply test cases
apply_test_cases() {
  echo "Applying Violating Resources..."

  # Create necessary namespaces
  kubectl create namespace unprotected-namespace --dry-run=client -o yaml | kubectl apply -f -
  kubectl create namespace protected-namespace --dry-run=client -o yaml | kubectl apply -f -

  kubectl apply -f "$VIOLATING_DIR/"

  echo "Applying Compliant Resources..."
  kubectl apply -f "$COMPLIANT_DIR/"
}

# Function to check for violations
check_violations() {
  echo "Checking for policy violations..."

  # Get all constraint kinds
  constraint_kinds=$(kubectl get constrainttemplate -o jsonpath='{.items[*].metadata.name}')

  for template in $constraint_kinds; do
    kind=$(kubectl get constrainttemplate $template -o jsonpath='{.spec.crd.spec.names.kind}')
    constraints=$(kubectl get $kind -o jsonpath='{.items[*].metadata.name}')
    for constraint in $constraints; do
      violations=$(kubectl get $kind $constraint -o json | jq '.status.violations')
      if [ "$violations" != "null" ] && [ "$violations" != "[]" ]; then
        echo "Violations for $constraint:"
        echo "$violations" | jq
        echo "---------------------------------------"
      else
        echo "No violations for $constraint."
      fi
    done
  done
}

# Function to cleanup test resources
cleanup() {
  echo "Cleaning up test resources..."

  kubectl delete -f "$VIOLATING_DIR/" --ignore-not-found
  kubectl delete -f "$COMPLIANT_DIR/" --ignore-not-found
  kubectl delete -f "$CONSTRAINT_DIR/" --ignore-not-found
  kubectl delete -f "$TEMPLATE_DIR/" --ignore-not-found

  # Delete namespaces if created
  kubectl delete namespace unprotected-namespace --ignore-not-found
  kubectl delete namespace protected-namespace --ignore-not-found
}

# Main script execution
echo "Starting OPA Gatekeeper Policy Tests..."

# Apply policies
apply_policies

# Wait for Gatekeeper to be ready
echo "Waiting for Gatekeeper to initialize..."
sleep 15

# Apply test cases
apply_test_cases

# Wait for Gatekeeper to process
echo "Waiting for Gatekeeper to audit resources..."
sleep 15

# Check for violations
check_violations

# Cleanup resources (optional)
# Uncomment the following line to automatically clean up after testing
#cleanup

echo "Testing completed."
