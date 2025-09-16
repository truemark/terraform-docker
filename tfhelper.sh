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
  use_lockfile="$(grep -E '^use_lockfile\s*=\s*true' "${config}" || true)"
  if ! aws s3api head-bucket --bucket "${bucket}" 2>/dev/null 1>&2; then
    echo "Bootstrapping S3 bucket: ${bucket}"
    # Create bucket
    debug "Running aws s3 mb"
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
  if [[ -z "${use_lockfile}" ]]; then
    table="$(grep table "${config}" | sed -e 's/.*=//' | xargs)"
    echo "Using DynamoDB table: ${table}"
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
  else
    debug "use_lockfile = true found, skipping DynamoDB bootstrap commands"
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

# Assumes management account role for OU operations
function aws_assume_management_role() {
  : "${AWS_MANAGEMENT_ACCOUNT_ID:?'is a required variable'}"
  : "${AWS_MANAGEMENT_ROLE_NAME:?'is a required variable'}"
  
  local management_role_arn="arn:aws:iam::${AWS_MANAGEMENT_ACCOUNT_ID}:role/${AWS_MANAGEMENT_ROLE_NAME}"
  local session_name="${AWS_ROLE_SESSION_NAME:-terraform-ou-session}"
  
  # Store current credentials for later restoration
  export AWS_ORIGINAL_ACCESS_KEY_ID="${AWS_ACCESS_KEY_ID:-}"
  export AWS_ORIGINAL_SECRET_ACCESS_KEY="${AWS_SECRET_ACCESS_KEY:-}"
  export AWS_ORIGINAL_SESSION_TOKEN="${AWS_SESSION_TOKEN:-}"
  export AWS_ORIGINAL_WEB_IDENTITY_TOKEN="${AWS_WEB_IDENTITY_TOKEN:-}"
  export AWS_ORIGINAL_WEB_IDENTITY_TOKEN_FILE="${AWS_WEB_IDENTITY_TOKEN_FILE:-}"
  export AWS_ORIGINAL_ROLE_ARN="${AWS_ROLE_ARN:-}"
  
  # Assume the management role
  local assume_role_output
  assume_role_output=$(aws sts assume-role \
    --role-arn "${management_role_arn}" \
    --role-session-name "${session_name}" \
    --output json)
  
  if [[ $? -ne 0 ]]; then
    echo "Failed to assume management account role: ${management_role_arn}" >&2
    exit 1
  fi
  
  # Extract credentials from the response
  export AWS_ACCESS_KEY_ID=$(echo "${assume_role_output}" | jq -r '.Credentials.AccessKeyId')
  export AWS_SECRET_ACCESS_KEY=$(echo "${assume_role_output}" | jq -r '.Credentials.SecretAccessKey')
  export AWS_SESSION_TOKEN=$(echo "${assume_role_output}" | jq -r '.Credentials.SessionToken')
  
  # Clear OIDC variables to prevent conflicts
  unset AWS_WEB_IDENTITY_TOKEN
  unset AWS_WEB_IDENTITY_TOKEN_FILE
  unset AWS_ROLE_ARN
  
  export AWS_MANAGEMENT_ROLE_ASSUMED="true"
}

# Restores original credentials after OU operations
function aws_restore_original_credentials() {
  if [[ "${AWS_MANAGEMENT_ROLE_ASSUMED:-false}" == "true" ]]; then
    export AWS_ACCESS_KEY_ID="${AWS_ORIGINAL_ACCESS_KEY_ID:-}"
    export AWS_SECRET_ACCESS_KEY="${AWS_ORIGINAL_SECRET_ACCESS_KEY:-}"
    export AWS_SESSION_TOKEN="${AWS_ORIGINAL_SESSION_TOKEN:-}"
    export AWS_WEB_IDENTITY_TOKEN="${AWS_ORIGINAL_WEB_IDENTITY_TOKEN:-}"
    export AWS_WEB_IDENTITY_TOKEN_FILE="${AWS_ORIGINAL_WEB_IDENTITY_TOKEN_FILE:-}"
    export AWS_ROLE_ARN="${AWS_ORIGINAL_ROLE_ARN:-}"
    
    # Clean up temporary variables
    unset AWS_ORIGINAL_ACCESS_KEY_ID
    unset AWS_ORIGINAL_SECRET_ACCESS_KEY
    unset AWS_ORIGINAL_SESSION_TOKEN
    unset AWS_ORIGINAL_WEB_IDENTITY_TOKEN
    unset AWS_ORIGINAL_WEB_IDENTITY_TOKEN_FILE
    unset AWS_ORIGINAL_ROLE_ARN
    unset AWS_MANAGEMENT_ROLE_ASSUMED
  fi
}

# Recursively gets all account IDs under a given OU ID (including nested OUs)
function aws_ou_account_ids() {
  : "${AWS_OU_ID:?'is a required variable'}"
  
  local ou_id="${AWS_OU_ID}"
  local all_accounts=""
  local management_role_assumed_locally=false
  
  # Check if we need to assume management role for OU operations
  # Skip if we're in GitHub Actions or already authenticated with the management account
  if [[ "${AWS_SKIP_MANAGEMENT_ROLE_ASSUMPTION:-false}" == "true" ]]; then
    : # Skip management role assumption
  elif [[ -n "${AWS_MANAGEMENT_ACCOUNT_ID+x}" ]] && [[ -n "${AWS_MANAGEMENT_ROLE_NAME+x}" ]] && [[ "${AWS_MANAGEMENT_ROLE_ASSUMED:-false}" != "true" ]]; then
    # Check current account ID to avoid circular role assumption
    local current_account_id
    current_account_id=$(aws sts get-caller-identity --query Account --output text 2>/dev/null || echo "")
    
    if [[ "${current_account_id}" != "${AWS_MANAGEMENT_ACCOUNT_ID}" ]]; then
      aws_assume_management_role
      management_role_assumed_locally=true
    fi
  fi
  
  # Get direct accounts under this OU
  local direct_accounts
  direct_accounts=$(aws organizations list-accounts-for-parent --parent-id "${ou_id}" --query 'Accounts[?Status==`ACTIVE`].Id' --output text 2>/dev/null || echo "")
  
  if [[ -n "${direct_accounts}" ]]; then
    all_accounts="${direct_accounts}"
  fi
  
  # Get child OUs and recursively get their accounts
  local child_ous
  child_ous=$(aws organizations list-organizational-units-for-parent --parent-id "${ou_id}" --query 'OrganizationalUnits[].Id' --output text 2>/dev/null || echo "")
  
  if [[ -n "${child_ous}" ]]; then
    for child_ou in ${child_ous}; do
      local child_accounts
      child_accounts=$(aws_ou_account_ids_recursive "${child_ou}")
      if [[ -n "${child_accounts}" ]]; then
        if [[ -n "${all_accounts}" ]]; then
          all_accounts="${all_accounts} ${child_accounts}"
        else
          all_accounts="${child_accounts}"
        fi
      fi
    done
  fi
  
  # Restore original credentials if we assumed the management role locally
  if [[ "${management_role_assumed_locally}" == "true" ]]; then
    aws_restore_original_credentials
  fi
  
  # Remove duplicates and export
  if [[ -n "${all_accounts}" ]]; then
    all_accounts=$(echo "${all_accounts}" | tr ' ' '\n' | sort -u | tr '\n' ' ' | sed 's/[[:space:]]*$//')
    echo "${all_accounts}"
  else
    echo ""
  fi
}

# Helper function for recursive OU account discovery
function aws_ou_account_ids_recursive() {
  local ou_id="$1"
  local all_accounts=""
  
  # Get direct accounts under this OU
  local direct_accounts
  direct_accounts=$(aws organizations list-accounts-for-parent --parent-id "${ou_id}" --query 'Accounts[?Status==`ACTIVE`].Id' --output text 2>/dev/null || echo "")
  
  if [[ -n "${direct_accounts}" ]]; then
    all_accounts="${direct_accounts}"
  fi
  
  # Get child OUs and recursively get their accounts
  local child_ous
  child_ous=$(aws organizations list-organizational-units-for-parent --parent-id "${ou_id}" --query 'OrganizationalUnits[].Id' --output text 2>/dev/null || echo "")
  
  if [[ -n "${child_ous}" ]]; then
    for child_ou in ${child_ous}; do
      local child_accounts
      child_accounts=$(aws_ou_account_ids_recursive "${child_ou}")
      if [[ -n "${child_accounts}" ]]; then
        if [[ -n "${all_accounts}" ]]; then
          all_accounts="${all_accounts} ${child_accounts}"
        else
          all_accounts="${child_accounts}"
        fi
      fi
    done
  fi
  
  echo "${all_accounts}"
}

# Gets OU name for logging purposes
function aws_ou_name() {
  : "${AWS_OU_ID:?'is a required variable'}"
  
  local ou_name
  local management_role_assumed_locally=false
  
  # Check if we need to assume management role for OU operations
  # Skip if we're in GitHub Actions or already authenticated with the management account
  if [[ "${AWS_SKIP_MANAGEMENT_ROLE_ASSUMPTION:-false}" == "true" ]]; then
    : # Skip management role assumption
  elif [[ -n "${AWS_MANAGEMENT_ACCOUNT_ID+x}" ]] && [[ -n "${AWS_MANAGEMENT_ROLE_NAME+x}" ]] && [[ "${AWS_MANAGEMENT_ROLE_ASSUMED:-false}" != "true" ]]; then
    # Check current account ID to avoid circular role assumption
    local current_account_id
    current_account_id=$(aws sts get-caller-identity --query Account --output text 2>/dev/null || echo "")
    
    if [[ "${current_account_id}" != "${AWS_MANAGEMENT_ACCOUNT_ID}" ]]; then
      aws_assume_management_role
      management_role_assumed_locally=true
    fi
  fi
  
  ou_name=$(aws organizations describe-organizational-unit --organizational-unit-id "${AWS_OU_ID}" --query 'OrganizationalUnit.Name' --output text 2>/dev/null || echo "Unknown")
  
  # Restore original credentials if we assumed the management role locally
  if [[ "${management_role_assumed_locally}" == "true" ]]; then
    aws_restore_original_credentials
  fi
  
  echo "${ou_name}"
}

function terraform_cleanup() {
  debug "Calling terraform_cleanup()"
  debug "Removing .terraform directories and .terraform.local.hcl files"
  find . -type d -name ".terraform" -prune -exec rm -rf {} \;
  find . -type f -name ".terraform.local.hcl" -exec rm -f {} \;
  debug "Removal completed"
}
