# opa 1.22.0
FROM docker.io/openpolicyagent/opa@sha256:0000000000000000000000000000000000000000000000000000000000000000        AS opa
FROM docker.io/openpolicyagent/conftest@sha256:0000000000000000000000000000000000000000000000000000000000000000   AS conftest
FROM docker.io/hashicorp/terraform@sha256:0000000000000000000000000000000000000000000000000000000000000000        AS tf
COPY gate-image/tf-mirror/versions.tf /stub/versions.tf
RUN terraform -chdir=/stub providers mirror -platform=linux_amd64 /mirror
FROM registry.access.redhat.com/ubi9/ubi-minimal@sha256:0000000000000000000000000000000000000000000000000000000000000000
LABEL org.opencontainers.image.title="governance-gate" gate.tool.opa="1.22.0"
COPY --from=opa      /opa            /usr/local/bin/opa
COPY --from=tf       /mirror         /opt/tf-mirror
ENV TF_CLI_CONFIG_FILE=/etc/terraform.rc CHECKPOINT_DISABLE=1
USER 10001
WORKDIR /src
