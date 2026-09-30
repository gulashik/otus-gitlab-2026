package com.gulash.cocktailsearch.infrastructure.messaging.web

import com.gulash.cocktailsearch.application.service.CocktailIngredientSearchService
import com.gulash.cocktailsearch.common.error.InvalidIngredientSearchException
import org.springframework.stereotype.Controller
import org.springframework.ui.Model
import org.springframework.web.bind.annotation.GetMapping
import org.springframework.web.bind.annotation.RequestParam

@Controller
class CocktailSearchPageController(
	private val searchService: CocktailIngredientSearchService,
) {
	@GetMapping("/")
	fun searchPage(
		@RequestParam(required = false) ingredients: String?,
		model: Model,
	): String {
		model.addAttribute("submittedIngredients", ingredients.orEmpty())
		model.addAttribute("invalidInput", false)
		model.addAttribute("noResults", false)
		if (ingredients == null) return "cocktail-search"

		try {
			val response = searchService.search(ingredients.split(','))
			model.addAttribute("searchResponse", response)
			if (response.cocktails.isEmpty()) model.addAttribute("noResults", true)
		} catch (_: InvalidIngredientSearchException) {
			model.addAttribute("invalidInput", true)
		}

		return "cocktail-search"
	}
}
