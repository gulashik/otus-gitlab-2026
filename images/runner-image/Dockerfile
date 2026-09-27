FROM ubuntu:24.04

ARG GITLAB_RUNNER_VERSION=18.4.0

ENV DEBIAN_FRONTEND=noninteractive

# docker.io is the daemon used *inside* this image. socat is the explicit
# bridge from nested Docker jobs to the outer Compose GitLab service.
RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates curl docker.io fuse-overlayfs jq socat \
    && case "$(dpkg --print-architecture)" in amd64|arm64) runner_arch="$(dpkg --print-architecture)" ;; *) echo "Unsupported architecture: $(dpkg --print-architecture)" >&2; exit 1 ;; esac \
    && curl --fail --location --silent --show-error \
      "https://s3.dualstack.us-east-1.amazonaws.com/gitlab-runner-downloads/v${GITLAB_RUNNER_VERSION}/binaries/gitlab-runner-linux-${runner_arch}" \
      --output /usr/local/bin/gitlab-runner \
    && chmod 0755 /usr/local/bin/gitlab-runner \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

COPY entrypoint.sh /usr/local/bin/runner-entrypoint
COPY config.toml.template /usr/local/share/gitlab-runner/config.toml.template
RUN chmod 0755 /usr/local/bin/runner-entrypoint

ENTRYPOINT ["/usr/local/bin/runner-entrypoint"]
