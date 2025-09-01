# Terraform Docker Images

This repository builds the primary terraform docker image used by TrueMark.

## Usage

### Base Images

We do not recommend you use the **_latest_** tag. Instead we recommend using one of the following tags

 * truemark/terraform-aws:1.4-3 - Terraform 1.3 bundled with AWS Provider 3.x
 * truemark/terraform-aws:1.4-4 - Terraform 1.4 bundled with AWS Provider 4.x
 * truemark/terraform-aws:1.4-5 - Terraform 1.4 bundled with AWS Provider 5.x

These images are

* Based on the amazon/aws-cli:latest image which is based on Amazon Linux
* Contains the latest aws command
* Contains the latest terraform and terraform-bundle commands
* Contains bash curl unzip jq git git-crypt and gnupg
* Contains a /helper.sh script to assist with git-crypt and AWS authentication

### BitBucket Pipeline Images

* truemark/terraform-aws-pipe:1.4-3 - Terraform 1.3 bundled with AWS Provider 3.x
* truemark/terraform-aws-pipe:1.4-4 - Terraform 1.4 bundled with AWS Provider 4.x
* truemark/terraform-aws-pipe-1.4-5 - Terraform 1.4 bundled with AWS Provider 5.x

These images are

- Based on the truemark/terraform-aws image
- Entrypoint is modified to call /pipe.sh
- Exposes AWS_ACCOUNT_ID environment variable to use in scripts
- Supports changing directories using LOCAL_PATH
- **NEW**: Supports OU-based deployment with automatic account discovery

## OU-Based Deployment (New Feature)

The pipeline images now support automatic account discovery based on AWS Organizations OU IDs. Instead of manually specifying account IDs, you can provide an OU ID and the system will:

- Recursively discover all active accounts under the specified OU
- Handle nested OUs automatically
- Apply account exclusions if needed
- Deploy to all discovered accounts using a single backend configuration
- **NEW**: Support for management account role assumption for OU operations

### Management Account Role Support

For OU operations, the system can automatically assume a management account role to perform Organizations API calls, then switch back to individual account credentials for deployment. This is essential when the deployment credentials don't have direct access to AWS Organizations APIs.

The system will:
1. Use the management account role to discover accounts under the specified OU
2. Restore original credentials after OU discovery
3. For each discovered account, assume the appropriate deployment role
4. Execute terraform commands with account-specific credentials

### Environment Variables for OU-Based Deployment

- `AWS_OU_ID`: AWS Organizations OU ID (e.g., `ou-root-abc123def4`)
- `AWS_EXCLUDE_ACCOUNT_IDS`: Space-separated list of account IDs to exclude
- `AWS_MANAGEMENT_ACCOUNT_ID`: Management account ID for OU operations (required if using management role)
- `AWS_MANAGEMENT_ROLE_NAME`: Management account role name for OU operations (default: `github-security-provisioner`)

### Example Usage

#### Basic OU Deployment (using current credentials for OU operations)
```bash
docker run --rm \
  -e AWS_OU_ID="ou-root-abc123def4" \
  -e AWS_EXCLUDE_ACCOUNT_IDS="123456789012" \
  -e TF_BACKEND_CONFIG="backends/development.tfvars" \
  -e TF_INIT="true" \
  -e COMMAND="terraform plan" \
  -v $(pwd):/workspace \
  -w /workspace \
  truemark/terraform-aws-pipe:1.5-5
```

#### OU Deployment with Management Account Role
```bash
docker run --rm \
  -e AWS_OU_ID="ou-root-abc123def4" \
  -e AWS_MANAGEMENT_ACCOUNT_ID="123456789012" \
  -e AWS_MANAGEMENT_ROLE_NAME="org-management-role" \
  -e AWS_EXCLUDE_ACCOUNT_IDS="123456789012" \
  -e TF_BACKEND_CONFIG="backends/development.tfvars" \
  -e TF_INIT="true" \
  -e COMMAND="terraform plan" \
  -v $(pwd):/workspace \
  -w /workspace \
  truemark/terraform-aws-pipe:1.5-5
```

### How It Works

1. **OU Discovery Phase**: If `AWS_OU_ID` is provided, the system will:
   - Use management account role (if `AWS_MANAGEMENT_ACCOUNT_ID` is configured) to query AWS Organizations APIs
   - Or use current credentials if no management account is configured
2. **Account Discovery**: Recursively discovers all active accounts under the specified OU, including nested OUs
3. **Credential Restoration**: Restores original credentials after OU discovery
4. **Account Iteration**: For each discovered account:
   - Assumes the appropriate role for that account (using existing `AWS_ASSUME_ROLE_ARN` logic)
   - Executes terraform commands with account-specific credentials
   - Cleans up terraform state between accounts

This approach ensures that OU operations work seamlessly while maintaining backward compatibility with existing deployment patterns.
