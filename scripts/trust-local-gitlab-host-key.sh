#!/usr/bin/env bash
# Verify and trust the SSH host key of the local GitLab learning instance.
set -euo pipefail

gitlab_host="${GITLAB_SSH_HOST:-localhost}"
gitlab_port="${GITLAB_SSH_PORT:-2222}"
known_hosts_path="${SSH_KNOWN_HOSTS_PATH:-${HOME}/.ssh/known_hosts}"
scan_file="$(mktemp)"

fail() {
  printf 'Error: %s\n' "$*" >&2
  exit 1
}

cleanup() {
  rm -f "$scan_file"
}
trap cleanup EXIT

command -v podman >/dev/null || fail "podman is required"
command -v ssh-keyscan >/dev/null || fail "ssh-keyscan is required"
command -v ssh-keygen >/dev/null || fail "ssh-keygen is required"
[[ "$gitlab_host" != *[[:space:]]* ]] || fail "GITLAB_SSH_HOST must not contain whitespace"
[[ "$gitlab_port" =~ ^[0-9]+$ ]] || fail "GITLAB_SSH_PORT must be numeric"

# The key inside the local container is the trusted reference. The key read
# from the TCP endpoint must have the same SHA-256 fingerprint before it can be
# added to known_hosts.
reference_fingerprint="$(podman compose exec -T gitlab \
  ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub \
  | awk '$2 ~ /^SHA256:/ { print $2; exit }')"
[[ -n "$reference_fingerprint" ]] || fail "Could not read GitLab's ED25519 host-key fingerprint"

ssh-keyscan -p "$gitlab_port" -t ed25519 "$gitlab_host" >"$scan_file" 2>/dev/null \
  || fail "Could not read the SSH host key from ${gitlab_host}:${gitlab_port}"

scanned_fingerprint="$(ssh-keygen -lf "$scan_file" | awk '$2 ~ /^SHA256:/ { print $2; exit }')"
[[ -n "$scanned_fingerprint" ]] || fail "The scanned SSH key has no SHA-256 fingerprint"
[[ "$reference_fingerprint" == "$scanned_fingerprint" ]] \
  || fail "Host-key fingerprint mismatch; known_hosts was not changed"

host_pattern="[${gitlab_host}]:${gitlab_port}"
scanned_key="$(awk '$1 !~ /^#/ { print $2 " " $3; exit }' "$scan_file")"
[[ -n "$scanned_key" ]] || fail "Could not parse the scanned SSH key"

known_hosts_directory="$(dirname "$known_hosts_path")"
mkdir -p "$known_hosts_directory"
chmod 700 "$known_hosts_directory"
touch "$known_hosts_path"
chmod 600 "$known_hosts_path"

existing_keys="$(ssh-keygen -F "$host_pattern" -f "$known_hosts_path" 2>/dev/null \
  | awk '$1 !~ /^#/ { print $2 " " $3 }' || true)"

if [[ -n "$existing_keys" ]]; then
  distinct_key_count="$(sort -u <<<"$existing_keys" | sed '/^$/d' | wc -l | tr -d ' ')"
  if grep -Fqx "$scanned_key" <<<"$existing_keys" && [[ "$distinct_key_count" == "1" ]]; then
    printf 'GitLab host key for %s is already trusted.\n' "$host_pattern"
    exit 0
  fi

  # The current endpoint has already matched the key read directly from the
  # trusted local container. A recreated learning stand legitimately gets new
  # host keys, so replace only entries for this exact host and port.
  ssh-keygen -R "$host_pattern" -f "$known_hosts_path" >/dev/null
  printf 'Removed stale GitLab host-key entries for %s.\n' "$host_pattern"
fi

cat "$scan_file" >>"$known_hosts_path"
printf 'Verified and trusted GitLab host key for %s (%s).\n' \
  "$host_pattern" "$reference_fingerprint"
