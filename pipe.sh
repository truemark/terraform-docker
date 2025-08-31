#!/usr/bin/env bash

# This script uses the following variables to drive its behavior

# Used for default AWS authentication
# AWS_ACCESS_KEY_ID
# AWS_SECRET_ACCESS_KEY

# Used for OIDC AWS authentication
# AWS_WEB_IDENTITY_TOKEN or AWS_WEB_IDENTITY_TOKEN_FILE
# AWS_ROLE_ARN or AWS_OIDC_ROLE_ARN

# Used to assume a role with STS
# AWS_ASSUME_ROLE_ARN
# AWS_ROLE_SESSION_NAME

# Used to execute command against multiple accounts
# AWS_ACCOUNT_IDS
# AWS_EXCLUDE_ACCOUNT_IDS

# TF_INIT (true, false)
# TF_BACKEND_CONFIG (path to config)
# TF_EXPAND_BACKEND_CONFIG (default true)
# TF_AWS_BOOTSTRAP (default false)
# TF_WORKSPACE or TF_WORKSPACES

# Exit on command failure and unset variables
set -euo pipefail

# Import helper functions
source /usr/local/bin/tfhelper.sh

# Turn off the AWS pager
aws_pager_off

# Handle AWS authentication
aws_authentication

# Unlock with git-crypt if needed
if_git_crypt_unlock

# Change working directory if LOCAL_PATH is set
if [[ -n "${LOCAL_PATH+x}" ]]; then
  debug "Changing working directories"
  cd "${LOCAL_PATH}" || exit 1
  debug "LOCAL_PATH=${LOCAL_PATH}"
fi

# Validate command is set
COMMAND=${COMMAND:?'variable is required'}

if [[ -n "${AWS_OU_ID+x}" ]]; then
  # If AWS_OU_ID is set, discover all accounts under that OU
  echo "OU-based deployment detected. Discovering accounts under OU: ${AWS_OU_ID}"
  OU_NAME=$(aws_ou_name)
  echo "OU Name: ${OU_NAME}"
  
  # Get all accounts under the OU (including nested OUs)
  AWS_ACCOUNT_IDS=$(aws_ou_account_ids)
  
  if [[ -z "${AWS_ACCOUNT_IDS}" ]]; then
    echo "No active accounts found under OU ${AWS_OU_ID} (${OU_NAME})" >&2
    exit 1
  fi
  
  echo "Found accounts under OU ${AWS_OU_ID} (${OU_NAME}): ${AWS_ACCOUNT_IDS}"
  
  # Apply exclusions if AWS_EXCLUDE_ACCOUNT_IDS is set
  if [[ -n "${AWS_EXCLUDE_ACCOUNT_IDS+x}" ]] && [[ "${AWS_EXCLUDE_ACCOUNT_IDS}" != "" ]]; then
    echo "Applying account exclusions: ${AWS_EXCLUDE_ACCOUNT_IDS}"
    local excluded_accounts="${AWS_EXCLUDE_ACCOUNT_IDS}"
    local filtered_accounts=""
    
    for account_id in ${AWS_ACCOUNT_IDS}; do
      local exclude_account=false
      for excluded_id in ${excluded_accounts}; do
        if [[ "${account_id}" == "${excluded_id}" ]]; then
          exclude_account=true
          break
        fi
      done
      
      if [[ "${exclude_account}" == "false" ]]; then
        if [[ -n "${filtered_accounts}" ]]; then
          filtered_accounts="${filtered_accounts} ${account_id}"
        else
          filtered_accounts="${account_id}"
        fi
      fi
    done
    
    AWS_ACCOUNT_IDS="${filtered_accounts}"
    echo "Accounts after exclusions: ${AWS_ACCOUNT_IDS}"
  fi
  
elif [[ -z "${AWS_ACCOUNT_IDS+x}" ]]; then
  # If AWS_ACCOUNT_IDS is not set, set it to the current account ID
  aws_account_id
  AWS_ACCOUNT_IDS="${AWS_ACCOUNT_ID}"
else
  # Expand any expression that may be set
  AWS_ACCOUNT_IDS="$(eval "echo -n ${AWS_ACCOUNT_IDS}")"
fi

# If AWS_ACCOUNT_IDS is set to "all"
if [[ "${AWS_ACCOUNT_IDS}" == "all" ]]; then
  aws_organization_account_ids
fi

function print_heading() {
  echo ""
  echo "-------------------------------------------------------------------------------"
  echo "Executing command(s) in AWS account ${AWS_ACCOUNT_ID}"
  echo "Terraform Workspace: $(terraform workspace show)"
  echo "Working Directory: $(pwd)"
  echo "Commands:"
  for CMD in "${!COMMAND@}"; do
    echo "  ${!CMD}"
  done
  echo "-------------------------------------------------------------------------------"
  echo ""
}

# For each account, run command
for AWS_ACCOUNT_ID in $AWS_ACCOUNT_IDS; do

  # Revert authentication if history was set and clear terraform files
  if [[ -n "${AWS_AUTHENTICATION_HISTORY+x}" ]]; then
    aws_pop_authentication_history
    terraform_cleanup
  fi

  # Assume the role into the next account if needed
  if_aws_assume_role

  # Set AWS_ACCOUNT_ID and verify match
  aws_account_id

  # Optionally expand backend config
  if_tf_expand_backend_config

  # Optionally bootstrap terraform
  if_tf_aws_bootstrap

  # Optionally initialize terraform
  if_tf_init

  if [[ -n "${TF_WORKSPACES+x}" ]] && [[ "${TF_WORKSPACES}" != "" ]]; then
    if [[ "${TF_WORKSPACES}" == "all" ]]; then
      if [[ ! -f mapping.json ]]; then
        echo "mapping.json file is required when TF_WORKSPACES is set to 'all'" 2>&1 && exit 1
      fi
      TF_WORKSPACES="$(jq -r ".\"${AWS_ACCOUNT_ID}\"[]" mapping.json)"
      debug "TF_WORKSPACES=${TF_WORKSPACES}"
    fi
    for TF_WORKSPACE in ${TF_WORKSPACES}; do
      tf_mapping_check
      if_tf_workspace
      print_heading
      # Execute command(s)
      for CMD in "${!COMMAND@}"; do
        eval "${!CMD}"
      done
    done
  else
    # Execute command(s)
    tf_mapping_check
    if_tf_workspace
    print_heading
    for CMD in "${!COMMAND@}"; do
      eval "${!CMD}"
    done
  fi

done
