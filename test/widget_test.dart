import 'package:flutter_test/flutter_test.dart';
import 'package:open_foldr/app.dart';

void main() {
  testWidgets('App renders without crashing', (WidgetTester tester) async {
    await tester.pumpWidget(const OpenFoldrApp());
    expect(find.byType(OpenFoldrApp), findsOneWidget);
  });
}
