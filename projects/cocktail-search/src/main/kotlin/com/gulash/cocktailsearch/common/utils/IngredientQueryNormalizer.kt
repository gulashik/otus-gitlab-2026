package com.gulash.cocktailsearch.common.utils

import org.springframework.stereotype.Component
import java.util.Locale

@Component
class IngredientQueryNormalizer {
	fun normalize(ingredients: List<String>): List<String> =
		ingredients.asSequence()
			.map(::normalizeOne)
			.filter(String::isNotBlank)
			.distinct()
			.toList()

	private fun normalizeOne(ingredient: String): String =
		ingredient.trim().replace(Regex("\\s+"), " ").lowercase(Locale.ROOT)
}
