# Platform Architecture

This document describes the architecture and configuration details of the Modern Engineering on AWS platform.

## Identity and Access Management

### Keycloak Configuration

Keycloak serves as the central identity provider for the platform, providing Single Sign-On (SSO) capabilities for all platform applications.

#### Database Configuration

**Database Type**: PostgreSQL 17.4  
**Connection**: `jdbc:postgresql://postgresql.keycloak.svc.cluster.local:5432/postgres`  
**Schema**: `public`  
**User**: `keycloak`  

#### Infrastructure

- **PostgreSQL StatefulSet**: Running in `keycloak` namespace as `postgresql-0`
- **Service**: `postgresql.keycloak.svc.cluster.local:5432`
- **Persistent Storage**: Configured via VolumeClaimTemplates for data persistence
- **Credentials**: Managed via `keycloak-config` Kubernetes secret

#### Realms and Users

**Realms**:
- `master` - Default Keycloak admin realm
- `platform` - Custom realm for platform applications

**Test Users in `platform` realm**:
- `user1` - Administrative user
  - Email: `user1@example.com`
  - Groups: `["admin"]`
  - Full Name: "user one"
  
- `user2` - Standard user
  - Email: `user2@example.com`
  - Groups: `["base-user"]`
  - Full Name: "user two"

#### OIDC Clients

The following OIDC clients are configured in the `platform` realm:

1. **backstage** - Backstage Developer Portal integration
2. **argocd** - ArgoCD GitOps platform integration
3. **argo-workflows** - Argo Workflows integration
4. **kargo** - Kargo deployment orchestration (uses PKCE, no client secret)

#### Authentication Flow

- **Protocol**: OpenID Connect (OIDC)
- **Token Type**: JWT Bearer tokens
- **Token Expiry**: 300 seconds (5 minutes)
- **Refresh Token Expiry**: 36000 seconds (10 hours)
- **Scopes**: `groups email profile`
- **Group Claims**: User group membership included in JWT tokens

#### Public Access

Keycloak is accessible via CloudFront at:
`https://d3n3wb604kark5.cloudfront.net/keycloak/`

#### Database Tables

Keycloak uses standard PostgreSQL tables including:
- `client` - OIDC client configurations
- `client_scope` - OAuth2/OIDC scopes (including groups scope)
- `keycloak_group` - User groups
- `user_entity` - User accounts
- `user_group_membership` - User-to-group mappings
- `realm` - Keycloak realms configuration

#### Security Configuration

- **Client Secrets**: Stored in both Kubernetes secrets and AWS Secrets Manager
- **Database Credentials**: Managed via External Secrets Operator
- **TLS**: Terminated at CloudFront/ALB level
- **Session Management**: Keycloak handles session state and refresh tokens

## External Secrets Integration

Keycloak integrates with the platform's External Secrets Operator (ESO) configuration:

- **OIDC Client Secrets**: Retrieved from `keycloak-clients` Kubernetes secret
- **Database Passwords**: Retrieved from AWS Secrets Manager
- **Admin Credentials**: Managed via `keycloak-config` secret
- **Real-time Token Updates**: Configuration job updates AWS Secrets Manager with live ArgoCD session tokens

This architecture ensures secure, scalable identity management across all platform applications with proper secret management and database persistence.
