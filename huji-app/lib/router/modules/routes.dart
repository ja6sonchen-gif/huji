import 'package:go_router/go_router.dart';
import 'package:huji_app/config/product_mode.dart';
import 'package:huji_app/router/modules/clip.dart';
import 'package:huji_app/router/modules/login.dart';
import 'package:huji_app/router/modules/main.dart';
import 'package:huji_app/router/modules/message.dart';
import 'package:huji_app/router/modules/offline_badminton.dart';
import 'package:huji_app/router/modules/profile.dart';
import 'package:huji_app/router/modules/splash.dart';
import 'package:huji_app/router/modules/subscription.dart';
import 'package:huji_app/router/modules/tools.dart';
import 'package:huji_app/router/modules/video.dart';

/// 聚合所有路由模块
/// 这个类用于聚合所有路由模块的 GoRoute
class AppPages {
  static List<GoRoute> getRoutes({ProductMode? productMode}) {
    final mode = productMode ?? ProductModeConfig.current;
    final List<GoRoute> routes = [];

    if (mode == ProductMode.offlineBadminton) {
      routes.addAll(SplashRoute().getRoutes());
      routes.addAll(OfflineBadmintonRoute().getRoutes());
      routes.addAll(const ClipRoute(offlineBadminton: true).getRoutes());
      return routes;
    }

    // 按顺序添加各个路由模块
    routes.addAll(SplashRoute().getRoutes());
    routes.addAll(LoginRoute().getRoutes());
    routes.addAll(MainRoute().getRoutes());
    routes.addAll(VideoRoute().getRoutes());
    routes.addAll(const ClipRoute().getRoutes());
    routes.addAll(ProfileRoute().getRoutes());
    routes.addAll(MessageRoute().getRoutes());
    routes.addAll(ToolsRoute().getRoutes());
    routes.addAll(SubscriptionRoute().getRoutes());

    return routes;
  }
}
