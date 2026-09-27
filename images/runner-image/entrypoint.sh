#!/usr/bin/env bash
set -euo pipefail

mkdir -p /etc/gitlab-runner /var/lib/docker /var/run
rm -f /var/run/docker.pid

# The daemon and all job containers belong to this Runner container; no outer
# Podman or Docker socket is mounted here.
# fuse-overlayfs avoids direct nested overlay mounts while preserving a
# compatible copy-on-write filesystem for Docker-in-Docker on macOS Podman.
dockerd --host=unix:///var/run/docker.sock --storage-driver=fuse-overlayfs > /var/log/dockerd.log 2>&1 &
dockerd_pid=$!
trap 'kill "$dockerd_pid" "${proxy_pid:-}" 2>/dev/null || true' EXIT INT TERM

for attempt in $(seq 1 60); do
  if docker info >/dev/null 2>&1; then
    break
  fi
  if ! kill -0 "$dockerd_pid" 2>/dev/null; then
    cat /var/log/dockerd.log >&2
    exit 1
  fi
  sleep 1
done
docker info >/dev/null

# Nested Docker containers cannot resolve the outer Compose service name.
# config.toml gives them gitlab.local -> host-gateway; this proxy finishes the
# route to the GitLab service on the outer Compose network.
socat TCP-LISTEN:8929,bind=0.0.0.0,reuseaddr,fork TCP:gitlab:8929 &
proxy_pid=$!

exec gitlab-runner run --user=root --working-directory=/etc/gitlab-runner
