import 'dart:io';

enum ProductMode { standard, offlineBadminton }

/// Selects the product surface without removing any standard/cloud modules.
///
/// Android defaults to the offline badminton experience. Builds can still opt
/// into the standard product with `--dart-define=HUJI_PRODUCT_MODE=standard`.
class ProductModeConfig {
  ProductModeConfig._();

  static const String _configuredMode = String.fromEnvironment(
    'HUJI_PRODUCT_MODE',
  );

  static ProductMode resolve({
    required bool isAndroid,
    String configuredMode = _configuredMode,
  }) {
    switch (configuredMode) {
      case 'offlineBadminton':
        return isAndroid
            ? ProductMode.offlineBadminton
            : ProductMode.standard;
      case 'standard':
        return ProductMode.standard;
      default:
        return isAndroid
            ? ProductMode.offlineBadminton
            : ProductMode.standard;
    }
  }

  static ProductMode get current => resolve(isAndroid: Platform.isAndroid);

  static bool get isOfflineBadminton =>
      current == ProductMode.offlineBadminton;
}
