#!/usr/bin/env bash
# Register one public SSH key for local GitLab root through the GitLab API.
set -euo pipefail

gitlab_url="${GITLAB_URL:-http://localhost:8929}"
public_key_path="${SSH_PUBLIC_KEY_PATH:-${HOME}/.ssh/id_ed25519.pub}"
key_title="${SSH_KEY_TITLE:-local-gitlab-lab}"
api_token=""
api_token_id=""

fail() {
  printf 'Error: %s\n' "$*" >&2
  exit 1
}

command -v curl >/dev/null || fail "curl is required"
command -v jq >/dev/null || fail "jq is required"
command -v podman >/dev/null || fail "podman is required"
[[ "$gitlab_url" =~ ^https?://[^[:space:]]+$ ]] || fail "GITLAB_URL must be an http(s) URL"
[[ -r "$public_key_path" ]] || fail "SSH_PUBLIC_KEY_PATH is not readable: $public_key_path"
[[ -n "$key_title" ]] || fail "SSH_KEY_TITLE must not be empty"

public_key="$(<"$public_key_path")"
[[ "$public_key" == ssh-* ]] || fail "SSH_PUBLIC_KEY_PATH does not contain an OpenSSH public key"

revoke_temporary_token() {
  [[ -n "$api_token_id" ]] || return 0

  # The token is local-only and exists solely for this script. Do not print it.
  podman compose exec -T gitlab gitlab-rails runner \
    "PersonalAccessToken.find_by(id: ${api_token_id})&.destroy!" >/dev/null 2>&1 || true
}
trap revoke_temporary_token EXIT

# A fresh local lab has no API token available to learners. Create a temporary
# root token inside the local GitLab container, use it below, and revoke it in
# the EXIT trap. This is appropriate only for the trusted local learning lab.
bootstrap_output="$(podman compose exec -T gitlab gitlab-rails runner '
root = User.find_by_username("root") or abort("root user not found")
token = SecureRandom.hex(32)
pat = PersonalAccessToken.new(user: root, name: "ssh-key-bootstrap", scopes: ["api"], expires_at: Date.current + 1)
pat.set_token(token)
pat.save!
puts "API_TOKEN_ID=#{pat.id}"
puts "API_TOKEN=#{token}"
')" || fail "Could not create a temporary local API token; start GitLab first"

api_token_id="$(sed -n 's/^API_TOKEN_ID=//p' <<<"$bootstrap_output" | tail -n 1)"
api_token="$(sed -n 's/^API_TOKEN=//p' <<<"$bootstrap_output" | tail -n 1)"
[[ "$api_token_id" =~ ^[0-9]+$ && -n "$api_token" ]] \
  || fail "GitLab did not return a usable temporary API token"

# Query first so repeating the script is safe and does not trigger GitLab's
# duplicate-key validation error.
existing_keys="$(curl --fail --silent --show-error \
  --header "PRIVATE-TOKEN: ${api_token}" \
  "${gitlab_url}/api/v4/user/keys")" \
  || fail "Could not list SSH keys. Check GITLAB_URL and GITLAB_API_TOKEN"

if jq -e --arg key "$public_key" '.[] | select(.key == $key)' >/dev/null <<<"$existing_keys"; then
  printf 'The public key from %s is already registered for local GitLab root.\n' "$public_key_path"
  exit 0
fi

create_response="$(curl --silent --show-error \
  --request POST \
  --header "PRIVATE-TOKEN: ${api_token}" \
  --data-urlencode "title=${key_title}" \
  --data-urlencode "key=${public_key}" \
  --write-out $'\n%{http_code}' \
  "${gitlab_url}/api/v4/user/keys")" \
  || fail "Could not reach the local GitLab API"

create_status="${create_response##*$'\n'}"
response="${create_response%$'\n'*}"

if [[ "$create_status" == "400" ]] \
  && jq -e '(.message.key[]?, .message.fingerprint[]?, .message.fingerprint_sha256[]?) == "has already been taken"' \
    >/dev/null <<<"$response"; then
  # GitLab may normalize a public key differently in GET /user/keys. Its
  # duplicate-key response is definitive: the same key is already registered.
  printf 'The public key from %s is already registered for local GitLab root.\n' "$public_key_path"
  exit 0
fi

[[ "$create_status" == "201" ]] \
  || fail "Could not add the SSH key through the local GitLab API (HTTP ${create_status})"

printf 'Registered SSH key "%s" for local GitLab root (key ID %s).\n' \
  "$key_title" "$(jq -er '.id' <<<"$response")"
