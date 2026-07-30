import 'package:flutter_test/flutter_test.dart';
import 'package:scp_app/app.dart';

void main() {
  testWidgets('App should build without error', (WidgetTester tester) async {
    await tester.pumpWidget(const ScpApp());
    expect(find.text('SCP基金会'), findsWidgets);
  });
}
