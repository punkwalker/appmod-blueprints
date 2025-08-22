# Amazon Q Target File - Platform on EKS Workshop

## Project Overview
This is a **Modern Engineering on AWS** platform workshop that demonstrates GitOps-based application deployment using ArgoCD ApplicationSets on Amazon EKS. The project implements a comprehensive platform engineering solution with multiple clusters, addons, and applications.

## Repository Structure
```
platform-on-eks-workshop/
├── gitops/                           # GitOps configurations
│   ├── addons/                       # Addon configurations
│   │   ├── charts/                   # Helm charts for applications (MOVED HERE)
│   │   │   ├── application-sets/     # ApplicationSet Helm chart
│   │   │   ├── argo-workflows/       # Argo Workflows chart
│   │   │   ├── backstage/            # Backstage chart
│   │   │   ├── gitlab/               # GitLab chart
│   │   │   ├── keycloak/             # Keycloak chart
│   │   │   ├── kro/                  # KRO (Kubernetes Resource Operator) charts
│   │   └── ...                       # Other application charts
│   │   ├── bootstrap/default/        # Bootstrap addon configurations
│   │   ├── environments/             # Environment-specific configs
│   │   └── tenants/                  # Tenant-specific configs
│   ├── fleet/                        # Fleet management
│   │   └── bootstrap/                # Bootstrap ApplicationSets
│   └── workloads/                    # Application workloads (created during fixes)
├── platform/                        # Platform infrastructure
├── scripts/                         # Utility scripts
│   ├── wait-for-applicationsets.sh  # Enhanced monitoring script
│   ├── 2-bootstrap-accounts.sh      # Fixed ResourceGraphDefinitions check
│   └── 6-tools-urls.sh              # Get URLs and credentials for all services
└── amazon-q-target-file.md          # This context file
```

## Key Architecture Components

### 1. GitOps with ArgoCD ApplicationSets
- **Hub Cluster**: `peeks-hub-cluster` - Main management cluster
- **ApplicationSets**: Generate Applications dynamically based on cluster/tenant configurations
- **Multi-source Applications**: Use both Git repository and Helm charts

### 2. Application Stack
- **ArgoCD**: GitOps controller and UI
- **Backstage**: Developer portal with OIDC integration
- **Keycloak**: Identity provider and SSO
- **GitLab**: Git repository and CI/CD
- **Argo Workflows**: Workflow engine
- **External Secrets**: Secret management
- **KRO**: Kubernetes Resource Operator for custom resources

### 3. Secret Management
- **External Secrets Operator**: Syncs secrets from external stores
- **ClusterSecretStores**: `argocd`, `keycloak` stores configured
- **Key Secrets**:
  - `peeks-hub-cluster`: Cluster configuration and domain info
  - `keycloak-clients`: OIDC client secrets for applications
  - `backstage-env-vars`: Database and OIDC configuration for Backstage

## Critical Configuration Details

### 1. Path Structure (IMPORTANT!)
**Charts Location**: `gitops/addons/charts/` (NOT `gitops/charts/`)
- This was moved during troubleshooting to match ApplicationSet expectations
- ApplicationSets use `{{.metadata.annotations.addons_repo_basepath}}charts/` pattern
- `addons_repo_basepath` = `gitops/addons/`

### 2. Cluster Secret Reference
**Keycloak Configuration**: Uses `peeks-hub-cluster` secret (NOT `hub-cluster`)
- Fixed in `gitops/addons/charts/keycloak/templates/keycloak-config.yaml`
- Line 286: `./kubectl get secret peeks-hub-cluster -n argocd`

### 3. ApplicationSet Template Variables
```yaml
# Key template variables used in ApplicationSets:
{{.metadata.annotations.addons_repo_basepath}}    # = "gitops/addons/"
{{.metadata.annotations.ingress_domain_name}}     # = Domain for ingress
{{.metadata.labels.environment}}                  # = "control-plane"
{{.metadata.labels.tenant}}                       # = "tenant1"
{{.name}}                                          # = "peeks-hub-cluster"
```

## Common Issues and Solutions

### 1. Path Configuration Errors
**Symptom**: "app path does not exist" errors
**Solution**: Ensure charts are in `gitops/addons/charts/` and ApplicationSets reference correct paths

### 2. Git Revision Mismatch
**Symptom**: "cannot reference a different revision of the same repository"
**Solution**: Hard refresh applications and force sync to HEAD:
```bash
kubectl patch application <app-name> -n argocd --type='json' -p='[
  {"op": "add", "path": "/metadata/annotations/argocd.argoproj.io~1refresh", "value": "hard"}
]'
```

### 3. Secret Dependencies
**Chain**: keycloak config job → keycloak-clients secret → backstage-env-vars secret → backstage pod
**Fix**: Ensure keycloak config job runs successfully to create client secrets

### 4. ResourceGraphDefinitions Check
**Issue**: Bootstrap script incorrectly marked RGDs as active when none existed
**Fix**: Added proper count check in `scripts/2-bootstrap-accounts.sh`

## Monitoring and Troubleshooting

### 1. Enhanced Wait Script
**Location**: `scripts/wait-for-applicationsets.sh`
**Features**:
- Shows each ApplicationSet with generated applications
- Visual health indicators (✅/❌)
- Detects path configuration issues
- Distinguishes critical vs minor errors

**Usage**:
```bash
./scripts/wait-for-applicationsets.sh [timeout_minutes]
```

### 2. Get Service URLs and Credentials
**Location**: `scripts/6-tools-urls.sh`
**Purpose**: Displays URLs and login credentials for all deployed services
**Usage**:
```bash
./scripts/6-tools-urls.sh
```
**Output**: Shows URLs, usernames, and passwords for:
- ArgoCD
- GitLab
- Backstage
- Keycloak
- Argo Workflows
- Other deployed services

### 3. Application Health Check
```bash
# Check all applications
kubectl get applications -n argocd

# Check specific application details
kubectl describe application <app-name> -n argocd

# Check for path errors
kubectl get applications -n argocd -o json | jq -r '.items[] | select(.status.conditions[]?.message? | contains("app path does not exist")) | .metadata.name'
```

### 4. Secret Troubleshooting
```bash
# Check ExternalSecrets
kubectl get externalsecrets -A

# Check cluster secret
kubectl get secret peeks-hub-cluster -n argocd -o yaml

# Force refresh ExternalSecret
kubectl annotate externalsecret <name> -n <namespace> force-sync=$(date +%s) --overwrite
```

## Current Status (as of 2025-08-22)

### Application Health: 20/23 Healthy (87% success rate)

**✅ Working Applications**: 20 applications fully functional
**🔄 Progressing**: backstage (database auth issues)
**⚠️ Issues**: argo-workflows (namespace), keycloak (config job)

### Recent Fixes Applied
1. **Fixed all ApplicationSet path configurations** - Moved charts directory
2. **Resolved Git revision mismatch errors** - Applications sync to correct commits
3. **Fixed keycloak cluster secret reference** - Uses correct secret name
4. **Enhanced monitoring scripts** - Better error detection and reporting
5. **Fixed ResourceGraphDefinitions check** - Proper validation logic

## Development Workflow

### 1. Making Changes
```bash
# Make changes to configurations
git add .
git commit -m "Description of changes"
git push origin main

# Applications will auto-sync or force sync:
kubectl patch application <app-name> -n argocd --type='json' -p='[
  {"op": "add", "path": "/operation", "value": {"sync": {"revision": "HEAD"}}}
]'
```

### 2. Adding New Applications
1. Create Helm chart in `gitops/addons/charts/<app-name>/`
2. Add configuration in `gitops/addons/bootstrap/default/addons.yaml`
3. Enable in cluster-specific config: `gitops/addons/tenants/tenant1/clusters/peeks-hub-cluster/application-sets/addons.yaml`

### 3. Debugging ApplicationSets
```bash
# Check ApplicationSet status
kubectl get applicationsets -n argocd

# Check generated applications
kubectl get applications -n argocd -l argocd.argoproj.io/application-set-name=<appset-name>

# Use enhanced monitoring script
./scripts/wait-for-applicationsets.sh 5
```

## Quick Start Commands for New Sessions

### 1. Get Service URLs and Access Information
```bash
# Get all service URLs and credentials
./scripts/6-tools-urls.sh
```

### 2. Check Overall Platform Health
```bash
# Monitor ApplicationSets and Applications
./scripts/wait-for-applicationsets.sh 5

# Check application status
kubectl get applications -n argocd
```

### 3. Common Troubleshooting
```bash
# Fix Git revision mismatch (if occurs)
for app in $(kubectl get applications -n argocd -o name); do
  kubectl patch $app -n argocd --type='json' -p='[
    {"op": "add", "path": "/metadata/annotations/argocd.argoproj.io~1refresh", "value": "hard"}
  ]'
done

# Check for path errors
kubectl get applications -n argocd -o json | jq -r '.items[] | select(.status.conditions[]?.message? | contains("app path does not exist")) | .metadata.name'
```

## Important Notes for Future Sessions

1. **Charts Location**: Always remember charts are in `gitops/addons/charts/`, not `gitops/charts/`
2. **Secret Names**: Use `peeks-hub-cluster` for cluster secret references
3. **Git Revisions**: If applications show revision mismatch, hard refresh and sync to HEAD
4. **Dependencies**: Keycloak must be working for Backstage to function (OIDC dependency)
5. **Monitoring**: Use the enhanced wait script for comprehensive status overview
6. **Access Info**: Run `./scripts/6-tools-urls.sh` to get current URLs and credentials
7. **Service Dependencies**: 
   - Keycloak → Backstage (OIDC)
   - External Secrets → Application secrets
   - ArgoCD → All application deployments

## Access Information
**To get current URLs and credentials, run**:
```bash
./scripts/6-tools-urls.sh
```

This will display:
- **ArgoCD URL**: `https://<domain>/argocd` (admin / password)
- **GitLab URL**: `https://<domain>/gitlab` (root / password)
- **Backstage URL**: `https://<domain>/backstage` (when working)
- **Keycloak URL**: `https://<domain>/keycloak` (admin / password)
- **Argo Workflows URL**: `https://<domain>/argo-workflows`
- **Other service URLs and credentials**

## Project Context Summary
This project demonstrates a production-ready GitOps platform with comprehensive application lifecycle management, secret handling, and multi-tenant support. The platform uses ArgoCD ApplicationSets to manage multiple applications across different environments and tenants, with proper secret management, OIDC integration, and monitoring capabilities.

**Key Achievement**: Successfully resolved major ApplicationSet path configuration issues and Git revision mismatch problems, achieving 87% application health rate with a fully functional GitOps pipeline.
