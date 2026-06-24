import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_utlva/main.dart';

void main() {
  testWidgets('UTLVA app launches and shows splash screen', (WidgetTester tester) async {
    await tester.pumpWidget(const UTLVAApp());
    await tester.pump();
    expect(find.text('UTLVA'), findsWidgets);
  });
}
