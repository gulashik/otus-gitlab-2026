package com.gulash.cocktailsearch.common.error

class InvalidIngredientSearchException : RuntimeException("Provide at least one non-blank ingredient parameter.")