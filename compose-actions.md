<!-- TOC -->
* [Recreate Gitlab instance](#recreate-gitlab-instance)
  * [Clear the current Gitlab instance](#clear-the-current-gitlab-instance)
  * [Show and generate a Gitlab root password.](#show-and-generate-a-gitlab-root-password)
  * [Start Gitlab in the background.](#start-gitlab-in-the-background)
  * [Verify readiness and sign in](#verify-readiness-and-sign-in)
* [Add and Register a Gitlab runner](#add-and-register-a-gitlab-runner)
  * [Build image: Ubuntu + Gitlab runner app + Docker app](#build-image-ubuntu--gitlab-runner-app--docker-app)
  * [Launch the Gitlab runner container and validate the docker image build process.](#launch-the-gitlab-runner-container-and-validate-the-docker-image-build-process)
    * [docker app check](#docker-app-check)
    * [runner app check](#runner-app-check)
  * [Register the Gitlab runner for the group `gulash-prj`](#register-the-gitlab-runner-for-the-group-gulash-prj)
* [Configure the GitLab ssh key](#configure-the-gitlab-ssh-key)
  * [Verify and trust the SSH host key of the local GitLab learning instance](#verify-and-trust-the-ssh-host-key-of-the-local-gitlab-learning-instance)
  * [Register the public SSH key for a local GitLab root through the GitLab API](#register-the-public-ssh-key-for-a-local-gitlab-root-through-the-gitlab-api)
  * [Test SSH without interactive host-key acceptance](#test-ssh-without-interactive-host-key-acceptance)
* [Add the SpringBoot app](#add-the-springboot-app)
  * [Register project `gulash-prj/cocktail-search`](#register-project-gulash-prjcocktail-search)
  * [Publish the tracked application source to local GitLab](#publish-the-tracked-application-source-to-local-gitlab)
  * [Verify feature and default-branch pipelines](#verify-feature-and-default-branch-pipelines)
* [Restart the Gitlab in the background.](#restart-the-gitlab-in-the-background)
  * [Suspend the training stand, keeping all container states intact.](#suspend-the-training-stand-keeping-all-container-states-intact-)
  * [Resume the training stand, restoring all container states.](#resume-the-training-stand-restoring-all-container-states)
  * [Wait for](#wait-for-)
<!-- TOC -->

# Recreate Gitlab instance
## Clear the current Gitlab instance
```bash
podman stop -a && podman rm -a && \
podman rmi -f otus-gitlab-runner:local
podman ps -a
rm -rf ./local/gitlab ./local/runner ./local/gitlab-root-password.env ./projects/cocktail-search/.git
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

## Start Gitlab in the background.
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
Check that the sign-in page responds – wait loop
```bash
until curl --fail --silent --show-error http://localhost:8929/users/sign_in >/dev/null; do
  echo "not yet"
  sleep 30
done
{ echo "GitLab is ready" && grep '^GITLAB_ROOT_PASSWORD=' local/gitlab-root-password.env }
```
Check that the sign-in page responds – manually
```bash
curl -fsS http://localhost:8929/users/sign_in >/dev/null && \
  { echo "it's ok" && grep '^GITLAB_ROOT_PASSWORD=' local/gitlab-root-password.env } || \
    echo "not yet"
```
Logs
```bash
podman compose logs -f gitlab
```

# Add and Register a Gitlab runner
## Build image: Ubuntu + Gitlab runner app + Docker app
```bash
podman compose build runner
```
## Launch the Gitlab runner container and validate the docker image build process.
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
## Register the Gitlab runner for the group `gulash-prj`
The command `podman compose exec -T runner gitlab-runner register ...` from the `register-group-runner.sh` adds a Docker-executor block to `local/runner/config/config.toml`
```bash
./scripts/register-group-runner.sh 
```
Verify that the runner is registered by running the command podman or by checking the UI at `http://localhost:8929/groups/gulash-prj/-/runners`
```bash
podman compose exec runner gitlab-runner verify
```

# Configure the GitLab ssh key
List an existing public key
```bash
ls ~/.ssh/id_ed25519.pub
```
If you do not have a suitable key, create a passphrase-protected Ed25519 key
```bash
# ssh-keygen -t ed25519 -C 'your@example.com'
```
## Verify and trust the SSH host key of the local GitLab learning instance
Careful, scripts affect file ~/.ssh/known_hosts
```bash 
./scripts/trust-local-gitlab-host-key.sh
```

## Register the public SSH key for a local GitLab root through the GitLab API
Register the public key in GitLab using either the UI or the included API script.

**UI**: In GitLab, select your avatar, then **Edit profile → Access → SSH keys**. Paste the contents of the chosen `.pub` file, give it a descriptive title, and add it.

**Script**:
```bash
./scripts/add-user-ssh-key.sh
```
## Test SSH without interactive host-key acceptance
This command makes both checks at once: GitLab must recognize your key, and your computer must recognize GitLab’s recorded host key.
GitLab responds with a greeting such as `Welcome to GitLab, @root!` if everything is good.
```bash 
ssh -o StrictHostKeyChecking=yes -p 2222 -T git@localhost
```

# Add the SpringBoot app
## Register project `gulash-prj/cocktail-search`
```bash
./scripts/create-cocktail-search-project.sh
```

## Link and Publish the subproject to the local GitLab repository
```bash
git -C projects/cocktail-search init --initial-branch=main
git -C projects/cocktail-search add .
git -C projects/cocktail-search commit -m 'Publish application to local GitLab'
git -C projects/cocktail-search remote add origin ssh://git@localhost:2222/gulash-prj/cocktail-search.git
git -C projects/cocktail-search push -u origin main
```

## Verify feature and default-branch pipelines
The initial push to `main` runs `test`, non-publishing `build_check`, and the
automatic `stage` placeholder, then waits at the blocking manual `prod` job.
Use **Play** for `prod` to complete its placeholder; neither deployment job
operates Podman. A feature-branch push runs only `build_check`.

Open `http://localhost:8929/gulash-prj/cocktail-search/-/pipelines` and confirm
the jobs match the branch you pushed. Check GitLab readiness separately with:
```bash
curl -fsS http://localhost:8929/users/sign_in >/dev/null && \
  { echo "it's ok" && grep '^GITLAB_ROOT_PASSWORD=' local/gitlab-root-password.env } || \
    echo "not yet started"
```

## Prepare the application source for a root repository commit

```bash
rm -rf ./projects/cocktail-search/.git
```
# Restart the Gitlab in the background.
## Suspend the training stand, keeping all container states intact. 
```bash
podman stop -a && podman ps -a
```
## Resume the training stand, restoring all container states.
```bash
podman compose up -d  && podman ps -a
```
## Wait for 
```bash
curl -fsS http://localhost:8929/users/sign_in >/dev/null && \
  { echo "it's ok" && grep '^GITLAB_ROOT_PASSWORD=' local/gitlab-root-password.env } || \
    echo "not yet"
```
