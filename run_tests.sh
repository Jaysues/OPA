#!/bin/bash

# Set variables
POLICY_DIR="./policies"
TEMPLATE_DIR="$POLICY_DIR/templates"
CONSTRAINT_DIR="$POLICY_DIR/constraints"
TEST_DIR="./tests"
VIOLATING_DIR="$TEST_DIR/violating-resources"
COMPLIANT_DIR="$TEST_DIR/compliant-resources"

# Function to apply all ConstraintTemplates and Constraints
apply_policies() {
  echo "Applying ConstraintTemplates..."
  kubectl apply -f "$TEMPLATE_DIR/"
  
  echo "Applying Constraints..."
  kubectl apply -f "$CONSTRAINT_DIR/"
}

# Function to apply test cases
apply_test_cases() {
  echo "Applying Violating Resources..."
  kubectl apply -f "$VIOLATING_DIR/"
  
  echo "Applying Compliant Resources..."
  kubectl apply -f "$COMPLIANT_DIR/"
}

# Function to check for violations
check_violations() {
  echo "Checking for policy violations..."

  # Get all constraints
  constraints=$(kubectl get constraints --all-namespaces -o json | jq -r '.items[].metadata.name')
  
  for constraint in $constraints; do
    constraint_kind=$(kubectl get constraint -n gatekeeper-system $constraint -o jsonpath='{.kind}')
    violations=$(kubectl get $constraint_kind $constraint -n gatekeeper-system -o json | jq '.status.violations')
    
    if [ "$violations" != "null" ] && [ "$violations" != "[]" ]; then
      echo "Violations for $constraint:"
      echo "$violations" | jq
      echo "---------------------------------------"
    else
      echo "No violations for $constraint."
    fi
  done
}

# Function to cleanup test resources
cleanup() {
  echo "Cleaning up test resources..."

  kubectl delete -f "$VIOLATING_DIR/" --ignore-not-found
  kubectl delete -f "$COMPLIANT_DIR/" --ignore-not-found
  kubectl delete -f "$CONSTRAINT_DIR/" --ignore-not-found
  kubectl delete -f "$TEMPLATE_DIR/" --ignore-not-found
}

# Main script execution
echo "Starting OPA Gatekeeper Policy Tests..."

# Apply policies
apply_policies

# Apply test cases
apply_test_cases

# Wait for Gatekeeper to process
echo "Waiting for Gatekeeper to audit resources..."
sleep 15

# Check for violations
check_violations

# Cleanup resources (optional)
# Uncomment the following line to automatically clean up after testing
# cleanup

echo "Testing completed."
