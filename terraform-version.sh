#!/usr/bin/env bash
set -euo pipefail
curl -sSLf https://checkpoint-api.hashicorp.com/v1/check/terraform | jq -r .current_version
