VisualizeConcentrations <- function(simulation_results,
                                    run_output_dir,
                                    input_paths = list(),
                                    target_substance = NULL,
                                    basin_id = NULL,
                                    substance_type = "chemical",
                                    pathogen_name = NULL,
                                    pathogen_units = NULL,
                                    visualization_variants = c("linear", "log10"),
                                    binned_breaks = NULL,
                                    binned_labels = NULL,
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
  static_paths <- character(0)

  for (variant in variants) {
    map_scale <- if (IsStaticOnlyVisualizationVariant(variant)) "linear" else variant
    spec <- BuildConcentrationMapSpec(
      simulation_results = simulation_results,
      run_output_dir = run_output_dir,
      input_paths = input_paths,
      target_substance = target_substance,
      basin_id = basin_id,
      substance_type = substance_type,
      pathogen_name = pathogen_name,
      pathogen_units = pathogen_units,
      map_scale = map_scale,
      map_variant = variant,
      binned_breaks = binned_breaks,
      binned_labels = binned_labels,
      write_legacy_map = identical(variant, primary_variant),
      provenance_label_mode = provenance_label_mode
    )
    specs[[variant]] <- spec

    if (!IsStaticOnlyVisualizationVariant(variant)) {
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
    } else {
      leaflet_paths[[variant]] <- NA_character_
      segment_leaflet_paths[[variant]] <- NA_character_
    }

    static_path <- RenderTmapConcentrationMap(
      spec = spec,
      plots_dir = plots_dir
    )
    static_paths[[variant]] <- if (is.null(static_path) || length(static_path) == 0) {
      NA_character_
    } else {
      static_path
    }
  }

  message("Visualization complete.")
  if (!is.na(leaflet_paths[[primary_variant]]) &&
      nzchar(leaflet_paths[[primary_variant]])) {
    cat("\n[CHECKPOINT] Interactive concentration map saved to:\n")
    cat(">>> ", normalizePath(leaflet_paths[[primary_variant]]), "\n")
  }
  if (!is.na(segment_leaflet_paths[[primary_variant]]) &&
      nzchar(segment_leaflet_paths[[primary_variant]])) {
    cat("[CHECKPOINT] Interactive segment concentration map saved to:\n")
    cat(">>> ", normalizePath(segment_leaflet_paths[[primary_variant]]), "\n")
  }
  if (!is.na(static_paths[[primary_variant]]) &&
      nzchar(static_paths[[primary_variant]])) {
    cat("[CHECKPOINT] Static concentration map saved to:\n")
    cat(">>> ", normalizePath(static_paths[[primary_variant]]), "\n")
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
  variants <- intersect(variants, c("linear", "log10", "auto", "linear_binned"))
  if (length(variants) == 0) variants <- c("linear", "log10")
  variants
}

ChoosePrimaryVisualizationVariant <- function(variants, substance_type = "chemical") {
  if (identical(substance_type, "pathogen") && "log10" %in% variants) return("log10")
  if ("linear" %in% variants) return("linear")
  variants[1]
}

IsStaticOnlyVisualizationVariant <- function(variant) {
  identical(tolower(as.character(variant[[1]])), "linear_binned")
}
