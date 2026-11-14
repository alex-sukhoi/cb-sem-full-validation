# =============================================================================
# 01_simulate_data.R
# Creates a synthetic employee survey (n = 480) for the CB-SEM example.
# No real respondents are involved: data come from a known population model,
# so every step of the validation can be checked against the "truth".
# =============================================================================

suppressPackageStartupMessages(library(lavaan))
set.seed(2026)
RNGkind(sample.kind = "Rejection")

# Population model -------------------------------------------------------------
# POS  = perceived organisational support
# ENG  = work engagement
# BRN  = burnout
# JSAT = job satisfaction
# TI   = turnover intention
pop_model <- '
  POS  =~ 0.80*pos1 + 0.78*pos2 + 0.74*pos3 + 0.70*pos4
  ENG  =~ 0.82*eng1 + 0.79*eng2 + 0.76*eng3 + 0.72*eng4
  BRN  =~ 0.80*brn1 + 0.77*brn2 + 0.75*brn3 + 0.71*brn4
  JSAT =~ 0.84*js1  + 0.80*js2  + 0.75*js3
  TI   =~ 0.85*ti1  + 0.81*ti2  + 0.77*ti3

  ENG  ~  0.50*POS
  BRN  ~ -0.40*POS
  JSAT ~  0.40*ENG + -0.30*BRN
  TI   ~ -0.45*JSAT + 0.25*BRN

  # small "real world" imperfections the hypothesised model ignores:
  # weak cross-loadings (items whose wording overlaps two constructs)
  ENG  =~ 0.18*pos4
  JSAT =~ 0.20*eng4
  BRN  =~ 0.15*ti3
'

n <- 480
latent <- simulateData(pop_model, sample.nobs = n, standardized = TRUE)

# Convert continuous responses to a 5-point Likert scale ---------------------
to_likert <- function(x) {
  cut(x, breaks = c(-Inf, -1.4, -0.5, 0.4, 1.3, Inf), labels = FALSE)
}
survey <- as.data.frame(lapply(latent, to_likert))

# Demographics (gender is used for measurement invariance) --------------------
survey$gender <- sample(c("female", "male"), n, replace = TRUE, prob = c(0.52, 0.48))
survey$tenure_years <- round(rexp(n, rate = 1 / 6), 1)
survey$id <- sprintf("R%03d", seq_len(n))

# A little realistic missingness (about 1% of item responses) -----------------
items <- setdiff(names(survey), c("gender", "tenure_years", "id"))
for (v in items) survey[sample(n, 5), v] <- NA

survey <- survey[, c("id", "gender", "tenure_years", items)]
dir.create("data", showWarnings = FALSE)
write.csv(survey, "data/employee_survey.csv", row.names = FALSE)
cat("Saved data/employee_survey.csv:", nrow(survey), "rows,", length(items), "items\n")
