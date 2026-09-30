package com.gulash.cocktailsearch.domain

data class ResolvedIngredientQuery(
    val recognized: LinkedHashMap<Long, String>,
    val unrecognized: List<String>,
)