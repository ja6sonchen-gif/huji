import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:huji_app/constants/theme.dart';
import 'package:huji_app/config/product_mode.dart';
import 'package:huji_app/l10n/huji_localizations_setup.dart';
import 'package:huji_app/main_desktop.dart';
import 'package:huji_app/pages/offline_badminton/offline_badminton_home_page.dart';
import 'package:huji_app/router/modules/clip.dart';
import 'package:huji_app/router/modules/main.dart';
import 'package:huji_app/router/modules/offline_badminton.dart';
import 'package:huji_app/router/modules/routes.dart';
import 'package:shared_ui/shared_ui.dart';

List<String> collectGoRoutePaths(List<RouteBase> routes) {
  final paths = <String>[];
  for (final route in routes) {
    if (route is GoRoute) {
      paths.add(route.path);
    }
    paths.addAll(collectGoRoutePaths(route.routes));
  }
  return paths;
}

void main() {
  test('offline badminton desktop router opens its home directly', () {
    final router = DesktopApp.createRouter(
      productMode: ProductMode.offlineBadminton,
    );
    addTearDown(router.dispose);

    expect(
      router.routeInformationProvider.value.uri.path,
      OfflineBadmintonRoute.home,
    );
    expect(
      collectGoRoutePaths(router.configuration.routes),
      contains(OfflineBadmintonRoute.home),
    );
    expect(
      collectGoRoutePaths(router.configuration.routes),
      isNot(contains('/account')),
    );
  });

  testWidgets('Windows offline router resolves root to the badminton home', (
    tester,
  ) async {
    final router = DesktopApp.createRouter(
      productMode: ProductMode.offlineBadminton,
    );
    addTearDown(router.dispose);

    final theme = AppTheme.lightTheme;
    await tester.pumpWidget(
      MaterialApp.router(
        routerConfig: router,
        theme: theme,
        locale: const Locale('zh'),
        localizationsDelegates: HujiLocalizationsSetup.localizationsDelegates,
        supportedLocales: HujiLocalizationsSetup.supportedLocales,
        builder: (context, child) => TpTheme(
          data: TpThemeData.fromColorScheme(theme.colorScheme, scale: 1.0),
          child: child ?? const SizedBox.shrink(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(OfflineBadmintonHomePage), findsOneWidget);

    final paths = collectGoRoutePaths(router.configuration.routes);
    expect(paths, contains('/'));
    expect(router.namedLocation('offlineBadmintonRoot'), '/');

    router.go('/');
    await tester.pumpAndSettle();
    expect(find.byType(OfflineBadmintonHomePage), findsOneWidget);

    router.go(MainRoute.mainHome);
    await tester.pumpAndSettle();
    expect(find.byType(OfflineBadmintonHomePage), findsOneWidget);
  });

  test(
    'offline task and completed-record preview destinations are registered',
    () {
      final router = DesktopApp.createRouter(
        productMode: ProductMode.offlineBadminton,
      );
      addTearDown(router.dispose);

      final paths = collectGoRoutePaths(router.configuration.routes);
      expect(paths, contains(MainRoute.mainTask));
      expect(paths, contains(ClipRoute.clipPreview));

      const id = '01481b4d-9137-4868-9655-d9ad1a4e0199';
      final completedTaskLocation = ClipRoute.clipPreviewPath(id);
      expect(
        router.namedLocation(
          'clipPreviewByRecordId',
          pathParameters: {'id': id},
        ),
        completedTaskLocation,
      );
      router.go(completedTaskLocation);
      expect(
        router.routeInformationProvider.value.uri.path,
        completedTaskLocation,
      );
      expect(
        router.namedLocation('offlineBadmintonHome'),
        OfflineBadmintonRoute.home,
      );
    },
  );

  test('Android offline router shares history and completed-record routes', () {
    final router = GoRouter(
      initialLocation: OfflineBadmintonRoute.home,
      routes: AppPages.getRoutes(productMode: ProductMode.offlineBadminton),
    );
    addTearDown(router.dispose);

    final paths = collectGoRoutePaths(router.configuration.routes);
    expect(paths, contains('/'));
    expect(paths, contains(MainRoute.mainTask));
    expect(paths, contains(ClipRoute.clipPreview));
    expect(
      router.namedLocation(
        'clipPreviewByRecordId',
        pathParameters: {'id': '01481b4d-9137-4868-9655-d9ad1a4e0199'},
      ),
      '/clip/01481b4d-9137-4868-9655-d9ad1a4e0199/preview',
    );
  });

  test('standard desktop router keeps the existing desktop shell entry', () {
    final router = DesktopApp.createRouter(productMode: ProductMode.standard);
    addTearDown(router.dispose);

    expect(router.routeInformationProvider.value.uri.path, '/');
    expect(
      collectGoRoutePaths(router.configuration.routes),
      contains('/login'),
    );
  });

  test('Windows defaults to the offline badminton desktop router', () {
    final mode = ProductModeConfig.resolve(isAndroid: false, isWindows: true);
    final router = DesktopApp.createRouter(productMode: mode);
    addTearDown(router.dispose);

    expect(mode, ProductMode.offlineBadminton);
    expect(
      router.routeInformationProvider.value.uri.path,
      OfflineBadmintonRoute.home,
    );
  });
}

