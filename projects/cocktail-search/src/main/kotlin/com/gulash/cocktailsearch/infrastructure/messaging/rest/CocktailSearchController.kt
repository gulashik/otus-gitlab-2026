package com.gulash.cocktailsearch.infrastructure.messaging.rest

import com.gulash.cocktailsearch.application.service.CocktailIngredientSearchService
import com.gulash.cocktailsearch.domain.CocktailSearchResponse
import org.springframework.web.bind.annotation.GetMapping
import org.springframework.web.bind.annotation.RequestMapping
import org.springframework.web.bind.annotation.RequestParam
import org.springframework.web.bind.annotation.RestController

@RestController
@RequestMapping("/api/cocktails")
class CocktailSearchController(
	private val searchService: CocktailIngredientSearchService
) {
	@GetMapping("/search")
	fun search(@RequestParam ingredient: List<String>?): CocktailSearchResponse =
		searchService.search(ingredient.orEmpty())
}
