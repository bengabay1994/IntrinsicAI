import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/ai/providers/ai_providers.dart';
import '../../../core/analysis/models/analysis_result.dart';

/// Widget displaying AI-generated analysis insights.
class AiInsightsCard extends ConsumerWidget {
  final AnalysisResult analysisResult;

  const AiInsightsCard({
    super.key,
    required this.analysisResult,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authProvider);
    final insightState = ref.watch(aiInsightProvider);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                Icon(
                  Icons.auto_awesome,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Text(
                  'AI Analysis',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
                const Spacer(),
                if (insightState.insight != null)
                  IconButton(
                    icon: const Icon(Icons.refresh),
                    onPressed: insightState.isLoading
                        ? null
                        : () => _generateInsight(ref),
                    tooltip: 'Regenerate',
                  ),
              ],
            ),
            const SizedBox(height: 16),

            // Content based on state
            if (!authState.isAuthenticated)
              _buildNotAuthenticatedView(context)
            else if (insightState.isLoading)
              _buildLoadingView(context)
            else if (insightState.error != null)
              _buildErrorView(context, ref, insightState.error!)
            else if (insightState.insight != null)
              _buildInsightView(context, insightState.insight!)
            else
              _buildGenerateView(context, ref),
          ],
        ),
      ),
    );
  }

  Widget _buildNotAuthenticatedView(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          Icon(
            Icons.lock_outline,
            size: 48,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          const SizedBox(height: 12),
          Text(
            'Connect to Gemini AI',
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: 8),
          Text(
            'Sign in with Google in Settings to unlock AI-powered investment analysis.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
        ],
      ),
    );
  }

  Widget _buildLoadingView(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(32),
      child: Column(
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 16),
          Text(
            'Analyzing with Gemini AI...',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorView(BuildContext context, WidgetRef ref, String error) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.red.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              const Icon(Icons.error_outline, color: Colors.red),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  error,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: () => _generateInsight(ref),
              child: const Text('Try Again'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInsightView(BuildContext context, String insight) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: SelectableText(
        insight,
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              height: 1.6,
            ),
      ),
    );
  }

  Widget _buildGenerateView(BuildContext context, WidgetRef ref) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          Icon(
            Icons.psychology,
            size: 48,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(height: 12),
          Text(
            'Get AI Insights',
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: 8),
          Text(
            'Let Gemini AI analyze this stock and provide investment insights based on Rule #1 criteria.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: () => _generateInsight(ref),
            icon: const Icon(Icons.auto_awesome),
            label: const Text('Generate Analysis'),
          ),
        ],
      ),
    );
  }

  void _generateInsight(WidgetRef ref) {
    ref.read(aiInsightProvider.notifier).generateInsight(
          ticker: analysisResult.ticker,
          companyName: analysisResult.companyName ?? analysisResult.ticker,
          analysisData: analysisResult.toJson(),
        );
  }
}
