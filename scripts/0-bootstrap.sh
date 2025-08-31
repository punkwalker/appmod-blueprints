#!/bin/bash

# Bootstrap script to run deployment scripts in order with retry logic
# Runs: 1-argocd-gitlab-setup.sh, 2-bootstrap-accounts.sh, and 6-tools-urls.sh in sequence
# Each script must succeed before proceeding to the next

set -e

# Source colors for output formatting
source "$(dirname "$0")/colors.sh"

# Configuration
MAX_RETRIES=3
RETRY_DELAY=30
SCRIPT_DIR="$(dirname "$0")"

# Define scripts to run in order
SCRIPTS=(
    "1-argocd-gitlab-setup.sh"
    "2-bootstrap-accounts.sh"
    "6-tools-urls.sh"
)

# Function to print colored output
print_status() {
    local status=$1
    local message=$2
    case $status in
        "INFO")
            echo -e "${BLUE}[INFO]${NC} $message"
            ;;
        "SUCCESS")
            echo -e "${GREEN}[SUCCESS]${NC} $message"
            ;;
        "ERROR")
            echo -e "${RED}[ERROR]${NC} $message"
            ;;
        "WARN")
            echo -e "${YELLOW}[WARN]${NC} $message"
            ;;
    esac
}

# Function to run script with retry logic
run_script_with_retry() {
    local script_path=$1
    local script_name=$(basename "$script_path")
    local attempt=1
    
    print_status "INFO" "Starting execution of $script_name"
    
    while [ $attempt -le $MAX_RETRIES ]; do
        print_status "INFO" "Attempt $attempt/$MAX_RETRIES for $script_name"
        
        if bash "$script_path"; then
            print_status "SUCCESS" "$script_name completed successfully"
            return 0
        else
            local exit_code=$?
            print_status "ERROR" "$script_name failed with exit code $exit_code (attempt $attempt/$MAX_RETRIES)"
            
            if [ $attempt -lt $MAX_RETRIES ]; then
                print_status "WARN" "Retrying $script_name in $RETRY_DELAY seconds..."
                sleep $RETRY_DELAY
            else
                print_status "ERROR" "$script_name failed after $MAX_RETRIES attempts"
                return $exit_code
            fi
        fi
        
        ((attempt++))
    done
}

# Main execution
main() {
    print_status "INFO" "Starting bootstrap deployment process"
    print_status "INFO" "Script directory: $SCRIPT_DIR"
    print_status "INFO" "Max retries per script: $MAX_RETRIES"
    print_status "INFO" "Retry delay: $RETRY_DELAY seconds"
    print_status "INFO" "Scripts to execute: ${SCRIPTS[*]}"
    
    for script_name in "${SCRIPTS[@]}"; do
        local script_path="$SCRIPT_DIR/$script_name"
        
        print_status "INFO" "Preparing to run: $script_name"
        
        if [ ! -f "$script_path" ]; then
            print_status "ERROR" "Script not found: $script_path"
            exit 1
        fi
        
        if [ ! -x "$script_path" ]; then
            print_status "ERROR" "Script not executable: $script_path"
            exit 1
        fi
        
        # Run script with retry logic
        if ! run_script_with_retry "$script_path"; then
            print_status "ERROR" "Bootstrap process failed at script: $script_name"
            exit 1
        fi
        
        print_status "SUCCESS" "Script $script_name completed successfully"
        echo "----------------------------------------"
    done
    
    print_status "SUCCESS" "Bootstrap deployment process completed successfully!"
    print_status "INFO" "All scripts have been executed successfully:"
    for script_name in "${SCRIPTS[@]}"; do
        print_status "INFO" "  ✓ $script_name"
    done
}

# Trap to handle script interruption
trap 'print_status "ERROR" "Bootstrap process interrupted"; exit 130' INT TERM

# Run main function
main "$@"
