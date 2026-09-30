package com.gulash.cocktailsearch

import org.junit.jupiter.api.Test
import org.springframework.beans.factory.annotation.Autowired
import org.springframework.test.context.DynamicPropertyRegistry
import org.springframework.test.context.DynamicPropertySource
import org.springframework.jdbc.core.JdbcTemplate
import org.springframework.boot.webmvc.test.autoconfigure.AutoConfigureMockMvc
import org.springframework.boot.test.context.SpringBootTest
import org.springframework.test.web.servlet.MockMvc
import org.springframework.test.web.servlet.get
import org.testcontainers.containers.PostgreSQLContainer
import org.testcontainers.junit.jupiter.Container
import org.testcontainers.junit.jupiter.Testcontainers

@SpringBootTest
@AutoConfigureMockMvc
@Testcontainers
class CocktailSearchApplicationTests(
	@Autowired private val mockMvc: MockMvc,
	@Autowired private val jdbcTemplate: JdbcTemplate,
) {
	companion object {
		@Container
		@JvmStatic
		val postgres = PostgreSQLContainer<Nothing>("postgres:17.11-alpine3.24").apply {
			withDatabaseName("cocktail_catalog")
			withUsername("cocktail")
			withPassword("cocktail-local-only")
		}

		@DynamicPropertySource
		@JvmStatic
		fun databaseProperties(registry: DynamicPropertyRegistry) {
			registry.add("spring.datasource.url", postgres::getJdbcUrl)
			registry.add("spring.datasource.username", postgres::getUsername)
			registry.add("spring.datasource.password", postgres::getPassword)
		}
	}

	@Test
	fun healthEndpointReturnsOk() {
		mockMvc.get("/actuator/health")
			.andExpect {
				status { isOk() }
				jsonPath("$.status") { value("UP") }
			}
	}

	@Test
	fun catalogueMigrationsSeedTheExpectedOriginalRecords() {
		val cocktailCount = jdbcTemplate.queryForObject(
			"SELECT COUNT(*) FROM cocktails",
			Int::class.java,
		)
		val dryGinIngredient = jdbcTemplate.queryForObject(
			"""
				SELECT i.canonical_name
				FROM ingredient_aliases AS a
				JOIN ingredients AS i ON i.id = a.ingredient_id
				WHERE a.alias = 'dry gin'
			""".trimIndent(),
			String::class.java,
		)

		kotlin.test.assertEquals(3, cocktailCount)
		kotlin.test.assertEquals("gin", dryGinIngredient)
	}

	@Test
	fun `search ranks distinct ingredient matches then cocktail name`() {
		mockMvc.get("/api/cocktails/search") {
			param("ingredient", "gin")
			param("ingredient", "lemon juice")
		}
			.andExpect {
				status { isOk() }
				jsonPath("$.cocktails[0].name") { value("Amber Orchard") }
				jsonPath("$.cocktails[0].matchCount") { value(2) }
				jsonPath("$.cocktails[1].name") { value("Bitter Sunset") }
				jsonPath("$.cocktails[1].matchCount") { value(1) }
				jsonPath("$.cocktails[2].name") { value("Citrus Fizz") }
				jsonPath("$.cocktails[2].matchCount") { value(1) }
			}
	}

	@Test
	fun `search resolves aliases and reports the canonical ingredient once`() {
		mockMvc.get("/api/cocktails/search") {
			param("ingredient", " dry gin ")
			param("ingredient", "GIN")
		}
			.andExpect {
				status { isOk() }
				jsonPath("$.recognizedIngredients[0]") { value("gin") }
				jsonPath("$.cocktails[0].matchedIngredients[0]") { value("gin") }
				jsonPath("$.cocktails[0].totalIngredientCount") { value(3) }
			}
	}

	@Test
	fun `unknown non blank ingredient is a valid empty search`() {
		mockMvc.get("/api/cocktails/search") { param("ingredient", "  Moon   dust ") }
			.andExpect {
				status { isOk() }
				jsonPath("$.recognizedIngredients") { isEmpty() }
				jsonPath("$.unrecognizedIngredients[0]") { value("moon dust") }
				jsonPath("$.cocktails") { isEmpty() }
			}
	}

	@Test
	fun `missing or blank ingredients return a JSON bad request`() {
		mockMvc.get("/api/cocktails/search")
			.andExpect {
				status { isBadRequest() }
				jsonPath("$.error") { value("Provide at least one non-blank ingredient parameter.") }
			}

		mockMvc.get("/api/cocktails/search") { param("ingredient", "   ", "\t") }
			.andExpect {
				status { isBadRequest() }
				jsonPath("$.error") { exists() }
			}
	}

	@Test
	fun `browser initial page contains the form without search feedback`() {
		val page = mockMvc.get("/")
			.andExpect {
				status { isOk() }
				content { contentTypeCompatibleWith("text/html") }
			}
			.andReturn().response.contentAsString

		kotlin.test.assertTrue(page.contains("<form"))
		kotlin.test.assertTrue(page.contains("Ingredients"))
		kotlin.test.assertFalse(page.contains("No matching cocktails"))
		kotlin.test.assertFalse(page.contains("Enter at least one ingredient"))
	}

	@Test
	fun `browser search resolves aliases and preserves ranking`() {
		val page = mockMvc.get("/") { param("ingredients", "dry gin, lemon juice") }
			.andExpect {
				status { isOk() }
			}
			.andReturn().response.contentAsString

		kotlin.test.assertTrue(page.contains("Recognized ingredients: <span>gin, lemon juice</span>"))
		kotlin.test.assertTrue(page.indexOf("Amber Orchard") < page.indexOf("Bitter Sunset"))
		kotlin.test.assertTrue(page.indexOf("Bitter Sunset") < page.indexOf("Citrus Fizz"))
	}

	@Test
	fun `browser unknown ingredient shows a no results state`() {
		val page = mockMvc.get("/") { param("ingredients", "  Moon   dust ") }
			.andExpect {
				status { isOk() }
			}
			.andReturn().response.contentAsString

		kotlin.test.assertTrue(page.contains("No matching cocktails"))
		kotlin.test.assertTrue(page.contains("moon dust"))
	}

	@Test
	fun `browser blank submission is HTML validation not REST JSON`() {
		val page = mockMvc.get("/") { param("ingredients", " , , ") }
			.andExpect {
				status { isOk() }
				content { contentTypeCompatibleWith("text/html") }
			}
			.andReturn().response.contentAsString

		kotlin.test.assertTrue(page.contains("Enter at least one ingredient"))
		kotlin.test.assertFalse(page.contains("Provide at least one non-blank ingredient parameter."))
	}
}
