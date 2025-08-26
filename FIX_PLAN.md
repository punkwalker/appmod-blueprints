# Platform Issues Fix Plan

## Issues Identified

### 1. EKS Cluster Creation Failures (Critical)
- **Status**: All 4 clusters in ERROR state
- **Root Cause**: IAM permission issues with ACK EC2 controller
- **Error**: Cannot assume role `arn:aws:iam::665742499430:role/eks-cluster-mgmt-ec2`

### 2. External Secrets Issues
- **AWS Secrets Manager**: Service account `external-secrets-sa` lacks IAM role
- **Keycloak OIDC**: Missing `keycloak-clients` secret

### 3. Application Sync Issues
- **Backstage**: OutOfSync/Missing due to External Secrets dependencies
- **Argo Workflows**: OutOfSync/Degraded due to keycloak-oidc secret failure

## Fix Strategy

### Phase 1: IAM and Service Account Configuration
1. Fix External Secrets service account IAM role association
2. Create missing keycloak secrets
3. Ensure proper IAM trust relationships

### Phase 2: Multi-Account Configuration
1. Verify account IDs in values files
2. Ensure proper cross-account role configuration
3. Update ACK controller configurations

### Phase 3: Application Dependencies
1. Fix External Secrets configurations
2. Resolve Backstage dependencies
3. Fix Argo Workflows OIDC configuration

## Implementation Log

### Changes Made:
