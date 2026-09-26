import 'package:huji_app/models/task.dart';

/// Centralizes which task updates should reach the operating-system
/// notification surface. The app's task page remains the source of live
/// progress for Windows Offline Badminton.
class TaskNotificationPolicy {
  final Set<String> _notifiedTerminalStates = <String>{};

  Future<void> dispatch(
    Task task, {
    required bool windowsOfflineBadminton,
    required Future<void> Function(Task task) notify,
  }) async {
    if (windowsOfflineBadminton) {
      switch (task.status) {
        case TaskStatusEnum.completed:
        case TaskStatusEnum.failed:
          final key = '${task.id}:${task.status.index}';
          if (!_notifiedTerminalStates.add(key)) return;
          break;
        case TaskStatusEnum.cancelled:
        case TaskStatusEnum.processing:
        case TaskStatusEnum.pending:
        case TaskStatusEnum.paused:
          return;
      }
    }

    await notify(task);
  }
}

