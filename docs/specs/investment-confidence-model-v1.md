# IntrinsicAI Investment Confidence Model v1

Status: Draft for review  
Issue: IntrinsicAI-e15  
Owner: bengabay1994  
Last updated: 2026-03-09

## 1. Purpose

Define a canonical score that answers:

"How attractive is this company as a Rule #1 investment candidate?"

This score is about business quality and investment attractiveness first. Data completeness does not add points; it only limits certainty using caps and warning flags.

## 2. Output Contract

For each analyzed ticker, produce:
- `investment_score` (0-100): attractiveness score.
- `investment_grade`: one of `perfect`, `good`, `optional`, `bad`, `very_bad`, `shit`.
- `score_breakdown`: points by component.
- `confidence_cap`: optional cap applied due to data/trust limitations.
- `cap_reasons`: list of cap reasons.

## 3. Scoring Philosophy

### 3.1 Principles
- Reward durable compounding quality (Big 5 + ROIC + consistency).
- Reward management quality and owner-oriented behavior (CEO letters and other signals when available).
- Penalize fragility, instability, and weak economics.
- Never reward a stock just because data is complete.

### 3.2 Score equation

`final_investment_score = min(base_quality_score, confidence_cap_if_any)`

Where:
- `base_quality_score` is computed from company quality components.
- `confidence_cap_if_any` defaults to 100 when no cap applies.

## 4. Base Quality Score (0-100)

### 4.1 Component weights
- `fundamentals_score` (0-75)
- `management_score` (0-20)
- `moat_score` (0-5)

`base_quality_score = fundamentals_score + management_score + moat_score`

### 4.2 Fundamentals score (0-75)

Importance order is applied directly in weights:
1. ROIC
2. Revenue
3. EPS
4. Equity
5. Free Cash Flow and Operating Cash Flow

#### A) ROIC quality (0-30)

Use 10y average ROIC as primary signal:
- >= 20%: 30
- >= 15% and < 20%: 27
- >= 12% and < 15%: 24
- >= 10% and < 12%: 21
- >= 8% and < 10%: 16
- >= 5% and < 8%: 9
- < 5%: 2
- missing: 8

Adjustments:
- If negative ROIC years exist in 10y set: -3
- If extreme outlier flags exist: -2
- Floor at 0.

#### B) Big 5 growth quality (0-45)

Metrics:
- Revenue growth
- EPS growth
- Equity growth
- Free cash flow growth
- Operating cash flow growth

Per metric max points (reflecting priority):
- Revenue: 14
- EPS: 12
- Equity: 9
- Free cash flow: 5
- Operating cash flow: 5

Per metric band score:
- >= 10%: 100% of that metric's max points
- >= 8% and < 10%: 80% of that metric's max points
- >= 5% and < 8%: 50% of that metric's max points
- > 0% and < 5%: 25% of that metric's max points
- <= 0%: 0% of that metric's max points
- turnaround or missing: 35% of that metric's max points (neutral-caution)

Window policy:
- Primary: 10y growth.
- Adjustment: if 5y materially contradicts 10y trend, subtract up to 2 points from that metric.

## 5. Management Score (0-20)

Scored from CEO letters and management evidence (manual or AI-assisted with review).

### 5.1 CEO communication quality (0-10)
- Candor about mistakes/risks: 0-3
- Long-term strategy clarity (5-10 year lens): 0-3
- Capital allocation discipline discussion: 0-2
- Shareholder alignment language and behavior: 0-2

### 5.2 Execution and alignment signals (0-10)
- Consistency between stated strategy and observed financial outcomes: 0-4
- Evidence of moat strengthening initiatives: 0-3
- Owner-operator behavior (long-term incentives, prudence): 0-3

If CEO letters unavailable, default management score is 10 with low-confidence flag (neutral baseline, not a reward).

## 6. Moat Score (0-10)

Based on Rule #1 moat categories (`Brand`, `Secret`, `Toll`, `Switching`, `Price`, `None`).

Scoring guide:
- Strong durable moat evidence: 8-10
- Moderate moat evidence: 5-7
- Weak/uncertain moat: 2-4
- None: 0-1

When uncertain, score conservatively.

## 7. Confidence Caps (Data/Trust Modifiers)

Caps prevent overconfidence when evidence quality is weak. They do not increase score.

Start with cap = 100, then apply minimum of all applicable caps.

### 7.1 Cap rules
- Years of data < 8: cap 69
- Years of data < 5: cap 59
- Missing 10y values for 2+ Big 5 metrics: cap 64
- ROIC missing for 4+ of last 10 years: cap 64
- Latest update older than 400 days: cap 64
- Multiple turnaround flags across Big 5: cap 69

### 7.2 Cap reason reporting

Each cap must emit structured reason text (example: `insufficient_history_under_8_years`).

## 8. Grade Mapping

- `perfect`: score >= 90 and <= 100
- `good`: score >= 80 and < 90
- `optional`: score >= 60 and < 80
- `bad`: score >= 40 and < 60
- `very_bad`: score >= 20 and < 40
- `shit`: score >= 0 and < 20

If a cap is active, include badge: `capped_confidence`.

## 9. Examples

### 9.1 High-quality compounder
- Base score: 90
- Cap: 100
- Final: 90 (`perfect`)

### 9.2 Good company but insufficient history
- Base score: 82
- Cap due to 6 years only: 69
- Final: 69 (`optional`, with cap reason)

### 9.3 Near-threshold grower with weak ROIC stability
- Base score: 63
- Cap: 100
- Final: 63 (`optional`)

## 10. Implementation Notes

- This document is a scoring contract; implementation should be incremental.
- Keep all component scores and cap reasons explainable in UI.
- AI-derived management/moat signals should be reviewable and overrideable.

## 11. Related Issues

- `IntrinsicAI-2uh`: data quality policy and confidence scoring model.
- `IntrinsicAI-fy9`: analysis provenance contract.
- `IntrinsicAI-mxg`: provenance display in UI.
- `IntrinsicAI-s4v`: benchmark ticker set.
- `IntrinsicAI-oms`: golden regression tests.

## 12. Acceptance Criteria for IntrinsicAI-e15

- A versioned scoring model spec exists and is committed.
- Model explicitly separates quality score from data/trust caps.
- Big 5, ROIC, management, and moat contributions are defined.
- Caps and grades are deterministic and reviewable.
