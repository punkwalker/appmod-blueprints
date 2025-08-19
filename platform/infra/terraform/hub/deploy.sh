#!/usr/bin/env bash

set -euo pipefail

SCRIPTDIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
ROOTDIR="$(cd ${SCRIPTDIR}/../..; pwd )"
[[ -n "${DEBUG:-}" ]] && set -x

TF_VAR_FILE=${TF_VAR_FILE:-"terraform.tfvars"}

# Parse command line arguments
CLUSTER_NAME=""

while [[ $# -gt 0 ]]; do
  key="$1"
  case $key in
    --cluster-name)
      CLUSTER_NAME="$2"
      shift
      shift
      ;;
    *)
      shift
      ;;
  esac
done

# Initialize Terraform
terraform -chdir=$SCRIPTDIR init --upgrade

echo "Deploy Hub cluster"

# Apply with custom cluster name if provided
if [ -n "$CLUSTER_NAME" ]; then
  echo "Using custom cluster name: $CLUSTER_NAME"
  terraform -chdir=$SCRIPTDIR apply -var-file=$TF_VAR_FILE -var="cluster_name=$CLUSTER_NAME" -var="account_ids=$AWS_ACCOUNT_ID" -auto-approve
else
  echo "Using default cluster name: peeks-hub-cluster"
  terraform -chdir=$SCRIPTDIR apply  -var-file=$TF_VAR_FILE -var="account_ids=$AWS_ACCOUNT_ID" -auto-approve
fi
