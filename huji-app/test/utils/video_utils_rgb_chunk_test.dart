import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:huji_app/services/ffmpeg/ffmpeg_runner.dart';
import 'package:huji_app/utils/video_utils.dart';

void main() {
  late FFmpegRunner originalRunner;

  setUpAll(() {
    originalRunner = FFmpegRunner.instance;
  });

  tearDown(() {
    FFmpegRunner.instance = originalRunner;
  });

  test('RGB chunk extraction uses seek, bounded duration, 6 fps and rgb24', () async {
    final root = await Directory.systemTemp.createTemp('rgb_chunk_args_');
    final source = File(path.join(root.path, 'source.mp4'));
    await source.writeAsBytes([0]);
    final output = Directory(path.join(root.path, 'chunk'));
    await output.create();
    final runner = _ChunkWritingFFmpegRunner();
    FFmpegRunner.instance = runner;

    final frames = await VideoUtils.extractRawRgbFrameChunk(
      videoPath: source.path,
      framesPerSecond: 6,
      tempDir: output,
      startSeconds: 30,
      durationSeconds: 5,
      width: 640,
      height: 640,
    );

    final args = runner.arguments!;
    expect(args[args.indexOf('-ss') + 1], '30.0');
    expect(args[args.indexOf('-t') + 1], '5.0');
    expect(args.indexOf('-ss'), lessThan(args.indexOf('-i')));
    expect(args.indexOf('-t'), greaterThan(args.indexOf('-i')));
    expect(args[args.indexOf('-vf') + 1], contains('fps=6'));
    expect(args[args.indexOf('-vf') + 1], contains('scale='));
    expect(args[args.indexOf('-vf') + 1], contains('crop='));
    expect(args[args.indexOf('-pix_fmt') + 1], 'rgb24');
    expect(frames.map(path.basename).toList(), ['000001.rgb', '000002.rgb']);

    final firstOutput = Directory(path.join(root.path, 'first_chunk'));
    await firstOutput.create();
    await VideoUtils.extractRawRgbFrameChunk(
      videoPath: source.path,
      framesPerSecond: 6,
      tempDir: firstOutput,
      startSeconds: 0,
      durationSeconds: 30,
      width: 640,
      height: 640,
    );
    final firstArgs = runner.arguments!;
    expect(firstArgs[firstArgs.indexOf('-ss') + 1], '0.0');
    expect(firstArgs[firstArgs.indexOf('-t') + 1], '30.0');

    await root.delete(recursive: true);
  });
}

class _ChunkWritingFFmpegRunner implements FFmpegRunner {
  List<String>? arguments;

  @override
  Future<FFmpegResult> execute(
    List<String> arguments, {
    void Function(double progressTimeMs)? onProgress,
  }) async {
    this.arguments = List<String>.from(arguments);
    final pattern = arguments.last;
    await File(pattern.replaceFirst('%06d', '000002')).writeAsBytes([2]);
    await File(pattern.replaceFirst('%06d', '000001')).writeAsBytes([1]);
    return const FFmpegResult(returnCode: 0);
  }

  @override
  Future<FFmpegResult> executeProbe(List<String> arguments) async {
    throw UnimplementedError();
  }

  @override
  Future<void> cancel() async {}

  @override
  Future<Process> start(List<String> arguments) {
    throw UnimplementedError();
  }
}
