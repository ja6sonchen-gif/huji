import 'package:go_router/go_router.dart';

import 'package:huji_app/pages/offline_badminton/offline_badminton_home_page.dart';
import 'package:huji_app/pages/offline_badminton/offline_badminton_task_page.dart';
import 'package:huji_app/router/modules/main.dart';
import 'package:huji_app/router/types.dart';
import 'package:huji_app/store/task/clip_task_prompt_store.dart';

class OfflineBadmintonRoute implements RouteModule {
  static const String root = '/';
  static const String home = '/offline-badminton';

  @override
  List<GoRoute> getRoutes() {
    return [
      GoRoute(
        path: root,
        name: 'offlineBadmintonRoot',
        redirect: (context, state) => home,
      ),
      GoRoute(
        path: home,
        name: 'offlineBadmintonHome',
        builder: (context, state) => const OfflineBadmintonHomePage(),
      ),
      GoRoute(
        path: MainRoute.mainHome,
        name: 'offlineBadmintonMainHome',
        redirect: (context, state) => home,
      ),
      GoRoute(
        path: MainRoute.mainTask,
        name: 'offlineBadmintonTask',
        builder: (context, state) {
          ClipTaskPromptStore.instance.register(
            state.uri.queryParameters['clipTaskId'],
          );
          return const OfflineBadmintonTaskPage();
        },
      ),
    ];
  }
}

