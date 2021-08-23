FROM golang:alpine AS terraform-bundler-build

ARG TERRAFORM_VERSION
RUN test -n "${TERRAFORM_VERSION}"

RUN apk --no-cache add git unzip jq curl && \
    git clone --single-branch --branch=v0.15 --depth=1 https://github.com/hashicorp/terraform.git && \
    cd terraform && \
    go build -o ../terraform-bundle ./tools/terraform-bundle && \
    mv /go/terraform-bundle /bin/

COPY terraform-bundle.hcl .

RUN sed -i "s/TERRAFORM_VERSION/${TERRAFORM_VERSION}/" terraform-bundle.hcl && \
    terraform-bundle package terraform-bundle.hcl && \
    mkdir -p terraform-bundle && \
    unzip -d terraform-bundle terraform_*.zip

FROM amazon/aws-cli:latest

RUN yum install -y bash curl unzip jq git git-crypt && \
    yum clean all && \
    rm -rf /var/cache/yum

COPY --from=terraform-bundler-build /go/terraform-bundle/plugins /root/.terraform.d/plugins
COPY --from=terraform-bundler-build /go/terraform-bundle/terraform /usr/bin/terraform
