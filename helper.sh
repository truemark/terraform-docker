#!/usr/bin/env bash

[[ "${BASH_VERSINFO:-0+x}" -lt 4 ]] && >&2 echo "bash 4 or greater required" && exit 1

# Prints arguments if DEBUG is set to true
function debug() {
  if [[ -n "${DEBUG+x}" ]] && [[ "${DEBUG}" == "true" ]]; then
    echo "${*}"
  fi
}

# This function requires the following variables be set
#  AWS_ACCESS_KEY_ID
#  AWS_SECRET_ACCESS_KEY
# This function will export the variables above.
function aws_default_authentication() {
  debug "Calling aws_default_authentication()"
  : "${AWS_ACCESS_KEY_ID:?'is a required variable'}"
  : "${AWS_SECRET_ACCESS_KEY:?'is a required variable'}"
  export AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY
  debug "AWS_ACCESS_KEY_ID=${AWS_ACCESS_KEY_ID}"
}

# This function requires the following variables be set
#  AWS_WEB_IDENTITY_TOKEN or AWS_WEB_IDENTITY_TOKEN_FILE
#  AWS_ROLE_ARN or AWS_OIDC_ROLE_ARN
# If not already set, this function will set AWS_WEB_IDENTITY_TOKEN_FILE and export
# the AWS_WEB_IDENTITY_TOKEN_FILE and AWS_ROLE_ARN variables.
function aws_oidc_authentication() {
  debug "Calling aws_oidc_authentication()"

  # BitBucket has standardized on AWS_OIDC_ROLE_ARN in most their pipes
  [[ -n "${AWS_OIDC_ROLE_ARN+x}" ]] && AWS_ROLE_ARN="${AWS_OIDC_ROLE_ARN}"
  AWS_ROLE_ARN=${AWS_ROLE_ARN:?'is a required variable or AWS_OIDC_ROLE_ARN must be set'}
  debug "AWS_ROLE_ARN=${AWS_ROLE_ARN}"

  if [[ -n "${AWS_WEB_IDENTITY_TOKEN+x}" ]]; then
    [[ "${AWS_WEB_IDENTITY_TOKEN}" == "" ]] && >&2 echo "AWS_WEB_IDENTITY_TOKEN was provided and is empty" && exit 1
    AWS_WEB_IDENTITY_TOKEN_FILE="$(mktemp -t web_identity_token.XXXXXXX)"
    chmod 600 "${AWS_WEB_IDENTITY_TOKEN_FILE}"
    echo "${AWS_WEB_IDENTITY_TOKEN}" >> "${AWS_WEB_IDENTITY_TOKEN_FILE}"
  fi

  : "${AWS_WEB_IDENTITY_TOKEN_FILE:?'is a required variable or AWS_WEB_IDENTITY_TOKEN must be set'}"
  debug "AWS_WEB_IDENTITY_TOKEN_FILE=${AWS_WEB_IDENTITY_TOKEN_FILE}"
  export AWS_WEB_IDENTITY_TOKEN_FILE AWS_ROLE_ARN
}

# Unsets variables used by AWS CLI & SDK for authentication
function aws_clear_authentication() {
  debug "Calling aws_clear_authentication()"
  unset AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN AWS_WEB_IDENTITY_TOKEN_FILE AWS_ROLE_ARN
  debug "Cleared authentication variables"
}

# Pushes authentication variables into the exported variable AWS_AUTHENTICATION_HISTORY
function aws_push_authentication_history() {
  debug "Calling aws_push_authentication_history()"
  [[ -z "${AWS_AUTHENTICATION_HISTORY+x}" ]] && declare -a arr
  [[ -n "${AWS_AUTHENTICATION_HISTORY+x}" ]] && mapfile -t arr <<< "${AWS_AUTHENTICATION_HISTORY}"
  local line=""
  [[ -n "${AWS_ACCESS_KEY_ID+x}" ]] && line="${line}export AWS_ACCESS_KEY_ID=\"${AWS_ACCESS_KEY_ID}\";"
  [[ -n "${AWS_SECRET_ACCESS_KEY+x}" ]] && line="${line}export AWS_SECRET_ACCESS_KEY=\"${AWS_SECRET_ACCESS_KEY}\";"
  [[ -n "${AWS_SESSION_TOKEN+x}" ]] && line="${line}export AWS_SESSION_TOKEN=\"${AWS_SESSION_TOKEN}\";"
  [[ -n "${AWS_WEB_IDENTITY_TOKEN_FILE+x}" ]] && line="${line}export AWS_WEB_IDENTITY_TOKEN_FILE=\"${AWS_WEB_IDENTITY_TOKEN_FILE}\";"
  [[ -n "${AWS_ROLE_ARN+x}" ]] && line="${line}export AWS_ROLE_ARN=\"${AWS_ROLE_ARN}\";"
  arr+=("${line}")
  AWS_AUTHENTICATION_HISTORY="$(IFS=$'\n'; echo "${arr[*]}")"
  export AWS_AUTHENTICATION_HISTORY
  debug "Pushed entry onto AWS_AUTHENTICATION_HISTORY"
}

# Pops authentication variables from AWS_AUTHENTICATION_HISTORY and unsets the variable if empty
function aws_pop_authentication_history() {
  debug "Calling aws_pop_authentication_history()"
  : "${AWS_AUTHENTICATION_HISTORY:?'variable is required'}"
  mapfile -t arr <<< "${AWS_AUTHENTICATION_HISTORY}"
  aws_clear_authentication
  eval "${arr[*]: -1}"
  unset 'arr[${#arr[@]}]'
  if [[ "${#arr[@]}" == "0" ]]; then
    unset AWS_AUTHENTICATION_HISTORY
  else
    AWS_AUTHENTICATION_HISTORY="$(IFS=$'\n'; echo "${arr[*]}")"
    export AWS_AUTHENTICATION_HISTORY
  fi
  debug "Popped entry off AWS_AUTHENTICATION_HISTORY"
}

# This function requires the following variables be set
#  AWS_ASSUME_ROLE_ARN
#  AWS_ROLE_SESSION_NAME
# This function will export the following variables
#  AWS_ACCESS_KEY_ID
#  AWS_SECRET_ACCESS_KEY
#  AWS_SESSION_TOKEN
#  AWS_AUTHENTICATION_HISTORY
function aws_assume_role() {
  debug "Calling aws_assume_role()"
  : "${AWS_ROLE_SESSION_NAME:?'variable is required'}"
  : "${AWS_ASSUME_ROLE_ARN:?'variable is required'}"
  ! command -v aws &> /dev/null && echo "aws command is missing" && exit 1
  ! command -v jq &> /dev/null && echo "jq command is missing" && exit 1

  # Fill in replacement variables
  local assume_role_arn_expanded
  assume_role_arn_expanded="$(eval "echo -n ${AWS_ASSUME_ROLE_ARN}")"
  debug "assume_role_arn_expanded=${assume_role_arn_expanded}"

  # Save the current state
  aws_push_authentication_history

  # Get the STS credentials and set them up for use
  local aws_sts_result
  aws_sts_result=$(aws sts assume-role --role-arn "${assume_role_arn_expanded}" --role-session-name "${AWS_ROLE_SESSION_NAME}")
  aws_clear_authentication
  AWS_ACCESS_KEY_ID=$(echo "${aws_sts_result}" | jq -r .Credentials.AccessKeyId)
  AWS_SECRET_ACCESS_KEY=$(echo "${aws_sts_result}" | jq -r .Credentials.SecretAccessKey)
  AWS_SESSION_TOKEN=$(echo "${aws_sts_result}" | jq -r .Credentials.SessionToken)
  export AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN
}

# Calls aws_assume_role if AWS_ASSUME_ROLE_ARN is set
function if_aws_assume_role() {
  debug "Calling if_aws_assume_role()"
  if [[ -n "${AWS_ASSUME_ROLE_ARN+x}" ]] && [[ "${AWS_ASSUME_ROLE_ARN}" != "" ]]; then
    aws_assume_role
  else
    debug "Skipping assume role"
  fi
}

# Entry function for AWS authentication which either uses default
# authentication or OIDC depending on what's set
#   AWS Default authentication requires:
#    - AWS_ACCESS_KEY_ID
#    - AWS_SECRET_ACCESS_KEY
#   AWS OIDC authentication requires:
#    - AWS_WEB_IDENTITY_TOKEN or AWS_WEB_IDENTITY_TOKEN_FILE
#    - AWS_ROLE_ARN
function aws_authentication() {
  debug "Calling aws_authentication()"
  if [[ -n "${AWS_WEB_IDENTITY_TOKEN+x}${AWS_WEB_IDENTITY_TOKEN_FILE+x}${AWS_ROLE_ARN+x}" ]]; then
    debug "Using aws_oidc_authentication"
    aws_oidc_authentication
  else
    debug "Using aws_default_authentication"
    aws_default_authentication
  fi
}

# Exports variable AWS_ACCOUNT_ID containing the current caller's account ID
function aws_account_id() {
  debug "Calling aws_account_id()"
  debug "Obtaining current AWS account ID"
  AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query 'Account' --output text)
  export AWS_ACCOUNT_ID
  debug "AWS_ACCOUNT_ID=${AWS_ACCOUNT_ID}"
}

# Obtains all AWS acount IDs in the caller's AWS organization, optionally filters
# them and then exports AWS_ACCOUNT_IDS containing the filtered result set.
#
# This function has the following optional variables as inputs which are used to
# filter down the list of accounts retrieved from the AWS organization
#   - AWS_EXCLUDE_ACCOUNT_IDS
#   - AWS_EXCLUDE_OU_IDS
function aws_organization_account_ids() {
  debug "Calling aws_organization_account_ids()"
  debug "Obtaining accounts from organization"
  AWS_ACCOUNT_IDS="$(aws organizations list-accounts --query 'Accounts[].[Id]' --output text --max-items 10000)"

  # Remove current account from list
  local id
  id=$(aws sts get-caller-identity --query 'Account' --output text)
  AWS_ACCOUNT_IDS="$(echo "${AWS_ACCOUNT_IDS}" | grep -v "${id}")"

  # Remove any accounts provided as arguments to the function
  for id in "${@}"; do
    AWS_ACCOUNT_IDS="$(echo "${AWS_ACCOUNT_IDS}" | grep -v "${id}")"
  done

  # Remove any accounts provided in AWS_EXCLUDE_ACCOUNT_IDS
  if [[ -n "${AWS_EXCLUDE_ACCOUNT_IDS+x}" ]]; then
    for id in ${AWS_EXCLUDE_ACCOUNT_IDS}; do
      AWS_ACCOUNT_IDS="$(echo "${AWS_ACCOUNT_IDS}" | grep -v "${id}")"
    done
  fi

  # Remove any accounts from OUs provided in AWS_EXCLUDE_OU_IDS
  if [[ -n "${AWS_EXCLUDE_OU_IDS+x}" ]]; then
    for oid in ${AWS_EXCLUDE_OU_IDS}; do
      for id in $(aws organizations list-accounts-for-parent --parent-id "${oid}" --query 'Accounts[].[Id]' --output text --max-items 10000); do
        AWS_ACCOUNT_IDS="$(echo "${AWS_ACCOUNT_IDS}" | grep -v "${id}")"
      done
    done
  fi

  export AWS_ACCOUNT_IDS
  debug "AWS_ACCOUNT_IDS=${AWS_ACCOUNT_IDS}"
}

# Turns off the AWS pager exporting the AWS_PAGER variable
function aws_pager_off() {
  export AWS_PAGER=""
}

# Removes all .terraform directories and .terraform.local.hcl files from the working directory
function terraform_cleanup() {
  debug "Calling terraform_cleanup()"
  debug "Removing .terraform directories and .terraform.local.hcl files"
  find . -type d -name ".terraform" -prune -exec rm -rf {} \;
  find . -type f -name ".terraform.local.hcl" -exec rm -f {} \;
  debug "Removal completed"
}

# Unlocks a repository with git-crypt. One of the following variables must be set
#  GIT_CRYPT_KEY - base64 encoded symmetric encryption key
#  GIT_CRYPT_KEY_FILE - location of the encryption key
function git_crypt_unlock() {
  debug "Calling git_crypt_unlock()"
  ! command -v git-crypt &> /dev/null && echo "git-crypt command is missing" && exit 1
  ! command -v base64 &> /dev/null && echo "base64 command is missing" && exit 1
  if [[ -n "${GIT_CRYPT_KEY+x}" ]] && [[ "${GIT_CRYPT_KEY}" != "" ]]; then
    keyfile="$(mktemp -t git_crypt_key.XXXXXXX)"
    chmod 600 "${keyfile}"
    echo -n "${GIT_CRYPT_KEY}" | base64 -d >> "${keyfile}"
    debug "Running git-crypt unlock \"${keyfile}\""
    git-crypt unlock "${keyfile}"
    rm -f "${keyfile}"
    return
  fi
  : "${GIT_CRYPT_KEY_FILE:?'is a required variable or GIT_CRYPT_KEY must be set to a non empty string'}"
  debug "GIT_CRYPT_KEY_FILE=${GIT_CRYPT_KEY_FILE}"
  git-crypt unlock "${GIT_CRYPT_KEY_FILE}"
}

# Calls git_crypt_unlock if GIT_CRYPT_KEY or GIT_CRYPT_KEY_FILE is set
function if_git_crypt_unlock() {
  debug "Calling if_git_crypt_unlock()"
  if [[ -n "${GIT_CRYPT_KEY+x}" ]] && [[ "${GIT_CRYPT_KEY}" != "" ]]; then
    git_crypt_unlock
  elif [[ -n "${GIT_CRYPT_KEY_FILE+x}" ]] && [[ "${GIT_CRYPT_KEY_FILE}" != "" ]]; then
    git_crypt_unlock
  else
    debug "Skipping git-crypt unlock"
  fi
}

# Expands variables in TF_BACKEND_CONFIG saving to a temp file
function tf_expand_backend_config() {
  debug "Calling tf_expand_backend_config()"
  : "${TF_BACKEND_CONFIG:?'is a required variable'}"
  local expanded
  expanded="$(eval "echo -n ${TF_BACKEND_CONFIG}")"
  if [[ ! -f "${expanded}" ]]; then
    >&2 echo "File ${expanded} does not exist" && exit 1
  fi
  debug "Expanding TF_BACKEND_CONFIG"
  debug "expanded=${expanded}"
  TF_BACKEND_CONFIG_EXPANDED="$(mktemp -t tf_backend_config.XXXXXXX)"
  eval "echo -e \"$(sed 's/"/\\"/g' "${expanded}")\"" > "${TF_BACKEND_CONFIG_EXPANDED}"
  export TF_BACKEND_CONFIG_EXPANDED
  debug "TF_BACKEND_CONFIG_EXPANDED=${TF_BACKEND_CONFIG_EXPANDED}"
}

# Expands variables if TF_BACKEND_CONFIG is set and TF_EXPAND_BACKEND_CONFIG is not set or is true
function if_tf_expand_backend_config() {
  debug "Executing if_tf_expand_backend_config()"
  if [[ -n "${TF_BACKEND_CONFIG+x}" ]] && { [[ -z "${TF_EXPAND_BACKEND_CONFIG+x}" ]] || [[ "${TF_EXPAND_BACKEND_CONFIG}" == "true" ]]; }; then
    tf_expand_backend_config
  else
    debug "Skipping terraform backend expansion"
  fi
}

# Executes terraform initialization
function tf_init() {
  debug "Executing tf_init()"
  debug "Initializing terraform"
  if [[ -n "${TF_BACKEND_CONFIG_EXPANDED+x}" ]]; then
    if [[ ! -f "${TF_BACKEND_CONFIG_EXPANDED}" ]]; then
      >&2 echo "File ${TF_BACKEND_CONFIG_EXPANDED} does not exist" && exit 1
    fi
    debug "terraform init -backend-config=\"${TF_BACKEND_CONFIG_EXPANDED}\""
    terraform init -backend-config="${TF_BACKEND_CONFIG_EXPANDED}"
  elif [[ -n "${TF_BACKEND_CONFIG+x}" ]]; then
    if [[ ! -f "${TF_BACKEND_CONFIG}" ]]; then
      >&2 echo "File ${TF_BACKEND_CONFIG} does not exist" && exit 1
    fi
    debug "terraform init -backend-config=\"${TF_BACKEND_CONFIG}\""
    terraform init -backend-config="${TF_BACKEND_CONFIG}"
  else
    debug "terraform init"
    terraform init
  fi
}

# Executes terraform initialization if TF_INIT is true
function if_tf_init() {
  debug "Executing if_tf_init()"
  if [[ -n "${TF_INIT+x}" ]] && [[ "${TF_INIT}" == "true" ]]; then
    tf_init
  else
    debug "Skipping terraform init"
  fi
}

# Creates the S3 and DynamoDB tables if TF_AWS_BOOTSTRAP is set to true.
# This function should be called after backend expansion.
function tf_aws_bootstrap() {
  debug "Executing tf_aws_bootstrap()"
  local bucket table config
  : "${TF_BACKEND_CONFIG:?'is a required variable'}"
  : "${AWS_DEFAULT_REGION:?'is a required variable'}"
  config="${TF_BACKEND_CONFIG}"
  if [[ -n "${TF_BACKEND_CONFIG_EXPANDED+x}" ]]; then
    config="${TF_BACKEND_CONFIG_EXPANDED}"
  fi
  bucket="$(grep bucket "${config}" | sed -e 's/.*=//' | xargs)"
  table="$(grep table "${config}" | sed -e 's/.*=//' | xargs)"
  if ! aws s3api head-bucket --bucket "${bucket}" 2>/dev/null 1>&2; then
    echo "Bootstrapping S3 bucket [${bucket}]"
    # Create bucket
    aws s3 mb "s3://${bucket}"
    # Setup encryption
    aws s3api put-bucket-encryption \
      --bucket "${bucket}" \
      --server-side-encryption-configuration '{"Rules": [{"ApplyServerSideEncryptionByDefault": {"SSEAlgorithm": "AES256"}}]}'
    # Setup versioning on bucket
    aws s3api put-bucket-versioning \
      --bucket "${bucket}" \
      --versioning-configuration Status=Enabled
    # Block public access
    aws s3api put-public-access-block \
      --bucket "${bucket}" \
      --public-access-block-configuration "BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true"
    sleep 5
  else
    debug "S3 bucket ${bucket} already exits"
  fi
  if ! aws dynamodb describe-table --table-name "${table}" 2>/dev/null 1>&2; then
    echo "Bootstrapping DynamoDB table [${table}]"
    aws dynamodb create-table \
      --region "${AWS_DEFAULT_REGION}" \
      --table-name "${table}" \
      --attribute-definitions AttributeName=LockID,AttributeType=S \
      --key-schema AttributeName=LockID,KeyType=HASH \
      --provisioned-throughput ReadCapacityUnits=1,WriteCapacityUnits=1
    sleep 5
  else
    debug "DynamoDB table ${table} already exists"
  fi
}

function if_tf_aws_bootstrap() {
  debug "Executing if_tf_aws_bootstrap()"
  if [[ -n "${TF_AWS_BOOTSTRAP+x}" ]] && [[ "${TF_AWS_BOOTSTRAP}" == "true" ]]; then
    tf_aws_bootstrap
  else
    debug "Skipping terraform bootstrap"
  fi
}
