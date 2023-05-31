#!/usr/bin/env bash

export TERRAFORM_VERSION=$(curl -sSLf https://checkpoint-api.hashicorp.com/v1/check/terraform | jq -r .current_version)
export TERRAFORM_MINOR_VERSION=$(echo "${TERRAFORM_VERSION}" | cut -d '.' -f 1,2)