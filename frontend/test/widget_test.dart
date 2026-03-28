/// WHAT: Provides a basic widget smoke test for the app shell.
/// WHY: Replacing the Flutter template means the starter test must now assert the real landing screen.
/// HOW: Pump the Riverpod-wrapped app and confirm a stable landing-page headline renders.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:frontend/app/app.dart';

void main() {
  testWidgets('renders landing page headline', (WidgetTester tester) async {
    await tester.pumpWidget(const ProviderScope(child: AdamsApp()));
    await tester.pumpAndSettle(const Duration(seconds: 2));

    expect(find.textContaining('Cleaner service requests'), findsOneWidget);
  });
}
