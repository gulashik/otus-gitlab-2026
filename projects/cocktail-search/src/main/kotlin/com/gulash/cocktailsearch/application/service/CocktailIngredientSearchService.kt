package com.gulash.cocktailsearch.application.service

import com.gulash.cocktailsearch.common.utils.IngredientQueryNormalizer
import com.gulash.cocktailsearch.common.utils.IngredientResolver
import com.gulash.cocktailsearch.application.gateway.CocktailGateway
import com.gulash.cocktailsearch.application.gateway.IngredientGateway
import com.gulash.cocktailsearch.common.error.InvalidIngredientSearchException
import com.gulash.cocktailsearch.domain.CocktailSearchResponse
import org.springframework.stereotype.Service

@Service
class CocktailIngredientSearchService(
	private val normalizer: IngredientQueryNormalizer,
	private val resolver: IngredientResolver,
	private val repositoryIngredient: IngredientGateway,
	private val repositoryCocktail: CocktailGateway,
) {
	fun search(rawIngredients: List<String>): CocktailSearchResponse {
		val normalizedIngredients = normalizer.normalize(rawIngredients)
		if (normalizedIngredients.isEmpty()) throw InvalidIngredientSearchException()

		val catalogue = repositoryIngredient.loadCatalogue()
		val resolved = resolver.resolve(normalizedIngredients, catalogue)

		return CocktailSearchResponse(
			recognizedIngredients = resolved.recognized.values.toList(),
			unrecognizedIngredients = resolved.unrecognized,
			cocktails = repositoryCocktail.findCocktails(resolved.recognized.keys.toList()),
		)
	}
}
