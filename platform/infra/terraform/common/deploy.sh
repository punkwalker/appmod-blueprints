#!/usr/bin/env bash

# Disable Terraform color output to prevent ANSI escape sequences
export TF_CLI_ARGS="-no-color"
set -euo pipefail

SCRIPTDIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
ROOTDIR="$(cd ${SCRIPTDIR}/../..; pwd )"
[[ -n "${DEBUG:-}" ]] && set -x


# Initialize Terraform
if [[ -n "${TFSTATE_BUCKET_NAME:-}" && -n "${TFSTATE_LOCK_TABLE:-}" ]]; then
  if ! terraform -chdir=$SCRIPTDIR init --upgrade \
    -backend-config="bucket=${TFSTATE_BUCKET_NAME}" \
    -backend-config="dynamodb_table=${TFSTATE_LOCK_TABLE}" \
    -backend-config="region=${AWS_REGION:-us-east-1}"; then
    echo "ERROR: Terraform init failed with remote backend"
    exit 1
  fi
else
  if ! terraform -chdir=$SCRIPTDIR init --upgrade; then
    echo "ERROR: Terraform init failed"
    exit 1
  fi
  echo "WARNING: TFSTATE_BUCKET_NAME and/or TFSTATE_LOCK_TABLE environment variables not set."
  echo "WARNING: Terraform state will be stored locally and may be lost!"
fi

echo "Applying git resources"

if ! terraform -chdir=$SCRIPTDIR apply -auto-approve; then
  echo "ERROR: Terraform apply failed"
  exit 1
fi

# wait for ssh access allowed
sleep 10
echo "SUCCESS: Common stack deployment completed successfully"

