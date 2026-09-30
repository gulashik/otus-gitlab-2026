package com.gulash.cocktailsearch.infrastructure.db.repository

import com.gulash.cocktailsearch.application.gateway.IngredientGateway
import com.gulash.cocktailsearch.domain.CatalogueIngredient
import org.springframework.jdbc.core.JdbcTemplate
import org.springframework.stereotype.Repository

@Repository
class IngredientRepository (
    private val jdbcTemplate: JdbcTemplate,
): IngredientGateway {

    override fun loadCatalogue(): Map<String, CatalogueIngredient> {
        val rows = jdbcTemplate.query(
            """
				SELECT i.id, i.canonical_name, i.canonical_name AS lookup_name FROM ingredients i
				UNION ALL
				SELECT i.id, i.canonical_name, a.alias AS lookup_name
				FROM ingredient_aliases a JOIN ingredients i ON i.id = a.ingredient_id
			""".trimIndent(),
        ) { rs, _ ->
            rs.getString("lookup_name") to CatalogueIngredient(rs.getLong("id"), rs.getString("canonical_name"))
        }
        return rows.toMap()
    }
}