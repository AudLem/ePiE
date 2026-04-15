library(ePiE)

v125_pts_path <- "/Users/gtazzi/SHoeks/ePiE/Outputs/bega_ibuprofen/results_pts_bega_Ibuprofen.csv"
v125_hl_path  <- "/Users/gtazzi/SHoeks/ePiE/Outputs/bega_ibuprofen/results_hl_bega_Ibuprofen.csv"
gm_dir <- file.path("golden_master")

if (!dir.exists(gm_dir)) dir.create(gm_dir, recursive = TRUE)

message("Generating Bega Ibuprofen golden master from SHoeks ePiE v1.25 results...")

pts_125 <- read.csv(v125_pts_path, stringsAsFactors = FALSE)
hl_125  <- read.csv(v125_hl_path, stringsAsFactors = FALSE)

chem <- LoadExampleChemProperties()
chem <- CompleteChemProperties(chem)

cons <- LoadExampleConsumption()

gm <- list(
  version = "v1.25",
  basin_id = "bega",
  substance = "Ibuprofen",
  timestamp = as.POSIXct("2026-04-15 14:31:00", tz = "UTC"),
  description = paste(
    "Bega Ibuprofen golden master from SHoeks ePiE v1.25.",
    "Run with C++ engine on 478-node Bega network (4 WWTPs, 9 lakes).",
    "Default T_AIR=11.0C, Wind=4.5 m/s, FLO1K average flow.",
    "v1.25 contains lake volume bug (V = Vol_total * 1e6 instead of 1e9),",
    "HL$E_in double-counting, and missing LakeInlet/LakeOutlet exclusion in k_NXT.",
    "v1.26 should produce: identical SimpleTreat/chem/WWTPremoval,",
    "lower lake C_w (volume fix), different downstream C_w (cascading)."
  ),
  chem = chem,
  cons = cons,
  results_cpp = list(pts = pts_125, hl = hl_125),
  metadata = list(
    n_pts = nrow(pts_125),
    n_hl = nrow(hl_125),
    n_wwtp = sum(pts_125$Pt_type == "WWTP", na.rm = TRUE),
    n_hydro_lake = sum(pts_125$Pt_type == "Hydro_Lake", na.rm = TRUE),
    engine = "C++",
    default_temp = 11.0,
    default_wind = 4.5,
    flow_source = "FLO1k.lt.2000.2015.qav.tif",
    known_v126_changes = list(
      lake_volume_fix = list(
        file = "R/Compute_env_concentrations_v4.R",
        v125_line = 58,
        v126_line = 84,
        description = "V = Vol_total * 1e6 -> V = Vol_total * 1e9 (correct km3->m3)"
      ),
      hl_ein_double_count = list(
        file = "R/Set_local_parameters_custom_removal_fast3.R",
        v125_lines = "197:200",
        v126_lines = "260:276",
        description = "HL$E_in now excludes LakeInlet/LakeOutlet/WWTP/agglomeration nodes"
      ),
      k_nxt_lake_exclusion = list(
        file = "R/Set_local_parameters_custom_removal_fast3.R",
        v125_line = 430,
        v126_line = 506,
        description = "k_NXT averaging excludes LakeInlet and LakeOutlet Down_types"
      ),
      cons_column_normalization = list(
        file = "R/Set_local_parameters_custom_removal_fast3.R",
        v125_lines = "82,88,179,184-185",
        v126_lines = "42-49,129,135,231-232",
        description = "cons$country -> cons$cnt normalization + F_direct -> f_direct"
      ),
      tertiary_column_safety = list(
        file = "R/Set_local_parameters_custom_removal_fast3.R",
        v125_lines = "(missing)",
        v126_lines = "194-198",
        description = "Defensive creation of uwwNRemova etc. columns when missing"
      ),
      cpp_which_fix = list(
        file = "src/compenvcons_v4.cpp",
        v125_lines = "28-68",
        v126_lines = "29-50",
        description = "which() returns -1 on miss instead of OOB index n"
      ),
      cpp_hl_reserve_fix = list(
        file = "src/compenvcons_v4.cpp",
        v125_line = "(near hl_fin.reserve)",
        v126_line = "(near hl_fin.reserve)",
        description = "hl_fin.reserve(nrow_pts) -> hl_fin.reserve(nrow_hl)"
      )
    )
  )
)

gm_path <- file.path(gm_dir, "gm_bega_ibuprofen_v1.25.rds")
saveRDS(gm, gm_path)

message("Golden master saved to: ", gm_path)
message("  pts rows: ", nrow(pts_125))
message("  hl rows:  ", nrow(hl_125))
message("  Max C_w:  ", max(pts_125$C_w, na.rm = TRUE))
message("  Non-zero C_w: ", sum(pts_125$C_w > 0, na.rm = TRUE))
