import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:intrinsic_ai/core/analysis/math_core.dart';
import 'package:intrinsic_ai/core/analysis/models/metric_result.dart';

void main() {
  group('MathCore.calculateCagr', () {
    test('returns missingData for null start value', () {
      final result = MathCore.calculateCagr(null, 10, 5);

      expect(result.value, isNull);
      expect(result.status, MetricStatus.missingData);
      expect(result.flag, MetricFlag.nullValues);
      expect(result.dataPoints, 0);
      expect(result.rawValues, [null, 10]);
    });

    test('returns missingData for null end value', () {
      final result = MathCore.calculateCagr(10, null, 5);

      expect(result.value, isNull);
      expect(result.status, MetricStatus.missingData);
      expect(result.flag, MetricFlag.nullValues);
      expect(result.dataPoints, 0);
      expect(result.rawValues, [10, null]);
    });

    test('returns invalid bothZero when both start and end are zero', () {
      final result = MathCore.calculateCagr(0, 0, 5);

      expect(result.value, isNull);
      expect(result.status, MetricStatus.invalid);
      expect(result.flag, MetricFlag.bothZero);
      expect(result.dataPoints, 2);
      expect(result.rawValues, [0, 0]);
    });

    test('returns invalid fromZero when start is zero', () {
      final result = MathCore.calculateCagr(0, 100, 5);

      expect(result.value, isNull);
      expect(result.status, MetricStatus.invalid);
      expect(result.flag, MetricFlag.fromZero);
      expect(result.dataPoints, 2);
      expect(result.rawValues, [0, 100]);
    });

    test('returns invalid toZero when end is zero', () {
      final result = MathCore.calculateCagr(100, 0, 5);

      expect(result.value, isNull);
      expect(result.status, MetricStatus.invalid);
      expect(result.flag, MetricFlag.toZero);
      expect(result.dataPoints, 2);
      expect(result.rawValues, [100, 0]);
    });

    test('returns turnaround negativeToPositive on sign change', () {
      final result = MathCore.calculateCagr(-10, 2, 5);

      expect(result.value, isNull);
      expect(result.status, MetricStatus.turnaround);
      expect(result.flag, MetricFlag.negativeToPositive);
      expect(result.dataPoints, 2);
    });

    test('returns turnaround positiveToNegative on sign change', () {
      final result = MathCore.calculateCagr(10, -2, 5);

      expect(result.value, isNull);
      expect(result.status, MetricStatus.turnaround);
      expect(result.flag, MetricFlag.positiveToNegative);
      expect(result.dataPoints, 2);
    });

    test('returns turnaround improvingLoss when both negative improve', () {
      final result = MathCore.calculateCagr(-10, -2, 5);

      expect(result.value, isNull);
      expect(result.status, MetricStatus.turnaround);
      expect(result.flag, MetricFlag.improvingLoss);
      expect(result.dataPoints, 2);
    });

    test('returns turnaround worseningLoss when both negative worsen', () {
      final result = MathCore.calculateCagr(-2, -10, 5);

      expect(result.value, isNull);
      expect(result.status, MetricStatus.turnaround);
      expect(result.flag, MetricFlag.worseningLoss);
      expect(result.dataPoints, 2);
    });

    test('returns turnaround worseningLoss when both negatives are equal', () {
      final result = MathCore.calculateCagr(-5, -5, 5);

      expect(result.value, isNull);
      expect(result.status, MetricStatus.turnaround);
      expect(result.flag, MetricFlag.worseningLoss);
      expect(result.dataPoints, 2);
    });

    test('returns invalidPeriod for non-positive years', () {
      final zeroYears = MathCore.calculateCagr(10, 20, 0);
      final negativeYears = MathCore.calculateCagr(10, 20, -2);

      expect(zeroYears.value, isNull);
      expect(zeroYears.status, MetricStatus.invalid);
      expect(zeroYears.flag, MetricFlag.invalidPeriod);

      expect(negativeYears.value, isNull);
      expect(negativeYears.status, MetricStatus.invalid);
      expect(negativeYears.flag, MetricFlag.invalidPeriod);
    });

    test('calculates valid CAGR for positive inputs', () {
      final result = MathCore.calculateCagr(100, 200, 10);

      final expected = math.pow(2, 1 / 10).toDouble() - 1;
      expect(result.status, MetricStatus.valid);
      expect(result.flag, isNull);
      expect(result.dataPoints, 2);
      expect(result.value, closeTo(expected, 1e-12));
      expect(result.rawValues, [100, 200]);
    });

    test('returns zero CAGR when start equals end and positive', () {
      final result = MathCore.calculateCagr(42, 42, 7);

      expect(result.status, MetricStatus.valid);
      expect(result.value, 0);
      expect(result.flag, isNull);
    });
  });

  group('MathCore.calculateAverage', () {
    test('returns missingData when all values are null', () {
      final result = MathCore.calculateAverage([null, null, null]);

      expect(result.value, isNull);
      expect(result.status, MetricStatus.missingData);
      expect(result.flag, MetricFlag.noValidValues);
      expect(result.dataPoints, 0);
      expect(result.rawValues, [null, null, null]);
    });

    test('calculates average using only non-null values', () {
      final result = MathCore.calculateAverage([0.10, null, 0.20, 0.30]);

      expect(result.status, MetricStatus.valid);
      expect(result.value, closeTo(0.20, 1e-12));
      expect(result.dataPoints, 3);
      expect(result.flag, isNull);
    });

    test('flags allNegative when every valid value is negative', () {
      final result = MathCore.calculateAverage([-0.10, -0.20, -0.30]);

      expect(result.status, MetricStatus.valid);
      expect(result.value, closeTo(-0.20, 1e-12));
      expect(result.flag, MetricFlag.allNegative);
    });

    test('flags negativeYears when some values are negative', () {
      final result = MathCore.calculateAverage([0.10, -0.05, 0.20]);

      expect(result.status, MetricStatus.valid);
      expect(result.value, closeTo(0.0833333333, 1e-9));
      expect(result.flag, MetricFlag.negativeYears);
    });

    test('flags extremeOutlierHigh when any value is greater than 1.0', () {
      final result = MathCore.calculateAverage([0.20, 1.01, -0.10]);

      expect(result.status, MetricStatus.valid);
      expect(result.flag, MetricFlag.extremeOutlierHigh);
    });

    test('flags extremeOutlierLow when any value is less than -0.5', () {
      final result = MathCore.calculateAverage([0.20, -0.51, 0.10]);

      expect(result.status, MetricStatus.valid);
      expect(result.flag, MetricFlag.extremeOutlierLow);
    });

    test('prioritizes low outlier over high outlier when both exist', () {
      final result = MathCore.calculateAverage([1.2, -0.6, 0.1]);

      expect(result.status, MetricStatus.valid);
      expect(result.flag, MetricFlag.extremeOutlierLow);
    });

    test('does not flag threshold boundary values as outliers', () {
      final result = MathCore.calculateAverage([1.0, -0.5, 0.2]);

      expect(result.status, MetricStatus.valid);
      expect(result.flag, MetricFlag.negativeYears);
    });
  });

  group('MathCore.calculateStickerPrice', () {
    test('returns null when currentEps is null or non-positive', () {
      expect(MathCore.calculateStickerPrice(null, 0.1, 20), isNull);
      expect(MathCore.calculateStickerPrice(0, 0.1, 20), isNull);
      expect(MathCore.calculateStickerPrice(-1, 0.1, 20), isNull);
    });

    test('returns null when estimatedGrowth is null or non-positive', () {
      expect(MathCore.calculateStickerPrice(2, null, 20), isNull);
      expect(MathCore.calculateStickerPrice(2, 0, 20), isNull);
      expect(MathCore.calculateStickerPrice(2, -0.01, 20), isNull);
    });

    test('returns null when futurePe is null or non-positive', () {
      expect(MathCore.calculateStickerPrice(2, 0.1, null), isNull);
      expect(MathCore.calculateStickerPrice(2, 0.1, 0), isNull);
      expect(MathCore.calculateStickerPrice(2, 0.1, -15), isNull);
    });

    test('uses default marr and formula correctly', () {
      final value = MathCore.calculateStickerPrice(2.5, 0.12, 24);

      final expected =
          2.5 * math.pow(1.12, 10) * 24 / math.pow(1.15, 10);
      expect(value, isNotNull);
      expect(value!, closeTo(expected.toDouble(), 1e-10));
    });

    test('uses custom marr in discounting step', () {
      final lowMarr = MathCore.calculateStickerPrice(3, 0.10, 20, marr: 0.10);
      final highMarr = MathCore.calculateStickerPrice(3, 0.10, 20, marr: 0.20);

      expect(lowMarr, isNotNull);
      expect(highMarr, isNotNull);
      expect(lowMarr!, greaterThan(highMarr!));
    });
  });
}
