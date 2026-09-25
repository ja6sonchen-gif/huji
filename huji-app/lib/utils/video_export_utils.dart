import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:huji_app/models/autoclip_models.dart';
import 'package:huji_app/services/ffmpeg/ffmpeg_runner.dart';
import 'package:huji_app/services/platform_capability.dart';

/// Color description read from the source stream. Unknown/unspecified fields
/// are deliberately omitted so FFmpeg keeps its normal stream inference.
class VideoColorMetadata {
  final String? range;
  final String? space;
  final String? primaries;
  final String? transfer;
  final String? pixelFormat;

  const VideoColorMetadata({
    this.range,
    this.space,
    this.primaries,
    this.transfer,
    this.pixelFormat,
  });

  factory VideoColorMetadata.fromProbeJson(String? output) {
    if (output == null || output.isEmpty) return const VideoColorMetadata();
    try {
      final json = jsonDecode(output) as Map<String, dynamic>;
      final streams = json['streams'] as List<dynamic>? ?? const [];
      if (streams.isEmpty) return const VideoColorMetadata();
      final stream = streams
          .cast<Map<String, dynamic>>()
          .firstWhere(
            (candidate) => candidate['codec_type'] == 'video',
            orElse: () => streams.first as Map<String, dynamic>,
          );
      String? value(String key, Set<String> supported) {
        final candidate = stream[key]?.toString().toLowerCase();
        return candidate != null && supported.contains(candidate)
            ? candidate
            : null;
      }

      return VideoColorMetadata(
        range: value('color_range', const {'tv', 'mpeg', 'pc', 'jpeg'}),
        space: value('color_space', const {
          'bt709', 'fcc', 'bt470bg', 'smpte170m', 'smpte240m', 'ycgco',
          'bt2020nc', 'bt2020c', 'smpte2085', 'chroma-derived-nc',
          'chroma-derived-c', 'ictcp',
        }),
        primaries: value('color_primaries', const {
          'bt709', 'bt470m', 'bt470bg', 'smpte170m', 'smpte240m', 'film',
          'bt2020', 'smpte428', 'smpte431', 'smpte432', 'jedec-p22',
          'ebu3213',
        }),
        transfer: value('color_transfer', const {
          'bt709', 'gamma22', 'gamma28', 'smpte170m', 'smpte240m', 'linear',
          'log', 'log_sqrt', 'iec61966-2-4', 'bt1361e', 'iec61966-2-1',
          'bt2020-10', 'bt2020-12', 'smpte2084', 'smpte428', 'arib-std-b67',
        }),
        pixelFormat: value('pix_fmt', const {
          'yuv420p', 'yuv422p', 'yuv444p',
        }),
      );
    } catch (_) {
      return const VideoColorMetadata();
    }
  }

  List<String> toFfmpegArguments() => [
    if (pixelFormat != null) ...['-pix_fmt', pixelFormat!],
    if (range != null) ...['-color_range', _normalizeRange(range!)],
    if (space != null) ...['-colorspace', space!],
    if (primaries != null) ...['-color_primaries', primaries!],
    if (transfer != null) ...['-color_trc', transfer!],
  ];

  static String _normalizeRange(String value) =>
      value == 'mpeg' ? 'tv' : (value == 'jpeg' ? 'pc' : value);
}

Future<VideoColorMetadata> probeVideoColorMetadata(String videoPath) async {
  final result = await FFmpegRunner.instance.executeProbe([
    '-v', 'error',
    '-select_streams', 'v:0',
    '-show_entries',
    'stream=color_range,color_space,color_primaries,color_transfer,pix_fmt',
    '-of', 'json',
    videoPath,
  ]);
  if (!result.isSuccess) return const VideoColorMetadata();
  return VideoColorMetadata.fromProbeJson(result.output);
}

List<String> buildVideoEncodingArguments({
  required VideoColorMetadata sourceColor,
  required String crf,
  required String preset,
  required int audioBitrate,
  String? scaleFilter,
}) => [
  '-c:v', 'libx264',
  '-crf', crf,
  '-preset', preset,
  if (scaleFilter != null && scaleFilter.isNotEmpty) ...['-vf', scaleFilter],
  ...sourceColor.toFfmpegArguments(),
  '-c:a', 'aac',
  '-b:a', '${audioBitrate}k',
];

class FrameTimestampStrategy {
  final List<String> arguments;
  final String name;

  const FrameTimestampStrategy(this.arguments, this.name);
}

/// Prefer the current per-stream switch, with its FFmpeg 4.4-era equivalent
/// for older FFmpeg/FFmpegKit builds. Both preserve timestamps rather than
/// forcing a fixed frame rate.
FrameTimestampStrategy frameTimestampStrategyFromHelp(String helpOutput) {
  if (helpOutput.contains('-fps_mode')) {
    return const FrameTimestampStrategy(
      ['-fps_mode', 'passthrough'],
      'fps_mode=passthrough',
    );
  }
  if (helpOutput.contains('-vsync')) {
    return const FrameTimestampStrategy(['-vsync', '0'], 'vsync=0 passthrough');
  }
  throw StateError('FFmpeg does not expose a timestamp passthrough option.');
}

FrameTimestampStrategy? _cachedFrameTimestampStrategy;
Future<FrameTimestampStrategy>? _pendingFrameTimestampStrategy;

Future<FrameTimestampStrategy> _resolveFrameTimestampStrategy() {
  final cached = _cachedFrameTimestampStrategy;
  if (cached != null) return Future.value(cached);
  return _pendingFrameTimestampStrategy ??= _probeFrameTimestampStrategy();
}

Future<FrameTimestampStrategy> _probeFrameTimestampStrategy() async {
  try {
    final help = await FFmpegRunner.instance.execute([
      '-hide_banner', '-h', 'full',
    ]);
    if (!help.isSuccess) {
      throw StateError(help.output ?? 'FFmpeg help probe failed.');
    }
    final strategy = frameTimestampStrategyFromHelp(help.output ?? '');
    _cachedFrameTimestampStrategy = strategy;
    return strategy;
  } finally {
    _pendingFrameTimestampStrategy = null;
  }
}

/// Build one filter graph that trims all ranges from a single input, resets
/// each range's timestamps, then joins them with continuous output PTS.
String buildConcatFilterComplex({
  required List<SegmentInfo> segments,
  required bool includeAudio,
  String? scaleFilter,
}) {
  if (segments.isEmpty) throw ArgumentError('No segments to concatenate.');

  final filters = <String>[];
  final concatInputs = <String>[];
  final videoSources = List.generate(segments.length, (index) => '[vsrc$index]');
  if (segments.length == 1) {
    filters.add('[0:v:0]null${videoSources.single}');
  } else {
    filters.add('[0:v:0]split=${segments.length}${videoSources.join()}');
  }
  final audioSources = List.generate(segments.length, (index) => '[asrc$index]');
  if (includeAudio) {
    if (segments.length == 1) {
      filters.add('[0:a:0]anull${audioSources.single}');
    } else {
      filters.add('[0:a:0]asplit=${segments.length}${audioSources.join()}');
    }
  }
  for (var index = 0; index < segments.length; index++) {
    final segment = segments[index];
    filters.add(
      '${videoSources[index]}trim=start=${segment.startSeconds}:end=${segment.endSeconds},'
      'setpts=PTS-STARTPTS[v$index]',
    );
    concatInputs.add('[v$index]');
    if (includeAudio) {
      filters.add(
        '${audioSources[index]}atrim=start=${segment.startSeconds}:end=${segment.endSeconds},'
        'asetpts=PTS-STARTPTS[a$index]',
      );
      concatInputs.add('[a$index]');
    }
  }

  final audioStreams = includeAudio ? 1 : 0;
  filters.add(
    '${concatInputs.join()}concat=n=${segments.length}:v=1:a=$audioStreams'
    '[vcat]${includeAudio ? '[acat]' : ''}',
  );
  if (scaleFilter != null && scaleFilter.isNotEmpty) {
    filters.add('[vcat]$scaleFilter[vout]');
  } else {
    filters.add('[vcat]null[vout]');
  }
  if (includeAudio) filters.add('[acat]anull[aout]');
  return filters.join(';');
}

/// 导出画质档位 key（与导出配置页的档位一一对应）。
abstract final class VideoExportQualities {
  static const original = 'original';
  static const p1080 = '1080p';
  static const p720 = '720p';
  static const p480 = '480p';
}

/// 把多个片段从同一源视频合成为单个 mp4。
///
/// 单次 filter_complex trim/concat + 单次 x264 编码，`-progress pipe:1`
/// 解析进度。每段在 filter graph 内归零 PTS，再由 concat filter 生成连续时间轴。
/// [onProgress] 只回传 0~1 的进度值，文案由调用方生成。
/// [onProcessStarted] 在 ffmpeg 启动后回调（桌面子进程分支），调用方可
/// 持有进程以实现取消。FFmpegKit 分支的取消走 [FFmpegRunner.cancel]。
/// 返回输出文件路径；失败抛异常（含 ffmpeg stderr）。
Future<String> runConcatVideoExport({
  required String videoPath,
  required List<SegmentInfo> segments,
  required String quality,
  required String outputPath,
  int? crfOverride,
  String? preset,
  int? audioBitrate,
  void Function(double progress)? onProgress,
  void Function(Process process)? onProcessStarted,
}) async {
  if (segments.isEmpty) {
    throw Exception('No segments to export');
  }

  final stopwatch = Stopwatch()..start();
  final timestampStrategy = await _resolveFrameTimestampStrategy();
  final sourceProbe = await _probeExportStreams(videoPath);
  if (sourceProbe == null) {
    throw StateError('Unable to probe source video streams.');
  }
  final sourceColor = VideoColorMetadata.fromProbeJson(sourceProbe);
  final includeAudio = _hasAudioStream(sourceProbe);
  _logExportProbe('source', sourceProbe);

  await Directory(File(outputPath).parent.path).create(recursive: true);

  final (scale, defaultCrf) = switch (quality) {
    VideoExportQualities.original => ('', '18'),
    VideoExportQualities.p1080 => ('scale=-2:1080', '20'),
    VideoExportQualities.p720 => ('scale=-2:720', '23'),
    _ => ('scale=-2:480', '26'),
  };
  final totalDurationSec = segments.fold<double>(
    0,
    (sum, s) => sum + (s.endSeconds - s.startSeconds),
  );
  final inputDurationSec = _formatDurationFromProbe(sourceProbe);
  debugPrint(
    '[VideoExport] inputDuration=${inputDurationSec?.toStringAsFixed(3) ?? "unknown"}s '
    'selectedDuration=${totalDurationSec.toStringAsFixed(3)}s '
    'segmentCount=${segments.length}',
  );
  debugPrint(
    '[VideoExport] outputCodec=libx264 fpsStrategy=${timestampStrategy.name} '
    'preset=${preset ?? "medium"} crf=${crfOverride ?? defaultCrf} '
    'audioBitrate=${audioBitrate ?? 128}k '
    'pixFmt=${sourceColor.pixelFormat ?? "encoder-default"}',
  );
  onProgress?.call(0);

  final commonArgs = [
    '-i', videoPath,
    '-filter_complex',
    buildConcatFilterComplex(
      segments: segments,
      includeAudio: includeAudio,
      scaleFilter: scale.isEmpty ? null : scale,
    ),
    '-map', '[vout]',
    if (includeAudio) ...['-map', '[aout]'],
    ...timestampStrategy.arguments,
    ...buildVideoEncodingArguments(
      sourceColor: sourceColor,
      crf: crfOverride?.toString() ?? defaultCrf,
      preset: preset ?? 'medium',
      audioBitrate: audioBitrate ?? 128,
    ),
    '-movflags', '+faststart',
    '-y', outputPath,
  ];

  try {
    // FFmpegKit 平台（Android/iOS/macOS）：无子进程可持有，经
    // [FFmpegRunner] 走会话执行；取消统一走 FFmpegRunner.cancel()。
    // 进度来自 FFmpegKit Statistics 的已编码时长（毫秒），与 Linux 分支
    // 解析 `-progress out_time_ms` 等价。
    if (PlatformCapability.supportsFFmpegKit) {
      final result = await FFmpegRunner.instance.execute(
        commonArgs,
        onProgress: totalDurationSec > 0 && onProgress != null
            ? (timeMs) {
                final seconds = timeMs / 1000;
                onProgress((seconds / totalDurationSec).clamp(0.0, 1.0));
              }
            : null,
      );
      if (!result.isSuccess && !result.isCancelled) {
        throw Exception(
          (result.output ?? '').trim().isEmpty
              ? 'ffmpeg exited with code ${result.returnCode}'
              : result.output,
        );
      }
      if (result.isSuccess) {
        _logExportProbe('output', await _probeExportStreams(outputPath));
      }
      onProgress?.call(1);
      return outputPath;
    }

    final process = await Process.start('ffmpeg', [
      ...commonArgs,
      '-progress', 'pipe:1', '-nostats',
    ]);
    onProcessStarted?.call(process);

    // ffmpeg 的 banner / 报错都写 stderr：必须边跑边排空管道，否则写满
    // ~64KB 缓冲后 ffmpeg 会阻塞在写 stderr 上永不退出。
    final stderrFuture = process.stderr.transform(utf8.decoder).join();

    // out_time_ms 实际单位是微秒（ffmpeg 历史遗留，与 out_time_us 同值），
    // 除以 1e6 才是秒；按毫秒算会把进度放大 1000 倍，刚开始编码就显示 100%。
    final attached = _attachProgressListener(
      process,
      totalDurationSec,
      onProgress ?? (_) {},
    );

    final exitCode = await process.exitCode;
    await attached;
    if (exitCode != 0) {
      final stderr = await stderrFuture;
      throw Exception(
        stderr.trim().isEmpty ? 'ffmpeg exited with code $exitCode' : stderr,
      );
    }

    _logExportProbe('output', await _probeExportStreams(outputPath));

    onProgress?.call(1);
    return outputPath;
  } catch (e) {
    rethrow;
  } finally {
    stopwatch.stop();
    debugPrint(
      '[VideoExport] exportElapsed=${(stopwatch.elapsedMilliseconds / 1000).toStringAsFixed(3)}s '
      'inputDuration=${inputDurationSec?.toStringAsFixed(3) ?? "unknown"}s '
      'selectedDuration=${totalDurationSec.toStringAsFixed(3)}s '
      'segmentCount=${segments.length}',
    );
  }
}

bool _hasAudioStream(String probeOutput) {
  final json = jsonDecode(probeOutput) as Map<String, dynamic>;
  final streams = json['streams'] as List<dynamic>? ?? const [];
  return streams.any((stream) =>
      (stream as Map<String, dynamic>)['codec_type'] == 'audio');
}

Future<String?> _probeExportStreams(String videoPath) async {
  try {
    final result = await FFmpegRunner.instance.executeProbe([
      '-v', 'error',
      '-show_format',
      '-show_streams',
      '-show_entries',
      'format=duration,bit_rate,start_time:stream=codec_type,codec_name,width,height,avg_frame_rate,r_frame_rate,time_base,pix_fmt,color_range,color_space,color_primaries,color_transfer,bit_rate,duration,sample_rate,start_time',
      '-of', 'json',
      videoPath,
    ]);
    return result.isSuccess ? result.output : null;
  } catch (error) {
    debugPrint('[VideoExport] ffprobe failed for $videoPath: $error');
    return null;
  }
}

double? _formatDurationFromProbe(String? output) {
  if (output == null || output.isEmpty) return null;
  try {
    final json = jsonDecode(output) as Map<String, dynamic>;
    final format = json['format'] as Map<String, dynamic>?;
    return double.tryParse(format?['duration']?.toString() ?? '');
  } catch (_) {
    return null;
  }
}

void _logExportProbe(String label, String? output) {
  if (output == null || output.isEmpty) {
    debugPrint('[VideoExport] $label ffprobe unavailable');
    return;
  }
  try {
    final json = jsonDecode(output) as Map<String, dynamic>;
    final format = json['format'] as Map<String, dynamic>? ?? const {};
    final streams = (json['streams'] as List<dynamic>? ?? const [])
        .cast<Map<String, dynamic>>();
    for (final stream in streams) {
      debugPrint(
        '[VideoExport] $label ${stream['codec_type']} '
        'codec=${stream['codec_name']} size=${stream['width'] ?? '-'}x${stream['height'] ?? '-'} '
        'avgFps=${stream['avg_frame_rate']} rFps=${stream['r_frame_rate']} '
        'timeBase=${stream['time_base']} pixFmt=${stream['pix_fmt']} '
        'color=${stream['color_range']}/${stream['color_space']}/'
        '${stream['color_primaries']}/${stream['color_transfer']} '
        'bitrate=${stream['bit_rate']} sampleRate=${stream['sample_rate']} '
        'duration=${stream['duration']} start=${stream['start_time']}',
      );
    }
    debugPrint(
      '[VideoExport] $label format duration=${format['duration']} '
      'bitrate=${format['bit_rate']} start=${format['start_time']}',
    );
  } catch (error) {
    debugPrint('[VideoExport] $label ffprobe parse failed: $error');
  }
}

Future<void> _attachProgressListener(
  Process process,
  double totalDurationSec,
  void Function(double) onProgress,
) async {
  final outLines = process.stdout
      .transform(utf8.decoder)
      .transform(const LineSplitter());
  await for (final line in outLines) {
    if (line.startsWith('out_time_ms=')) {
      // out_time_ms 的值其实是微秒（ffmpeg 历史遗留命名），换算成秒。
      final micros = int.tryParse(line.substring(12)) ?? 0;
      if (totalDurationSec > 0) {
        onProgress(((micros / 1e6) / totalDurationSec).clamp(0.0, 1.0));
      }
    }
  }
}
