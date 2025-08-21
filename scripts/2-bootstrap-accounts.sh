#!/bin/bash

#############################################################################
# Bootstrap Management and Spoke Accounts
#############################################################################
#
# DESCRIPTION:
#   This script bootstraps the management and spoke AWS accounts for EKS
#   cluster management. It:
#   1. Creates ACK workload roles with the current user added
#   2. Monitors ResourceGraphDefinitions until they are all in Active state
#   3. Restarts the KRO deployment if needed to activate resources
#
# USAGE:
#   ./2-bootstrap-accounts.sh
#
# PREREQUISITES:
#   - ArgoCD and GitLab must be set up (run 1-argocd-gitlab-setup.sh first)
#   - The create_ack_workload_roles.sh script must be available
#   - kubectl must be configured to access the hub cluster
#
# SEQUENCE:
#   This is the third script (2) in the setup sequence.
#   Run after 1-argocd-gitlab-setup.sh and before 3-create-spoke-clusters.sh
#
#############################################################################

set -e

# Source the colors script
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
source "$SCRIPT_DIR/colors.sh"

print_header "Bootstrapping Management and Spoke Accounts"

#print_step "Creating ACK workload roles"
#$SCRIPT_DIR/create_ack_workload_roles.sh

print_header "Checking ResourceGraphDefinitions Status"
print_info "Waiting for ResourceGraphDefinitions to be created and become Active..."

while true; do
  # First check if any ResourceGraphDefinitions exist
  total_rgds=$(kubectl get resourcegraphdefinitions.kro.run --no-headers 2>/dev/null | wc -l)
  
  if [ "$total_rgds" -eq 0 ]; then
    print_warning "No ResourceGraphDefinitions found yet. Waiting for KRO to create them..."
    print_info "This is expected if KRO applications are still being deployed."
    print_info "Waiting 30 seconds before checking again..."
    sleep 30
    continue
  fi
  
  # Get ResourceGraphDefinitions that are not in Active state
  inactive_rgds=$(kubectl get resourcegraphdefinitions.kro.run -o jsonpath='{.items[?(@.status.state!="Active")].metadata.name}' 2>/dev/null || echo "")
  active_rgds=$(kubectl get resourcegraphdefinitions.kro.run -o jsonpath='{.items[?(@.status.state=="Active")].metadata.name}' 2>/dev/null || echo "")
  
  print_info "Found $total_rgds ResourceGraphDefinitions total"
  if [ -n "$active_rgds" ]; then
    print_success "Active ResourceGraphDefinitions: $active_rgds"
  fi
  
  if [ -z "$inactive_rgds" ]; then
    print_success "All $total_rgds ResourceGraphDefinitions are in Active state!"
    break
  else
    print_warning "Found ResourceGraphDefinitions not in Active state: $inactive_rgds"
    
    # Show detailed status for debugging
    print_info "Detailed ResourceGraphDefinitions status:"
    kubectl get resourcegraphdefinitions.kro.run -o custom-columns="NAME:.metadata.name,STATE:.status.state,AGE:.metadata.creationTimestamp" 2>/dev/null || true
    
    print_step "Restarting kro deployment in kro-system namespace..."
    kubectl rollout restart deployment -n kro-system kro
    print_info "Waiting 60 seconds for KRO to process ResourceGraphDefinitions..."
    sleep 60
  fi
done

print_success "Account bootstrapping completed successfully."
print_info "Next step: Run 3-create-spoke-clusters.sh to create the spoke EKS clusters."
