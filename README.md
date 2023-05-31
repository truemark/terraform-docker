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
