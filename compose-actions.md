<!-- TOC -->
* [Run/Rerun Gitlab instance](#runrerun-gitlab-instance)
  * [Clear the current gitlab instance](#clear-the-current-gitlab-instance)
  * [Show and generate a Gitlab root password.](#show-and-generate-a-gitlab-root-password)
  * [Start gitLab in the background.](#start-gitlab-in-the-background)
  * [Verify readiness and sign in](#verify-readiness-and-sign-in)
* [Add and Registration a gitlab runner](#add-and-registration-a-gitlab-runner)
  * [Build image: ubuntu + runner app + docker app](#build-image-ubuntu--runner-app--docker-app)
  * [Launch the gitLab runner container to validate the docker image build process.](#launch-the-gitlab-runner-container-to-validate-the-docker-image-build-process)
    * [docker app check](#docker-app-check)
    * [runner app check](#runner-app-check)
  * [Register the gitlab runner for the group `gulash-prj`](#register-the-gitlab-runner-for-the-group-gulash-prj)
* [Restart gitlab in the background.](#restart-gitlab-in-the-background)
  * [All down](#all-down-)
  * [All up](#all-up)
  * [Wait for](#wait-for-)
* [Not yet needed](#not-yet-needed)
<!-- TOC -->

# Run/Rerun Gitlab instance
## Clear the current gitlab instance
```bash
podman stop -a && podman rm -a && \
podman rmi -f otus-gitlab-runner:local
podman ps -a
rm -rf ./local/gitlab ./local/runner ./local/gitlab-root-password.env
```

## Show and generate a Gitlab root password.
GitLab reads the initial password setting only when it creates its first database.
`./scripts/initialize-gitlab.sh --replace` intentionally generates a new file, but **does not change the password in an already-created GitLab database**.
```bash
clear
./scripts/initialize-gitlab.sh
clear
echo 'login: root' && \
grep '^GITLAB_ROOT_PASSWORD=' local/gitlab-root-password.env
```

## Start gitLab in the background.
Up
```bash
podman compose up -d gitlab
```
Down if needed
```bash
podman stop -a && podman rm -a && \
podman ps -a
```

## Verify readiness and sign in
Logs
```bash
podman compose logs -f gitlab
```
Check that the sign-in page responds
```bash
curl -fsS http://localhost:8929/users/sign_in >/dev/null && \
  { echo "it's ok" && grep '^GITLAB_ROOT_PASSWORD=' local/gitlab-root-password.env } || \
    echo "not yet"
```

# Add and Registration a gitlab runner
## Build image: ubuntu + runner app + docker app
```bash
podman compose build runner
```
## Launch the gitLab runner container to validate the docker image build process.
```bash
podman compose up -d runner
```
### docker app check
`docker info` proves the internal daemon is ready
```bash
podman compose exec runner docker info
```
### runner app check
`gitlab-runner --version` proves the Runner binary is available
```bash
podman compose exec runner gitlab-runner --version
```
## Register the gitlab runner for the group `gulash-prj`
The command `podman compose exec -T runner gitlab-runner register ...` from the `register-group-runner.sh` adds a Docker-executor block to `local/runner/config/config.toml`
```bash
./scripts/register-group-runner.sh 
```
Verify that the runner is registered by running the command podman or by checking the UI at `http://localhost:8929/groups/gulash-prj/-/runners`
```bash
podman compose exec runner gitlab-runner verify
```

# Restart gitlab in the background.
## All down 
```bash
podman stop -a && podman ps -a
```
## All up
```bash
podman compose up -d  && podman ps -a
```
## Wait for 
```bash
curl -fsS http://localhost:8929/users/sign_in >/dev/null && \
  { echo "it's ok" && grep '^GITLAB_ROOT_PASSWORD=' local/gitlab-root-password.env } || \
    echo "not yet"
```

// ------------------------ //
# Not yet needed
Git-over-SSH endpoint is `ssh://git@localhost:2222/<group>/<project>.git`.
