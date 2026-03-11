import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/ai/providers/ai_providers.dart';
import '../../core/ai/services/gemini_service.dart';

/// Settings screen for app configuration and Gemini OAuth.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authProvider);

    // Show error snackbar when there's an auth error
    ref.listen<AuthState>(authProvider, (previous, next) {
      if (next.error != null && previous?.error != next.error) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(next.error!),
            backgroundColor: Colors.red,
            action: SnackBarAction(
              label: 'Dismiss',
              textColor: Colors.white,
              onPressed: () {
                ref.read(authProvider.notifier).clearError();
              },
            ),
          ),
        );
      }
    });

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Gemini AI Integration Section
          _buildGeminiSection(context, ref, authState),
          const SizedBox(height: 16),

          // About Section
          _buildAboutSection(context, authState),
        ],
      ),
    );
  }

  Widget _buildGeminiSection(
    BuildContext context,
    WidgetRef ref,
    AuthState authState,
  ) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.auto_awesome,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Text(
                  'Gemini AI Integration',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              'Connect to Google Gemini for AI-powered investment analysis and insights. '
              'Works with your Google AI Pro subscription.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),

            // Model Selection
            _buildModelSelector(context, ref, authState),
            const SizedBox(height: 16),

            // Status indicator
            _buildStatusRow(context, authState),
            const SizedBox(height: 16),

            // Action button
            if (authState.isLoading)
              const Center(child: CircularProgressIndicator())
            else if (authState.isAuthenticated)
              _buildSignedInActions(context, ref, authState)
            else
              _buildSignInButton(context, ref),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusRow(BuildContext context, AuthState authState) {
    final isConnected = authState.isAuthenticated;
    final statusText =
        isConnected
            ? 'Connected${authState.userEmail != null ? ' as ${authState.userEmail}' : ''}'
            : 'Not connected';

    return Row(
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: isConnected ? Colors.green : Colors.grey,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            statusText,
            style: Theme.of(context).textTheme.bodyMedium,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  Widget _buildSignInButton(BuildContext context, WidgetRef ref) {
    return SizedBox(
      width: double.infinity,
      child: FilledButton.icon(
        onPressed: () {
          ref.read(authProvider.notifier).signIn();
        },
        icon: const Icon(Icons.login),
        label: const Text('Connect with Google'),
      ),
    );
  }

  Widget _buildSignedInActions(
    BuildContext context,
    WidgetRef ref,
    AuthState authState,
  ) {
    return Column(
      children: [
        // Success message
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.green.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.green.withValues(alpha: 0.3)),
          ),
          child: Row(
            children: [
              const Icon(Icons.check_circle, color: Colors.green, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'AI analysis is ready! Analyze a stock to get AI-powered insights.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // Sign out button
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: () {
              _showSignOutDialog(context, ref);
            },
            icon: const Icon(Icons.logout),
            label: const Text('Sign Out'),
          ),
        ),
      ],
    );
  }

  void _showSignOutDialog(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('Sign Out'),
            content: const Text(
              'Are you sure you want to sign out? You will need to sign in again to use AI analysis.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () {
                  Navigator.of(context).pop();
                  ref.read(authProvider.notifier).signOut();
                },
                child: const Text('Sign Out'),
              ),
            ],
          ),
    );
  }

  Widget _buildAboutSection(BuildContext context, AuthState authState) {
    // Get selected model display name
    String selectedModelName = authState.selectedModel;
    if (authState.availableModels.isNotEmpty) {
      final model = authState.availableModels.firstWhere(
        (m) => m.id == authState.selectedModel,
        orElse: () => GeminiModel(
          id: authState.selectedModel,
          displayName: authState.selectedModel,
        ),
      );
      selectedModelName = model.displayName;
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.info_outline,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Text(
                  'About IntrinsicAI',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _buildInfoRow(context, 'Version', '1.0.0'),
            const Divider(height: 24),
            _buildInfoRow(context, 'Method', 'Phil Town Rule #1'),
            const Divider(height: 24),
            _buildInfoRow(context, 'AI Model', selectedModelName),
            const Divider(height: 24),
            Text(
              'IntrinsicAI analyzes stocks using the "Big 5" metrics from Phil Town\'s Rule #1 investing strategy. Connect to Gemini AI for deeper insights and analysis.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildModelSelector(
    BuildContext context,
    WidgetRef ref,
    AuthState authState,
  ) {
    if (!authState.isAuthenticated) return const SizedBox.shrink();

    final models = authState.availableModels;
    final isLoading = authState.isLoadingModels;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Select Model',
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.bold),
            ),
            if (isLoading)
              const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            else
              IconButton(
                icon: const Icon(Icons.refresh, size: 18),
                onPressed: () {
                  ref.read(authProvider.notifier).refreshModels();
                },
                tooltip: 'Refresh models',
                constraints: const BoxConstraints(
                  minWidth: 32,
                  minHeight: 32,
                ),
                padding: EdgeInsets.zero,
              ),
          ],
        ),
        const SizedBox(height: 8),
        if (models.isEmpty && !isLoading)
          // Show default dropdown while loading
          DropdownButtonFormField<String>(
            initialValue: authState.selectedModel,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            ),
            items: [
              DropdownMenuItem(
                value: authState.selectedModel,
                child: Text(authState.selectedModel),
              ),
            ],
            onChanged: null,
          )
        else
          // Show dynamic models
          DropdownButtonFormField<String>(
            initialValue: models.any((m) => m.id == authState.selectedModel)
                ? authState.selectedModel
                : (models.isNotEmpty ? models.first.id : null),
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            ),
            isExpanded: true,
            items: models.map((model) {
              return DropdownMenuItem<String>(
                value: model.id,
                child: Text(
                  model.displayName,
                  overflow: TextOverflow.ellipsis,
                ),
              );
            }).toList(),
            onChanged: (value) {
              if (value != null) {
                ref.read(authProvider.notifier).updateModel(value);
              }
            },
          ),
        const SizedBox(height: 4),
        Text(
          '${models.length} models available',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  Widget _buildInfoRow(BuildContext context, String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: Theme.of(context).textTheme.bodyMedium),
        Text(
          value,
          style: Theme.of(
            context,
          ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.bold),
        ),
      ],
    );
  }
}
