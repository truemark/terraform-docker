ARG TERRAFORM_VERSION
FROM hashicorp/terraform:${TERRAFORM_VERSION} AS terraform
ARG AWS_PROVIDER_VERSION
RUN printf "terraform {\nrequired_providers {\naws = {\nsource = \"hashicorp/aws\"\nversion = \"~> ${AWS_PROVIDER_VERSION}\"\n}\n}\n}" > terraform-plugins.tf && \
    mkdir -p /root/.terraform.d/plugins && \
    terraform providers mirror /root/.terraform.d/plugins/ && \
    rm -f terraform-plugins.tf

FROM truemark/aws-cli:amazonlinux-2023 AS base
COPY --from=truemark/git:amazonlinux-2023 /usr/local/ /usr/local/
COPY --from=truemark/git-crypt:amazonlinux-2023 /usr/local/ /usr/local/
COPY --from=terraform /root/.terraform.d/plugins /root/.terraform.d/plugins
COPY --from=terraform /bin/terraform /bin/terraform
COPY tfhelper.sh /usr/local/bin/tfhelper.sh
RUN yum install -y gnupg && yum clean all && rm -rf /var/cache/yum
ENTRYPOINT ["/usr/bin/terraform"]
