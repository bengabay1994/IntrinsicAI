import 'dart:math' as math;
import '../config/app_config.dart';
import '../database/database_service.dart';
import '../database/models/financial.dart';
import 'math_core.dart';
import 'models/metric_result.dart';
import 'models/analysis_result.dart';

/// Service for performing Rule #1 analysis on stocks.
class Rule1Analyzer {
  final DatabaseService _dbService;

  Rule1Analyzer(this._dbService);

  /// Performs complete Rule #1 analysis for a ticker.
  AnalysisResult analyze(String ticker) {
    // Normalize ticker format
    final normalizedTicker = ticker.toUpperCase();
    final dbTicker = normalizedTicker.contains('.')
        ? normalizedTicker
        : '$normalizedTicker.US';

    // Get company info
    final company = _dbService.getCompany(dbTicker);

    // Get financial data (sorted DESC by year, so newest first)
    final financials = _dbService.getFinancials(dbTicker);

    if (financials.isEmpty) {
      return _createEmptyResult(dbTicker, company?.name);
    }

    // Sort by year ascending (oldest first) for calculations
    final sortedFinancials = List<Financial>.from(financials)
      ..sort((a, b) => a.year.compareTo(b.year));

    final yearsOfData = sortedFinancials.length;

    // Determine data quality
    final dataQuality = _getDataQuality(yearsOfData);

    // Build historical data
    final historicalData = _buildHistoricalData(sortedFinancials);

    // Get latest values
    final latest = sortedFinancials.last;
    final latestIdx = sortedFinancials.length - 1;

    // Calculate growth metrics (CAGR)
    final periods = [10, 5, 1];

    double? getValue(Financial f, String metric) {
      switch (metric) {
        case 'eps':
          return f.epsDiluted;
        case 'equity':
          return f.totalEquity;
        case 'revenue':
          return f.revenue;
        case 'fcf':
          return f.freeCashFlow;
        case 'ocf':
          return f.cashFlowOps;
        case 'roic':
          return f.roic;
        default:
          return null;
      }
    }

    GrowthMetrics calculateGrowthForMetric(String metric) {
      MetricResult? calcForPeriod(int period) {
        final startIdx = latestIdx - period;
        if (startIdx < 0) return null;

        final startVal = getValue(sortedFinancials[startIdx], metric);
        final endVal = getValue(latest, metric);
        return MathCore.calculateCagr(startVal, endVal, period);
      }

      return GrowthMetrics(
        tenYear: periods.contains(10) ? calcForPeriod(10) : null,
        fiveYear: periods.contains(5) ? calcForPeriod(5) : null,
        oneYear: periods.contains(1) ? calcForPeriod(1) : null,
      );
    }

    final epsGrowth = calculateGrowthForMetric('eps');
    final equityGrowth = calculateGrowthForMetric('equity');
    final revenueGrowth = calculateGrowthForMetric('revenue');
    final fcfGrowth = calculateGrowthForMetric('fcf');
    final ocfGrowth = calculateGrowthForMetric('ocf');

    // Calculate ROIC averages
    GrowthMetrics calculateRoicAverages() {
      MetricResult? calcAvgForPeriod(int period) {
        final startIdx = math.max(0, latestIdx - period + 1);
        final values = sortedFinancials
            .sublist(startIdx, latestIdx + 1)
            .map((f) => f.roic)
            .toList();
        return MathCore.calculateAverage(values);
      }

      return GrowthMetrics(
        tenYear: calcAvgForPeriod(10),
        fiveYear: calcAvgForPeriod(5),
        oneYear: calcAvgForPeriod(1),
      );
    }

    final roicAverages = calculateRoicAverages();

    // Calculate Sticker Price
    double? stickerPrice;
    double? mosPrice;

    // Use lowest of equity/eps growth for conservative estimate
    final growthCandidates = <double>[];
    if (epsGrowth.tenYear?.isValid == true) {
      growthCandidates.add(epsGrowth.tenYear!.value!);
    }
    if (equityGrowth.tenYear?.isValid == true) {
      growthCandidates.add(equityGrowth.tenYear!.value!);
    }

    if (growthCandidates.isNotEmpty) {
      var estimatedGrowth = growthCandidates.reduce(math.min);
      // Cap growth at 25% for safety
      estimatedGrowth = math.min(estimatedGrowth, 0.25);

      if (estimatedGrowth > 0) {
        // Future PE = 2 * Growth Rate (as percentage), capped at 50
        final futurePe = math.min(estimatedGrowth * 100 * 2, 50.0);

        stickerPrice = MathCore.calculateStickerPrice(
          latest.epsDiluted,
          estimatedGrowth,
          futurePe,
        );

        if (stickerPrice != null) {
          mosPrice = stickerPrice * 0.5;
        }
      }
    }

    // Determine overall status
    var status = AnalysisStatus.green;
    final statusReasons = <String>[];

    // Check data quality
    if (dataQuality == DataQuality.insufficient) {
      status = AnalysisStatus.red;
      statusReasons.add(
        'Insufficient data: only $yearsOfData years (need ${AppConfig.minYearsRequired})',
      );
    } else if (dataQuality == DataQuality.partial) {
      status = AnalysisStatus.yellow;
      statusReasons.add(
        'Partial data: $yearsOfData years (recommend ${AppConfig.minYearsRequired}+)',
      );
    }

    // Check growth metrics (10yr preferred)
    final growthChecks = [
      ('EPS', epsGrowth),
      ('Equity', equityGrowth),
      ('Revenue', revenueGrowth),
      ('FCF', fcfGrowth),
      ('Operating Cash Flow', ocfGrowth),
    ];

    for (final check in growthChecks) {
      final name = check.$1;
      final growth = check.$2;
      final result10yr = growth.tenYear;

      if (result10yr == null) continue;

      if (result10yr.status == MetricStatus.turnaround) {
        if (status != AnalysisStatus.red) {
          status = AnalysisStatus.yellow;
        }
        statusReasons.add('$name: turnaround (${_flagToString(result10yr.flag)})');
      } else if (result10yr.status == MetricStatus.missingData) {
        if (status != AnalysisStatus.red) {
          status = AnalysisStatus.yellow;
        }
        statusReasons.add('$name: missing data');
      } else if (result10yr.isValid) {
        if (result10yr.value! < AppConfig.growthThreshold) {
          status = AnalysisStatus.red;
          final pct = (result10yr.value! * 100).toStringAsFixed(1);
          final threshold = (AppConfig.growthThreshold * 100).toStringAsFixed(0);
          statusReasons.add('$name 10yr CAGR: $pct% (< $threshold%)');
        }
      }
    }

    // Check ROIC average
    final roic10yr = roicAverages.tenYear;
    if (roic10yr != null && roic10yr.value != null) {
      if (roic10yr.value! < AppConfig.roicThreshold) {
        status = AnalysisStatus.red;
        final pct = (roic10yr.value! * 100).toStringAsFixed(1);
        final threshold = (AppConfig.roicThreshold * 100).toStringAsFixed(0);
        statusReasons.add('ROIC 10yr avg: $pct% (< $threshold%)');
      }
      if (roic10yr.flag != null &&
          (roic10yr.flag == MetricFlag.allNegative ||
              roic10yr.flag == MetricFlag.negativeYears)) {
        if (status != AnalysisStatus.red) {
          status = AnalysisStatus.yellow;
        }
        statusReasons.add('ROIC concern: ${_flagToString(roic10yr.flag)}');
      }
    }

    if (statusReasons.isEmpty) {
      statusReasons.add('All metrics pass Rule #1 criteria');
    }

    return AnalysisResult(
      ticker: dbTicker,
      companyName: company?.name,
      yearsOfData: yearsOfData,
      dataQuality: dataQuality,
      epsGrowth: epsGrowth,
      equityGrowth: equityGrowth,
      revenueGrowth: revenueGrowth,
      fcfGrowth: fcfGrowth,
      operatingCashFlowGrowth: ocfGrowth,
      roicAverages: roicAverages,
      historicalData: historicalData,
      stickerPrice: stickerPrice,
      mosPrice: mosPrice,
      status: status,
      statusReasons: statusReasons,
    );
  }

  DataQuality _getDataQuality(int years) {
    if (years >= AppConfig.minYearsRequired) {
      return DataQuality.reliable;
    } else if (years >= 3) {
      return DataQuality.partial;
    } else {
      return DataQuality.insufficient;
    }
  }

  HistoricalData _buildHistoricalData(List<Financial> financials) {
    return HistoricalData(
      years: financials.map((f) => f.year).toList(),
      eps: financials.map((f) => f.epsDiluted).toList(),
      equity: financials.map((f) => f.totalEquity).toList(),
      revenue: financials.map((f) => f.revenue).toList(),
      fcf: financials.map((f) => f.freeCashFlow).toList(),
      operatingCashFlow: financials.map((f) => f.cashFlowOps).toList(),
      roic: financials.map((f) => f.roic).toList(),
    );
  }

  AnalysisResult _createEmptyResult(String ticker, String? companyName) {
    return AnalysisResult(
      ticker: ticker,
      companyName: companyName,
      yearsOfData: 0,
      dataQuality: DataQuality.insufficient,
      epsGrowth: const GrowthMetrics(),
      equityGrowth: const GrowthMetrics(),
      revenueGrowth: const GrowthMetrics(),
      fcfGrowth: const GrowthMetrics(),
      operatingCashFlowGrowth: const GrowthMetrics(),
      roicAverages: const GrowthMetrics(),
      historicalData: const HistoricalData(
        years: [],
        eps: [],
        equity: [],
        revenue: [],
        fcf: [],
        operatingCashFlow: [],
        roic: [],
      ),
      stickerPrice: null,
      mosPrice: null,
      status: AnalysisStatus.red,
      statusReasons: ['No data found for $ticker'],
    );
  }

  String _flagToString(MetricFlag? flag) {
    if (flag == null) return '';
    switch (flag) {
      case MetricFlag.negativeToPositive:
        return 'negative to positive';
      case MetricFlag.positiveToNegative:
        return 'positive to negative';
      case MetricFlag.improvingLoss:
        return 'improving loss';
      case MetricFlag.worseningLoss:
        return 'worsening loss';
      case MetricFlag.allNegative:
        return 'all negative';
      case MetricFlag.negativeYears:
        return 'some negative years';
      default:
        return flag.name;
    }
  }
}
