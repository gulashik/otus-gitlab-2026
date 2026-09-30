package com.gulash.cocktailsearch

import com.gulash.cocktailsearch.common.utils.IngredientQueryNormalizer
import com.gulash.cocktailsearch.common.utils.IngredientResolver
import com.gulash.cocktailsearch.domain.CatalogueIngredient
import kotlin.test.Test
import kotlin.test.assertEquals

class IngredientQueryNormalizerTests {
	private val normalizer = IngredientQueryNormalizer()
	private val resolver = IngredientResolver()

	@Test
	fun `normalizes case and whitespace then removes duplicates`() {
		assertEquals(
			listOf("dry gin", "lemon juice"),
			normalizer.normalize(listOf("  DRY   gin  ", "dry gin", " Lemon\tjuice ")),
		)
	}

	@Test
	fun `resolves aliases to canonical names and does not inflate repeated values`() {
		val resolved = resolver.resolve(
			normalizer.normalize(listOf("dry gin", "GIN", "dry gin")),
			mapOf(
				"gin" to CatalogueIngredient(1, "gin"),
				"dry gin" to CatalogueIngredient(1, "gin"),
			),
		)

		assertEquals(listOf("gin"), resolved.recognized.values.toList())
		assertEquals(emptyList(), resolved.unrecognized)
	}
}
