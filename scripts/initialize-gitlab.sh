#!/usr/bin/env bash
# Create the local, first-install credential consumed by compose.yml.
set -euo pipefail

credential_file="local/gitlab-root-password.env"

if [[ "${1:-}" == "--help" ]]; then
  printf 'Usage: %s [--replace]\n' "$0"
  printf 'Creates %s without printing its password.\n' "$credential_file"
  exit 0
fi

if [[ "${1:-}" != "" && "${1:-}" != "--replace" ]]; then
  printf 'Usage: %s [--replace]\n' "$0" >&2
  exit 2
fi

if [[ -e "$credential_file" && "${1:-}" != "--replace" ]]; then
  printf 'Existing credential preserved at %s.\n' "$credential_file"
  printf 'To deliberately replace it, run %s --replace. This does not change an existing GitLab root password.\n' "$0"
  exit 0
fi

if ! command -v openssl >/dev/null 2>&1; then
  printf 'openssl is required to generate a cryptographically secure password.\n' >&2
  exit 1
fi

mkdir -p "$(dirname "$credential_file")"
umask 077
temporary_file="${credential_file}.tmp.$$"
trap 'rm -f "$temporary_file"' EXIT

# Hex encoding makes a high-entropy value that is safe in a dotenv file.
password="$(openssl rand -hex 32)"
printf 'GITLAB_ROOT_PASSWORD=%s\n' "$password" >"$temporary_file"
chmod 600 "$temporary_file" 2>/dev/null || true
mv "$temporary_file" "$credential_file"
trap - EXIT

printf 'Local GitLab root credential created at %s (password not printed).\n' "$credential_file"
printf 'It is applied only when GitLab creates its first database.\n'
