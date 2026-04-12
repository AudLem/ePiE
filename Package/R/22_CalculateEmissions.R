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

  mean_per_capita_use <- mean(consumption_table[[target_substance]] / consumption_table$population, na.rm = TRUE)
  if (is.na(mean_per_capita_use)) mean_per_capita_use <- 0

  synthetic_row <- data.frame(
    cnt = study_country,
    population = country_pop,
    year = max(consumption_table$year, na.rm = TRUE)
  )
  synthetic_row[[target_substance]] <- country_pop * mean_per_capita_use

  plyr::rbind.fill(consumption_table, synthetic_row)
}
