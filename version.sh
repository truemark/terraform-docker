#!/usr/bin/env bash

set -euo pipefail
TERRAFORM_VERSION=$(curl -sSLf https://checkpoint-api.hashicorp.com/v1/check/terraform | jq -r .current_version)
echo "export TERRAFORM_VERSION=${TERRAFORM_VERSION}"
echo "export TERRAFORM_MINOR_VERSION=$(echo "${TERRAFORM_VERSION}" | cut -d '.' -f 1,2 )"