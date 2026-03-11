import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/database/models/ceo_letter.dart';
import '../../../shared/providers/providers.dart';

/// Widget displaying CEO letters to shareholders from 10-K filings.
class CeoLettersCard extends ConsumerStatefulWidget {
  final String ticker;

  const CeoLettersCard({super.key, required this.ticker});

  @override
  ConsumerState<CeoLettersCard> createState() => _CeoLettersCardState();
}

class _CeoLettersCardState extends ConsumerState<CeoLettersCard> {
  @override
  void initState() {
    super.initState();
    // Load CEO letters when the widget is first built
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(ceoLetterProvider.notifier).loadLetters(widget.ticker);
    });
  }

  @override
  Widget build(BuildContext context) {
    final letterState = ref.watch(ceoLetterProvider);

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
                  Icons.mail_outline,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Text(
                  'CEO Letters to Shareholders',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Content based on state
            if (letterState.isLoading)
              _buildLoadingView(context)
            else if (letterState.error != null)
              _buildErrorView(context, letterState.error!)
            else if (letterState.letters.isEmpty)
              _buildEmptyView(context)
            else
              _buildLettersView(context, letterState.letters),
          ],
        ),
      ),
    );
  }

  Widget _buildLoadingView(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(16),
        child: CircularProgressIndicator(),
      ),
    );
  }

  Widget _buildErrorView(BuildContext context, String error) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.red.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        error,
        style: Theme.of(context).textTheme.bodyMedium,
      ),
    );
  }

  Widget _buildEmptyView(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          Icon(
            Icons.inbox_outlined,
            size: 40,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          const SizedBox(height: 12),
          Text(
            'No CEO Letters Available',
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: 8),
          Text(
            'Run the Updater with the --letters flag to fetch CEO annual letters from SEC 10-K filings.\n\n'
            'Example: python update.py --tickers ${widget.ticker.split(".").first} --letters',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLettersView(BuildContext context, List<CeoLetter> letters) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${letters.length} annual letter${letters.length == 1 ? '' : 's'} found',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 8),
        ...letters.map((letter) => _buildLetterTile(context, letter)),
      ],
    );
  }

  Widget _buildLetterTile(BuildContext context, CeoLetter letter) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 8),
        childrenPadding: const EdgeInsets.fromLTRB(8, 0, 8, 16),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(
            color: Theme.of(context).colorScheme.outlineVariant,
          ),
        ),
        collapsedShape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(
            color: Theme.of(context).colorScheme.outlineVariant,
          ),
        ),
        leading: Icon(
          letter.hasSummary ? Icons.summarize : Icons.description_outlined,
          size: 20,
          color: letter.hasSummary
              ? Theme.of(context).colorScheme.primary
              : Theme.of(context).colorScheme.onSurfaceVariant,
        ),
        title: Text(
          'FY ${letter.fiscalYear}',
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        subtitle: letter.filingDate != null
            ? Text(
                'Filed: ${letter.filingDate}',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              )
            : null,
        children: [
          if (letter.hasSummary)
            SelectableText(
              letter.summary!,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                height: 1.6,
              ),
            )
          else
            Text(
              'No summary available. The Updater may not have had a Gemini API key '
              'configured when this letter was fetched. Re-run with a valid '
              'GEMINI_API_KEY in .env and use --force-letters.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontStyle: FontStyle.italic,
              ),
            ),
        ],
      ),
    );
  }
}
