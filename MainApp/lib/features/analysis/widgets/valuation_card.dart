import 'package:flutter/material.dart';

/// Card displaying valuation information (Sticker Price, MOS Price).
class ValuationCard extends StatelessWidget {
  final double? stickerPrice;
  final double? mosPrice;

  const ValuationCard({
    super.key,
    this.stickerPrice,
    this.mosPrice,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Valuation',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 16),
            _buildRow(context, 'Sticker Price', stickerPrice),
            const SizedBox(height: 8),
            _buildRow(context, 'MOS Price (50%)', mosPrice, highlight: true),
          ],
        ),
      ),
    );
  }

  Widget _buildRow(BuildContext context, String label, double? value,
      {bool highlight = false}) {
    final valueText = value != null ? '\$${value.toStringAsFixed(2)}' : 'N/A';
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label),
        Text(
          valueText,
          style: TextStyle(
            fontWeight: highlight ? FontWeight.bold : FontWeight.normal,
            fontSize: highlight ? 18 : 14,
            color: highlight ? Theme.of(context).colorScheme.primary : null,
          ),
        ),
      ],
    );
  }
}
