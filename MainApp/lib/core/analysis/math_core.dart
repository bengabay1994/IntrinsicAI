import 'dart:math' as math;
import 'models/metric_result.dart';

/// Core mathematical functions for Rule #1 analysis.
class MathCore {
  MathCore._();

  /// Calculates Compound Annual Growth Rate (CAGR) with edge case handling.
  ///
  /// CAGR = (endVal / startVal) ^ (1/years) - 1
  ///
  /// Edge cases:
  /// - Negative to positive: turnaround (cannot calculate meaningful CAGR)
  /// - Positive to negative: deteriorating
  /// - Zero values: cannot calculate
  /// - Both negative: improving_loss or worsening_loss
  static MetricResult calculateCagr(double? startVal, double? endVal, int years) {
    final rawValues = [startVal, endVal];

    // Check for None/missing values
    if (startVal == null || endVal == null) {
      return MetricResult(
        value: null,
        status: MetricStatus.missingData,
        flag: MetricFlag.nullValues,
        dataPoints: 0,
        rawValues: rawValues,
      );
    }

    // Check for zero values
    if (startVal == 0 && endVal == 0) {
      return MetricResult(
        value: null,
        status: MetricStatus.invalid,
        flag: MetricFlag.bothZero,
        dataPoints: 2,
        rawValues: rawValues,
      );
    }

    if (startVal == 0) {
      return MetricResult(
        value: null,
        status: MetricStatus.invalid,
        flag: MetricFlag.fromZero,
        dataPoints: 2,
        rawValues: rawValues,
      );
    }

    if (endVal == 0) {
      return MetricResult(
        value: null,
        status: MetricStatus.invalid,
        flag: MetricFlag.toZero,
        dataPoints: 2,
        rawValues: rawValues,
      );
    }

    // Check for sign changes (turnarounds)
    if (startVal < 0 && endVal > 0) {
      return MetricResult(
        value: null,
        status: MetricStatus.turnaround,
        flag: MetricFlag.negativeToPositive,
        dataPoints: 2,
        rawValues: rawValues,
      );
    }

    if (startVal > 0 && endVal < 0) {
      return MetricResult(
        value: null,
        status: MetricStatus.turnaround,
        flag: MetricFlag.positiveToNegative,
        dataPoints: 2,
        rawValues: rawValues,
      );
    }

    // Both negative
    if (startVal < 0 && endVal < 0) {
      // Check if losses are improving or worsening
      // Less negative = improving (e.g., -10 to -2)
      final flag = endVal.abs() < startVal.abs()
          ? MetricFlag.improvingLoss
          : MetricFlag.worseningLoss;
      return MetricResult(
        value: null,
        status: MetricStatus.turnaround,
        flag: flag,
        dataPoints: 2,
        rawValues: rawValues,
      );
    }

    // Standard CAGR calculation (both positive)
    if (years <= 0) {
      return MetricResult(
        value: null,
        status: MetricStatus.invalid,
        flag: MetricFlag.invalidPeriod,
        dataPoints: 2,
        rawValues: rawValues,
      );
    }

    final cagr = math.pow(endVal / startVal, 1 / years) - 1;

    return MetricResult(
      value: cagr.toDouble(),
      status: MetricStatus.valid,
      flag: null,
      dataPoints: 2,
      rawValues: rawValues,
    );
  }

  /// Calculates average with edge case handling.
  /// Used for ROIC averages.
  static MetricResult calculateAverage(List<double?> values) {
    // Filter out null values
    final validValues = values.whereType<double>().toList();

    if (validValues.isEmpty) {
      return MetricResult(
        value: null,
        status: MetricStatus.missingData,
        flag: MetricFlag.noValidValues,
        dataPoints: 0,
        rawValues: values,
      );
    }

    final avg = validValues.reduce((a, b) => a + b) / validValues.length;

    // Check for concerning patterns
    MetricFlag? flag;
    final negativeCount = validValues.where((v) => v < 0).length;

    if (negativeCount == validValues.length) {
      flag = MetricFlag.allNegative;
    } else if (negativeCount > 0) {
      flag = MetricFlag.negativeYears;
    }

    // Check for extreme outliers (data quality issue)
    if (validValues.any((v) => v > 1.0)) {
      // > 100% ROIC
      flag = MetricFlag.extremeOutlierHigh;
    }
    if (validValues.any((v) => v < -0.5)) {
      // < -50% ROIC
      flag = MetricFlag.extremeOutlierLow;
    }

    return MetricResult(
      value: avg,
      status: MetricStatus.valid,
      flag: flag,
      dataPoints: validValues.length,
      rawValues: values,
    );
  }

  /// Calculates Rule #1 Sticker Price (Intrinsic Value).
  ///
  /// 1. Project EPS forward 10 years at estimatedGrowth
  /// 2. Multiply projected EPS by futurePe to get future stock price
  /// 3. Discount future stock price back to today at MARR
  static double? calculateStickerPrice(
    double? currentEps,
    double? estimatedGrowth,
    double? futurePe, {
    double marr = 0.15,
  }) {
    if (currentEps == null || currentEps <= 0) return null;
    if (estimatedGrowth == null || estimatedGrowth <= 0) return null;
    if (futurePe == null || futurePe <= 0) return null;

    // Future EPS in 10 years
    final futureEps = currentEps * math.pow(1 + estimatedGrowth, 10);

    // Future Price
    final futurePrice = futureEps * futurePe;

    // Present Value (Sticker Price)
    final stickerPrice = futurePrice / math.pow(1 + marr, 10);

    return stickerPrice;
  }
}
