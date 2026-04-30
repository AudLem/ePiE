pathogen_profiles <- data.frame(
  profile_set = c(
    rep("ghana_ssa_screening", 4),
    rep("romania_eu_screening", 4)
  ),
  profile_id = c(
    "ghana_ssa_cryptosporidium_screening",
    "ghana_ssa_campylobacter_screening",
    "ghana_ssa_rotavirus_screening",
    "ghana_ssa_giardia_screening",
    "romania_eu_cryptosporidium_screening",
    "romania_eu_campylobacter_screening",
    "romania_eu_rotavirus_screening",
    "romania_eu_giardia_screening"
  ),
  pathogen_name = c(
    "cryptosporidium", "campylobacter", "rotavirus", "giardia",
    "cryptosporidium", "campylobacter", "rotavirus", "giardia"
  ),
  study_country = c("GH", "GH", "GH", "GH", "RO", "RO", "RO", "RO"),
  region = c(
    "Ghana / Sub-Saharan Africa",
    "Ghana / Sub-Saharan Africa",
    "Ghana / Sub-Saharan Africa",
    "Ghana / Sub-Saharan Africa",
    "Romania / Europe",
    "Romania / Europe",
    "Romania / Europe",
    "Romania / Europe"
  ),
  profile_label = c(
    "Ghana/SSA Cryptosporidium screening profile",
    "Ghana/SSA Campylobacter screening profile",
    "Ghana/SSA Rotavirus screening profile",
    "Ghana/SSA Giardia screening profile",
    "Romania/EU Cryptosporidium screening profile",
    "Romania/EU Campylobacter screening profile",
    "Romania/EU Rotavirus screening profile",
    "Romania/EU Giardia screening profile"
  ),
  prevalence_rate = c(0.05, 0.11, 0.06, 0.07, 0.005, 0.01, 0.01, 0.02),
  prevalence_basis = c(
    "Sub-Saharan Africa screening prevalence used by GloWPa-style human emission modelling.",
    "Ghana/SSA screening prevalence; local surface-water occurrence confirms relevance but not infection prevalence.",
    "Global rotavirus screening prevalence for human emission modelling; Ghana context has documented seasonality.",
    "Ghana screening prevalence; Ghana scoping literature reports broad giardiasis prevalence ranges.",
    "European screening prevalence; Romania-specific monitoring confirms occurrence in western Romanian waters.",
    "European screening prevalence based on EU/EEA campylobacteriosis context; not a direct shedding prevalence.",
    "European screening prevalence for rotavirus after vaccination-era reductions; not a direct shedding prevalence.",
    "Romania/EU screening prevalence; Romania has long-term giardiasis surveillance and western Romania water occurrence."
  ),
  excretion_rate = c(1e8, 1e11, 1e12, 1e9, 1e8, 1e11, 1e12, 1e9),
  excretion_basis = c(
    "Oocysts per infected person per year from GloWPa-Crypto literature.",
    "CFU per infected person per year retained from legacy ePiE screening setup pending pathogen-specific calibration.",
    "Viral particles per infected person per year from GloWPa-Rota literature range.",
    "Cysts per infected person per year retained from legacy ePiE screening setup pending pathogen-specific calibration.",
    "Oocysts per infected person per year from GloWPa-Crypto literature; applied as pathogen biology, not country-specific prevalence.",
    "CFU per infected person per year retained from legacy ePiE screening setup pending pathogen-specific calibration.",
    "Viral particles per infected person per year from GloWPa-Rota literature range.",
    "Cysts per infected person per year retained from legacy ePiE screening setup pending pathogen-specific calibration."
  ),
  wwtp_primary_removal = c(0.23, 0.50, 0.10, 0.30, 0.23, 0.50, 0.10, 0.30),
  wwtp_secondary_removal = c(0.96, 0.99, 0.90, 0.95, 0.96, 0.99, 0.90, 0.95),
  units = c(
    "oocysts/L", "CFU/L", "viral particles/L", "cysts/L",
    "oocysts/L", "CFU/L", "viral particles/L", "cysts/L"
  ),
  prevalence_source_short = c(
    "Vermeulen et al. 2019; SSA burden context",
    "Karikari et al. 2016; screening assumption",
    "Kiulia et al. 2015; Ghana seasonality context",
    "University of Ghana scoping review; screening assumption",
    "Imre et al. 2017; ECDC AER context",
    "ECDC Campylobacteriosis AER; screening assumption",
    "Kiulia et al. 2015; ECDC/Europe screening context",
    "Imre et al. 2017; Romanian giardiasis context"
  ),
  prevalence_source_url = c(
    "https://pubmed.ncbi.nlm.nih.gov/30447525/",
    "https://doi.org/10.5897/AJMR2016.8296",
    "https://www.mdpi.com/2076-0817/4/2/229",
    "https://pure.ug.edu.gh/en/publications/human-giardiasis-in-ghana-a-scoping-review-of-studies-from-2004-t/",
    "https://pubmed.ncbi.nlm.nih.gov/28832257/",
    "https://www.ecdc.europa.eu/en/publications-data/campylobacteriosis-annual-epidemiological-report-2019",
    "https://www.mdpi.com/2076-0817/4/2/229",
    "https://pubmed.ncbi.nlm.nih.gov/28832257/"
  ),
  excretion_source_short = c(
    "Vermeulen et al. 2019",
    "Legacy ePiE screening value; literature review required",
    "Kiulia et al. 2015",
    "Legacy ePiE screening value; literature review required",
    "Vermeulen et al. 2019",
    "Legacy ePiE screening value; literature review required",
    "Kiulia et al. 2015",
    "Legacy ePiE screening value; literature review required"
  ),
  excretion_source_url = c(
    "https://pubmed.ncbi.nlm.nih.gov/30447525/",
    "https://www.ecdc.europa.eu/en/publications-data/campylobacteriosis-annual-epidemiological-report-2019",
    "https://www.mdpi.com/2076-0817/4/2/229",
    "https://www.mdpi.com/2504-3900/2/11/690",
    "https://pubmed.ncbi.nlm.nih.gov/30447525/",
    "https://www.ecdc.europa.eu/en/publications-data/campylobacteriosis-annual-epidemiological-report-2019",
    "https://www.mdpi.com/2076-0817/4/2/229",
    "https://www.mdpi.com/2504-3900/2/11/690"
  ),
  wwtp_source_short = c(
    "Vermeulen et al. 2019 / WHO-style screening removals",
    "Legacy ePiE screening WWTP removals",
    "Kiulia et al. 2015 / legacy ePiE removals",
    "Legacy ePiE screening WWTP removals",
    "Vermeulen et al. 2019 / WHO-style screening removals",
    "Legacy ePiE screening WWTP removals",
    "Kiulia et al. 2015 / legacy ePiE removals",
    "Legacy ePiE screening WWTP removals"
  ),
  wwtp_source_url = c(
    "https://pubmed.ncbi.nlm.nih.gov/30447525/",
    "https://www.ecdc.europa.eu/en/publications-data/campylobacteriosis-annual-epidemiological-report-2019",
    "https://www.mdpi.com/2076-0817/4/2/229",
    "https://www.mdpi.com/2504-3900/2/11/690",
    "https://pubmed.ncbi.nlm.nih.gov/30447525/",
    "https://www.ecdc.europa.eu/en/publications-data/campylobacteriosis-annual-epidemiological-report-2019",
    "https://www.mdpi.com/2076-0817/4/2/229",
    "https://www.mdpi.com/2504-3900/2/11/690"
  ),
  publication_year = c(2019, 2016, 2015, 2024, 2017, 2024, 2015, 2017),
  data_period = c(
    "screening profile for Ghana/SSA case study",
    "screening profile for Ghana/SSA case study",
    "screening profile for Ghana/SSA case study",
    "2004-2024 review context",
    "2017 western Romania water occurrence context",
    "2019 EU/EEA surveillance report context",
    "2015 global rotavirus model context",
    "2017 western Romania water occurrence context"
  ),
  profile_confidence = c(
    "literature_screening",
    "screening_requires_calibration",
    "literature_screening",
    "screening_requires_calibration",
    "screening_requires_calibration",
    "screening_requires_calibration",
    "screening_requires_calibration",
    "screening_requires_calibration"
  ),
  profile_notes = c(
    "Default Volta profile. Use local measured prevalence/excretion if available.",
    "Default Volta profile. Ghana water occurrence supports relevance; emission values still need calibration.",
    "Default Volta profile. Rotavirus units are viral particles/L, not genome copies/L.",
    "Default Volta profile. Replace with local age-stratified prevalence when available.",
    "Default Bega profile. Lower European screening prevalence avoids reusing Ghana/SSA prevalence in Romania.",
    "Default Bega profile. ECDC data are reported cases, not direct shedding prevalence; calibrate if measured wastewater data exist.",
    "Default Bega profile. Rotavirus units are viral particles/L, not genome copies/L.",
    "Default Bega profile. Romania occurrence literature supports presence; calibrate prevalence/excretion when possible."
  ),
  stringsAsFactors = FALSE
)
