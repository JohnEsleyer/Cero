import 'package:flutter_test/flutter_test.dart';
import 'package:pocketdatabase/main.dart';
import 'package:pocketdatabase/services/server_service.dart';

void main() {
  testWidgets('Cero Mobile Smoke Test', (WidgetTester tester) async {
    final serverService = ServerService();
    await tester.pumpWidget(MyApp(serverService: serverService));

    // Verify that Cero elements are shown
    expect(find.text('Cero'), findsOneWidget);
    expect(find.text('Cero Personal Journal'), findsOneWidget);
  });
}
