package com.gulash.cocktailsearch.common.utils

import com.gulash.cocktailsearch.domain.CatalogueIngredient
import com.gulash.cocktailsearch.domain.ResolvedIngredientQuery
import org.springframework.stereotype.Component

@Component
class IngredientResolver {
    fun resolve(
        normalizedIngredients: List<String>,
        catalogue: Map<String, CatalogueIngredient>,
    ): ResolvedIngredientQuery {
        val recognized = linkedMapOf<Long, String>()
        val unrecognized = mutableListOf<String>()
        for (ingredient in normalizedIngredients) {
            val resolved = catalogue[ingredient]
            if (resolved == null) unrecognized += ingredient else recognized[resolved.id] = resolved.canonicalName
        }
        return ResolvedIngredientQuery(recognized, unrecognized)
    }
}
