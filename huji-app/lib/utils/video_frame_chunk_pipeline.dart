import 'dart:io';

import 'package:path/path.dart' as path;

class VideoFrameChunk {
  const VideoFrameChunk({
    required this.index,
    required this.startSeconds,
    required this.durationSeconds,
  });

  final int index;
  final double startSeconds;
  final double durationSeconds;

  double get endSeconds => startSeconds + durationSeconds;
}

class VideoFrameInfo {
  const VideoFrameInfo({
    required this.chunk,
    required this.frameIndex,
    required this.filePath,
    required this.timestampSeconds,
  });

  final VideoFrameChunk chunk;
  final int frameIndex;
  final String filePath;
  final double timestampSeconds;
}

typedef VideoFrameChunkExtractor =
    Future<List<String>> Function(VideoFrameChunk chunk, Directory directory);
typedef VideoFrameConsumer = Future<void> Function(VideoFrameInfo frame);

/// Bounded-disk orchestration for file-based RGB24 inference.
///
/// Only one chunk directory exists at a time. The caller owns the detector and
/// predictor, so their state remains continuous across chunk boundaries.
class VideoFrameChunkPipeline {
  const VideoFrameChunkPipeline({
    this.chunkDurationSeconds = 30,
    this.framesPerSecond = 6,
  });

  final double chunkDurationSeconds;
  final int framesPerSecond;

  static List<VideoFrameChunk> planChunks({
    required double videoDurationSeconds,
    double chunkDurationSeconds = 30,
  }) {
    if (videoDurationSeconds < 0) {
      throw ArgumentError.value(
        videoDurationSeconds,
        'videoDurationSeconds',
        'must not be negative',
      );
    }
    if (chunkDurationSeconds <= 0) {
      throw ArgumentError.value(
        chunkDurationSeconds,
        'chunkDurationSeconds',
        'must be positive',
      );
    }

    final chunks = <VideoFrameChunk>[];
    var start = 0.0;
    var index = 0;
    while (start < videoDurationSeconds) {
      final remaining = videoDurationSeconds - start;
      final duration = remaining < chunkDurationSeconds
          ? remaining
          : chunkDurationSeconds;
      chunks.add(
        VideoFrameChunk(
          index: index,
          startSeconds: start,
          durationSeconds: duration,
        ),
      );
      start += duration;
      index++;
    }
    return chunks;
  }

  static double globalTimestamp({
    required double chunkStartSeconds,
    required int frameIndex,
    required int framesPerSecond,
  }) {
    if (frameIndex < 0) {
      throw ArgumentError.value(frameIndex, 'frameIndex', 'must be non-negative');
    }
    if (framesPerSecond <= 0) {
      throw ArgumentError.value(
        framesPerSecond,
        'framesPerSecond',
        'must be positive',
      );
    }
    return chunkStartSeconds + frameIndex / framesPerSecond;
  }

  /// Returns true when all chunks completed, false when cancellation stopped
  /// the pipeline. Cleanup runs for success, failure, and cancellation.
  Future<bool> process({
    required double videoDurationSeconds,
    required Directory taskDirectory,
    required VideoFrameChunkExtractor extractChunk,
    required VideoFrameConsumer consumeFrame,
    bool Function()? isCancelled,
    void Function(VideoFrameChunk chunk)? onChunkStarted,
  }) async {
    await taskDirectory.create(recursive: true);

    try {
      final chunks = planChunks(
        videoDurationSeconds: videoDurationSeconds,
        chunkDurationSeconds: chunkDurationSeconds,
      );
      for (final chunk in chunks) {
        if (isCancelled?.call() ?? false) return false;

        onChunkStarted?.call(chunk);
        final chunkDirectory = Directory(
          path.join(
            taskDirectory.path,
            'chunk_${chunk.index.toString().padLeft(3, '0')}',
          ),
        );
        await chunkDirectory.create(recursive: true);

        try {
          late final List<String> framePaths;
          try {
            framePaths = await extractChunk(chunk, chunkDirectory);
          } catch (_) {
            if (isCancelled?.call() ?? false) return false;
            rethrow;
          }

          for (var frameIndex = 0; frameIndex < framePaths.length; frameIndex++) {
            if (isCancelled?.call() ?? false) return false;
            final framePath = framePaths[frameIndex];
            await consumeFrame(
              VideoFrameInfo(
                chunk: chunk,
                frameIndex: frameIndex,
                filePath: framePath,
                timestampSeconds: globalTimestamp(
                  chunkStartSeconds: chunk.startSeconds,
                  frameIndex: frameIndex,
                  framesPerSecond: framesPerSecond,
                ),
              ),
            );

            // Inference has consumed the bytes; release each large RGB file as
            // early as possible instead of retaining the full chunk.
            final frameFile = File(framePath);
            if (await frameFile.exists()) {
              await frameFile.delete();
            }
          }
        } finally {
          await _deleteDirectoryIfPresent(chunkDirectory);
        }
      }
      return true;
    } finally {
      await _deleteDirectoryIfPresent(taskDirectory);
    }
  }

  static Future<void> _deleteDirectoryIfPresent(Directory directory) async {
    Object? lastError;
    for (var attempt = 0; attempt < 3; attempt++) {
      if (!await directory.exists()) return;
      try {
        await directory.delete(recursive: true);
        return;
      } catch (error) {
        lastError = error;
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
    }
    throw FileSystemException(
      'Unable to delete RGB chunk directory after retries: $lastError',
      directory.path,
    );
  }
}
