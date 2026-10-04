# cocktail-search

A Kotlin and Spring Boot application that will search cocktail recipes by ingredient. 

## Run test

```bash
cd projects/cocktail-search
./gradlew test
```

## Build an image and run the service

```bash
cd projects/cocktail-search
DB_NAME=cocktail_catalog \
DB_USER=cocktail \
DB_PASSWORD=cocktail-local-only \
podman compose up -d postgres
podman build --network host --tag cocktail-search:local .
podman run --rm --name cocktail-search-container \
  --publish 8082:8080 \
  --env DB_HOST=host.containers.internal \
  --env DB_PORT=5432 \
  --env DB_NAME=cocktail_catalog \
  --env DB_USER=cocktail \
  --env DB_PASSWORD=cocktail-local-only \
  cocktail-search:local
```

In another terminal, verify that it is ready:

```bash
curl --fail --silent --show-error http://localhost:8082/actuator/health
```
The response contains `{"status":"UP"}` and has HTTP status 200 when the  service is ready.

## Browser search UI

Open [http://localhost:8082/](http://localhost:8082/) after the service is ready. 
Enter a comma-separated ingredient list, for example `dry gin, lemon juice`. 
The page resolves `dry gin` to `gin` and displays ranked recipe cards.
Try `xxx` to see the no-results state, or submit only commas to see the HTML input correction message. 

## Ingredient search API

`GET /api/cocktails/search` accepts one or more repeated `ingredient` query parameters. 
Results are ordered by the number of distinct matched ingredients (descending), then cocktail name (ascending).

```bash
curl --get --silent --show-error http://localhost:8082/api/cocktails/search \
  --data-urlencode 'ingredient=dry gin' \
  --data-urlencode 'ingredient=lemon juice' | jq
```

The response contains canonical recognized ingredients, normalized unknown
ingredients, and each matching recipe. For the seeded catalogue it begins like:

```json
{
  "recognizedIngredients": ["gin", "lemon juice"],
  "unrecognizedIngredients": [],
  "cocktails": [
    {
      "name": "Amber Orchard",
      "matchedIngredients": ["gin", "lemon juice"],
      "matchCount": 2,
      "totalIngredientCount": 3
    }
  ]
}
```

An unknown non-blank value is a valid search and returns HTTP 200 with an empty `cocktails` list and that normalized value in `unrecognizedIngredients`.
Omitting `ingredient`, or supplying only blank values, returns HTTP 400:

```json
{"error":"Provide at least one non-blank ingredient parameter."}
```

Inspect the records without installing `psql`:

```bash
podman compose exec postgres psql -U cocktail -d cocktail_catalog \
  -c 'SELECT name FROM cocktails ORDER BY name;'
```

The PostgreSQL connection requires the following variables at process start.
The values shown are the local teaching values used by the Compose command
above; they are not embedded defaults in the application or image.

| Variable      | Local teaching value  |
|---------------|-----------------------|
| `DB_HOST`     | `localhost`           |
| `DB_PORT`     | `5432`                |
| `DB_NAME`     | `cocktail_catalog`    |
| `DB_USER`     | `cocktail`            |
| `DB_PASSWORD` | `cocktail-local-only` |
