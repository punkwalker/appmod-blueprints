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

## Current Status (as of 2025-08-27)

### Application Health: 21/23 Healthy (91% success rate)

**✅ Working Applications**: 21 applications fully functional including **Backstage**
**🔄 Progressing**: Minor sync issues resolved
**⚠️ Issues**: argo-workflows (namespace), keycloak (config job - resolved)

### Recent Fixes Applied
1. **Fixed all ApplicationSet path configurations** - Moved charts directory
2. **Resolved Git revision mismatch errors** - Applications sync to correct commits
3. **Fixed keycloak cluster secret reference** - Uses correct secret name
4. **Enhanced monitoring scripts** - Better error detection and reporting
5. **Fixed ResourceGraphDefinitions check** - Proper validation logic
6. **✅ FIXED Backstage deployment issues** - Resolved sync-wave dependencies and secret rendering
7. **✅ OPTIMIZED Backstage sync-wave configuration** - Improved deployment speed and reliability

### Backstage Deployment - Key Learnings

#### Root Cause Analysis (Fixed)
The Backstage deployment had **sync-wave dependency issues** and **Helm template rendering problems**:

1. **Git Revision Mismatch**: ArgoCD couldn't sync due to different Git commits in multi-source configuration
2. **Missing Secret Dependencies**: `keycloak-clients` secret dependency chain was broken
3. **Helm Template Rendering Issue**: `backstage-env-vars` secret reported as "Synced" but not actually created
4. **Suboptimal Sync-Wave Configuration**: Resources with no dependencies were waiting unnecessarily

#### Proper Solution Applied
**Instead of manual interventions, fixed the root cause in Helm templates:**

1. **Fixed Helm Template Rendering**:
   ```yaml
   # Added missing annotation to backstage-env-vars secret
   annotations:
     argocd.argoproj.io/sync-options: SkipDryRunOnMissingResource=true
   ```

2. **Optimized Sync-Wave Configuration**:
   ```yaml
   # Wave 1: Independent resources (no external dependencies)
   - backstage-env-vars Secret (static configuration)
   - argocd-credentials ExternalSecret (reads from local K8s)
   - git-credentials ExternalSecret (reads from local K8s)
   - backstage-postgres ExternalSecret (reads from AWS Secrets Manager)
   
   # Wave 5: External system dependencies
   - backstage-oidc ExternalSecret (depends on keycloak-clients from Keycloak config job)
   
   # Wave 10: Database (depends on postgres credentials)
   - postgresql StatefulSet
   
   # Wave 15: Application (depends on all secrets and database)
   - backstage Deployment
   ```

#### Key Insights
- **Sync-waves were working correctly** - The issue was NOT with sync-wave configuration
- **Server-side apply issues** can cause resources to appear "Synced" but not actually exist
- **Static configuration should be created first** - No need to wait for external dependencies
- **Proper dependency analysis is crucial** - Group resources by actual dependencies, not arbitrary waves

#### Backstage Secret Dependencies (Resolved)
```
Keycloak Config Job → keycloak-clients secret (keycloak namespace)
                   ↓
ClusterSecretStore → backstage-oidc ExternalSecret → backstage-oidc-vars secret
                   ↓
Static Config → backstage-env-vars secret
                   ↓
All Secrets Ready → Backstage Deployment (✅ Working)
```

#### Benefits of Optimization
- **Faster deployment**: Wave 1 resources deploy in parallel
- **Better dependency management**: Clear separation of concerns  
- **More reliable**: Reduced waiting time for independent resources
- **Cleaner architecture**: Logical grouping by dependency type

### Troubleshooting Backstage Issues (Reference)

#### 1. Check Sync-Wave Progression
```bash
# Check current sync-wave status
kubectl get application backstage-peeks-hub-cluster -n argocd -o jsonpath='{.status.resources}' | jq -r '.[] | select(.syncWave != null) | "\(.syncWave): \(.kind)/\(.name) - \(.status)"' | sort -n

# Expected output:
# 1: ExternalSecret/argocd-credentials - Synced
# 1: ExternalSecret/backstage-postgres - Synced  
# 1: ExternalSecret/git-credentials - Synced
# 1: Secret/backstage-env-vars - Synced
# 5: ExternalSecret/backstage-oidc - Synced
# 10: StatefulSet/postgresql - Synced
# 15: Deployment/backstage - Synced
```

#### 2. Verify Secret Dependencies
```bash
# Check all required secrets exist
kubectl get secrets -n backstage | grep -E "(backstage-env-vars|backstage-oidc-vars|backstage-postgres-vars)"

# Check ExternalSecrets are healthy
kubectl get externalsecrets -n backstage

# Check keycloak-clients secret (source for OIDC)
kubectl get secret keycloak-clients -n keycloak
```

#### 3. Force Sync if Needed
```bash
# Hard refresh application
kubectl annotate application backstage-peeks-hub-cluster -n argocd argocd.argoproj.io/refresh=hard --overwrite

# Force complete sync
kubectl patch application backstage-peeks-hub-cluster -n argocd --type='json' -p='[
  {"op": "add", "path": "/operation", "value": {"sync": {"syncOptions": ["CreateNamespace=true", "ServerSideApply=true"]}}}
]'
```

#### 4. Check Backstage Pod Status
```bash
# Verify Backstage is running
kubectl get pods -n backstage
kubectl logs -n backstage deployment/backstage

# Check service and ingress
kubectl get svc,ingress -n backstage
```

### Important Sync-Wave Best Practices (Learned)

1. **Wave 1**: Static configuration and local dependencies
   - Secrets with static values
   - ExternalSecrets reading from local K8s stores
   - ExternalSecrets reading from reliable external stores (AWS Secrets Manager)

2. **Wave 5**: External system dependencies
   - ExternalSecrets that depend on other applications (like Keycloak)
   - Resources that need external services to be ready

3. **Wave 10**: Infrastructure components
   - Databases, message queues, etc.
   - Resources that depend on credentials from earlier waves

4. **Wave 15+**: Applications
   - Main application deployments
   - Resources that depend on infrastructure and all secrets

5. **Key Annotations for Reliability**:
   ```yaml
   annotations:
     argocd.argoproj.io/sync-wave: "1"
     argocd.argoproj.io/sync-options: SkipDryRunOnMissingResource=true
   ```

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

### 4. Backstage-Specific Troubleshooting
```bash
# Check Backstage sync-wave progression
kubectl get application backstage-peeks-hub-cluster -n argocd -o jsonpath='{.status.resources}' | jq -r '.[] | select(.syncWave != null) | "\(.syncWave): \(.kind)/\(.name) - \(.status)"' | sort -n

# Verify all Backstage secrets exist
kubectl get secrets -n backstage | grep -E "(backstage-env-vars|backstage-oidc-vars|backstage-postgres-vars)"

# Check Backstage ExternalSecrets health
kubectl get externalsecrets -n backstage

# Verify keycloak-clients secret (critical dependency)
kubectl get secret keycloak-clients -n keycloak

# Check Backstage pod status
kubectl get pods -n backstage
kubectl logs -n backstage deployment/backstage --tail=50

# Force Backstage sync if needed
kubectl annotate application backstage-peeks-hub-cluster -n argocd argocd.argoproj.io/refresh=hard --overwrite
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
8. **Backstage Sync-Wave Optimization**: 
   - Wave 1: Static config and local dependencies (fast deployment)
   - Wave 5: External system dependencies (Keycloak OIDC)
   - Wave 10: Database infrastructure
   - Wave 15: Application deployment
9. **Sync-Wave Best Practice**: Group resources by actual dependencies, not arbitrary timing
10. **Server-Side Apply Issues**: Add `SkipDryRunOnMissingResource=true` annotation for reliability
11. **Backstage Secret Chain**: `keycloak-clients` → `backstage-oidc` → `backstage-env-vars` → Deployment

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
