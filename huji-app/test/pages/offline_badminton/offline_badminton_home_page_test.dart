import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:huji_app/constants/theme.dart';
import 'package:huji_app/l10n/huji_localizations_setup.dart';
import 'package:huji_app/pages/offline_badminton/offline_badminton_home_page.dart';
import 'package:shared_ui/shared_ui.dart';

void main() {
  testWidgets('offline home contains only the badminton start controls', (
    tester,
  ) async {
    final theme = AppTheme.lightTheme;
    await tester.pumpWidget(
      MaterialApp(
        theme: theme,
        locale: const Locale('zh'),
        localizationsDelegates: HujiLocalizationsSetup.localizationsDelegates,
        supportedLocales: HujiLocalizationsSetup.supportedLocales,
        home: TpTheme(
          data: TpThemeData.fromColorScheme(theme.colorScheme, scale: 1.0),
          child: const OfflineBadmintonHomePage(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('选择视频'), findsOneWidget);
    expect(find.text('羽毛球单打'), findsOneWidget);
    expect(find.text('羽毛球双打'), findsOneWidget);
    expect(find.text('开始分析'), findsOneWidget);
    expect(find.textContaining('乒乓球'), findsNothing);
    expect(find.textContaining('云端'), findsNothing);
    expect(find.textContaining('登录'), findsNothing);
  });
}
