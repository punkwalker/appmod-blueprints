#!/usr/bin/env bash

# Disable Terraform color output to prevent ANSI escape sequences
export TF_CLI_ARGS="-no-color"
set -uo pipefail

SCRIPTDIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
ROOTDIR="$(cd ${SCRIPTDIR}/..; pwd )"
[[ -n "${DEBUG:-}" ]] && set -x

echo "Destroying AWS git and iam resources"
if [[ -n "${TFSTATE_BUCKET_NAME:-}" && -n "${TFSTATE_LOCK_TABLE:-}" ]]; then
  if ! terraform -chdir=$SCRIPTDIR init --upgrade \
    -backend-config="bucket=${TFSTATE_BUCKET_NAME}" \
    -backend-config="dynamodb_table=${TFSTATE_LOCK_TABLE}" \
    -backend-config="region=${AWS_REGION:-us-east-1}"; then
    echo "ERROR: Terraform init failed with remote backend"
    exit 1
  fi
else
  # Try to get backend config from SSM parameters
  BUCKET_NAME=$(aws ssm get-parameter --name tf-backend-bucket --query 'Parameter.Value' --output text 2>/dev/null || echo "")
  LOCK_TABLE=$(aws ssm get-parameter --name tf-backend-lock-table --query 'Parameter.Value' --output text 2>/dev/null || echo "")
  
  if [[ -n "$BUCKET_NAME" && -n "$LOCK_TABLE" ]]; then
    if ! terraform -chdir=$SCRIPTDIR init --upgrade \
      -backend-config="bucket=${BUCKET_NAME}" \
      -backend-config="dynamodb_table=${LOCK_TABLE}" \
      -backend-config="region=${AWS_REGION:-us-east-1}"; then
      echo "ERROR: Terraform init failed with SSM backend config"
      exit 1
    fi
  else
    if ! terraform -chdir=$SCRIPTDIR init --upgrade; then
      echo "ERROR: Terraform init failed with local backend"
      exit 1
    fi
    echo "WARNING: Backend configuration not found in environment variables or SSM parameters."
    echo "WARNING: Terraform state will be stored locally and may be lost!"
  fi
fi

if ! terraform -chdir=$SCRIPTDIR destroy -auto-approve; then
  echo "ERROR: Common stack destroy failed"
  exit 1
fi

echo "SUCCESS: Common stack destroy completed successfully"

# Delete parameter created in the bootstrap
# aws ssm delete-parameter --name GiteaExternalUrl || true
# aws ssm delete-parameter --name GiteaExternalUrl || true
