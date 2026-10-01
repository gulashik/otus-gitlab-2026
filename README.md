# OTUS GitLab learning lab

This repository is a hands-on, local GitLab CE learning lab for  [OTUS course](https://otus.ru/lessons/cicd_gitlab/). 

## Environment 

- macOS with Podman and Podman Compose (Docker Compose also works for the GitLab service).
- Bash, Git, OpenSSH, `curl`, and `jq` etc.
- Podman machine with 16 GB of memory, sufficient disk space, and host ports `8929` and `2222` available.

The lab stores its GitLab data and local credentials under `local/`. Those files are intentionally ignored and must never be committed or shared.

## Ineractive GitLab lab start

```bash
./scripts/start-lab-dashboard.sh
```
## See also
- [compose-actions.md](compose-actions.md) — the existing command-by-command guide for starting, restarting, and configuring the local GitLab lab.