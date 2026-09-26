import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:huji_app/config/product_mode.dart';
import 'package:huji_app/main_desktop.dart';
import 'package:huji_app/router/modules/offline_badminton.dart';

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

