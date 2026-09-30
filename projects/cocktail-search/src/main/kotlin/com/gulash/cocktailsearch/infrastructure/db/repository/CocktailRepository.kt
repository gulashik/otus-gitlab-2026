package com.gulash.cocktailsearch.infrastructure.db.repository

import com.gulash.cocktailsearch.application.gateway.CocktailGateway
import com.gulash.cocktailsearch.domain.CocktailSearchResult
import org.springframework.jdbc.core.JdbcTemplate
import org.springframework.stereotype.Repository

@Repository
class CocktailRepository (
    private val jdbcTemplate: JdbcTemplate,
): CocktailGateway {

    override fun findCocktails(ingredientIds: List<Long>): List<CocktailSearchResult> {
        if (ingredientIds.isEmpty()) return emptyList()
        val placeholders = ingredientIds.joinToString(",") { "?" }
        val rows = jdbcTemplate.query(
            """
				SELECT c.id, c.name, c.recipe, i.canonical_name AS matched_ingredient,
				       (SELECT COUNT(*) FROM cocktail_ingredients all_ci WHERE all_ci.cocktail_id = c.id) AS total_ingredient_count
				FROM cocktails c
				JOIN cocktail_ingredients ci ON ci.cocktail_id = c.id
				JOIN ingredients i ON i.id = ci.ingredient_id
				WHERE ci.ingredient_id IN ($placeholders)
			""".trimIndent(),
            ingredientIds.toTypedArray(),
        ) { rs, _ ->
            MatchRow(
                rs.getLong("id"), rs.getString("name"), rs.getString("recipe"),
                rs.getString("matched_ingredient"), rs.getInt("total_ingredient_count"),
            )
        }

        return rows.groupBy { it.cocktailId }.values.map { matches ->
            val first = matches.first()
            CocktailSearchResult(
                name = first.name,
                recipe = first.recipe,
                matchedIngredients = matches.map { it.matchedIngredient }.distinct().sorted(),
                matchCount = matches.map { it.matchedIngredient }.distinct().size,
                totalIngredientCount = first.totalIngredientCount,
            )
        }.sortedWith(compareByDescending<CocktailSearchResult> { it.matchCount }.thenBy { it.name })
    }

    private data class MatchRow(
        val cocktailId: Long,
        val name: String,
        val recipe: String,
        val matchedIngredient: String,
        val totalIngredientCount: Int,
    )
}