<!-- TOC -->
* [Run Gitlab instance](#run-gitlab-instance)
  * [Clear current gitlab instance](#clear-current-gitlab-instance)
  * [Show and generate Gitlab root password.](#show-and-generate-gitlab-root-password)
  * [Start GitLab in the background.](#start-gitlab-in-the-background)
  * [Verify readiness and sign in](#verify-readiness-and-sign-in)
<!-- TOC -->

# Run Gitlab instance
## Clear current gitlab instance
```bash
podman stop -a && podman rm -a && \
podman ps -a
rm -rf ./local/gitlab
```

## Show and generate Gitlab root password.
GitLab reads the initial password setting only when it creates its first database.
`./scripts/initialize-gitlab.sh --replace` intentionally generates a new file, but **does not change the password in an already-created GitLab database**.
```bash
clear
./scripts/initialize-gitlab.sh
clear
echo 'login: root' && \
grep '^GITLAB_ROOT_PASSWORD=' local/gitlab-root-password.env
```

## Start GitLab in the background.
Down
```bash
podman stop -a && podman rm -a && \
podman ps -a
```
Up
```bash
podman compose up -d
```

## Verify readiness and sign in
Logs
```bash
podman compose logs -f gitlab
```
Check that the sign-in page responds
```bash
curl -fsS http://localhost:8929/users/sign_in >/dev/null && echo "it's ok" || echo "not yet"
```

// ------------------------ //
Git-over-SSH endpoint is `ssh://git@localhost:2222/<group>/<project>.git`.
