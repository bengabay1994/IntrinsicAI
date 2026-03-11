import 'package:equatable/equatable.dart';

/// Represents annual financial data for a company.
class Financial extends Equatable {
  final String ticker;
  final int year;
  final double? revenue;
  final double? netIncome;
  final double? epsDiluted;
  final double? totalEquity;
  final double? cashFlowOps;
  final double? freeCashFlow;
  final double? capitalExp;
  final double? roic;
  final double? sharesOutstanding;

  const Financial({
    required this.ticker,
    required this.year,
    this.revenue,
    this.netIncome,
    this.epsDiluted,
    this.totalEquity,
    this.cashFlowOps,
    this.freeCashFlow,
    this.capitalExp,
    this.roic,
    this.sharesOutstanding,
  });

  factory Financial.fromMap(Map<String, dynamic> map) {
    return Financial(
      ticker: map['ticker'] as String,
      year: map['year'] as int,
      revenue: map['revenue'] as double?,
      netIncome: map['net_income'] as double?,
      epsDiluted: map['eps_diluted'] as double?,
      totalEquity: map['total_equity'] as double?,
      cashFlowOps: map['cash_flow_ops'] as double?,
      freeCashFlow: map['free_cash_flow'] as double?,
      capitalExp: map['capital_exp'] as double?,
      roic: map['roic'] as double?,
      sharesOutstanding: map['shares_outstanding'] as double?,
    );
  }

  @override
  List<Object?> get props => [
        ticker,
        year,
        revenue,
        netIncome,
        epsDiluted,
        totalEquity,
        cashFlowOps,
        freeCashFlow,
        capitalExp,
        roic,
        sharesOutstanding,
      ];
}
