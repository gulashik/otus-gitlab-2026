package com.gulash.cocktailsearch.common.error

import com.gulash.cocktailsearch.common.error.domain.SearchErrorResponse
import org.springframework.http.HttpStatus
import org.springframework.web.bind.annotation.ExceptionHandler
import org.springframework.web.bind.annotation.ResponseStatus
import org.springframework.web.bind.annotation.RestControllerAdvice

@RestControllerAdvice
class ExceptionHandler {
    @ExceptionHandler(InvalidIngredientSearchException::class)
    @ResponseStatus(HttpStatus.BAD_REQUEST)
    fun invalidSearch(exception: InvalidIngredientSearchException) =
        SearchErrorResponse(exception.message!!)
}