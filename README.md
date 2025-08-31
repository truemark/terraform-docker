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

### Environment Variables for OU-Based Deployment

- `AWS_OU_ID`: AWS Organizations OU ID (e.g., `ou-root-abc123def4`)
- `AWS_EXCLUDE_ACCOUNT_IDS`: Space-separated list of account IDs to exclude

### Example Usage

```bash
docker run --rm \
  -e AWS_OU_ID="ou-root-abc123def4" \
  -e AWS_EXCLUDE_ACCOUNT_IDS="975050112768" \
  -e TF_BACKEND_CONFIG="backends/development.tfvars" \
  -e TF_INIT="true" \
  -e COMMAND="terraform plan" \
  -v $(pwd):/workspace \
  -w /workspace \
  truemark/terraform-aws-pipe:1.5-5
```

This will automatically discover all accounts under the specified OU and run the terraform command against each one.
