package com.gulash.cocktailsearch.domain

data class CocktailSearchResult(
    val name: String,
    val recipe: String,
    val matchedIngredients: List<String>,
    val matchCount: Int,
    val totalIngredientCount: Int,
)