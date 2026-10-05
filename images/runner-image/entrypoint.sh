#!/usr/bin/env bash
set -euo pipefail

mkdir -p /etc/gitlab-runner /var/lib/docker /var/run
rm -f /var/run/docker.pid
gitlab_proxy_pid=''
registry_proxy_pid=''

# The daemon and all job containers belong to this Runner container; no outer
# Podman or Docker socket is mounted here.
# fuse-overlayfs avoids direct nested overlay mounts while preserving a
# compatible copy-on-write filesystem for Docker-in-Docker on macOS Podman.
# The lab Registry deliberately uses local HTTP only.
dockerd --host=unix:///var/run/docker.sock --storage-driver=fuse-overlayfs \
  --insecure-registry=registry.localhost:5000 > /var/log/dockerd.log 2>&1 &
dockerd_pid=$!
trap 'kill "$dockerd_pid" "$gitlab_proxy_pid" "$registry_proxy_pid" 2>/dev/null || true' EXIT INT TERM

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

# Nested Docker containers cannot resolve the outer Compose service names.
# config.toml maps each documented lab hostname to host-gateway; these proxies
# finish the routes on the outer Compose network.
socat TCP-LISTEN:8929,bind=0.0.0.0,reuseaddr,fork TCP:gitlab:8929 &
gitlab_proxy_pid=$!
socat TCP-LISTEN:5000,bind=0.0.0.0,reuseaddr,fork TCP:registry:5000 &
registry_proxy_pid=$!

exec gitlab-runner run --user=root --working-directory=/etc/gitlab-runner
