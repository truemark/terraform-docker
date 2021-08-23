#!/usr/bin/env bash

function _aws_default_authentication() {
  AWS_ACCESS_KEY_ID=${AWS_ACCESS_KEY_ID:?'AWS_ACCESS_KEY_ID variable is required'}
  AWS_SECRET_ACCESS_KEY=${AWS_SECRET_ACCESS_KEY:?'AWS_SECRET_ACCESS_KEY variable is required'}
}

function _aws_oidc_authentication() {
  AWS_WEB_IDENTITY_TOKEN=${AWS_WEB_IDENTITY_TOKEN:?'AWS_WEB_IDENTITY_TOKEN variable is required'}
  AWS_WEB_IDENTITY_TOKEN_FILE="$(mktemp -t web_identity_token.XXXXXXX)"
  chmod 600 "${AWS_WEB_IDENTITY_TOKEN_FILE}"
  echo "${AWS_WEB_IDENTITY_TOKEN}" >> "${AWS_WEB_IDENTITY_TOKEN_FILE}"
  export AWS_WEB_IDENTITY_TOKEN_FILE AWS_ROLE_ARN="${AWS_OIDC_ROLE_ARN}"
  unset AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN
}

function _aws_assume_role() {
  if [[ -n "${AWS_ASSUME_ROLE_ARN+x}" ]]; then
    AWS_ROLE_SESSION_NAME=${AWS_ROLE_SESSION_NAME:?'AWS_ROLE_SESSION_NAME variable is required if AWS_ASSUME_ROLE_ARN is set'}
    TEMP_FILE="$(mktemp -t sts_credentials.XXXXXXX)"
    chmod 600 "${TEMP_FILE}"
    aws sts assume-role --role-arn "${AWS_ASSUME_ROLE_ARN}" --role-session-name "${AWS_ROLE_SESSION_NAME}" >> "${TEMP_FILE}"
    AWS_ACCESS_KEY_ID="$(jq -r .Credentials.AccessKeyId "${TEMP_FILE}")"
    AWS_SECRET_ACCESS_KEY="$(jq -r .Credentials.SecretAccessKey "${TEMP_FILE}")"
    AWS_SESSION_TOKEN="$(jq -r .Credentials.SessionToken "${TEMP_FILE}")"
    rm -f "${TEMP_FILE}"
    export AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN
    unset AWS_ROLE_ARN AWS_WEB_IDENTITY_TOKEN_FILE
  fi
}

# Entry function for AWS authentication which can handle OIDC and STS assume role.
#   AWS Default authentication requires:
#    - AWS_ACCESS_KEY_ID
#    - AWS_SECRET_ACCESS_KEY
#   AWS OIDC authentication requires:
#    - AWS_OIDC_ROLE_ARN
#    - AWS_WEB_IDENTITY_TOKEN
#   AWS Assume role requires:
#    - AWS_ASSUME_ROLE_ARN
#    - AWS_ROLE_SESSION_NAME
function aws_authentication() {
  AWS_DEFAULT_REGION=${AWS_DEFAULT_REGION:?'AWS_DEFAULT_REGION is required'}
  if ! command -v aws &> /dev/null; then echo "aws command missing"; exit 1; fi
  if ! command -v jq &> /dev/null; then echo "jq command missing"; exit 1; fi
  if [[ -n "${AWS_OIDC_ROLE_ARN+x}" ]]; then
    _aws_oidc_authentication
  else
    _aws_default_authentication
  fi
  _aws_assume_role
}

# Handles unlocking git-crypt if GIT_CRYPT_KEY is set. This function assumes
# you are in a directory containing a git repository.
function git_crypt_unlock() {
  if [[ -n "${GIT_CRYPT_KEY+x}" ]]; then
    if ! command -v git-crypt &> /dev/null; then echo "jq command missing"; exit 1; fi
    if ! command -v base64 &> /dev/null; then echo "base64 command missing"; exit 1; fi
    GIT_CRYPT_KEY_FILE="$(mktemp -t git_crypt_key)"
    chmod 600 "${GIT_CRYPT_KEY_FILE}"
    echo -n "${GIT_CRYPT_KEY}" | base64 -d >> "${GIT_CRYPT_KEY_FILE}"
    git-crypt unlock "${GIT_CRYPT_KEY_FILE}"
  fi
}
