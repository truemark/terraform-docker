#!/usr/bin/env bash

set -euo pipefail

source /helper.sh
aws_authentication
git_crypt_unlock

AWS_ACCOUNT_ID="$(aws_current_account_id)"
export AWS_ACCOUNT_ID

if [[ -z "${SAM_CLI_TELEMETRY+x}" ]]; then
  SAM_CLI_TELEMETRY=0
fi
export SAM_CLI_TELEMETRY

if [[ -n "${LOCAL_PATH+x}" ]]; then
  cd "${LOCAL_PATH}" || exit 1
fi

COMMAND=${COMMAND:?'COMMAND variable is required'}
for CMD in "${!COMMAND@}"; do
  eval "${!CMD}"
done
