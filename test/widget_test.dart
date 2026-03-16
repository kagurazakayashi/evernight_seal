import 'package:flutter_test/flutter_test.dart';

import 'package:evernight_seal/main.dart';

void main() {
  testWidgets('App renders home screen', (WidgetTester tester) async {
    await tester.pumpWidget(const EvernightSealApp());
    await tester.pumpAndSettle();

    // 驗證版本號存在
    expect(find.text('v1.0.0'), findsOneWidget);
  });
}
