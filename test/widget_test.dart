import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:playsphere/main.dart';

void main() {
  testWidgets('App boots directly into organization portal with skip-login', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: PlaySphereApp()));
    await tester.pumpAndSettle();

    expect(find.text('Maram Garlapati Homes'), findsAtLeast(1));
  });
}
