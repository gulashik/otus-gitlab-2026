INSERT INTO ingredients (canonical_name) VALUES
    ('gin'),
    ('sweet vermouth'),
    ('bitter aperitif'),
    ('lemon juice'),
    ('apple juice'),
    ('vodka'),
    ('soda water');

INSERT INTO ingredient_aliases (ingredient_id, alias)
SELECT id, 'dry gin' FROM ingredients WHERE canonical_name = 'gin'
UNION ALL
SELECT id, 'london dry gin' FROM ingredients WHERE canonical_name = 'gin'
UNION ALL
SELECT id, 'vermouth rosso' FROM ingredients WHERE canonical_name = 'sweet vermouth'
UNION ALL
SELECT id, 'club soda' FROM ingredients WHERE canonical_name = 'soda water';

INSERT INTO cocktails (name, recipe) VALUES
    ('Amber Orchard', 'Shake gin, lemon juice, and apple juice with ice; strain into a chilled glass.'),
    ('Bitter Sunset', 'Stir gin, sweet vermouth, and bitter aperitif with ice; strain over fresh ice.'),
    ('Citrus Fizz', 'Shake vodka and lemon juice with ice, strain over ice, then top with soda water.');

INSERT INTO cocktail_ingredients (cocktail_id, ingredient_id, amount)
SELECT c.id, i.id, recipe.amount
FROM (
    VALUES
        ('Amber Orchard', 'gin', '45 ml'),
        ('Amber Orchard', 'lemon juice', '20 ml'),
        ('Amber Orchard', 'apple juice', '60 ml'),
        ('Bitter Sunset', 'gin', '30 ml'),
        ('Bitter Sunset', 'sweet vermouth', '30 ml'),
        ('Bitter Sunset', 'bitter aperitif', '30 ml'),
        ('Citrus Fizz', 'vodka', '45 ml'),
        ('Citrus Fizz', 'lemon juice', '20 ml'),
        ('Citrus Fizz', 'soda water', '90 ml')
) AS recipe(cocktail_name, ingredient_name, amount)
JOIN cocktails c ON c.name = recipe.cocktail_name
JOIN ingredients i ON i.canonical_name = recipe.ingredient_name;
