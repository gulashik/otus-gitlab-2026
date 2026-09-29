#!/usr/bin/env bash
# Create or reuse the local learning group, then create and register one runner.
set -euo pipefail

gitlab_url="${GITLAB_URL:-http://localhost:8929}"
runner_gitlab_url="${RUNNER_GITLAB_URL:-http://gitlab.local:8929}"
bootstrap_token="${GITLAB_BOOTSTRAP_TOKEN:-}"
bootstrap_token_id=""
group_id=""
group_access_token_id=""
generated_bootstrap_token=false
group_path="${GITLAB_GROUP_PATH:-gulash-prj}"
runner_name="${RUNNER_NAME:-gulash-team-runner}"
runner_tag="${RUNNER_TAG:-docker}"
token_name="${GROUP_ACCESS_TOKEN_NAME:-gulash-runner-bootstrap}"
token_expiry="${GROUP_ACCESS_TOKEN_EXPIRY:-$(date -u -v+1d +%F 2>/dev/null || date -u -d '+1 day' +%F)}"

fail() { printf 'Error: %s\n' "$*" >&2; exit 1; }
command -v curl >/dev/null || fail "curl is required"
command -v jq >/dev/null || fail "jq is required"
[[ "$gitlab_url" =~ ^https?://[^[:space:]]+$ ]] || fail "GITLAB_URL must be an http(s) URL"
[[ "$runner_gitlab_url" =~ ^https?://[^[:space:]]+$ ]] || fail "RUNNER_GITLAB_URL must be an http(s) URL"
[[ "$group_path" =~ ^[a-z0-9][a-z0-9-]*$ ]] || fail "GITLAB_GROUP_PATH must contain lowercase letters, digits, and hyphens"
[[ "$token_expiry" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]] || fail "GROUP_ACCESS_TOKEN_EXPIRY must use YYYY-MM-DD"

# In this local-only lab the script can mint its own one-day API token through
# GitLab's Rails console. An explicitly supplied token remains supported, but
# is never written, printed, or revoked by this script.
if [[ -z "$bootstrap_token" ]]; then
  bootstrap_output="$(podman compose exec -T gitlab gitlab-rails runner '
root = User.find_by_username("root") or abort("root user not found")
token = SecureRandom.hex(32)
pat = PersonalAccessToken.new(user: root, name: "runner-bootstrap", scopes: ["api"], expires_at: Date.current + 1)
pat.set_token(token)
pat.save!
puts "BOOTSTRAP_TOKEN_ID=#{pat.id}"
puts "BOOTSTRAP_TOKEN=#{token}"
')" || fail "Could not create a local bootstrap token; start GitLab first"
  bootstrap_token_id="$(sed -n 's/^BOOTSTRAP_TOKEN_ID=//p' <<<"$bootstrap_output" | tail -n 1)"
  bootstrap_token="$(sed -n 's/^BOOTSTRAP_TOKEN=//p' <<<"$bootstrap_output" | tail -n 1)"
  [[ "$bootstrap_token_id" =~ ^[0-9]+$ && -n "$bootstrap_token" ]] || fail "GitLab did not return a bootstrap token"
  generated_bootstrap_token=true
fi

revoke_temporary_tokens() {
  if [[ "$group_id" =~ ^[0-9]+$ && "$group_access_token_id" =~ ^[0-9]+$ ]]; then
    curl --silent --show-error --fail --request DELETE \
      --header "PRIVATE-TOKEN: ${bootstrap_token}" \
      "${gitlab_url}/api/v4/groups/${group_id}/access_tokens/${group_access_token_id}" >/dev/null 2>&1 || true
    group_access_token_id=""
  fi
  if [[ "$generated_bootstrap_token" == true && "$bootstrap_token_id" =~ ^[0-9]+$ ]]; then
    curl --silent --show-error --fail --request DELETE \
      --header "PRIVATE-TOKEN: ${bootstrap_token}" \
      "${gitlab_url}/api/v4/personal_access_tokens/${bootstrap_token_id}" >/dev/null 2>&1 || true
    bootstrap_token_id=""
  fi
}
trap revoke_temporary_tokens EXIT

# All validation completes before the first request that can create a group,
# access token, or runner. The response is discarded to protect credentials.
curl --fail --silent --show-error --location \
  --header "PRIVATE-TOKEN: ${bootstrap_token}" \
  "${gitlab_url}/api/v4/user" >/dev/null \
  || fail "GitLab URL or GITLAB_BOOTSTRAP_TOKEN could not be validated"

# A direct lookup makes the named top-level group safe to reuse on reruns.
group_response="$(curl --silent --show-error --location \
  --header "PRIVATE-TOKEN: ${bootstrap_token}" \
  -w '\n%{http_code}' "${gitlab_url}/api/v4/groups/${group_path}")"
group_status="${group_response##*$'\n'}"
group_body="${group_response%$'\n'*}"
if [[ "$group_status" == "200" ]]; then
  group_id="$(jq -er '.id' <<<"$group_body")" || fail "GitLab returned an invalid existing group"
  printf 'Reusing group "%s" (ID %s).\n' "$group_path" "$group_id"
elif [[ "$group_status" == "404" ]]; then
  group_body="$(curl --fail --silent --show-error --location \
    --request POST \
    --header "PRIVATE-TOKEN: ${bootstrap_token}" \
    --header "Content-Type: application/json" \
    --data "$(jq -nc --arg name "$group_path" --arg path "$group_path" '{name:$name,path:$path,visibility:"private"}')" \
    "${gitlab_url}/api/v4/groups")" || fail "Could not create group ${group_path}"
  group_id="$(jq -er '.id' <<<"$group_body")" || fail "GitLab returned an invalid created group"
  printf 'Created group "%s" (ID %s).\n' "$group_path" "$group_id"
else
  fail "Could not look up group ${group_path} (HTTP ${group_status})"
fi

# This short-lived token exists only in this process. It is neither logged nor saved.
access_token_response="$(curl --fail --silent --show-error --location \
  --request POST \
  --header "PRIVATE-TOKEN: ${bootstrap_token}" \
  --header "Content-Type: application/json" \
  --data "$(jq -nc --arg name "$token_name" --arg expires_at "$token_expiry" '{name:$name,scopes:["create_runner"],access_level:50,expires_at:$expires_at}')" \
  "${gitlab_url}/api/v4/groups/${group_id}/access_tokens")" \
  || fail "Could not create the short-lived group access token"
group_access_token="$(jq -er '.token' <<<"$access_token_response")" || fail "GitLab did not return a group access token"
group_access_token_id="$(jq -er '.id' <<<"$access_token_response")" || fail "GitLab did not return a group access token ID"

response="$(curl --fail --silent --show-error --location \
  --request POST \
  --header "PRIVATE-TOKEN: ${group_access_token}" \
  --header "Content-Type: application/json" \
  --data "$(jq -nc --argjson group_id "$group_id" --arg description "$runner_name" --arg tag "$runner_tag" '{runner_type:"group_type", group_id:$group_id, description:$description, tag_list:[$tag], run_untagged:false}')" \
  "${gitlab_url}/api/v4/user/runners")" \
  || fail "Could not create the group runner"

runner_token="$(jq -er '.token' <<<"$response")" || fail "GitLab did not return a runner authentication token"

# The server has issued the runner token, so neither API token is needed for
# local registration. Revoke both before invoking GitLab Runner.
revoke_temporary_tokens

# The API owns description, tag, and untagged-job policy for authentication
# tokens. Registration supplies only executor-local settings. No token is
# printed or written to a tracked file. Each repeat deliberately creates
# another distinct runner; delete the old one in GitLab first, or set a new
# RUNNER_NAME and RUNNER_TAG.
podman compose exec -T runner gitlab-runner register --non-interactive \
  --template-config /usr/local/share/gitlab-runner/config.toml.template \
  --url "$runner_gitlab_url" \
  --token "$runner_token" \
  --executor docker \
  --docker-host unix:///var/run/docker.sock \
  --docker-image alpine:3 \
  --docker-extra-hosts gitlab.local:host-gateway \
  --clone-url "$runner_gitlab_url"

podman compose exec -T runner gitlab-runner verify
printf 'Created and registered group runner "%s" with tag "%s". No token was printed.\n' "$runner_name" "$runner_tag"
