import 'package:flutter_test/flutter_test.dart';
import 'package:huji_app/config/product_mode.dart';

void main() {
  group('ProductModeConfig', () {
    test('Android defaults to offline badminton', () {
      expect(
        ProductModeConfig.resolve(isAndroid: true),
        ProductMode.offlineBadminton,
      );
    });

    test('non-Android defaults to standard mode', () {
      expect(
        ProductModeConfig.resolve(isAndroid: false),
        ProductMode.standard,
      );
    });

    test('standard mode can explicitly override the Android default', () {
      expect(
        ProductModeConfig.resolve(
          isAndroid: true,
          configuredMode: 'standard',
        ),
        ProductMode.standard,
      );
    });
  });
}
