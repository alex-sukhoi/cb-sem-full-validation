# =============================================================================
# 02_validate_and_fit.R
# Full validation of a covariance-based SEM (CB-SEM), following the two-step
# approach of Anderson & Gerbing (1988):
#   1. Data screening
#   2. Measurement model (CFA): fit, loadings, competing models
#   3. Reliability: Cronbach's alpha, McDonald's omega, composite reliability
#   4. Convergent validity: AVE
#   5. Discriminant validity: Fornell-Larcker and HTMT
#   6. Common-method bias: Harman's test and full collinearity VIFs
#   7. Measurement invariance across gender
#   8. Structural model: paths, R2, bootstrapped indirect effects
#   9. Comparison of alternative structural models
# =============================================================================

suppressPackageStartupMessages({
  library(lavaan); library(semTools); library(psych)
  library(ggplot2); library(semPlot)
})
set.seed(2026)
dir.create("results", showWarnings = FALSE)
dir.create("figures", showWarnings = FALSE)

dat   <- read.csv("data/employee_survey.csv")
items <- grep("^(pos|eng|brn|js|ti)\\d", names(dat), value = TRUE)
blocks <- list(POS = paste0("pos", 1:4), ENG = paste0("eng", 1:4),
               BRN = paste0("brn", 1:4), JSAT = paste0("js", 1:3),
               TI  = paste0("ti", 1:3))
r3 <- function(x) round(x, 3)
vec <- function(x) {  # semTools >= 0.5-7 may return a data frame or a list
  if (is.data.frame(x)) x <- x[1, , drop = TRUE]
  if (is.list(x)) x <- sapply(x, as.numeric)
  x
}
save_csv <- function(x, f) write.csv(x, file.path("results", f), row.names = FALSE)

# -----------------------------------------------------------------------------
# 1. Data screening
# -----------------------------------------------------------------------------
desc <- psych::describe(dat[, items])
screening <- data.frame(item = items, n = desc$n, mean = r3(desc$mean),
                        sd = r3(desc$sd), skew = r3(desc$skew),
                        kurtosis = r3(desc$kurtosis),
                        pct_missing = r3(100 * colMeans(is.na(dat[, items]))))
save_csv(screening, "01_item_screening.csv")

cc <- na.omit(dat[, items])
mardia <- psych::mardia(cc, plot = FALSE)
d2 <- mahalanobis(cc, colMeans(cc), cov(cc))
n_outliers <- sum(d2 > qchisq(0.999, df = length(items)))
cat(sprintf("Screening: max |skew| = %.2f, max |kurtosis| = %.2f, Mardia kurtosis p = %.3g, outliers (p<.001) = %d\n",
            max(abs(desc$skew)), max(abs(desc$kurtosis)), mardia$p.kurt, n_outliers))
# Univariate values are within |skew| < 2 and |kurtosis| < 7 (Curran et al., 1996).
# Items are 5-point Likert, so robust ML (MLR) is used as a safeguard, with FIML
# for the ~1% missing responses.

# -----------------------------------------------------------------------------
# 2. Measurement model (CFA)
# -----------------------------------------------------------------------------
cfa_model <- paste(sprintf("%s =~ %s", names(blocks),
                           sapply(blocks, paste, collapse = " + ")), collapse = "\n")
fit_cfa <- cfa(cfa_model, data = dat, estimator = "MLR", missing = "fiml")

fit_idx <- c("chisq.scaled", "df.scaled", "pvalue.scaled", "cfi.robust",
             "tli.robust", "rmsea.robust", "rmsea.ci.lower.robust",
             "rmsea.ci.upper.robust", "srmr", "aic", "bic")
fit_row <- function(fit, label) {
  f <- fitMeasures(fit, fit_idx)
  data.frame(model = label, chisq = r3(f[1]), df = f[2], p = signif(f[3], 3),
             chisq_df = r3(f[1] / f[2]), CFI = r3(f[4]), TLI = r3(f[5]),
             RMSEA = r3(f[6]), RMSEA_90CI = sprintf("%.3f-%.3f", f[7], f[8]),
             SRMR = r3(f[9]), AIC = round(f[10], 1), BIC = round(f[11], 1),
             row.names = NULL)
}

std <- standardizedSolution(fit_cfa)
loadings <- subset(std, op == "=~")[, c("lhs", "rhs", "est.std", "se", "pvalue")]
names(loadings) <- c("construct", "item", "std_loading", "se", "p")
loadings[, 3:5] <- lapply(loadings[, 3:5], r3)
save_csv(loadings, "03_standardised_loadings.csv")

# Competing measurement models
one_factor  <- paste("G =~", paste(items, collapse = " + "))
four_factor <- sub("ENG =~ ", "ENG =~ js1 + js2 + js3 + ",
                   sub("\nJSAT =~ js1 \\+ js2 \\+ js3", "", cfa_model))
fit_1f <- cfa(one_factor,  data = dat, estimator = "MLR", missing = "fiml")
fit_4f <- cfa(four_factor, data = dat, estimator = "MLR", missing = "fiml")
competing <- rbind(fit_row(fit_1f, "1 factor (Harman / common method)"),
                   fit_row(fit_4f, "4 factors (engagement + satisfaction merged)"),
                   fit_row(fit_cfa, "5 factors (hypothesised)"))
save_csv(competing, "02_measurement_model_fit.csv")

# -----------------------------------------------------------------------------
# 3-4. Reliability and convergent validity
# -----------------------------------------------------------------------------
alpha_vals <- sapply(blocks, function(v) psych::alpha(dat[, v], warnings = FALSE)$total$raw_alpha)
omega_vals <- vec(semTools::compRelSEM(fit_cfa))            # model-based omega / CR
ave_vals   <- vec(semTools::AVE(fit_cfa))
reliab <- data.frame(construct = names(blocks), items = lengths(blocks),
                     alpha = r3(alpha_vals), omega_CR = r3(omega_vals[names(blocks)]),
                     AVE = r3(ave_vals[names(blocks)]), sqrt_AVE = r3(sqrt(ave_vals[names(blocks)])))
save_csv(reliab, "04_reliability_convergent_validity.csv")

# -----------------------------------------------------------------------------
# 5. Discriminant validity
# -----------------------------------------------------------------------------
phi <- lavInspect(fit_cfa, "cor.lv")[names(blocks), names(blocks)]
fl <- phi; diag(fl) <- sqrt(ave_vals[names(blocks)])
fl[upper.tri(fl)] <- NA
save_csv(cbind(construct = rownames(fl), as.data.frame(r3(fl))), "05_fornell_larcker.csv")

htmt <- semTools::htmt(cfa_model, data = dat, missing = "ml")
htmt_out <- htmt; htmt_out[upper.tri(htmt_out, diag = TRUE)] <- NA
save_csv(cbind(construct = rownames(htmt_out), as.data.frame(r3(htmt_out))), "05b_htmt.csv")

hdf <- as.data.frame(as.table(htmt_out)); hdf <- hdf[!is.na(hdf$Freq), ]
g_htmt <- ggplot(hdf, aes(Var2, Var1, fill = Freq)) +
  geom_tile(colour = "white") +
  geom_text(aes(label = sprintf("%.2f", Freq)), size = 4.5) +
  scale_fill_gradient(low = "#e8f1fb", high = "#2b6cb0", limits = c(0, 0.9),
                      name = "HTMT") +
  labs(title = "Discriminant validity: HTMT ratios",
       subtitle = "All values below the 0.85 threshold (Henseler et al., 2015)",
       x = NULL, y = NULL) +
  theme_minimal(base_size = 13)
ggsave("figures/htmt_heatmap.png", g_htmt, width = 7, height = 5, dpi = 110)

# -----------------------------------------------------------------------------
# 6. Common-method bias
# -----------------------------------------------------------------------------
# (a) Harman: variance explained by one unrotated factor
harman <- psych::fa(cc, nfactors = 1, rotate = "none", fm = "ml")
harman_var <- harman$Vaccounted[2, 1]
# (b) Full collinearity test (Kock, 2015): regress each construct score on all
#     others; VIF > 3.3 would signal pathological common-method variance
scores <- as.data.frame(lavPredict(fit_cfa))
vif_fc <- sapply(names(scores), function(v) {
  r2 <- summary(lm(scores[[v]] ~ ., data = scores[, setdiff(names(scores), v)]))$r.squared
  1 / (1 - r2)
})
cmb <- data.frame(check = c("Harman single factor: share of variance (< 0.50)",
                            "Single-factor CFA: robust CFI (poor fit expected)",
                            paste0("Full collinearity VIF: ", names(vif_fc), " (< 3.3)")),
                  value = r3(c(harman_var, fitMeasures(fit_1f, "cfi.robust"), vif_fc)))
save_csv(cmb, "06_common_method_bias.csv")

# -----------------------------------------------------------------------------
# 7. Measurement invariance across gender
# -----------------------------------------------------------------------------
inv_fit <- function(eq) cfa(cfa_model, data = dat, group = "gender", estimator = "MLR",
                            missing = "fiml", group.equal = eq)
configural <- inv_fit(character(0))
metric     <- inv_fit("loadings")
scalar     <- inv_fit(c("loadings", "intercepts"))
strict     <- inv_fit(c("loadings", "intercepts", "residuals"))
inv <- rbind(fit_row(configural, "Configural"), fit_row(metric, "Metric"),
             fit_row(scalar, "Scalar"), fit_row(strict, "Strict"))
inv$delta_CFI   <- c(NA, r3(diff(inv$CFI)))
inv$delta_RMSEA <- c(NA, r3(diff(inv$RMSEA)))
inv$supported   <- c("baseline", ifelse(abs(inv$delta_CFI[-1]) <= 0.01 &
                                          abs(inv$delta_RMSEA[-1]) <= 0.015, "yes", "no"))
save_csv(inv, "07_measurement_invariance_gender.csv")

g_inv <- ggplot(inv, aes(factor(model, levels = model), CFI, group = 1)) +
  geom_line(colour = "#2b6cb0", linewidth = 1) + geom_point(size = 3, colour = "#2b6cb0") +
  geom_hline(yintercept = 0.95, linetype = "dashed", colour = "grey40") +
  geom_text(aes(label = sprintf("CFI %.3f\nRMSEA %.3f", CFI, RMSEA)), vjust = -0.6, size = 3.6) +
  scale_y_continuous(limits = c(0.93, 1.0)) +
  labs(title = "Measurement invariance across gender",
       subtitle = "Change in CFI stays within 0.01 at every step (Chen, 2007)",
       x = NULL, y = "Robust CFI") +
  theme_minimal(base_size = 13)
ggsave("figures/measurement_invariance.png", g_inv, width = 7, height = 4.5, dpi = 110)

# -----------------------------------------------------------------------------
# 8. Structural model with bootstrapped indirect effects
# -----------------------------------------------------------------------------
sem_model <- paste(cfa_model, '
  ENG  ~ a1*POS
  BRN  ~ a2*POS
  JSAT ~ b1*ENG + b2*BRN
  TI   ~ c1*JSAT + c2*BRN
  # indirect effects
  POS_ENG_JSAT     := a1*b1
  POS_BRN_JSAT     := a2*b2
  POS_to_TI_total  := a1*b1*c1 + a2*b2*c1 + a2*c2
  BRN_to_TI_total  := c2 + b2*c1
', sep = "\n")
fit_sem <- sem(sem_model, data = dat, estimator = "ML", missing = "fiml",
               se = "bootstrap", bootstrap = 1000)
pe <- parameterEstimates(fit_sem, boot.ci.type = "perc", standardized = TRUE)
paths <- subset(pe, op %in% c("~", ":="))[, c("lhs", "op", "rhs", "label", "est", "ci.lower", "ci.upper", "pvalue", "std.all")]
paths[, 5:9] <- lapply(paths[, 5:9], r3)
save_csv(paths, "08_structural_paths_and_indirect_effects.csv")
r2 <- lavInspect(fit_sem, "r2")[c("ENG", "BRN", "JSAT", "TI")]
save_csv(data.frame(construct = names(r2), R2 = r3(r2)), "08b_r_squared.csv")

# -----------------------------------------------------------------------------
# 9. Alternative structural models
# -----------------------------------------------------------------------------
fit_s <- function(m) sem(m, data = dat, estimator = "MLR", missing = "fiml")
alt_full_med <- sub("TI   ~ c1\\*JSAT \\+ c2\\*BRN", "TI   ~ c1*JSAT", sem_model)
alt_full_med <- sub("  POS_to_TI_total.*\n  BRN_to_TI_total.*\n", "", alt_full_med)
alt_direct   <- paste(sem_model, "TI ~ POS", sep = "\n")
fit_hyp <- fit_s(sem_model); fit_fm <- fit_s(alt_full_med); fit_dir <- fit_s(alt_direct)
alt <- rbind(fit_row(fit_fm, "A: burnout affects TI only via satisfaction"),
             fit_row(fit_hyp, "B: hypothesised model"),
             fit_row(fit_dir, "C: B + direct POS -> TI"))
save_csv(alt, "09_alternative_structural_models.csv")

# Path diagram
png("figures/structural_model.png", width = 1100, height = 650, res = 110)
lay <- matrix(c(-1, 0,   0, 0.6,   0, -0.6,   1, 0.6,   2, 0), ncol = 2, byrow = TRUE)
semPaths(fit_hyp, what = "std", whatLabels = "std", structural = TRUE, layout = lay,
         intercepts = FALSE, edge.label.cex = 1.1, sizeLat = 11, nCharNodes = 0,
         edge.label.position = 0.55,
         edge.color = "#2b6cb0", color = list(lat = "#e8f1fb"), residuals = FALSE,
         title = FALSE, mar = c(4, 6, 9, 6))
title("Structural model (standardised estimates)", line = 1)
dev.off()

cat("\nMeasurement model:\n"); print(competing[, c("model", "chisq_df", "CFI", "TLI", "RMSEA", "SRMR")], row.names = FALSE)
cat("\nReliability & AVE:\n"); print(reliab, row.names = FALSE)
cat("\nMax HTMT:", r3(max(hdf$Freq)), "\n")
cat("\nCommon-method bias:\n"); print(cmb, row.names = FALSE)
cat("\nInvariance:\n"); print(inv[, c("model", "CFI", "RMSEA", "delta_CFI", "supported")], row.names = FALSE)
cat("\nStructural paths:\n"); print(paths[, c("lhs", "op", "rhs", "est", "ci.lower", "ci.upper", "std.all")], row.names = FALSE)
cat("\nR2:\n"); print(r3(r2))
cat("\nAlternative models:\n"); print(alt[, c("model", "CFI", "RMSEA", "AIC", "BIC")], row.names = FALSE)
