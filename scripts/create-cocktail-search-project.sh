#!/usr/bin/env bash
# Create or reuse the local GitLab group and empty cocktail-search project.
set -euo pipefail

gitlab_url="${GITLAB_URL:-http://localhost:8929}"
group_path="${GITLAB_GROUP_PATH:-gulash-prj}"
project_path="${GITLAB_PROJECT_PATH:-cocktail-search}"
api_token=""
api_token_id=""

fail() {
  printf 'Error: %s\n' "$*" >&2
  exit 1
}

api_response() {
  curl --silent --show-error \
    --header "PRIVATE-TOKEN: ${api_token}" \
    --write-out $'\n%{http_code}' \
    "$@"
}

revoke_temporary_token() {
  [[ -n "$api_token_id" ]] || return 0
  podman compose exec -T gitlab gitlab-rails runner \
    "PersonalAccessToken.find_by(id: ${api_token_id})&.destroy!" >/dev/null 2>&1 || true
}
trap revoke_temporary_token EXIT

command -v curl >/dev/null || fail "curl is required"
command -v jq >/dev/null || fail "jq is required"
command -v podman >/dev/null || fail "podman is required"
[[ "$gitlab_url" =~ ^https?://[^[:space:]]+$ ]] || fail "GITLAB_URL must be an http(s) URL"
[[ "$group_path" =~ ^[a-z0-9][a-z0-9-]*$ ]] || fail "GITLAB_GROUP_PATH must contain lowercase letters, digits, and hyphens"
[[ "$project_path" =~ ^[a-z0-9][a-z0-9-]*$ ]] || fail "GITLAB_PROJECT_PATH must contain lowercase letters, digits, and hyphens"

# This local-only convenience creates a temporary root token inside the
# container. It is never printed or saved, and the EXIT trap revokes it.
bootstrap_output="$(podman compose exec -T gitlab gitlab-rails runner '
root = User.find_by_username("root") or abort("root user not found")
token = SecureRandom.hex(32)
pat = PersonalAccessToken.new(user: root, name: "project-bootstrap", scopes: ["api"], expires_at: Date.current + 1)
pat.set_token(token)
pat.save!
puts "API_TOKEN_ID=#{pat.id}"
puts "API_TOKEN=#{token}"
')" || fail "Could not create a temporary local API token; start GitLab first"

api_token_id="$(sed -n 's/^API_TOKEN_ID=//p' <<<"$bootstrap_output" | tail -n 1)"
api_token="$(sed -n 's/^API_TOKEN=//p' <<<"$bootstrap_output" | tail -n 1)"
[[ "$api_token_id" =~ ^[0-9]+$ && -n "$api_token" ]] \
  || fail "GitLab did not return a usable temporary API token"

group_response="$(api_response "${gitlab_url}/api/v4/groups/${group_path}")" \
  || fail "Could not reach the local GitLab API"
group_status="${group_response##*$'\n'}"
group_body="${group_response%$'\n'*}"

if [[ "$group_status" == "200" ]]; then
  group_id="$(jq -er '.id' <<<"$group_body")" || fail "GitLab returned an invalid existing group"
  printf 'Reusing group "%s" (ID %s).\n' "$group_path" "$group_id"
elif [[ "$group_status" == "404" ]]; then
  group_response="$(api_response --request POST \
    --data-urlencode "name=${group_path}" \
    --data-urlencode "path=${group_path}" \
    --data-urlencode 'visibility=private' \
    "${gitlab_url}/api/v4/groups")" \
    || fail "Could not create group ${group_path}"
  group_status="${group_response##*$'\n'}"
  group_body="${group_response%$'\n'*}"
  [[ "$group_status" == "201" ]] || fail "Could not create group ${group_path} (HTTP ${group_status})"
  group_id="$(jq -er '.id' <<<"$group_body")" || fail "GitLab returned an invalid created group"
  printf 'Created group "%s" (ID %s).\n' "$group_path" "$group_id"
else
  fail "Could not look up group ${group_path} (HTTP ${group_status})"
fi

project_full_path="${group_path}/${project_path}"
project_encoded_path="${group_path}%2F${project_path}"
project_response="$(api_response "${gitlab_url}/api/v4/projects/${project_encoded_path}")" \
  || fail "Could not look up project ${project_full_path}"
project_status="${project_response##*$'\n'}"
project_body="${project_response%$'\n'*}"

if [[ "$project_status" == "200" ]]; then
  printf 'Reusing project "%s".\n' "$project_full_path"
elif [[ "$project_status" == "404" ]]; then
  project_response="$(api_response --request POST \
    --data-urlencode "name=${project_path}" \
    --data-urlencode "path=${project_path}" \
    --data-urlencode "namespace_id=${group_id}" \
    --data-urlencode 'visibility=private' \
    "${gitlab_url}/api/v4/projects")" \
    || fail "Could not create project ${project_full_path}"
  project_status="${project_response##*$'\n'}"
  project_body="${project_response%$'\n'*}"
  [[ "$project_status" == "201" ]] || fail "Could not create project ${project_full_path} (HTTP ${project_status})"
  printf 'Created empty project "%s".\n' "$project_full_path"
else
  fail "Could not look up project ${project_full_path} (HTTP ${project_status})"
fi

# Enables the project’s CI job token to push release Git tags back to the repository.
project_id="$(jq -er '.id' <<<"$project_body")" \
  || fail "GitLab returned an invalid project"
project_response="$(api_response --request PUT \
  --data-urlencode 'ci_push_repository_for_job_token_allowed=true' \
  "${gitlab_url}/api/v4/projects/${project_id}")" \
  || fail "Could not enable CI job-token tag pushes for ${project_full_path}"
project_status="${project_response##*$'\n'}"
project_body="${project_response%$'\n'*}"
[[ "$project_status" == "200" ]] \
  || fail "Could not enable CI job-token tag pushes for ${project_full_path} (HTTP ${project_status})"
jq -e '.ci_push_repository_for_job_token_allowed == true' <<<"$project_body" >/dev/null \
  || fail "GitLab did not enable CI job-token tag pushes for ${project_full_path}"
printf 'Enabled CI job-token repository pushes for "%s".\n' "$project_full_path"

# Allow only this application project's short-lived job tokens to clone the
# private shared CI helpers during deployment jobs.
ci_project_path="${group_path}/ci"
ci_project_encoded_path="${group_path}%2Fci"
ci_project_response="$(api_response "${gitlab_url}/api/v4/projects/${ci_project_encoded_path}")" \
  || fail "Could not look up shared CI project ${ci_project_path}"
ci_project_status="${ci_project_response##*$'\n'}"
ci_project_body="${ci_project_response%$'\n'*}"
[[ "$ci_project_status" == "200" ]] \
  || fail "Shared CI project ${ci_project_path} must exist before ${project_full_path} (HTTP ${ci_project_status})"
ci_project_id="$(jq -er '.id' <<<"$ci_project_body")" \
  || fail "GitLab returned an invalid shared CI project"

allowlist_response="$(api_response "${gitlab_url}/api/v4/projects/${ci_project_id}/job_token_scope/allowlist")" \
  || fail "Could not read the job-token allowlist for ${ci_project_path}"
allowlist_status="${allowlist_response##*$'\n'}"
allowlist_body="${allowlist_response%$'\n'*}"
[[ "$allowlist_status" == "200" ]] \
  || fail "Could not read the job-token allowlist for ${ci_project_path} (HTTP ${allowlist_status})"
if jq -e --argjson project_id "$project_id" --arg path "$project_full_path" \
  '.[] | select(.id == $project_id and .path_with_namespace == $path)' <<<"$allowlist_body" >/dev/null; then
  printf 'Job-token allowlist already contains "%s" for "%s".\n' "$project_full_path" "$ci_project_path"
else
  allowlist_response="$(api_response --request POST \
    --data-urlencode "target_project_id=${project_id}" \
    "${gitlab_url}/api/v4/projects/${ci_project_id}/job_token_scope/allowlist")" \
    || fail "Could not allow ${project_full_path} to read ${ci_project_path} helpers"
  allowlist_status="${allowlist_response##*$'\n'}"
  [[ "$allowlist_status" == "201" ]] \
    || fail "Could not allow ${project_full_path} to read ${ci_project_path} helpers (HTTP ${allowlist_status})"
  printf 'Allowed "%s" job tokens to read "%s".\n' "$project_full_path" "$ci_project_path"
fi

allowlist_response="$(api_response "${gitlab_url}/api/v4/projects/${ci_project_id}/job_token_scope/allowlist")" \
  || fail "Could not verify the job-token allowlist for ${ci_project_path}"
allowlist_status="${allowlist_response##*$'\n'}"
allowlist_body="${allowlist_response%$'\n'*}"
[[ "$allowlist_status" == "200" ]] \
  || fail "Could not verify the job-token allowlist for ${ci_project_path} (HTTP ${allowlist_status})"
jq -e --argjson project_id "$project_id" --arg path "$project_full_path" \
  '.[] | select(.id == $project_id and .path_with_namespace == $path)' <<<"$allowlist_body" >/dev/null \
  || fail "GitLab allowlist does not contain ${project_full_path}"

ssh_url="$(jq -er '.ssh_url_to_repo' <<<"$project_body")" \
  || fail "GitLab did not return an SSH clone URL"
expected_ssh_url="ssh://git@localhost:2222/${project_full_path}.git"
[[ "$ssh_url" == "$expected_ssh_url" ]] \
  || fail "GitLab advertised unexpected SSH URL: ${ssh_url}"

printf 'Verified SSH URL: %s\n' "$ssh_url"
