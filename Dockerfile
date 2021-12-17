FROM amazonlinux:2 AS git-crypt-build

RUN yum install -y git make gcc-c++ openssl-devel openssl && \
    git clone https://www.agwa.name/git/git-crypt.git && \
    cd git-crypt && \
    make && \
    make install

FROM lacework/lacework-cli:latest AS lacework

FROM hashicorp/terraform:latest AS terraform
ARG TERRAFORM_VERSION
RUN test -n "${TERRAFORM_VERSION}"
COPY terraform-plugins.tf .
RUN mkdir -p /root/.terraform.d/plugins && \
    terraform providers mirror /root/.terraform.d/plugins/

FROM amazon/aws-cli:latest

RUN yum install -y bash curl unzip git gnupg python3 && \
    yum clean all && \
    rm -rf /var/cache/yum && \
    curl -sSL https://github.com/stedolan/jq/releases/download/jq-1.6/jq-linux64 -o /usr/local/bin/jq && \
    chmod +x /usr/local/bin/jq

COPY --from=git-crypt-build /usr/local/bin/git-crypt /usr/local/bin/git-crypt
COPY --from=terraform /root/.terraform.d/plugins /root/.terraform.d/plugins
COPY --from=terraform /bin/terraform /bin/terraform
COPY --from=lacework /usr/local/bin/lacework /usr/local/bin/lacework
COPY helper.sh /helper.sh
