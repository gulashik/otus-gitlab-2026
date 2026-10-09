#!/usr/bin/env bash
# Deploy one persistent local environment through the Runner's internal Docker daemon.
set -euo pipefail

environment_name=${1:?Usage: deploy-environment.sh <stage|prod> <host-port> <image-reference>}
host_port=${2:?Usage: deploy-environment.sh <stage|prod> <host-port> <image-reference>}
app_image_ref=${3:?Usage: deploy-environment.sh <stage|prod> <host-port> <image-reference>}

case "$environment_name" in
  stage|prod) ;;
  *) echo "Environment must be stage or prod." >&2; exit 2 ;;
esac
[[ "$host_port" =~ ^[0-9]+$ ]] || { echo "Host port must be numeric." >&2; exit 2; }

network_name="cocktail-search-${environment_name}"
database_name="cocktail-search-${environment_name}-postgres"
database_volume="cocktail-search-${environment_name}-postgres-data"
application_name="cocktail-search-${environment_name}"
database_password=${DB_PASSWORD:-cocktail-local-only}

docker network inspect "$network_name" >/dev/null 2>&1 || docker network create "$network_name" >/dev/null
docker volume inspect "$database_volume" >/dev/null 2>&1 || docker volume create "$database_volume" >/dev/null

if ! docker container inspect "$database_name" >/dev/null 2>&1; then
  docker run --detach --name "$database_name" --restart unless-stopped \
    --network "$network_name" \
    --volume "${database_volume}:/var/lib/postgresql/data" \
    --env POSTGRES_DB=cocktail_catalog \
    --env POSTGRES_USER=cocktail \
    --env POSTGRES_PASSWORD="$database_password" \
    postgres:17.11-alpine3.24 >/dev/null
elif [[ "$(docker container inspect --format '{{.State.Running}}' "$database_name")" != "true" ]]; then
  docker start "$database_name" >/dev/null
fi

# Pull before removing the current application. The database and its volume remain intact.
docker pull "$app_image_ref" >/dev/null
if docker container inspect "$application_name" >/dev/null 2>&1; then
  docker rm --force "$application_name" >/dev/null
fi

docker run --detach --name "$application_name" --restart unless-stopped \
  --network "$network_name" --publish "${host_port}:8080" \
  --env DB_HOST="$database_name" \
  --env DB_PORT=5432 \
  --env DB_NAME=cocktail_catalog \
  --env DB_USER=cocktail \
  --env DB_PASSWORD="$database_password" \
  "$app_image_ref" >/dev/null

for attempt in $(seq 1 60); do
  if docker run --rm --network "$network_name" alpine:3.21 \
    wget --quiet --output-document=/dev/null "http://${application_name}:8080/actuator/health"; then
    echo "${environment_name} is healthy after ${attempt} second(s)."
    exit 0
  fi
  sleep 1
done

echo "${environment_name} did not become healthy within 60 seconds; no automatic rollback was attempted." >&2
exit 1
