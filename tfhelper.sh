#!/usr/bin/env bash

source /usr/local/bin/helper.sh

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

# Creates or select workspace defined in TF_WORKSPACE
function tf_workspace() {
  debug "Executing tf_workspace()"
  : "${TF_WORKSPACE:?'is a required variable'}"
  debug "Switching to terraform workspace ${TF_WORKSPACE}"
  terraform workspace select "${TF_WORKSPACE}" || terraform workspace new "${TF_WORKSPACE}"
  echo "Terraform Workspace: ${TF_WORKSPACE}"
}

# Optionally creates or selects workspace is TF_WORKSPACE is defined
function if_tf_workspace() {
  debug "Executing if_tf_workspace()"
  if [[ -n "${TF_WORKSPACE+x}" ]] && [[ "${TF_WORKSPACE}" != "" ]]; then
    tf_workspace
  else
    debug "Skipping change terraform workspace"
  fi
}

function tf_mapping_check() {
  debug "Executing tf_mapping_check()"
  local workspace
  workspace="default"
  if [[ -n "${TF_WORKSPACE+x}" ]] && [[ "${TF_WORKSPACE}" != "" ]]; then
    workspace="${TF_WORKSPACE}"
  fi
  if [[ -f "./mapping.json" ]]; then
    debug "Checking mapping.json file for account ${AWS_ACCOUNT_ID} and workspace ${workspace}"
    : "${AWS_ACCOUNT_ID:?'variable is required'}"

    # Validate account is in the mapping file
    [[ $(jq "keys as \$k | \"${AWS_ACCOUNT_ID}\" | IN(\$k[])" "./mapping.json" 2> /dev/null) == "true" ]] || \
    (echo "Deployment target ${AWS_ACCOUNT_ID} is not valid according to mapping.json" 1>&2 && exit 1)

    # Validate workspace is allowed in the account
    [[ $(jq ".\"${AWS_ACCOUNT_ID}\" as \$d | \"${workspace}\" | IN(\$d[])" "./mapping.json" 2> /dev/null) == "true" ]] || \
    (echo "Workspace ${workspace} is not valid for ${AWS_ACCOUNT_ID} according to mapping.json" 1>&2 && exit 1)
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
  debug "Backend config file: ${TF_BACKEND_CONFIG}"
  debug "Backend config file expanded: ${TF_BACKEND_CONFIG_EXPANDED}"
  bucket="$(grep bucket "${config}" | sed -e 's/.*=//' | xargs)"
  echo "Using S3 bucket: ${bucket}"
  table="$(grep table "${config}" | sed -e 's/.*=//' | xargs)"
  echo "Using DynamoDB table: ${table}"
  if ! aws s3api head-bucket --bucket "${bucket}" 2>/dev/null 1>&2; then
    echo "Bootstrapping S3 bucket: ${bucket}"
    # Create bucket
    aws --version
    debug "Running aws s3 mb s3://${bucket}"
    aws s3 mb "s3://${bucket}"
    # Setup encryption
    debug "Running aws s3api put-bucket-encryption"
    aws s3api put-bucket-encryption \
      --bucket "${bucket}" \
      --server-side-encryption-configuration '{"Rules": [{"ApplyServerSideEncryptionByDefault": {"SSEAlgorithm": "AES256"}}]}'
    # Setup versioning on bucket
    debug "Running aws s3api put-bucket-versioning"
    aws s3api put-bucket-versioning \
      --bucket "${bucket}" \
      --versioning-configuration Status=Enabled
    # Block public access
    debug "Running aws s3api put-public-access-block"
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

function terraform_cleanup() {
  debug "Calling terraform_cleanup()"
  debug "Removing .terraform directories and .terraform.local.hcl files"
  find . -type d -name ".terraform" -prune -exec rm -rf {} \;
  find . -type f -name ".terraform.local.hcl" -exec rm -f {} \;
  debug "Removal completed"
}
