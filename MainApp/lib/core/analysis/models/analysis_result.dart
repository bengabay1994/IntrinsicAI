import 'package:equatable/equatable.dart';
import 'metric_result.dart';

/// Overall status of a stock analysis.
enum AnalysisStatus {
  green,  // Passes all Rule #1 criteria
  yellow, // Needs manual review (turnarounds, partial data)
  red,    // Fails Rule #1 criteria
}

/// Data quality classification.
enum DataQuality {
  reliable,     // 7+ years of data
  partial,      // 3-6 years of data
  insufficient, // <3 years of data
}

/// Historical data for a single metric.
class HistoricalData extends Equatable {
  final List<int> years;
  final List<double?> eps;
  final List<double?> equity;
  final List<double?> revenue;
  final List<double?> fcf;
  final List<double?> operatingCashFlow;
  final List<double?> roic;

  const HistoricalData({
    required this.years,
    required this.eps,
    required this.equity,
    required this.revenue,
    required this.fcf,
    required this.operatingCashFlow,
    required this.roic,
  });

  @override
  List<Object?> get props => [years, eps, equity, revenue, fcf, operatingCashFlow, roic];

  Map<String, dynamic> toJson() {
    return {
      'years': years,
      'eps': eps,
      'equity': equity,
      'revenue': revenue,
      'fcf': fcf,
      'operating_cash_flow': operatingCashFlow,
      'roic': roic,
    };
  }
}

/// Growth metrics for different time periods.
class GrowthMetrics extends Equatable {
  final MetricResult? tenYear;
  final MetricResult? fiveYear;
  final MetricResult? oneYear;

  const GrowthMetrics({
    this.tenYear,
    this.fiveYear,
    this.oneYear,
  });

  @override
  List<Object?> get props => [tenYear, fiveYear, oneYear];

  Map<String, dynamic> toJson() {
    return {
      '10yr': tenYear?.toJson(),
      '5yr': fiveYear?.toJson(),
      '1yr': oneYear?.toJson(),
    };
  }
}

/// Complete analysis result for a ticker.
class AnalysisResult extends Equatable {
  final String ticker;
  final String? companyName;
  final int yearsOfData;
  final DataQuality dataQuality;

  // Growth metrics (CAGR)
  final GrowthMetrics epsGrowth;
  final GrowthMetrics equityGrowth;
  final GrowthMetrics revenueGrowth;
  final GrowthMetrics fcfGrowth;
  final GrowthMetrics operatingCashFlowGrowth;

  // Average metrics
  final GrowthMetrics roicAverages;

  // Raw historical data for LLM
  final HistoricalData historicalData;

  // Valuation
  final double? stickerPrice;
  final double? mosPrice;

  // Overall assessment
  final AnalysisStatus status;
  final List<String> statusReasons;

  const AnalysisResult({
    required this.ticker,
    this.companyName,
    required this.yearsOfData,
    required this.dataQuality,
    required this.epsGrowth,
    required this.equityGrowth,
    required this.revenueGrowth,
    required this.fcfGrowth,
    required this.operatingCashFlowGrowth,
    required this.roicAverages,
    required this.historicalData,
    this.stickerPrice,
    this.mosPrice,
    required this.status,
    required this.statusReasons,
  });

  @override
  List<Object?> get props => [
        ticker,
        companyName,
        yearsOfData,
        dataQuality,
        epsGrowth,
        equityGrowth,
        revenueGrowth,
        fcfGrowth,
        operatingCashFlowGrowth,
        roicAverages,
        historicalData,
        stickerPrice,
        mosPrice,
        status,
        statusReasons,
      ];

  Map<String, dynamic> toJson() {
    return {
      'ticker': ticker,
      'company_name': companyName,
      'years_of_data': yearsOfData,
      'data_quality': dataQuality.name,
      'eps_growth': epsGrowth.toJson(),
      'equity_growth': equityGrowth.toJson(),
      'revenue_growth': revenueGrowth.toJson(),
      'fcf_growth': fcfGrowth.toJson(),
      'operating_cash_flow_growth': operatingCashFlowGrowth.toJson(),
      'roic_averages': roicAverages.toJson(),
      'historical_data': historicalData.toJson(),
      'sticker_price': stickerPrice,
      'mos_price': mosPrice,
      'status': status.name,
      'status_reasons': statusReasons,
    };
  }
}
