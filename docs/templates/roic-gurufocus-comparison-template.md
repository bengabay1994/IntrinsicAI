# ROIC vs GuruFocus Comparison Template

Use this table when a markdown artifact is preferred over CSV. Keep one row per ticker-year.

| ticker | fiscal_year | intrinsicai_roic | gurufocus_roic | abs_delta_roic | signed_delta_roic | rel_delta_pct | intrinsicai_tax_rate | gurufocus_tax_rate | tax_rate_delta | tax_mode_intrinsicai | tax_mode_gurufocus | tax_mode_match | reason_code | notes |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---|---|---|---|---|
| AAPL.US | 2024 |  |  |  |  |  |  |  |  |  |  |  |  |  |
| MSFT.US | 2024 |  |  |  |  |  |  |  |  |  |  |  |  |  |
| GOOGL.US | 2024 |  |  |  |  |  |  |  |  |  |  |  |  |  |

## Reason Codes

- `tax_fallback_default_25`
- `tax_ratio_outlier`
- `invested_capital_component_gap`
- `period_alignment_mismatch`
- `rounding_or_display_only`
- `unclassified`

## Aggregate Summary Block

Record these per run:

| metric | value |
|---|---:|
| mae_roic |  |
| medae_roic |  |
| p90_abs_delta_roic |  |
| bias_signed_delta_roic |  |
| pct_rows_abs_delta_le_0_020 |  |
| run_status (`pass` / `pass_with_notes` / `needs_calibration`) |  |
