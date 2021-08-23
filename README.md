# Terraform Docker Images

This repository contains a set of docker image useful for working with
terraform. If you can, you should use the Hashicorp provided docker images
located at https://hub.docker.com/r/hashicorp/terraform. However, the images
in the Hashicorp provided repository are only based on Alpine Linux which does
not support tools like the AWS CLI v2 because of required glibc support.

## Images

truemark/terraform-aws
 - Based on the amazon/aws-cli:latest image which is based on Amazon Linux
 - Contains the latest aws command
 - Contains the latest terraform and terraform-bundle commands
 - Contains bash curl unzip jq git git-crypt and gnupg
 - Contains a /helper.sh script to assist with git-crypt and AWS authentication

truemark/terraform-aws-pipe
 - Based on the truemark/terraform-aws image
 - Entrypoint is modified to call /pipe.sh
 - Exposes AWS_ACCOUNT_ID environment variable to use in scripts
 - Supports changing directories using LOCAL_PATH
