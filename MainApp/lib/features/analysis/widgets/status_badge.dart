import 'package:flutter/material.dart';
import 'package:intrinsic_ai/core/analysis/models/analysis_result.dart';
import 'package:intrinsic_ai/shared/theme/app_theme.dart';

/// Badge showing the analysis status (GREEN/YELLOW/RED).
class StatusBadge extends StatelessWidget {
  final AnalysisStatus status;
  final double fontSize;

  const StatusBadge({
    super.key,
    required this.status,
    this.fontSize = 14,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: _getColor(),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        _getText(),
        style: TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.bold,
          fontSize: fontSize,
        ),
      ),
    );
  }

  Color _getColor() {
    switch (status) {
      case AnalysisStatus.green:
        return AppTheme.greenStatus;
      case AnalysisStatus.yellow:
        return AppTheme.yellowStatus;
      case AnalysisStatus.red:
        return AppTheme.redStatus;
    }
  }

  String _getText() {
    switch (status) {
      case AnalysisStatus.green:
        return 'GREEN - PASS';
      case AnalysisStatus.yellow:
        return 'YELLOW - REVIEW';
      case AnalysisStatus.red:
        return 'RED - FAIL';
    }
  }
}
