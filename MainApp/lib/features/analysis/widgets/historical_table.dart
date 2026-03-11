import 'package:flutter/material.dart';
import 'package:intrinsic_ai/core/analysis/models/analysis_result.dart';
import 'package:intl/intl.dart';

/// Table displaying historical financial data.
class HistoricalTable extends StatelessWidget {
  final HistoricalData data;

  const HistoricalTable({
    super.key,
    required this.data,
  });

  @override
  Widget build(BuildContext context) {
    if (data.years.isEmpty) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Text('No historical data available'),
        ),
      );
    }

    final numberFormat = NumberFormat.compact();

    return Card(
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: DataTable(
            columnSpacing: 24,
            columns: const [
              DataColumn(label: Text('Year')),
              DataColumn(label: Text('EPS'), numeric: true),
              DataColumn(label: Text('Equity'), numeric: true),
              DataColumn(label: Text('Revenue'), numeric: true),
              DataColumn(label: Text('FCF'), numeric: true),
              DataColumn(label: Text('OCF'), numeric: true),
              DataColumn(label: Text('ROIC'), numeric: true),
            ],
            rows: List.generate(data.years.length, (index) {
              return DataRow(cells: [
                DataCell(Text(data.years[index].toString())),
                DataCell(Text(_formatEps(data.eps[index]))),
                DataCell(Text(_formatBillions(data.equity[index], numberFormat))),
                DataCell(Text(_formatBillions(data.revenue[index], numberFormat))),
                DataCell(Text(_formatBillions(data.fcf[index], numberFormat))),
                DataCell(Text(_formatBillions(data.operatingCashFlow[index], numberFormat))),
                DataCell(Text(_formatPercent(data.roic[index]))),
              ]);
            }),
          ),
        ),
      ),
    );
  }

  String _formatEps(double? value) {
    if (value == null) return 'N/A';
    return value.toStringAsFixed(2);
  }

  String _formatBillions(double? value, NumberFormat format) {
    if (value == null) return 'N/A';
    return '${(value / 1e9).toStringAsFixed(1)}B';
  }

  String _formatPercent(double? value) {
    if (value == null) return 'N/A';
    return '${(value * 100).toStringAsFixed(1)}%';
  }
}
