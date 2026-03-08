// Basic widget test for IntrinsicAI app.

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:intrinsic_ai/main.dart';

void main() {
  testWidgets('App renders correctly', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(
      const ProviderScope(child: IntrinsicAIApp()),
    );

    // Verify the app title is shown
    expect(find.text('IntrinsicAI'), findsOneWidget);
  });
}
