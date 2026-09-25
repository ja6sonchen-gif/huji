import 'package:go_router/go_router.dart';
import 'package:huji_app/config/product_mode.dart';
import 'package:huji_app/router/modules/offline_badminton.dart';
import 'package:huji_app/router/modules/routes.dart';
import 'package:huji_app/router/modules/splash.dart';

final appRouter = GoRouter(
  initialLocation: ProductModeConfig.isOfflineBadminton
      ? OfflineBadmintonRoute.home
      : SplashRoute.splash,
  routes: AppPages.getRoutes(productMode: ProductModeConfig.current),
);
