import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intrinsic_ai/core/analysis/models/analysis_result.dart';
import 'package:intrinsic_ai/shared/providers/providers.dart';
import 'widgets/status_badge.dart';
import 'widgets/valuation_card.dart';
import 'widgets/growth_metrics_card.dart';
import 'widgets/historical_table.dart';
import 'widgets/ai_insights_card.dart';
import 'widgets/ceo_letters_card.dart';

/// Screen displaying the analysis results for a stock.
class AnalysisScreen extends ConsumerWidget {
  const AnalysisScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(analysisProvider);

    if (state.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (state.error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 48, color: Colors.red),
            const SizedBox(height: 16),
            Text(
              'Error: ${state.error}',
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    final result = state.result;
    if (result == null) {
      return const Center(
        child: Text('Enter a ticker symbol to analyze'),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          _buildHeader(context, result),
          const SizedBox(height: 24),

          // Status and Valuation Row
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: _buildStatusCard(context, result)),
              const SizedBox(width: 16),
              Expanded(
                child: ValuationCard(
                  stickerPrice: result.stickerPrice,
                  mosPrice: result.mosPrice,
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),

          // Growth Metrics Section
          Text(
            'Growth Metrics (CAGR)',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 16),
          _buildGrowthMetricsGrid(result),
          const SizedBox(height: 24),

          // ROIC Averages Section
          Text(
            'ROIC Averages',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 16),
          GrowthMetricsCard(
            title: 'Return on Invested Capital',
            metrics: result.roicAverages,
          ),
          const SizedBox(height: 24),

          // Historical Data Section
          Text(
            'Historical Data',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 16),
          HistoricalTable(data: result.historicalData),
          const SizedBox(height: 24),

          // AI Insights Section
          Text(
            'AI Insights',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 16),
          AiInsightsCard(analysisResult: result),
          const SizedBox(height: 24),

          // CEO Letters Section
          Text(
            'CEO Letters',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 16),
          CeoLettersCard(ticker: result.ticker),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context, AnalysisResult result) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                result.ticker,
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
              if (result.companyName != null)
                Text(
                  result.companyName!,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
            ],
          ),
        ),
        StatusBadge(status: result.status),
      ],
    );
  }

  Widget _buildStatusCard(BuildContext context, AnalysisResult result) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Analysis Summary',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 8),
            Text(
              'Data: ${result.yearsOfData} years (${result.dataQuality.name})',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 16),
            Text(
              'Reasons:',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 4),
            ...result.statusReasons.map(
              (reason) => Padding(
                padding: const EdgeInsets.only(left: 8, top: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('• '),
                    Expanded(child: Text(reason)),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGrowthMetricsGrid(AnalysisResult result) {
    return Wrap(
      spacing: 16,
      runSpacing: 16,
      children: [
        SizedBox(
          width: 280,
          child: GrowthMetricsCard(
            title: 'EPS (Earnings Per Share)',
            metrics: result.epsGrowth,
          ),
        ),
        SizedBox(
          width: 280,
          child: GrowthMetricsCard(
            title: 'Equity (Book Value)',
            metrics: result.equityGrowth,
          ),
        ),
        SizedBox(
          width: 280,
          child: GrowthMetricsCard(
            title: 'Revenue',
            metrics: result.revenueGrowth,
          ),
        ),
        SizedBox(
          width: 280,
          child: GrowthMetricsCard(
            title: 'Free Cash Flow',
            metrics: result.fcfGrowth,
          ),
        ),
        SizedBox(
          width: 280,
          child: GrowthMetricsCard(
            title: 'Operating Cash Flow',
            metrics: result.operatingCashFlowGrowth,
          ),
        ),
      ],
    );
  }
}
