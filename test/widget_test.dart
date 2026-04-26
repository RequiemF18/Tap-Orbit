import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:tap_orbit/main.dart';

void main() {
  testWidgets('Tap Orbit renders the game HUD', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(const TapOrbitApp());
    await tester.pump();

    expect(find.text('SCORE'), findsOneWidget);
    expect(find.text('BEST'), findsOneWidget);
    expect(find.text('TAP WHEN THE PLANET ENTERS THE GATE'), findsOneWidget);
  });
}
