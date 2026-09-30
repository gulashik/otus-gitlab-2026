package com.gulash.cocktailsearch.application.gateway

import com.gulash.cocktailsearch.domain.CatalogueIngredient

interface IngredientGateway {
    fun loadCatalogue(): Map<String, CatalogueIngredient>
}