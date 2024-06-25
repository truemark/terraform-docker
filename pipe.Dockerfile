ARG SOURCE_IMAGE
FROM $SOURCE_IMAGE as base
COPY pipe.sh /pipe.sh
RUN git config --global --add safe.directory /opt/atlassian/pipelines/agent/build
ENTRYPOINT ["/pipe.sh"]
