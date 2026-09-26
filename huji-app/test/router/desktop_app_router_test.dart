import 'package:flutter_test/flutter_test.dart';
import 'package:huji_app/config/product_mode.dart';
import 'package:huji_app/main_desktop.dart';
import 'package:huji_app/router/modules/offline_badminton.dart';

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
      router.configuration.routes.map((route) => route.path),
      contains(OfflineBadmintonRoute.home),
    );
    expect(
      router.configuration.routes.map((route) => route.path),
      isNot(contains('/account')),
    );
  });

  test('standard desktop router keeps the existing desktop shell entry', () {
    final router = DesktopApp.createRouter(productMode: ProductMode.standard);
    addTearDown(router.dispose);

    expect(router.routeInformationProvider.value.uri.path, '/');
    expect(
      router.configuration.routes.map((route) => route.path),
      contains('/login'),
    );
  });
}
