import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:huji_app/l10n/l10n_extensions.dart';
import 'package:huji_app/models/task.dart';
import 'package:huji_app/pages/task/task/task_tab/task_tab_content.dart';
import 'package:huji_app/router/modules/main.dart';

class OfflineBadmintonTaskPage extends StatelessWidget {
  const OfflineBadmintonTaskPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.home_outlined),
          onPressed: () => context.go(MainRoute.mainHome),
        ),
        title: Text(context.hujiL10n.localTasks),
      ),
      body: TaskTabContent(
        allowedTaskTypes: {TaskTypeEnum.videoSegmentDetect},
        initialStatuses: {
          TaskStatusEnum.completed,
          TaskStatusEnum.processing,
          TaskStatusEnum.pending,
          TaskStatusEnum.failed,
        },
      ),
    );
  }
}
