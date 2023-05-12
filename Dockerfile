FROM hashicorp/terraform:latest AS terraform
ARG TERRAFORM_VERSION
RUN test -n "${TERRAFORM_VERSION}"
COPY terraform-plugins.tf .
RUN mkdir -p /root/.terraform.d/plugins && \
    terraform providers mirror /root/.terraform.d/plugins/

FROM truemark/aws-cli:amazonlinux-2023 AS base
COPY --from=truemark/git:amazonlinux-2023 /usr/local/ /usr/local/
COPY --from=truemark/git-crypt:amazonlinux-2023 /usr/local/ /usr/local/
COPY --from=truemark/aws-cli:latest helper.sh /helper.sh
COPY --from=terraform /root/.terraform.d/plugins /root/.terraform.d/plugins
COPY --from=terraform /bin/terraform /bin/terraform
RUN yum install -y zip unzip tar gnupg python3 findutils && \
    yum clean all && rm -rf /var/cache/yum
ENTRYPOINT ["/usr/bin/terraform"]
