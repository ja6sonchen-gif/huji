import 'package:flutter_test/flutter_test.dart';
import 'package:huji_app/api/models/autoclip/clip_models.dart';
import 'package:huji_app/api/models/autoclip/video_models.dart';
import 'package:huji_app/models/task.dart';
import 'package:huji_app/store/task/task_manager.dart';
import 'package:huji_app/store/task/video_segment_detect_task.dart';

void main() {
  test('task receives match type from its UI clip config', () {
    final task = VideoSegmentDetectTask(
      id: 'doubles-task',
      createdAt: 1,
      videoPath: '/video.mp4',
      sportType: SportType.badminton,
      clipConfig: BadmintonVideoClipConfigReqVo(
        matchType: MatchType.doublesMatch,
      ),
    );

    expect(task.matchType, MatchType.doublesMatch);
  });

  test('task serializes and restores match type independently', () {
    final original = VideoSegmentDetectTask(
      id: 'persisted-doubles-task',
      createdAt: 1,
      videoPath: '/video.mp4',
      sportType: SportType.badminton,
      matchType: MatchType.doublesMatch,
    );

    final json = original.toJson();
    expect(json['matchType'], MatchType.doublesMatch.value);
    expect(
      VideoSegmentDetectTask.fromJson(json).matchType,
      MatchType.doublesMatch,
    );

    final storageJson = VideoSegmentDetectTaskManager(
      TaskStorage(),
    ).getInsertJson(original);
    expect(storageJson['matchType'], MatchType.doublesMatch.value);
  });

  test('legacy task without a column value falls back to clip config', () {
    final original = VideoSegmentDetectTask(
      id: 'legacy-doubles-task',
      createdAt: 1,
      videoPath: '/video.mp4',
      sportType: SportType.badminton,
    );
    final json = original.toJson()
      ..remove('matchType')
      ..['clipConfig'] = BadmintonVideoClipConfigReqVo(
        matchType: MatchType.doublesMatch,
      ).toJson();

    expect(
      VideoSegmentDetectTask.fromJson(json).matchType,
      MatchType.doublesMatch,
    );
  });
}
