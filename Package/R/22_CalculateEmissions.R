#' Calculate Emissions
#'
#' Prepares country-level consumption data, creates synthetic entries for
#' countries not in the default table, and validates that consumption data
#' is available for all source countries in the network.
#'
#' @param network_nodes data.frame. Normalised network nodes with Pt_type and country fields.
#' @param chem data.frame. Chemical property table (one row per substance).
#' @param study_country Character. ISO country code for the basin.
#' @param target_substance Character. Name of the target substance column (e.g. \code{"Ibuprofen"}).
#' @return A named list with \code{cons} (consumption table ready for concentration engine).
#' @export
CalculateEmissions <- function(network_nodes, chem, study_country, target_substance) {
  message("--- Step 4: Source & Emission Setup ---")

  cons_table <- PrepareCountryConsumption(network_nodes, study_country, target_substance)

  network_nodes_for_check <- network_nodes
  network_nodes_for_check$Pt_type <- as.character(network_nodes_for_check$Pt_type)
  network_nodes_for_check$Pt_type[tolower(network_nodes_for_check$Pt_type) == "agglomeration"] <- "Agglomerations"

  CheckConsumptionData(pts = network_nodes_for_check, chem = chem, cons = cons_table)

  list(cons = cons_table)
}

PrepareCountryConsumption <- function(network_nodes, study_country, target_substance) {
  consumption_table <- LoadExampleConsumption()
  if (study_country %in% consumption_table$cnt) {
    return(consumption_table)
  }

  message("Adding custom consumption data for ", study_country)
  country_pop <- sum(as.numeric(network_nodes$total_population[network_nodes$rptMStateK == study_country]), na.rm = TRUE)
  if (is.na(country_pop) || country_pop <= 0) country_pop <- 1e6

  synthetic_row <- data.frame(
    cnt = study_country,
    population = country_pop,
    year = max(consumption_table$year, na.rm = TRUE)
  )
  substance_col <- which(tolower(names(consumption_table)) == tolower(target_substance))[1]
  
  synthetic_row[[target_substance]] <- if(!is.na(substance_col)) {
    country_pop * mean(consumption_table[[substance_col]] / consumption_table$population, na.rm = TRUE)
  } else {
    NA
  }

  plyr::rbind.fill(consumption_table, synthetic_row)
}
