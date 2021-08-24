#!/usr/bin/env bash

set -euo pipefail

source /helper.sh
aws_authentication
git_crypt_unlock

AWS_ACCOUNT_ID="$(aws_current_account_id)"
export AWS_ACCOUNT_ID

if [[ -n "${LOCAL_PATH+x}" ]]; then
  cd "${LOCAL_PATH}" || exit 1
fi

COMMAND=${COMMAND:?'COMMAND variable is required'}
for CMD in "${!COMMAND@}"; do
  eval "${!CMD}"
done
