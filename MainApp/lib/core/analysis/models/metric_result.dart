import 'package:equatable/equatable.dart';

/// Status of a metric calculation.
enum MetricStatus {
  valid,
  invalid,
  turnaround,
  missingData,
  insufficientData,
}

/// Flag providing additional context for metric calculations.
enum MetricFlag {
  negativeToPositive,
  positiveToNegative,
  improvingLoss,
  worseningLoss,
  fromZero,
  toZero,
  bothZero,
  nullValues,
  invalidPeriod,
  noValidValues,
  allNegative,
  negativeYears,
  extremeOutlierHigh,
  extremeOutlierLow,
}

/// Result of a single metric calculation with status and context.
class MetricResult extends Equatable {
  /// The calculated value (null if invalid).
  final double? value;

  /// Status of the calculation.
  final MetricStatus status;

  /// Additional context flag.
  final MetricFlag? flag;

  /// Number of data points used.
  final int dataPoints;

  /// The raw values used in calculation.
  final List<double?> rawValues;

  const MetricResult({
    this.value,
    required this.status,
    this.flag,
    required this.dataPoints,
    required this.rawValues,
  });

  /// Whether the calculation produced a valid result.
  bool get isValid => status == MetricStatus.valid && value != null;

  /// Whether this result requires manual review.
  bool get needsReview => status == MetricStatus.turnaround;

  @override
  List<Object?> get props => [value, status, flag, dataPoints, rawValues];

  Map<String, dynamic> toJson() {
    return {
      'value': value,
      'status': status.name,
      'flag': flag?.name,
      'data_points': dataPoints,
      'raw_values': rawValues,
    };
  }
}
