import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:openlist_renamer/main.dart';

void main() {
  testWidgets('App boots to the login screen', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(RenamerApp(prefs: prefs));
    await tester.pump();
    expect(find.text('OpenList 影视重命名'), findsWidgets);
    expect(find.text('服务器地址'), findsOneWidget);
  });
}
