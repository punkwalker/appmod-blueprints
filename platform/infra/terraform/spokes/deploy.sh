#!/usr/bin/env bash

set -euo pipefail

SCRIPTDIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
ROOTDIR="$(cd ${SCRIPTDIR}/../..; pwd )"
[[ -n "${DEBUG:-}" ]] && set -x

if [[ $# -eq 0 ]] ; then
    echo "No arguments supplied"
    echo "Usage: deploy.sh <environment> [--cluster-name-prefix <prefix>]"
    echo "Example: deploy.sh dev"
    echo "Example with custom cluster name prefix: deploy.sh dev --cluster-name-prefix peeks-spoke-test"
    exit 1
fi
env=$1
shift

# Parse additional command line arguments
CLUSTER_NAME_PREFIX=""

while [[ $# -gt 0 ]]; do
  key="$1"
  case $key in
    --cluster-name-prefix)
      CLUSTER_NAME_PREFIX="$2"
      shift
      shift
      ;;
    *)
      shift
      ;;
  esac
done

echo "Deploying $env with "workspaces/${env}.tfvars" ..."

if [[ -n "${TFSTATE_BUCKET_NAME:-}" && -n "${TFSTATE_LOCK_TABLE:-}" ]]; then
  terraform -chdir=$SCRIPTDIR init --upgrade -backend-config="bucket=${TFSTATE_BUCKET_NAME}" -backend-config="dynamodb_table=${TFSTATE_LOCK_TABLE}"
else
  terraform -chdir=$SCRIPTDIR init --upgrade
  echo "WARNING: TFSTATE_BUCKET_NAME and/or TFSTATE_LOCK_TABLE environment variables not set."
  echo "WARNING: Terraform state will be stored locally and may be lost!"
fi
terraform -chdir=$SCRIPTDIR workspace select -or-create $env

# Apply with custom cluster name prefix if provided
if [ -n "$CLUSTER_NAME_PREFIX" ]; then
  echo "Using custom cluster name prefix: $CLUSTER_NAME_PREFIX"
  terraform -chdir=$SCRIPTDIR apply -var-file="workspaces/${env}.tfvars" -var="cluster_name_prefix=$CLUSTER_NAME_PREFIX" -auto-approve
else
  echo "Using default cluster name prefix: peeks-spoke"
  terraform -chdir=$SCRIPTDIR apply -var-file="workspaces/${env}.tfvars" -auto-approve
fi
