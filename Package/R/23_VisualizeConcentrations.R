VisualizeConcentrations <- function(simulation_results,
                                    run_output_dir,
                                    input_paths = list(),
                                    target_substance = NULL,
                                    basin_id = NULL,
                                    substance_type = "chemical",
                                    pathogen_name = NULL,
                                    pathogen_units = NULL,
                                    visualization_variants = c("linear", "log10"),
                                    provenance_label_mode = "concise_visible",
                                    open_map_output_in_browser = TRUE,
                                    show_interactive_map_preview = FALSE) {
  message("--- Step 6: Generating Simulation Visualizations ---")

  plots_dir <- file.path(run_output_dir, "plots")
  if (!dir.exists(plots_dir)) dir.create(plots_dir, recursive = TRUE)

  variants <- NormalizeVisualizationVariants(visualization_variants, substance_type)
  primary_variant <- ChoosePrimaryVisualizationVariant(variants, substance_type)
  specs <- list()
  leaflet_paths <- character(0)
  segment_leaflet_paths <- character(0)

  for (variant in variants) {
    spec <- BuildConcentrationMapSpec(
      simulation_results = simulation_results,
      run_output_dir = run_output_dir,
      input_paths = input_paths,
      target_substance = target_substance,
      basin_id = basin_id,
      substance_type = substance_type,
      pathogen_name = pathogen_name,
      pathogen_units = pathogen_units,
      map_scale = variant,
      map_variant = variant,
      write_legacy_map = identical(variant, primary_variant),
      provenance_label_mode = provenance_label_mode
    )
    specs[[variant]] <- spec

    leaflet_paths[[variant]] <- RenderLeafletConcentrationMap(
      spec = spec,
      plots_dir = plots_dir
    )

    segment_path <- RenderLeafletConcentrationSegmentMap(
      spec = spec,
      plots_dir = plots_dir
    )
    segment_leaflet_paths[[variant]] <- if (is.null(segment_path) || length(segment_path) == 0) {
      NA_character_
    } else {
      segment_path
    }

    RenderTmapConcentrationMap(
      spec = spec,
      plots_dir = plots_dir
    )
  }

  message("Visualization complete.")
  cat("\n[CHECKPOINT] Interactive concentration map saved to:\n")
  cat(">>> ", normalizePath(leaflet_paths[[primary_variant]]), "\n")
  if (!is.na(segment_leaflet_paths[[primary_variant]]) &&
      nzchar(segment_leaflet_paths[[primary_variant]])) {
    cat("[CHECKPOINT] Interactive segment concentration map saved to:\n")
    cat(">>> ", normalizePath(segment_leaflet_paths[[primary_variant]]), "\n")
  }

  invisible(specs[[primary_variant]])
}

NormalizeVisualizationVariants <- function(visualization_variants, substance_type = "chemical") {
  if (is.null(visualization_variants) || length(visualization_variants) == 0) {
    visualization_variants <- c("linear", "log10")
  }
  variants <- unique(tolower(as.character(visualization_variants)))
  variants <- variants[nzchar(variants)]
  variants[variants == "log"] <- "log10"
  variants <- intersect(variants, c("linear", "log10", "auto"))
  if (length(variants) == 0) variants <- c("linear", "log10")
  variants
}

ChoosePrimaryVisualizationVariant <- function(variants, substance_type = "chemical") {
  if (identical(substance_type, "pathogen") && "log10" %in% variants) return("log10")
  if ("linear" %in% variants) return("linear")
  variants[1]
}
