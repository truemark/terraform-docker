#/usr/bin/env bash

# This script is only intended to be used for local development on this project.

set -euo pipefail

TERRAFORM_VERSION=$(curl -sSLf https://checkpoint-api.hashicorp.com/v1/check/terraform | jq -r .current_version)

docker build -t moo -f Dockerfile --build-arg TERRAFORM_VERSION="${TERRAFORM_VERSION}" --build-arg AWS_PROVIDER_VERSION=4.0 .
docker build -t moopipe -f pipe.Dockerfile --build-arg SOURCE_IMAGE=moo .
