import 'dart:io';

enum ProductMode { standard, offlineBadminton }

/// Selects the product surface without removing any standard/cloud modules.
///
/// Android and Windows default to the offline badminton experience. Builds
/// can still opt into the standard product with
/// `--dart-define=HUJI_PRODUCT_MODE=standard`.
class ProductModeConfig {
  ProductModeConfig._();

  static const String _configuredMode = String.fromEnvironment(
    'HUJI_PRODUCT_MODE',
  );

  static ProductMode resolve({
    required bool isAndroid,
    bool isWindows = false,
    String configuredMode = _configuredMode,
  }) {
    final supportsOfflineBadminton = isAndroid || isWindows;
    switch (configuredMode) {
      case 'offlineBadminton':
        return supportsOfflineBadminton
            ? ProductMode.offlineBadminton
            : ProductMode.standard;
      case 'standard':
        return ProductMode.standard;
      default:
        return supportsOfflineBadminton
            ? ProductMode.offlineBadminton
            : ProductMode.standard;
    }
  }

  static ProductMode get current => resolve(
    isAndroid: Platform.isAndroid,
    isWindows: Platform.isWindows,
  );

  static bool get isOfflineBadminton =>
      current == ProductMode.offlineBadminton;

  static bool shouldCheckRemotePermissions(ProductMode mode) =>
      mode != ProductMode.offlineBadminton;
}
