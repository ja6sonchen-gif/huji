import 'package:flutter_test/flutter_test.dart';
import 'package:huji_app/config/product_mode.dart';

void main() {
  test('offline badminton mode does not require remote permission checks', () {
    expect(
      ProductModeConfig.shouldCheckRemotePermissions(
        ProductMode.offlineBadminton,
      ),
      isFalse,
    );
    expect(
      ProductModeConfig.shouldCheckRemotePermissions(ProductMode.standard),
      isTrue,
    );
  });
}
