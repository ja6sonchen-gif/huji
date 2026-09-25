import 'package:flutter_test/flutter_test.dart';
import 'package:huji_app/config/product_mode.dart';
import 'package:huji_app/router/modules/clip.dart';
import 'package:huji_app/router/modules/main.dart';
import 'package:huji_app/router/modules/offline_badminton.dart';
import 'package:huji_app/router/modules/routes.dart';

void main() {
  test('offline badminton exposes only the local product routes', () {
    final paths = AppPages.getRoutes(
      productMode: ProductMode.offlineBadminton,
    ).map((route) => route.path).toSet();

    expect(paths, contains(OfflineBadmintonRoute.home));
    expect(paths, contains(MainRoute.mainTask));
    expect(paths, contains(ClipRoute.videoEditConfig));
    expect(paths, contains(ClipRoute.roundClip));

    expect(paths, isNot(contains('/login')));
    expect(paths, isNot(contains('/profile')));
    expect(paths, isNot(contains('/message')));
    expect(paths, isNot(contains('/tools')));
    expect(paths, isNot(contains('/subscription')));
    expect(paths, isNot(contains(ClipRoute.clipTypeSelection)));
    expect(paths, isNot(contains(ClipRoute.sportSelection)));
  });
}
