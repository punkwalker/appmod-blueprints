#!/bin/bash

#############################################################################
# ArgoCD and GitLab Setup Script
#############################################################################
#
# DESCRIPTION:
#   This script configures ArgoCD and GitLab for the EKS cluster management
#   environment. It:
#   1. Updates the kubeconfig to connect to the hub cluster
#   2. Retrieves and displays the ArgoCD URL and credentials
#   3. Sets up GitLab repository and SSH keys
#   4. Configures Git remote for the working repository
#   5. Creates a secret in ArgoCD for Git repository access
#   6. Logs in to ArgoCD CLI and lists applications
#
# USAGE:
#   ./1-argocd-gitlab-setup.sh
#
# PREREQUISITES:
#   - The management cluster must be created (run 0-initial-setup.sh first)
#   - Environment variables must be set:
#     - AWS_REGION: AWS region where resources are deployed
#     - WORKSPACE_PATH: Path to the workspace directory
#     - WORKING_REPO: Name of the working repository
#     - GIT_USERNAME: Git username for authentication
#     - IDE_PASSWORD: Password for ArgoCD and GitLab authentication
#
# SEQUENCE:
#   This is the second script (1) in the setup sequence.
#   Run after 0-initial-setup.sh and before 2-bootstrap-accounts.sh
#
#############################################################################
# Source the colors script
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
source "$SCRIPT_DIR/colors.sh"

set -e
#set -x

# Function to update or add environment variable to /etc/profile.d/workshop.sh
update_workshop_var() {
    local var_name="$1"
    local var_value="$2"
    local workshop_file="/etc/profile.d/workshop.sh"
    
    # Check if variable already exists in the file
    if grep -q "^export ${var_name}=" "$workshop_file" 2>/dev/null; then
        # Variable exists, update it
        sudo sed -i "s|^export ${var_name}=.*|export ${var_name}=\"${var_value}\"|" "$workshop_file"
        print_info "Updated ${var_name} in ${workshop_file}"
    else
        # Variable doesn't exist, add it
        echo "export ${var_name}=\"${var_value}\"" | sudo tee -a "$workshop_file" > /dev/null
        print_info "Added ${var_name} to ${workshop_file}"
    fi
}

print_header "ArgoCD and GitLab Setup"

print_step "Updating kubeconfig to connect to the hub cluster"
aws eks update-kubeconfig --name peeks-hub-cluster --alias peeks-hub-cluster

export DOMAIN_NAME=$(aws cloudfront list-distributions --query "DistributionList.Items[?contains(Origins.Items[0].Id, 'http-origin')].DomainName | [0]" --output text)
update_workshop_var "DOMAIN_NAME" "$DOMAIN_NAME"

print_header "Setting up GitLab repository and ArgoCD access"

export GITLAB_URL=https://$(aws cloudfront list-distributions --query "DistributionList.Items[?contains(Origins.Items[0].Id, 'gitlab')].DomainName | [0]" --output text)
export NLB_DNS=$(aws elbv2 describe-load-balancers --region $AWS_REGION --names gitlab --query 'LoadBalancers[0].DNSName' --output text)
update_workshop_var "GITLAB_URL" "$GITLAB_URL"
update_workshop_var "NLB_DNS" "$NLB_DNS"

update_workshop_var "GIT_USERNAME" "user1"

update_workshop_var "WORKSPACE_PATH" "$HOME/environment" 
update_workshop_var "WORKING_REPO" "platform-on-eks-workshop"

source /etc/profile.d/workshop.sh

print_info "Creating GitLab SSH keys"
$SCRIPT_DIR/gitlab_create_keys.sh

print_step "Configuring Git remote and pushing to GitLab"
cd $WORKSPACE_PATH/$WORKING_REPO
git remote remove workshop || true
git remote add workshop ssh://git@$NLB_DNS/$GIT_USERNAME/$WORKING_REPO.git
git config remote.pushdefault workshop

print_step "Updating Backstage templates"
$SCRIPT_DIR/update_template_defaults.sh
git add . && git commit -m "Update Backstage Templates" || true

git push --set-upstream workshop main

print_step "Creating ArgoCD Git repository secret"
envsubst << 'EOF' | kubectl apply -f -
apiVersion: v1
kind: Secret
metadata:
   name: git-${WORKING_REPO}
   namespace: argocd
   labels:
      argocd.argoproj.io/secret-type: repository
stringData:
   url: ${GITLAB_URL}/${GIT_USERNAME}/${WORKING_REPO}.git
   type: git
   username: $GIT_USERNAME
   password: $IDE_PASSWORD
EOF

sleep 5

print_step "Creating Amazon Elastic Container Repository (Amazon ECR) for Backstage image"
aws ecr create-repository --repository-name backstage --region $AWS_REGION || true

print_step "Building Backstage image"
$SCRIPT_DIR/build_backstage.sh $WORKSHOP_DIR/backstage

print_step "Logging in to ArgoCD CLI"
argocd login --username admin --password $IDE_PASSWORD --grpc-web-root-path /argocd $DOMAIN_NAME

print_info "Listing ArgoCD applications"
argocd app list

print_step "Syncing bootstrap application"
argocd app sync bootstrap

print_info "Checking ArgoCD applications status"
kubectl get applications -n argocd

print_success "ArgoCD and GitLab setup completed successfully."

print_header "Access Information"
print_info "You can connect to Argo CD UI and check everything is ok"
echo -e "${CYAN}ArgoCD URL:${BOLD} https://$DOMAIN_NAME/argocd${NC}"
echo -e "${CYAN}   Login:${BOLD} admin${NC}"
echo -e "${CYAN}   Password:${BOLD} $IDE_PASSWORD${NC}"

print_info "Next step: Run 2-bootstrap-accounts.sh to bootstrap management and spoke accounts."
