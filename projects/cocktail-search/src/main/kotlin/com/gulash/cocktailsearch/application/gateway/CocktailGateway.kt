package com.gulash.cocktailsearch.application.gateway

import com.gulash.cocktailsearch.domain.CocktailSearchResult

interface CocktailGateway {
    fun findCocktails(ingredientIds: List<Long>): List<CocktailSearchResult>
}