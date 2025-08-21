#!/bin/bash

#############################################################################
# Wait for ApplicationSets Deployment Script
#############################################################################
#
# DESCRIPTION:
#   This script waits for all ApplicationSets to be deployed and considers
#   applications as healthy even if they're OutOfSync due to minor 
#   configuration differences or unrecognized values.
#
# USAGE:
#   ./wait-for-applicationsets.sh [timeout_minutes]
#
# PARAMETERS:
#   timeout_minutes: Maximum time to wait in minutes (default: 30)
#
#############################################################################

# Source the colors script
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
source "$SCRIPT_DIR/colors.sh"

set -e

# Configuration
TIMEOUT_MINUTES=${1:-30}
TIMEOUT_SECONDS=$((TIMEOUT_MINUTES * 60))
CHECK_INTERVAL=30
NAMESPACE="argocd"

# Counters
START_TIME=$(date +%s)
LAST_APPSET_COUNT=0
STABLE_ITERATIONS=0
REQUIRED_STABLE_ITERATIONS=3

print_header "Waiting for ApplicationSets Deployment"

print_info "Configuration:"
echo "  - Timeout: ${TIMEOUT_MINUTES} minutes"
echo "  - Check interval: ${CHECK_INTERVAL} seconds"
echo "  - Namespace: ${NAMESPACE}"
echo "  - Required stable iterations: ${REQUIRED_STABLE_ITERATIONS}"

# Function to check if an application is considered healthy
is_application_healthy() {
    local app_name="$1"
    local sync_status="$2"
    local health_status="$3"
    
    # Consider healthy if:
    # 1. Health is Healthy, Progressing, or Missing (for new apps)
    # 2. Sync can be Synced, OutOfSync, or Unknown (we're lenient on sync)
    case "$health_status" in
        "Healthy"|"Progressing"|"Missing"|"")
            return 0
            ;;
        "Degraded")
            # Check if it's a known issue we can ignore
            local conditions=$(kubectl get application "$app_name" -n "$NAMESPACE" -o json 2>/dev/null | jq -r '.status.conditions[]?.message // ""' | grep -i -E "(unrecognized|unknown|values|config)" || true)
            if [ -n "$conditions" ]; then
                print_info "  Ignoring degraded state for $app_name (configuration issue): $conditions"
                return 0
            fi
            return 1
            ;;
        *)
            return 1
            ;;
    esac
}

# Function to get ApplicationSet status
get_applicationset_status() {
    print_step "Checking ApplicationSets status..."
    
    local appsets=$(kubectl get applicationsets -n "$NAMESPACE" -o json 2>/dev/null)
    local appset_count=$(echo "$appsets" | jq -r '.items | length')
    
    echo "  ApplicationSets found: $appset_count"
    
    # List all ApplicationSets
    echo "$appsets" | jq -r '.items[] | "  - \(.metadata.name) (age: \(.metadata.creationTimestamp))"'
    
    # Check if ApplicationSet count is stable
    if [ "$appset_count" -eq "$LAST_APPSET_COUNT" ]; then
        STABLE_ITERATIONS=$((STABLE_ITERATIONS + 1))
        print_info "  ApplicationSet count stable for $STABLE_ITERATIONS iterations"
    else
        STABLE_ITERATIONS=0
        print_info "  ApplicationSet count changed: $LAST_APPSET_COUNT -> $appset_count"
    fi
    
    LAST_APPSET_COUNT=$appset_count
    
    return $appset_count
}

# Function to get Application status
get_application_status() {
    print_step "Checking Applications status..."
    
    local apps=$(kubectl get applications -n "$NAMESPACE" -o json 2>/dev/null)
    local total_apps=$(echo "$apps" | jq -r '.items | length')
    local healthy_apps=0
    local unhealthy_apps=0
    
    echo "  Total applications: $total_apps"
    
    if [ "$total_apps" -eq 0 ]; then
        print_warning "  No applications found yet"
        return 1
    fi
    
    # Check each application
    while IFS=$'\t' read -r name sync_status health_status; do
        if [ -n "$name" ]; then
            if is_application_healthy "$name" "$sync_status" "$health_status"; then
                healthy_apps=$((healthy_apps + 1))
                echo "  ✅ $name ($sync_status/$health_status)"
            else
                unhealthy_apps=$((unhealthy_apps + 1))
                echo "  ❌ $name ($sync_status/$health_status)"
            fi
        fi
    done < <(echo "$apps" | jq -r '.items[] | "\(.metadata.name)\t\(.status.sync.status // "Unknown")\t\(.status.health.status // "Unknown")"')
    
    print_info "  Healthy applications: $healthy_apps/$total_apps"
    
    if [ "$unhealthy_apps" -gt 0 ]; then
        print_warning "  Unhealthy applications: $unhealthy_apps"
        return 1
    fi
    
    return 0
}

# Function to check overall readiness
check_readiness() {
    local current_time=$(date +%s)
    local elapsed=$((current_time - START_TIME))
    
    print_info "Elapsed time: $((elapsed / 60))m $((elapsed % 60))s"
    
    # Get ApplicationSet status
    get_applicationset_status
    local appset_count=$?
    
    # Check if we have a reasonable number of ApplicationSets
    if [ "$appset_count" -lt 5 ]; then
        print_warning "Waiting for more ApplicationSets to be created..."
        return 1
    fi
    
    # Check if ApplicationSet count is stable
    if [ "$STABLE_ITERATIONS" -lt "$REQUIRED_STABLE_ITERATIONS" ]; then
        print_warning "Waiting for ApplicationSet count to stabilize..."
        return 1
    fi
    
    # Get Application status
    if ! get_application_status; then
        return 1
    fi
    
    return 0
}

# Main waiting loop
print_step "Starting monitoring loop..."

while true; do
    current_time=$(date +%s)
    elapsed=$((current_time - START_TIME))
    
    # Check timeout
    if [ "$elapsed" -ge "$TIMEOUT_SECONDS" ]; then
        print_error "Timeout reached after ${TIMEOUT_MINUTES} minutes"
        print_info "Final status:"
        get_applicationset_status > /dev/null
        get_application_status || true
        exit 1
    fi
    
    # Check readiness
    if check_readiness; then
        print_success "All ApplicationSets and Applications are ready!"
        break
    fi
    
    print_info "Waiting ${CHECK_INTERVAL} seconds before next check..."
    sleep "$CHECK_INTERVAL"
done

# Final summary
print_header "Deployment Summary"
get_applicationset_status > /dev/null
get_application_status > /dev/null

current_time=$(date +%s)
total_elapsed=$((current_time - START_TIME))

print_success "ApplicationSets deployment completed successfully!"
print_info "Total time: $((total_elapsed / 60))m $((total_elapsed % 60))s"

print_header "Access Information"
DOMAIN_NAME=$(kubectl get secret peeks-hub-cluster -n argocd -o json | jq -r '.metadata.annotations.ingress_domain_name // ""')
if [ -n "$DOMAIN_NAME" ]; then
    echo -e "${CYAN}ArgoCD URL:${BOLD} https://$DOMAIN_NAME/argocd${NC}"
    echo -e "${CYAN}   Login:${BOLD} admin${NC}"
    echo -e "${CYAN}   Password:${BOLD} $IDE_PASSWORD${NC}"
fi
