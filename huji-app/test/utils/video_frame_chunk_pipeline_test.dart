import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:huji_app/utils/video_frame_chunk_pipeline.dart';

void main() {
  group('VideoFrameChunkPipeline', () {
    test('plans 65 seconds as 30, 30, and 5 second chunks', () {
      final chunks = VideoFrameChunkPipeline.planChunks(
        videoDurationSeconds: 65,
      );

      expect(chunks, hasLength(3));
      expect(
        chunks
            .map((chunk) => (chunk.startSeconds, chunk.endSeconds))
            .toList(),
        [(0.0, 30.0), (30.0, 60.0), (60.0, 65.0)],
      );
    });

    test('computes frame timestamps on the global video timeline', () {
      expect(
        VideoFrameChunkPipeline.globalTimestamp(
          chunkStartSeconds: 30,
          frameIndex: 0,
          framesPerSecond: 6,
        ),
        30,
      );
      expect(
        VideoFrameChunkPipeline.globalTimestamp(
          chunkStartSeconds: 30,
          frameIndex: 6,
          framesPerSecond: 6,
        ),
        31,
      );
    });

    test('removes chunk and task directories after successful processing', () async {
      final root = await Directory.systemTemp.createTemp('chunk_success_');
      final taskDirectory = Directory(path.join(root.path, 'task'));
      final createdChunkDirectories = <String>[];
      String? previousChunkDirectory;
      const pipeline = VideoFrameChunkPipeline();

      final completed = await pipeline.process(
        videoDurationSeconds: 31,
        taskDirectory: taskDirectory,
        extractChunk: (chunk, directory) async {
          if (previousChunkDirectory != null) {
            expect(
              await Directory(previousChunkDirectory!).exists(),
              isFalse,
              reason: 'previous chunk must be deleted before the next starts',
            );
          }
          createdChunkDirectories.add(directory.path);
          previousChunkDirectory = directory.path;
          final frame = File(path.join(directory.path, '000001.rgb'));
          await frame.writeAsBytes([1, 2, 3]);
          return [frame.path];
        },
        consumeFrame: (_) async {},
      );

      expect(completed, isTrue);
      expect(await taskDirectory.exists(), isFalse);
      for (final directory in createdChunkDirectories) {
        expect(await Directory(directory).exists(), isFalse);
      }
      await root.delete(recursive: true);
    });

    test('removes the current chunk when frame consumption throws', () async {
      final root = await Directory.systemTemp.createTemp('chunk_error_');
      final taskDirectory = Directory(path.join(root.path, 'task'));
      const pipeline = VideoFrameChunkPipeline();

      await expectLater(
        pipeline.process(
          videoDurationSeconds: 30,
          taskDirectory: taskDirectory,
          extractChunk: (chunk, directory) async {
            final frame = File(path.join(directory.path, '000001.rgb'));
            await frame.writeAsBytes([1, 2, 3]);
            return [frame.path];
          },
          consumeFrame: (_) => throw StateError('inference failed'),
        ),
        throwsStateError,
      );

      expect(await taskDirectory.exists(), isFalse);
      await root.delete(recursive: true);
    });

    test('removes the current chunk when extraction throws', () async {
      final root = await Directory.systemTemp.createTemp('chunk_extract_error_');
      final taskDirectory = Directory(path.join(root.path, 'task'));
      const pipeline = VideoFrameChunkPipeline();

      await expectLater(
        pipeline.process(
          videoDurationSeconds: 30,
          taskDirectory: taskDirectory,
          extractChunk: (chunk, directory) async {
            final partialFrame = File(
              path.join(directory.path, '000001.rgb'),
            );
            await partialFrame.writeAsBytes([1, 2, 3]);
            throw StateError('ffmpeg failed');
          },
          consumeFrame: (_) async {},
        ),
        throwsStateError,
      );

      expect(await taskDirectory.exists(), isFalse);
      await root.delete(recursive: true);
    });

    test('cancellation after chunk zero prevents chunk one from starting', () async {
      final root = await Directory.systemTemp.createTemp('chunk_cancel_');
      final taskDirectory = Directory(path.join(root.path, 'task'));
      final startedChunks = <int>[];
      var cancelled = false;
      const pipeline = VideoFrameChunkPipeline();

      final completed = await pipeline.process(
        videoDurationSeconds: 65,
        taskDirectory: taskDirectory,
        isCancelled: () => cancelled,
        onChunkStarted: (chunk) => startedChunks.add(chunk.index),
        extractChunk: (chunk, directory) async {
          final frame = File(path.join(directory.path, '000001.rgb'));
          await frame.writeAsBytes([1, 2, 3]);
          return [frame.path];
        },
        consumeFrame: (_) async {
          cancelled = true;
        },
      );

      expect(completed, isFalse);
      expect(startedChunks, [0]);
      expect(await taskDirectory.exists(), isFalse);
      await root.delete(recursive: true);
    });
  });
}
