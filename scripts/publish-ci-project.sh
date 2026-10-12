#!/usr/bin/env bash
# Create the shared CI project and publish the tracked repository contents.
set -euo pipefail

project_dir="${CI_PROJECT_DIR:-projects/ci}"
remote_url="${CI_PROJECT_REMOTE_URL:-ssh://git@localhost:2222/gulash-prj/ci.git}"
branch="main"

fail() {
  printf 'Error: %s\n' "$*" >&2
  exit 1
}

[[ -d "$project_dir" ]] || fail "Shared CI source directory does not exist: ${project_dir}"
[[ -f "${project_dir}/pipeline.yml" ]] || fail "Missing ${project_dir}/pipeline.yml"
[[ -d "${project_dir}/common" ]] || fail "Missing ${project_dir}/common"
[[ -d "${project_dir}/stages" ]] || fail "Missing ${project_dir}/stages"

./scripts/create-ci-project.sh

if [[ ! -d "${project_dir}/.git" ]]; then
  git -C "$project_dir" init --initial-branch="$branch"
else
  git -C "$project_dir" switch --quiet --create "$branch" 2>/dev/null \
    || git -C "$project_dir" switch --quiet "$branch"
fi

git -C "$project_dir" add pipeline.yml common stages
if ! git -C "$project_dir" diff --cached --quiet; then
  git -C "$project_dir" commit -m 'Publish shared CI configuration'
fi

if git -C "$project_dir" remote get-url origin >/dev/null 2>&1; then
  git -C "$project_dir" remote set-url origin "$remote_url"
else
  git -C "$project_dir" remote add origin "$remote_url"
fi

git -C "$project_dir" push --set-upstream origin "$branch"
local_revision="$(git -C "$project_dir" rev-parse "refs/heads/${branch}")"
remote_revision="$(git -C "$project_dir" ls-remote --heads origin "refs/heads/${branch}" | awk 'NR == 1 { print $1 }')"
[[ -n "$remote_revision" ]] || fail "GitLab did not publish origin/${branch}"
[[ "$local_revision" == "$remote_revision" ]] \
  || fail "Remote ${branch} revision ${remote_revision} differs from local ${local_revision}"

printf 'Published gulash-prj/ci %s at %s.\n' "$branch" "$remote_revision"
