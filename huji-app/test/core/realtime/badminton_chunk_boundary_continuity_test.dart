import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:huji_app/api/models/autoclip/clip_models.dart';
import 'package:huji_app/core/realtime/badminton_realtime_action_segment_detector.dart';
import 'package:huji_app/models/autoclip_models.dart';
import 'package:huji_app/models/large_model.dart';
import 'package:huji_app/services/large_model_service.dart';
import 'package:huji_app/utils/video_frame_chunk_pipeline.dart';

void main() {
  test(
    'chunked 28-34 second rally matches the unchunked detector result',
    () async {
      final unchunkedTimestamps = List<double>.generate(
        37,
        (frameIndex) => 28 + frameIndex / 6,
      );
      final chunkedTimestamps = <double>[];
      final chunks = VideoFrameChunkPipeline.planChunks(
        videoDurationSeconds: 65,
      );
      for (final chunk in chunks) {
        final frameCount = (chunk.durationSeconds * 6).round();
        for (var frameIndex = 0; frameIndex < frameCount; frameIndex++) {
          final timestamp = VideoFrameChunkPipeline.globalTimestamp(
            chunkStartSeconds: chunk.startSeconds,
            frameIndex: frameIndex,
            framesPerSecond: 6,
          );
          if (timestamp >= 28 && timestamp <= 34) {
            chunkedTimestamps.add(timestamp);
          }
        }
      }

      final unchunked = await _detectPlayBall(unchunkedTimestamps);
      final chunked = await _detectPlayBall(chunkedTimestamps);

      expect(unchunked, hasLength(1));
      expect(chunked, hasLength(unchunked.length));
      expect(chunked.single.actionType, unchunked.single.actionType);
      expect(
        chunked.single.startSeconds,
        closeTo(unchunked.single.startSeconds, 1 / 6),
      );
      expect(
        chunked.single.endSeconds,
        closeTo(unchunked.single.endSeconds, 1 / 6),
      );
      expect(chunked.single.startSeconds, closeTo(28, 1 / 6));
      expect(chunked.single.endSeconds, closeTo(34, 1 / 6));
    },
  );
}

Future<List<SegmentInfo>> _detectPlayBall(Iterable<double> timestamps) async {
  final detector = BadmintonRealtimeActionSegmentDetector(
    config: BadmintonVideoClipConfigReqVo(),
    segmentDetectConfig: defaultBadmintonSegmentDetectConfig,
    largeModelService: LargeModelService(),
    modelPredictor: _PlayBallPredictor(),
  );
  await detector.start();
  for (final timestamp in timestamps) {
    await detector.addRgb24Prediction('unused.rgb', timestamp);
  }
  await detector.stop();
  final segments = detector.detectedSegments
      .where((segment) => segment.actionType == ActionType.playBall)
      .toList();
  await detector.dispose();
  return segments;
}

class _PlayBallPredictor implements ModelPredictor {
  @override
  Future<ActionType> predict(
    String framePath,
    Map<String, ActionType> classMappings,
  ) async => ActionType.playBall;

  @override
  Future<ActionType> predictWithBytes(
    Uint8List imageBytes,
    Map<String, ActionType> classMappings,
  ) async => ActionType.playBall;

  @override
  Future<ActionType> predictRgb24FromFile(
    String rgbFilePath,
    int width,
    int height,
    Map<String, ActionType> classMappings,
  ) async => ActionType.playBall;

  @override
  Future<ClassifierResult> predictForResult(
    String framePath,
    Map<String, ActionType> classMappings,
  ) => throw UnimplementedError();

  @override
  Future<ClassifierResult> predictWithBytesForResult(
    Uint8List imageBytes,
    Map<String, ActionType> classMappings,
  ) => throw UnimplementedError();

  @override
  Future<void> dispose() async {}
}
