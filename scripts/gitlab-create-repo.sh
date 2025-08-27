#!/bin/bash

#############################################################################
# GitLab Repository Creation Script
#############################################################################
#
# DESCRIPTION:
#   This script creates repositories in GitLab similar to how giteaInit.sh
#   creates repositories in Gitea. It uses the GitLab API to create repos
#   and can optionally populate them with initial content.
#
# USAGE:
#   ./gitlab-create-repo.sh <repo-name> [template-type]
#
# EXAMPLES:
#   ./gitlab-create-repo.sh my-new-repo
#   ./gitlab-create-repo.sh terraform-eks terraform
#   ./gitlab-create-repo.sh my-app application
#
# PREREQUISITES:
#   - GitLab must be accessible
#   - GitLab access token must be available
#   - Environment variables must be set (done automatically)
#
#############################################################################

# Source the colors script
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
source "$SCRIPT_DIR/colors.sh"

set -e

# Get environment variables
export GITLAB_URL=${GITLAB_URL:-$(aws cloudfront list-distributions --query "DistributionList.Items[?contains(Origins.Items[0].Id, 'gitlab')].DomainName | [0]" --output text | sed 's/^/https:\/\//')}
export GIT_USERNAME=${GIT_USERNAME:-"user1"}
export IDE_PASSWORD=${IDE_PASSWORD:-$(kubectl get secret argocd-initial-admin-secret -n argocd -o jsonpath='{.data.password}' | base64 --decode)}

# Configuration
export TIMEOUT=10
export RETRY_INTERVAL=10
export MAX_RETRIES=20

# Function to check if GitLab is available
check_gitlab_available() {
    print_info "Checking if GitLab is available at $GITLAB_URL..."
    if curl -k -s -o /dev/null -w "%{http_code}" --connect-timeout $TIMEOUT "$GITLAB_URL" | grep -q "200\|302"; then
        print_success "GitLab is available!"
        return 0
    else
        print_warning "GitLab is not available yet."
        return 1
    fi
}

# Wait for GitLab to be available
wait_for_gitlab() {
    local retries=0
    until check_gitlab_available || [ $retries -ge $MAX_RETRIES ]; do
        retries=$((retries+1))
        print_info "Retry $retries/$MAX_RETRIES. Waiting $RETRY_INTERVAL seconds..."
        sleep $RETRY_INTERVAL
    done

    if [ $retries -ge $MAX_RETRIES ]; then
        print_error "GitLab is not available after $MAX_RETRIES retries."
        exit 1
    fi
}

# Get or create GitLab access token
get_gitlab_token() {
    print_step "Getting GitLab access token"
    
    # Try to get existing token from ArgoCD secret
    local existing_token=$(kubectl get secret git-platform-on-eks-workshop -n argocd -o jsonpath='{.data.password}' 2>/dev/null | base64 --decode 2>/dev/null || echo "")
    
    if [ -n "$existing_token" ] && [ "$existing_token" != "$IDE_PASSWORD" ]; then
        print_info "Using existing GitLab token from ArgoCD secret"
        GITLAB_TOKEN="$existing_token"
        return 0
    fi
    
    # Create new token using root access
    local root_token="root-$IDE_PASSWORD"
    
    # Get the user ID for the GIT_USERNAME
    local user_id=$(curl -sS -X GET "$GITLAB_URL/api/v4/users?username=$GIT_USERNAME" \
        -H "PRIVATE-TOKEN: $root_token" | jq -r '.[0].id')

    if [ "$user_id" = "null" ] || [ -z "$user_id" ]; then
        print_error "Failed to find user ID for username: $GIT_USERNAME"
        exit 1
    fi

    print_info "Found user ID $user_id for username $GIT_USERNAME"

    # Create GitLab personal access token
    GITLAB_TOKEN=$(curl -sS -X POST "$GITLAB_URL/api/v4/users/$user_id/personal_access_tokens" \
        -H "PRIVATE-TOKEN: $root_token" \
        -H "Content-Type: application/json" \
        -d '{
            "name": "repo-creation-token",
            "scopes": ["api", "read_repository", "write_repository"],
            "expires_at": "2025-12-31"
        }' | jq -r '.token')

    if [ "$GITLAB_TOKEN" = "null" ] || [ -z "$GITLAB_TOKEN" ]; then
        print_error "Failed to create GitLab access token"
        exit 1
    fi

    print_success "GitLab access token created successfully"
}

# Check if repository exists
check_repo_exist() {
    local repo_name=$1
    print_info "Checking if repository $repo_name exists..."
    
    local response=$(curl -sS -o /dev/null -w "%{http_code}" \
        -H "PRIVATE-TOKEN: $GITLAB_TOKEN" \
        "$GITLAB_URL/api/v4/projects/$GIT_USERNAME%2F$repo_name")
    
    if [[ "$response" == "200" ]]; then
        print_info "Repository $repo_name already exists."
        return 0
    else
        print_info "Repository $repo_name does not exist."
        return 1
    fi
}

# Create repository
create_repo() {
    local repo_name=$1
    print_step "Creating repository $repo_name..."
    
    local response=$(curl -sS -X POST "$GITLAB_URL/api/v4/projects" \
        -H "PRIVATE-TOKEN: $GITLAB_TOKEN" \
        -H "Content-Type: application/json" \
        -d '{
            "name": "'$repo_name'",
            "path": "'$repo_name'",
            "visibility": "private",
            "initialize_with_readme": true
        }')
    
    local project_id=$(echo "$response" | jq -r '.id')
    
    if [ "$project_id" = "null" ] || [ -z "$project_id" ]; then
        print_error "Failed to create repository $repo_name"
        echo "Response: $response"
        exit 1
    fi
    
    print_success "Repository $repo_name created successfully! (ID: $project_id)"
}

# Create repository content for applications
create_repo_content_application() {
    local repo_name=$1
    print_step "Creating initial repo content for application $repo_name..."
    
    export REPO_ROOT=$(git rev-parse --show-toplevel)
    local temp_dir="${REPO_ROOT}/temp-gitlab"
    
    # Clean up any existing temp directory
    rm -rf "$temp_dir"
    mkdir -p "$temp_dir"
    
    # Clone the new repository
    git clone "$GITLAB_URL/$GIT_USERNAME/$repo_name.git" "$temp_dir/$repo_name"
    
    pushd "$temp_dir/$repo_name" > /dev/null
    
    # Configure git
    git config user.email "participants@workshops.aws"
    git config user.name "Workshop Participant"
    
    # Copy application content if it exists
    if [ -d "${REPO_ROOT}/applications/$repo_name" ]; then
        cp -r "${REPO_ROOT}/applications/$repo_name"/* .
        git add .
        git commit -m "Add initial application content"
        git push origin main
        print_success "Initial content pushed to $repo_name"
    else
        print_warning "No application content found for $repo_name"
    fi
    
    popd > /dev/null
    
    # Clean up
    rm -rf "$temp_dir"
}

# Create repository content for terraform
create_repo_content_terraform() {
    local repo_name=$1
    print_step "Creating initial repo content for terraform $repo_name..."
    
    export REPO_ROOT=$(git rev-parse --show-toplevel)
    local temp_dir="${REPO_ROOT}/temp-gitlab"
    
    # Clean up any existing temp directory
    rm -rf "$temp_dir"
    mkdir -p "$temp_dir"
    
    # Clone the new repository
    git clone "$GITLAB_URL/$GIT_USERNAME/$repo_name.git" "$temp_dir/$repo_name"
    
    pushd "$temp_dir/$repo_name" > /dev/null
    
    # Configure git
    git config user.email "participants@workshops.aws"
    git config user.name "Workshop Participant"
    
    # Copy terraform content
    if [ -d "${REPO_ROOT}/platform/infra/terraform/dev" ]; then
        cp -r "${REPO_ROOT}/platform/infra/terraform/dev" .
        cp -r "${REPO_ROOT}/platform/infra/terraform/prod" .
        cp -r "${REPO_ROOT}/platform/infra/terraform/database" .
        cp "${REPO_ROOT}/platform/infra/terraform/.gitignore" .
        cp "${REPO_ROOT}/platform/infra/terraform/create-cluster.sh" .
        cp "${REPO_ROOT}/platform/infra/terraform/create-database.sh" .
        
        git add .
        git commit -m "Add initial terraform content"
        git push origin main
        print_success "Initial terraform content pushed to $repo_name"
    else
        print_warning "No terraform content found"
    fi
    
    popd > /dev/null
    
    # Clean up
    rm -rf "$temp_dir"
}

# Main function to check and create repository
check_and_create_repo() {
    local repo_name=$1
    local template_type=${2:-""}
    
    if check_repo_exist "$repo_name"; then
        print_info "Repository $repo_name already exists, skipping creation."
        return 0
    fi
    
    create_repo "$repo_name"
    
    # Add initial content based on template type
    case "$template_type" in
        "application")
            create_repo_content_application "$repo_name"
            ;;
        "terraform")
            create_repo_content_terraform "$repo_name"
            ;;
        "")
            print_info "No template type specified, repository created empty."
            ;;
        *)
            print_warning "Unknown template type: $template_type"
            ;;
    esac
}

# Main execution
main() {
    local repo_name=$1
    local template_type=$2
    
    if [ -z "$repo_name" ]; then
        print_error "Usage: $0 <repo-name> [template-type]"
        print_info "Template types: application, terraform"
        print_info "Examples:"
        print_info "  $0 my-new-repo"
        print_info "  $0 terraform-eks terraform"
        print_info "  $0 my-app application"
        exit 1
    fi
    
    print_header "GitLab Repository Creation"
    print_info "Repository: $repo_name"
    print_info "Template: ${template_type:-none}"
    print_info "GitLab URL: $GITLAB_URL"
    print_info "Username: $GIT_USERNAME"
    
    wait_for_gitlab
    get_gitlab_token
    check_and_create_repo "$repo_name" "$template_type"
    
    print_success "Repository creation process completed!"
    print_info "Repository URL: $GITLAB_URL/$GIT_USERNAME/$repo_name"
}

# Run main function with all arguments
main "$@"
