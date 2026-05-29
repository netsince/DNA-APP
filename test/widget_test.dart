import 'package:dna/main.dart';
import 'package:dna/services/openai_service.dart';
import 'package:dna/services/settings_service.dart';
import 'package:dna/services/ta_service.dart';
import 'package:dna/state/app_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('shows OOBE when app starts without setup', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final AppController controller = AppController(
      settingsService: SettingsService(),
      openAiService: OpenAiService(),
      taService: TaService(),
    );
    await controller.initialize();

    await tester.pumpWidget(DnaApp(controller: controller));
    await tester.pumpAndSettle();

    expect(find.text('与汝共奏'), findsOneWidget);
  });
}
