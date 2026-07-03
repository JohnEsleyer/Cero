import 'package:flutter_test/flutter_test.dart';
import 'package:pocketdatabase/main.dart';
import 'package:pocketdatabase/services/server_service.dart';

void main() {
  testWidgets('PocketDB Server Smoke Test', (WidgetTester tester) async {
    final serverService = ServerService();
    await tester.pumpWidget(MyApp(serverService: serverService));

    // Verify that the title is displayed.
    expect(find.text('PocketDB Mobile'), findsOneWidget);
    expect(find.text('Local Sync Server'), findsOneWidget);
  });
}
