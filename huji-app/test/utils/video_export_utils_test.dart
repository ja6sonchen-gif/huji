import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:huji_app/models/autoclip_models.dart';
import 'package:huji_app/utils/video_export_utils.dart';
import 'package:path/path.dart' as p;

import '../helpers/autoclip_fixtures.dart';

/// PATH 上同时有 ffmpeg 与 ffprobe 才可跑真导出。
Future<bool> _ffmpegAvailable() async {
  const bins = ['ffmpeg', 'ffprobe'];
  for (final bin in bins) {
    try {
      final result = await Process.run(bin, ['-version']);
      if (result.exitCode != 0) return false;
    } catch (_) {
      return false;
    }
  }
  return true;
}

/// ffprobe 输出的 JSON（format + streams）。
Future<Map<String, dynamic>> _ffprobeJson(String path) async {
  final result = await Process.run('ffprobe', [
    '-v', 'error',
    '-print_format', 'json',
    '-show_format',
    '-show_streams',
    path,
  ]);
  if (result.exitCode != 0) {
    throw StateError('ffprobe failed: ${result.stderr}');
  }
  return json.decode(result.stdout as String) as Map<String, dynamic>;
}

double _formatDurationSeconds(Map<String, dynamic> probe) {
  return double.parse((probe['format'] as Map<String, dynamic>)['duration'] as String);
}

double _parseRate(String value) {
  final pieces = value.split('/');
  if (pieces.length == 2) {
    return (double.parse(pieces[0]) / double.parse(pieces[1]));
  }
  return double.parse(value);
}

Future<void> _createFrameRateFixture(String path, int fps) async {
  final result = await Process.run('ffmpeg', [
    '-hide_banner', '-loglevel', 'error',
    '-f', 'lavfi', '-i', 'testsrc=size=160x120:rate=$fps:duration=4',
    '-f', 'lavfi', '-i', 'sine=frequency=1000:sample_rate=48000:duration=4',
    '-c:v', 'libx264', '-preset', 'ultrafast', '-g', '$fps',
    '-pix_fmt', 'yuv420p', '-c:a', 'aac', '-shortest', '-y', path,
  ]);
  if (result.exitCode != 0) {
    throw StateError('ffmpeg fixture generation failed: ${result.stderr}');
  }
}

int _videoHeight(Map<String, dynamic> probe) {
  final streams = (probe['streams'] as List).cast<Map<String, dynamic>>();
  final video = streams.firstWhere((s) => s['codec_type'] == 'video');
  return (video['height'] as num).toInt();
}

/// golden JSON 的分段 → SegmentInfo（与检测 golden 测试同一数据源）。
List<SegmentInfo> _goldenSegments() {
  final golden = loadGoldenJson(pingPongGoldenRel, appRoot: findAppRoot());
  return goldenAllMatchSegments(golden)
      .map((s) => SegmentInfo(
            actionType: ActionType.fromString(s['action'] as String?),
            startSeconds: (s['start'] as num).toDouble(),
            endSeconds: (s['end'] as num).toDouble(),
          ))
      .toList();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late bool ffmpegAvailable;
  late String videoPath;
  late List<SegmentInfo> segments;
  late Directory tempDir;

  setUpAll(() async {
    ffmpegAvailable = await _ffmpegAvailable();
    videoPath =
        resolveFixtureFile(pingPongTestVideoRel, appRoot: findAppRoot()).path;
    segments = _goldenSegments();
    tempDir = await Directory.systemTemp.createTemp('huji_export_test_');
  });

  tearDownAll(() async {
    try {
      await tempDir.delete(recursive: true);
    } catch (_) {}
  });

  group('runConcatVideoExport', () {
    test('filter graph resets each segment PTS and joins video/audio in order', () {
      final filter = buildConcatFilterComplex(
        segments: [
          SegmentInfo(actionType: ActionType.playBall, startSeconds: 1, endSeconds: 2),
          SegmentInfo(actionType: ActionType.playBall, startSeconds: 4, endSeconds: 5.5),
        ],
        includeAudio: true,
      );

      expect(filter, contains('trim=start=1.0:end=2.0,setpts=PTS-STARTPTS[v0]'));
      expect(filter, contains('atrim=start=4.0:end=5.5,asetpts=PTS-STARTPTS[a1]'));
      expect(filter, contains('concat=n=2:v=1:a=1[vcat][acat]'));
      expect(filter, contains('[vcat]null[vout]'));
      expect(filter, contains('[acat]anull[aout]'));
    });

    test('filter graph supports source clips without an audio stream', () {
      final filter = buildConcatFilterComplex(
        segments: [
          SegmentInfo(actionType: ActionType.playBall, startSeconds: 0, endSeconds: 1),
        ],
        includeAudio: false,
        scaleFilter: 'scale=-2:720',
      );

      expect(filter, contains('concat=n=1:v=1:a=0[vcat]'));
      expect(filter, contains('[vcat]scale=-2:720[vout]'));
      expect(filter, isNot(contains('atrim=')));
    });

    test('preserves known source color metadata without color filters', () {
      final metadata = VideoColorMetadata.fromProbeJson(
        '{"streams":[{"color_range":"tv","color_space":"bt709",'
        '"color_primaries":"bt709","color_transfer":"bt709",'
        '"pix_fmt":"yuv420p"}]}',
      );

      final args = buildVideoEncodingArguments(
        sourceColor: metadata,
        crf: '18',
        preset: 'medium',
        audioBitrate: 128,
      );
      expect(args, containsAll([
        '-vsync', '0',
        '-pix_fmt', 'yuv420p',
        '-color_range', 'tv',
        '-colorspace', 'bt709',
        '-color_primaries', 'bt709',
        '-color_trc', 'bt709',
      ]));
      expect(args.join(' '), isNot(contains('eq=')));
      expect(args.join(' '), isNot(contains('hue=')));
      expect(args.join(' '), isNot(contains('colorbalance')));
      expect(args, isNot(contains('-vf')));
    });

    test('omits unspecified source color metadata instead of assuming BT.709', () {
      final metadata = VideoColorMetadata.fromProbeJson(
        '{"streams":[{"color_range":"unknown","color_space":"unknown",'
        '"color_primaries":"unknown","color_transfer":"unknown",'
        '"pix_fmt":"yuv420p10le"}]}',
      );

      expect(metadata.toFfmpegArguments(), isEmpty);
    });

    test('empty segments throws', () async {
      await expectLater(
        runConcatVideoExport(
          videoPath: videoPath,
          segments: [],
          quality: VideoExportQualities.original,
          outputPath: p.join(tempDir.path, 'never_created.mp4'),
        ),
        throwsA(isA<Exception>().having(
          (e) => e.toString(),
          'message',
          contains('No segments to export'),
        )),
      );
    });

    test('golden segments export to a valid mp4 (original quality)',
        timeout: const Timeout(Duration(minutes: 3)), () async {
      if (!ffmpegAvailable) {
        markTestSkipped('ffmpeg/ffprobe not on PATH');
        return;
      }

      final outputPath = p.join(tempDir.path, 'golden_original.mp4');
      final expectedDuration = segments.fold<double>(
        0,
        (sum, s) => sum + (s.endSeconds - s.startSeconds),
      );

      final returned = await runConcatVideoExport(
        videoPath: videoPath,
        segments: segments,
        quality: VideoExportQualities.original,
        outputPath: outputPath,
      );

      expect(returned, outputPath);
      expect(File(outputPath).existsSync(), isTrue, reason: '输出文件应存在');

      final probe = await _ffprobeJson(outputPath);
      final duration = _formatDurationSeconds(probe);
      // concat 按关键帧对齐引入误差，±1s 容差。
      expect(
        (duration - expectedDuration).abs(),
        lessThanOrEqualTo(1.0),
        reason: '输出时长 $duration vs 期望 $expectedDuration',
      );
      // 至少有一条可解封装的视频流。
      expect(
        (probe['streams'] as List)
            .where((s) => (s as Map)['codec_type'] == 'video'),
        isNotEmpty,
      );
    });

    test('720p quality scales output height to 720',
        timeout: const Timeout(Duration(minutes: 3)), () async {
      if (!ffmpegAvailable) {
        markTestSkipped('ffmpeg/ffprobe not on PATH');
        return;
      }

      final outputPath = p.join(tempDir.path, 'golden_720p.mp4');
      await runConcatVideoExport(
        videoPath: videoPath,
        segments: segments,
        quality: VideoExportQualities.p720,
        outputPath: outputPath,
      );

      final probe = await _ffprobeJson(outputPath);
      expect(_videoHeight(probe), 720);
    });

    test('progress callback goes 0 → 1 monotonically',
        timeout: const Timeout(Duration(minutes: 3)), () async {
      if (!ffmpegAvailable) {
        markTestSkipped('ffmpeg/ffprobe not on PATH');
        return;
      }

      final progressValues = <double>[];
      final outputPath = p.join(tempDir.path, 'golden_progress.mp4');
      await runConcatVideoExport(
        videoPath: videoPath,
        segments: segments,
        quality: VideoExportQualities.original,
        outputPath: outputPath,
        onProgress: progressValues.add,
      );

      expect(progressValues, isNotEmpty);
      expect(progressValues.first, 0.0);
      expect(progressValues.last, 1.0);
      for (final v in progressValues) {
        expect(v, inInclusiveRange(0.0, 1.0));
      }
      for (var i = 1; i < progressValues.length; i++) {
        expect(
          progressValues[i],
          greaterThanOrEqualTo(progressValues[i - 1]),
          reason: 'progress 不应回退（$i: ${progressValues[i - 1]} → ${progressValues[i]}）',
        );
      }
    });

    test('preserves 30/60 fps and continuous multi-segment A/V timing',
        timeout: const Timeout(Duration(minutes: 3)), () async {
      if (!ffmpegAvailable) {
        markTestSkipped('ffmpeg/ffprobe not on PATH');
        return;
      }

      for (final fps in [30, 60]) {
        final sourcePath = p.join(tempDir.path, 'source_${fps}fps.mp4');
        final outputPath = p.join(tempDir.path, 'output_${fps}fps.mp4');
        await _createFrameRateFixture(sourcePath, fps);
        await runConcatVideoExport(
          videoPath: sourcePath,
          segments: [
            SegmentInfo(actionType: ActionType.playBall, startSeconds: 0.5, endSeconds: 1.5),
            SegmentInfo(actionType: ActionType.playBall, startSeconds: 2, endSeconds: 3),
          ],
          quality: VideoExportQualities.original,
          outputPath: outputPath,
        );

        final probe = await _ffprobeJson(outputPath);
        final streams = (probe['streams'] as List).cast<Map<String, dynamic>>();
        final video = streams.firstWhere((s) => s['codec_type'] == 'video');
        final audio = streams.firstWhere((s) => s['codec_type'] == 'audio');
        expect(_parseRate(video['avg_frame_rate'] as String), closeTo(fps, 0.1));
        expect(
          (_formatDurationSeconds(probe) - 2).abs(),
          lessThan(0.15),
          reason: '$fps fps: concatenated duration should match selected ranges',
        );
        final audioDuration = double.tryParse(audio['duration']?.toString() ?? '') ??
            _formatDurationSeconds(probe);
        final videoDuration = double.tryParse(video['duration']?.toString() ?? '') ??
            _formatDurationSeconds(probe);
        expect((audioDuration - videoDuration).abs(), lessThan(0.12),
          reason: '$fps fps: audio/video durations should stay synchronized',
        );

        final packetResult = await Process.run('ffprobe', [
          '-v', 'error', '-select_streams', 'v:0',
          '-show_entries', 'packet=pts_time', '-of', 'json', outputPath,
        ]);
        expect(packetResult.exitCode, 0);
        final packetJson = json.decode(packetResult.stdout as String) as Map<String, dynamic>;
        final pts = (packetJson['packets'] as List)
            .cast<Map<String, dynamic>>()
            .map((packet) => double.parse(packet['pts_time'] as String))
            .toList();
        expect(pts.length, greaterThan(fps));
        for (var index = 1; index < pts.length; index++) {
          expect(pts[index], greaterThan(pts[index - 1]));
          expect(pts[index] - pts[index - 1], lessThan(2.5 / fps));
        }
      }
    });

    test('killing the process makes export fail',
        timeout: const Timeout(Duration(minutes: 3)), () async {
      if (!ffmpegAvailable) {
        markTestSkipped('ffmpeg/ffprobe not on PATH');
        return;
      }

      final outputPath = p.join(tempDir.path, 'cancelled.mp4');
      final completed = <double>[];

      await expectLater(
        runConcatVideoExport(
          videoPath: videoPath,
          segments: segments,
          quality: VideoExportQualities.original,
          outputPath: outputPath,
          onProgress: completed.add,
          onProcessStarted: (process) {
            // 启动即杀：模拟用户立刻取消。
            process.kill();
          },
        ),
        throwsA(anything),
      );

      // 被取消的导出不应走完整成路径：onProgress 不应收到 1.0 的完成值。
      expect(completed, isNot(contains(1.0)));
    });
  });
}
