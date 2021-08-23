#!/usr/bin/env bash

set -euo pipefail

source /helper.sh
aws_authentication
git_crypt_unlock

COMMAND=${COMMAND:?'COMMAND variable is required'}
echo "${COMMAND}"
set -x
for CMD in "${!COMMAND@}"; do
  eval "${!CMD}"
done
