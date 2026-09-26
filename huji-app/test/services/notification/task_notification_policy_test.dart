import 'package:flutter_test/flutter_test.dart';
import 'package:huji_app/models/task.dart';
import 'package:huji_app/services/notification/task_notification_policy.dart';

VideoSegmentDetectTask makeTask(
  String id,
  TaskStatusEnum status, {
  double progress = 0,
}) => VideoSegmentDetectTask(
  id: id,
  name: 'local match',
  createdAt: 1,
  videoPath: 'match.mp4',
  status: status,
  progress: progress,
);

void main() {
  test(
    'Windows offline badminton suppresses progress and cancel notices',
    () async {
      final policy = TaskNotificationPolicy();
      var count = 0;
      Future<void> dispatch(Task task) => policy.dispatch(
        task,
        windowsOfflineBadminton: true,
        notify: (_) async {
          count++;
        },
      );

      for (final progress in [0.01, 0.02, 0.5, 0.99]) {
        await dispatch(
          makeTask(
            'progress-task',
            TaskStatusEnum.processing,
            progress: progress,
          ),
        );
      }
      await dispatch(makeTask('cancel-task', TaskStatusEnum.cancelled));

      expect(count, 0);
    },
  );

  test(
    'Windows offline completion is notified only once per task state',
    () async {
      final policy = TaskNotificationPolicy();
      var count = 0;
      Future<void> dispatch(Task task) => policy.dispatch(
        task,
        windowsOfflineBadminton: true,
        notify: (_) async {
          count++;
        },
      );

      await dispatch(
        makeTask('done-task', TaskStatusEnum.completed, progress: 1),
      );
      await dispatch(
        makeTask('done-task', TaskStatusEnum.completed, progress: 1),
      );

      expect(count, 1);
    },
  );

  test('Windows offline failure is notified once', () async {
    final policy = TaskNotificationPolicy();
    var count = 0;
    Future<void> dispatch(Task task) => policy.dispatch(
      task,
      windowsOfflineBadminton: true,
      notify: (_) async {
        count++;
      },
    );

    await dispatch(makeTask('failed-task', TaskStatusEnum.failed));
    await dispatch(makeTask('failed-task', TaskStatusEnum.failed));

    expect(count, 1);
  });

  test(
    'Android and standard modes retain their existing notification behavior',
    () async {
      for (final mode in ['android', 'standard']) {
        final policy = TaskNotificationPolicy();
        var count = 0;
        await policy.dispatch(
          makeTask(
            '$mode-progress',
            TaskStatusEnum.processing,
            progress: 0.01,
          ),
          windowsOfflineBadminton: false,
          notify: (_) async {
            count++;
          },
        );
        await policy.dispatch(
          makeTask(
            '$mode-progress',
            TaskStatusEnum.processing,
            progress: 0.02,
          ),
          windowsOfflineBadminton: false,
          notify: (_) async {
            count++;
          },
        );
        expect(
          count,
          2,
          reason: '$mode mode keeps per-update notification behavior',
        );
      }
    },
  );
}

