import 'package:flutter/material.dart';
import 'package:intrinsic_ai/core/analysis/models/analysis_result.dart';
import 'package:intrinsic_ai/core/analysis/models/metric_result.dart';

/// Card displaying growth metrics (CAGR) for a specific metric.
class GrowthMetricsCard extends StatelessWidget {
  final String title;
  final GrowthMetrics metrics;

  const GrowthMetricsCard({
    super.key,
    required this.title,
    required this.metrics,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 12),
            _buildMetricRow(context, '10yr', metrics.tenYear),
            const Divider(height: 16),
            _buildMetricRow(context, '5yr', metrics.fiveYear),
            const Divider(height: 16),
            _buildMetricRow(context, '1yr', metrics.oneYear),
          ],
        ),
      ),
    );
  }

  Widget _buildMetricRow(
      BuildContext context, String period, MetricResult? result) {
    String valueText;
    Color? valueColor;
    String? flagText;

    if (result == null) {
      valueText = 'N/A';
    } else if (result.value != null) {
      final pct = (result.value! * 100).toStringAsFixed(1);
      valueText = '$pct%';
      valueColor = result.value! >= 0.10
          ? Colors.green
          : result.value! >= 0
              ? Colors.orange
              : Colors.red;
    } else {
      valueText = 'N/A';
    }

    if (result?.status == MetricStatus.turnaround) {
      flagText = '[TURNAROUND]';
      valueColor = Colors.orange;
    } else if (result?.status == MetricStatus.missingData) {
      flagText = '[MISSING]';
      valueColor = Colors.grey;
    }

    return Row(
      children: [
        SizedBox(
          width: 40,
          child: Text(
            period,
            style: const TextStyle(fontWeight: FontWeight.w500),
          ),
        ),
        Expanded(
          child: Row(
            children: [
              Text(
                valueText,
                style: TextStyle(
                  color: valueColor,
                  fontWeight: FontWeight.bold,
                ),
              ),
              if (flagText != null) ...[
                const SizedBox(width: 8),
                Text(
                  flagText,
                  style: TextStyle(
                    color: valueColor,
                    fontSize: 12,
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}
