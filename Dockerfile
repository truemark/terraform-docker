ARG TERRAFORM_VERSION
FROM hashicorp/terraform:${TERRAFORM_VERSION} AS terraform

FROM truemark/aws-cli:amazonlinux-2023 AS base
COPY --from=truemark/git:amazonlinux-2023 /usr/local/ /usr/local/
COPY --from=truemark/git-crypt:amazonlinux-2023 /usr/local/ /usr/local/
COPY --from=terraform /bin/terraform /bin/terraform
COPY tfhelper.sh /usr/local/bin/tfhelper.sh
RUN yum install -y gnupg && yum clean all && rm -rf /var/cache/yum
ENTRYPOINT ["/usr/bin/terraform"]
