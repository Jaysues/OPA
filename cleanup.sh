#!/bin/bash

# Exit on error
set -e

echo "Cleaning up Gatekeeper policies..."

# Delete all constraints
echo "Deleting constraints..."
for constraint in $(kubectl get constraints --no-headers -o custom-columns=":metadata.name,:metadata.namespace"); do
    echo "Deleting constraint: $constraint"
    kubectl delete constraints.gatekeeper.sh "$constraint"
done

# Delete all constraint templates
echo "Deleting constraint templates..."
for template in $(kubectl get constrainttemplates --no-headers -o custom-columns=":metadata.name"); do
    echo "Deleting constraint template: $template"
    kubectl delete constrainttemplates.templates.gatekeeper.sh "$template"
done

echo "Gatekeeper policies have been cleaned up."
