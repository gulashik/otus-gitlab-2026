package com.gulash.cocktailsearch.domain


data class CocktailSearchResponse(
    val recognizedIngredients: List<String>,
    val unrecognizedIngredients: List<String>,
    val cocktails: List<CocktailSearchResult>,
)