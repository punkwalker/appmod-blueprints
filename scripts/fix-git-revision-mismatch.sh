#!/bin/bash

# fix-git-revision-mismatch.sh
# Script to fix Git revision mismatch issues by clearing ArgoCD cache and forcing refresh
# Usage: ./fix-git-revision-mismatch.sh [app-name] [namespace]

set -e

APP_NAME=${1:-}
NAMESPACE=${2:-argocd}
DRY_RUN=${DRY_RUN:-false}

echo "🔧 ArgoCD Git Revision Mismatch Fixer"
echo "====================================="
echo "Namespace: $NAMESPACE"
echo "Timestamp: $(date)"
echo ""

# Function to check if kubectl and jq are available
check_dependencies() {
    if ! command -v kubectl &> /dev/null; then
        echo "❌ Error: kubectl is not installed or not in PATH"
        exit 1
    fi
    
    if ! command -v jq &> /dev/null; then
        echo "❌ Error: jq is not installed or not in PATH"
        exit 1
    fi
}

# Function to detect if application has revision mismatch
has_revision_mismatch() {
    local app_name=$1
    local status_message
    
    status_message=$(kubectl get application "$app_name" -n "$NAMESPACE" -o json 2>/dev/null | jq -r '.status.operationState.message // ""')
    
    if [[ "$status_message" == *"cannot reference a different revision of the same repository"* ]]; then
        return 0  # Has mismatch
    else
        return 1  # No mismatch
    fi
}

# Function to clear ArgoCD cache for an application
clear_app_cache() {
    local app_name=$1
    
    echo "🧹 Clearing cache for application: $app_name"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        echo "   [DRY RUN] Would execute: kubectl patch application $app_name -n $NAMESPACE --type='json' -p='[{\"op\": \"add\", \"path\": \"/metadata/annotations/argocd.argoproj.io~1refresh\", \"value\": \"hard\"}]'"
        return 0
    fi
    
    # Step 1: Hard refresh to clear Git cache
    echo "   📡 Step 1: Hard refresh (clearing Git cache)..."
    kubectl patch application "$app_name" -n "$NAMESPACE" --type='json' -p='[
        {
            "op": "add",
            "path": "/metadata/annotations/argocd.argoproj.io~1refresh",
            "value": "hard"
        }
    ]' 2>/dev/null || {
        echo "   ⚠️  Warning: Could not apply hard refresh annotation"
    }
    
    # Step 2: Clear any existing operation
    echo "   🛑 Step 2: Clearing existing operation..."
    kubectl patch application "$app_name" -n "$NAMESPACE" --type='json' -p='[
        {
            "op": "remove",
            "path": "/operation"
        }
    ]' 2>/dev/null || {
        echo "   ℹ️  No existing operation to clear"
    }
    
    # Step 3: Wait a moment for cache clearing
    echo "   ⏳ Step 3: Waiting for cache to clear..."
    sleep 5
    
    # Step 4: Force sync with HEAD revision
    echo "   🔄 Step 4: Force sync to HEAD..."
    kubectl patch application "$app_name" -n "$NAMESPACE" --type='json' -p='[
        {
            "op": "add",
            "path": "/operation",
            "value": {
                "sync": {
                    "revision": "HEAD",
                    "syncOptions": ["CreateNamespace=true", "ServerSideApply=true"]
                }
            }
        }
    ]' 2>/dev/null || {
        echo "   ⚠️  Warning: Could not initiate sync operation"
        return 1
    }
    
    echo "   ✅ Cache clearing and sync initiated for $app_name"
    return 0
}

# Function to wait for application sync to complete
wait_for_sync() {
    local app_name=$1
    local max_wait=${2:-300}  # 5 minutes default
    local wait_time=0
    
    echo "⏳ Waiting for $app_name to sync (max ${max_wait}s)..."
    
    while [[ $wait_time -lt $max_wait ]]; do
        local phase
        phase=$(kubectl get application "$app_name" -n "$NAMESPACE" -o json 2>/dev/null | jq -r '.status.operationState.phase // "Unknown"')
        
        case "$phase" in
            "Succeeded")
                echo "   ✅ Sync completed successfully!"
                return 0
                ;;
            "Failed")
                echo "   ❌ Sync failed!"
                local message
                message=$(kubectl get application "$app_name" -n "$NAMESPACE" -o json | jq -r '.status.operationState.message // "No message"')
                echo "   Error: $message"
                return 1
                ;;
            "Running")
                echo "   🔄 Sync in progress... (${wait_time}s elapsed)"
                ;;
            *)
                echo "   ⏳ Waiting for sync to start... (${wait_time}s elapsed)"
                ;;
        esac
        
        sleep 10
        wait_time=$((wait_time + 10))
    done
    
    echo "   ⏰ Timeout waiting for sync to complete"
    return 1
}

# Function to verify fix
verify_fix() {
    local app_name=$1
    
    echo "🔍 Verifying fix for $app_name..."
    
    if has_revision_mismatch "$app_name"; then
        echo "   ❌ Revision mismatch still exists"
        return 1
    else
        local sync_status
        sync_status=$(kubectl get application "$app_name" -n "$NAMESPACE" -o json | jq -r '.status.sync.status // "Unknown"')
        local health_status
        health_status=$(kubectl get application "$app_name" -n "$NAMESPACE" -o json | jq -r '.status.health.status // "Unknown"')
        
        echo "   📊 Current Status: Sync=$sync_status, Health=$health_status"
        
        if [[ "$sync_status" == "Synced" ]]; then
            echo "   ✅ Fix successful! Application is now synced"
            return 0
        else
            echo "   ⚠️  Application synced but may need more time to become healthy"
            return 0
        fi
    fi
}

# Function to fix all applications with revision mismatch
fix_all_apps() {
    echo "🔍 Scanning for applications with Git revision mismatch..."
    
    local apps_with_issues=()
    local apps
    apps=$(kubectl get applications -n "$NAMESPACE" -o json | jq -r '.items[].metadata.name' 2>/dev/null)
    
    if [[ -z "$apps" ]]; then
        echo "❌ No applications found in namespace '$NAMESPACE'"
        exit 1
    fi
    
    # Find applications with revision mismatch
    for app in $apps; do
        if has_revision_mismatch "$app"; then
            apps_with_issues+=("$app")
            echo "   🚨 Found revision mismatch in: $app"
        fi
    done
    
    if [[ ${#apps_with_issues[@]} -eq 0 ]]; then
        echo "✅ No applications with Git revision mismatch found!"
        exit 0
    fi
    
    echo ""
    echo "📋 Found ${#apps_with_issues[@]} application(s) with revision mismatch:"
    printf '   - %s\n' "${apps_with_issues[@]}"
    echo ""
    
    if [[ "$DRY_RUN" != "true" ]]; then
        read -p "🤔 Do you want to fix all these applications? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            echo "❌ Operation cancelled by user"
            exit 0
        fi
    fi
    
    # Fix each application
    local fixed_count=0
    local failed_count=0
    
    for app in "${apps_with_issues[@]}"; do
        echo ""
        echo "🔧 Fixing application: $app"
        echo "================================"
        
        if clear_app_cache "$app"; then
            if [[ "$DRY_RUN" != "true" ]]; then
                if wait_for_sync "$app" 120; then  # 2 minute timeout per app
                    if verify_fix "$app"; then
                        fixed_count=$((fixed_count + 1))
                        echo "   🎉 Successfully fixed $app"
                    else
                        failed_count=$((failed_count + 1))
                        echo "   ⚠️  $app may need manual attention"
                    fi
                else
                    failed_count=$((failed_count + 1))
                    echo "   ❌ Failed to sync $app within timeout"
                fi
            else
                echo "   [DRY RUN] Would fix $app"
                fixed_count=$((fixed_count + 1))
            fi
        else
            failed_count=$((failed_count + 1))
            echo "   ❌ Failed to clear cache for $app"
        fi
    done
    
    # Summary
    echo ""
    echo "📊 FIX SUMMARY"
    echo "=============="
    echo "Applications processed: ${#apps_with_issues[@]}"
    echo "Successfully fixed: $fixed_count"
    echo "Failed or need attention: $failed_count"
    
    if [[ $failed_count -gt 0 ]]; then
        echo ""
        echo "⚠️  Some applications may need manual attention."
        echo "   Check their status with: kubectl get applications -n $NAMESPACE"
        exit 1
    else
        echo ""
        echo "🎉 All applications fixed successfully!"
        exit 0
    fi
}

# Function to fix single application
fix_single_app() {
    local app_name=$1
    
    echo "🔍 Checking application: $app_name"
    
    # Check if application exists
    if ! kubectl get application "$app_name" -n "$NAMESPACE" &>/dev/null; then
        echo "❌ Application '$app_name' not found in namespace '$NAMESPACE'"
        exit 1
    fi
    
    # Check if it has revision mismatch
    if ! has_revision_mismatch "$app_name"; then
        echo "ℹ️  Application '$app_name' does not have a Git revision mismatch"
        
        local sync_status
        sync_status=$(kubectl get application "$app_name" -n "$NAMESPACE" -o json | jq -r '.status.sync.status // "Unknown"')
        local health_status
        health_status=$(kubectl get application "$app_name" -n "$NAMESPACE" -o json | jq -r '.status.health.status // "Unknown"')
        
        echo "   Current Status: Sync=$sync_status, Health=$health_status"
        
        if [[ "$sync_status" == "Synced" && "$health_status" == "Healthy" ]]; then
            echo "✅ Application is already healthy!"
            exit 0
        else
            echo "⚠️  Application has other issues. Attempting cache clear anyway..."
        fi
    else
        echo "🚨 Git revision mismatch detected in '$app_name'"
    fi
    
    echo ""
    echo "🔧 Fixing application: $app_name"
    echo "==============================="
    
    if clear_app_cache "$app_name"; then
        if [[ "$DRY_RUN" != "true" ]]; then
            if wait_for_sync "$app_name"; then
                verify_fix "$app_name"
                echo "🎉 Fix process completed for $app_name"
            else
                echo "❌ Sync did not complete within timeout"
                exit 1
            fi
        else
            echo "[DRY RUN] Would fix $app_name"
        fi
    else
        echo "❌ Failed to clear cache for $app_name"
        exit 1
    fi
}

# Help function
show_help() {
    echo "ArgoCD Git Revision Mismatch Fixer"
    echo ""
    echo "Usage: $0 [OPTIONS] [APP_NAME] [NAMESPACE]"
    echo ""
    echo "OPTIONS:"
    echo "  -h, --help     Show this help message"
    echo "  --dry-run      Show what would be done without making changes"
    echo ""
    echo "ARGUMENTS:"
    echo "  APP_NAME       Specific application to fix (optional)"
    echo "  NAMESPACE      ArgoCD namespace (default: argocd)"
    echo ""
    echo "ENVIRONMENT VARIABLES:"
    echo "  DRY_RUN=true   Enable dry-run mode"
    echo ""
    echo "Examples:"
    echo "  $0                                    # Fix all applications with mismatch"
    echo "  $0 my-app                            # Fix specific application"
    echo "  $0 my-app argocd-system              # Fix app in specific namespace"
    echo "  DRY_RUN=true $0                      # Dry-run mode"
    echo "  $0 --dry-run my-app                  # Dry-run for specific app"
    echo ""
    echo "This script fixes Git revision mismatch issues by:"
    echo "1. Hard refreshing ArgoCD cache"
    echo "2. Clearing existing sync operations"
    echo "3. Forcing sync to HEAD revision"
    echo "4. Waiting for sync completion"
    echo "5. Verifying the fix"
}

# Main function
main() {
    check_dependencies
    
    if [[ -n "$APP_NAME" ]]; then
        fix_single_app "$APP_NAME"
    else
        fix_all_apps
    fi
}

# Parse command line arguments
case "${1:-}" in
    -h|--help)
        show_help
        exit 0
        ;;
    --dry-run)
        DRY_RUN=true
        APP_NAME=${2:-}
        NAMESPACE=${3:-argocd}
        main
        ;;
    *)
        main "$@"
        ;;
esac
