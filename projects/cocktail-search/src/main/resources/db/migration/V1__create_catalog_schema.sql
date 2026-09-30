CREATE TABLE cocktails (
    id BIGSERIAL PRIMARY KEY,
    name VARCHAR(120) NOT NULL UNIQUE,
    recipe TEXT NOT NULL
);

CREATE TABLE ingredients (
    id BIGSERIAL PRIMARY KEY,
    canonical_name VARCHAR(120) NOT NULL UNIQUE
);

CREATE TABLE ingredient_aliases (
    id BIGSERIAL PRIMARY KEY,
    ingredient_id BIGINT NOT NULL REFERENCES ingredients (id) ON DELETE CASCADE,
    alias VARCHAR(120) NOT NULL UNIQUE
);

CREATE TABLE cocktail_ingredients (
    cocktail_id BIGINT NOT NULL REFERENCES cocktails (id) ON DELETE CASCADE,
    ingredient_id BIGINT NOT NULL REFERENCES ingredients (id) ON DELETE RESTRICT,
    amount VARCHAR(80) NOT NULL,
    PRIMARY KEY (cocktail_id, ingredient_id)
);

CREATE INDEX ingredient_aliases_ingredient_id_idx ON ingredient_aliases (ingredient_id);
CREATE INDEX cocktail_ingredients_ingredient_id_idx ON cocktail_ingredients (ingredient_id);
