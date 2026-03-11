import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intrinsic_ai/core/config/app_config.dart';
import 'package:intrinsic_ai/shared/providers/providers.dart';
import '../analysis/analysis_screen.dart';
import '../settings/settings_screen.dart';

/// Home screen with ticker search and analysis.
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  final _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _onSearch() {
    final ticker = _searchController.text.trim();
    if (ticker.isNotEmpty) {
      ref.read(analysisProvider.notifier).analyze(ticker);
    }
  }

  @override
  Widget build(BuildContext context) {
    final databaseExists = ref.watch(databaseExistsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('IntrinsicAI'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const SettingsScreen()),
              );
            },
          ),
        ],
      ),
      body: databaseExists
          ? _buildMainContent(context)
          : _buildNoDatabaseMessage(context),
    );
  }

  Widget _buildMainContent(BuildContext context) {
    return Column(
      children: [
        // Search bar
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _searchController,
                  decoration: const InputDecoration(
                    hintText: 'Enter ticker symbol (e.g., AAPL)',
                    prefixIcon: Icon(Icons.search),
                  ),
                  textCapitalization: TextCapitalization.characters,
                  onSubmitted: (_) => _onSearch(),
                ),
              ),
              const SizedBox(width: 16),
              FilledButton(
                onPressed: _onSearch,
                child: const Text('Analyze'),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        // Analysis results
        const Expanded(child: AnalysisScreen()),
      ],
    );
  }

  Widget _buildNoDatabaseMessage(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.storage_outlined,
              size: 80,
              color: Theme.of(context).colorScheme.outline,
            ),
            const SizedBox(height: 24),
            Text(
              'No Database Found',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 16),
            Text(
              'The stock database was not found. Please run the Updater tool first to download financial data.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
            const SizedBox(height: 24),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'How to set up:',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                    const SizedBox(height: 12),
                    const Text('1. Open a terminal in the Updater directory'),
                    const SizedBox(height: 4),
                    const Text('2. Run: uv sync'),
                    const SizedBox(height: 4),
                    const Text('3. Add your EODHD API key to .env'),
                    const SizedBox(height: 4),
                    const Text('4. Run: uv run python update.py --tickers AAPL'),
                    const SizedBox(height: 12),
                    Text(
                      'Database will be created at:',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 4),
                    SelectableText(
                      AppConfig.getDatabasePath(),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            fontFamily: 'monospace',
                            color: Theme.of(context).colorScheme.primary,
                          ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: () {
                // Refresh to check if database exists now
                ref.invalidate(databaseExistsProvider);
              },
              icon: const Icon(Icons.refresh),
              label: const Text('Check Again'),
            ),
          ],
        ),
      ),
    );
  }
}
