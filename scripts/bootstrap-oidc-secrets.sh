#!/bin/bash

#############################################################################
# Bootstrap OIDC Client Secrets
#############################################################################
#
# DESCRIPTION:
#   This function pre-creates OIDC client secrets for Keycloak integration
#   to break the chicken-and-egg dependency cycle. It generates secrets
#   and stores them in both AWS Secrets Manager and Kubernetes secrets.
#
# USAGE:
#   Called from 1-argocd-gitlab-setup.sh
#
#############################################################################

bootstrap_oidc_secrets() {
    print_step "Pre-creating OIDC client secrets for Keycloak integration"
    
    # Generate secure random secrets for OIDC clients
    BACKSTAGE_CLIENT_SECRET=$(openssl rand -base64 32 | tr -d "=+/" | cut -c1-32)
    ARGO_WORKFLOWS_CLIENT_SECRET=$(openssl rand -base64 32 | tr -d "=+/" | cut -c1-32)
    ARGOCD_CLIENT_SECRET=$(openssl rand -base64 32 | tr -d "=+/" | cut -c1-32)
    
    # Get ArgoCD session token (will be updated later by Keycloak job)
    ARGOCD_SESSION_TOKEN="bootstrap-token-$(openssl rand -hex 16)"
    
    print_info "Generated OIDC client secrets"
    
    # Function to create or update secrets in AWS Secrets Manager
    create_or_update_aws_secret() {
        local secret_name="$1"
        local secret_value="$2"
        local description="$3"
        local application="$4"
        
        print_info "Managing AWS secret: $secret_name"
        
        # Try to update existing secret first
        if aws secretsmanager put-secret-value \
            --region us-east-1 \
            --secret-id "$secret_name" \
            --secret-string "$secret_value" >/dev/null 2>&1; then
            print_success "Updated existing AWS secret: $secret_name"
        else
            # Create new secret if update failed
            print_info "Creating new AWS secret: $secret_name"
            if aws secretsmanager create-secret \
                --region us-east-1 \
                --name "$secret_name" \
                --description "$description" \
                --secret-string "$secret_value" \
                --tags '[
                    {"Key":"Environment","Value":"Platform"},
                    {"Key":"Purpose","Value":"OIDC Authentication"},
                    {"Key":"ManagedBy","Value":"Bootstrap"},
                    {"Key":"Application","Value":"'$application'"},
                    {"Key":"CreatedBy","Value":"bootstrap-script"},
                    {"Key":"SecretType","Value":"OIDC-Client"}
                ]' >/dev/null 2>&1; then
                print_success "Created new AWS secret: $secret_name"
            else
                print_error "Failed to create AWS secret: $secret_name"
                return 1
            fi
        fi
        
        # Verify secret was created/updated
        if aws secretsmanager describe-secret --region us-east-1 --secret-id "$secret_name" >/dev/null 2>&1; then
            print_success "Verified AWS secret: $secret_name"
        else
            print_error "Failed to verify AWS secret: $secret_name"
            return 1
        fi
    }
    
    # Store OIDC client secrets in AWS Secrets Manager
    PROJECT_PREFIX="peeks-workshop-gitops"
    
    # Backstage OIDC credentials
    create_or_update_aws_secret \
        "${PROJECT_PREFIX}-backstage-oidc-credentials" \
        "{\"BACKSTAGE_CLIENT_ID\":\"backstage\",\"BACKSTAGE_CLIENT_SECRET\":\"${BACKSTAGE_CLIENT_SECRET}\",\"ARGOCD_SESSION_TOKEN\":\"${ARGOCD_SESSION_TOKEN}\"}" \
        "Backstage OIDC client credentials pre-created by bootstrap script" \
        "Backstage"
    
    # Argo Workflows OIDC credentials
    create_or_update_aws_secret \
        "${PROJECT_PREFIX}-argo-workflows-oidc-credentials" \
        "{\"ARGO_WORKFLOWS_CLIENT_ID\":\"argo-workflows\",\"ARGO_WORKFLOWS_CLIENT_SECRET\":\"${ARGO_WORKFLOWS_CLIENT_SECRET}\"}" \
        "Argo Workflows OIDC client credentials pre-created by bootstrap script" \
        "ArgoWorkflows"
    
    # ArgoCD OIDC credentials
    create_or_update_aws_secret \
        "${PROJECT_PREFIX}-argocd-oidc-credentials" \
        "{\"ARGOCD_CLIENT_ID\":\"argocd\",\"ARGOCD_CLIENT_SECRET\":\"${ARGOCD_CLIENT_SECRET}\",\"ARGOCD_SESSION_TOKEN\":\"${ARGOCD_SESSION_TOKEN}\"}" \
        "ArgoCD OIDC client credentials pre-created by bootstrap script" \
        "ArgoCD"
    
    print_success "All OIDC client secrets stored in AWS Secrets Manager"
    
    # Create Kubernetes secret for backward compatibility and immediate availability
    print_step "Creating Kubernetes keycloak-clients secret"
    
    # Ensure keycloak namespace exists
    kubectl create namespace keycloak --dry-run=client -o yaml | kubectl apply -f -
    
    # Create the keycloak-clients secret
    kubectl create secret generic keycloak-clients \
        --namespace=keycloak \
        --from-literal=ARGO_WORKFLOWS_CLIENT_SECRET="$ARGO_WORKFLOWS_CLIENT_SECRET" \
        --from-literal=ARGO_WORKFLOWS_CLIENT_ID="argo-workflows" \
        --from-literal=ARGOCD_SESSION_TOKEN="$ARGOCD_SESSION_TOKEN" \
        --from-literal=BACKSTAGE_CLIENT_SECRET="$BACKSTAGE_CLIENT_SECRET" \
        --from-literal=BACKSTAGE_CLIENT_ID="backstage" \
        --from-literal=ARGOCD_CLIENT_SECRET="$ARGOCD_CLIENT_SECRET" \
        --from-literal=ARGOCD_CLIENT_ID="argocd" \
        --dry-run=client -o yaml | \
    kubectl apply -f -
    
    # Add annotations and labels to the secret
    kubectl annotate secret keycloak-clients -n keycloak \
        managed-by=bootstrap-script \
        aws-secrets-manager-backup=true \
        secret-source=bootstrap-pre-creation \
        last-updated="$(date -u +"%Y-%m-%dT%H:%M:%SZ")" \
        --overwrite
    
    kubectl label secret keycloak-clients -n keycloak \
        app.kubernetes.io/managed-by=bootstrap-script \
        secret-type=oidc-client \
        backup-location=aws-secrets-manager \
        --overwrite
    
    print_success "Kubernetes keycloak-clients secret created"
    
    print_success "OIDC client secrets bootstrap completed successfully!"
    print_info "Secrets are now available in both AWS Secrets Manager and Kubernetes"
    print_info "Applications can start immediately without waiting for Keycloak configuration"
}
