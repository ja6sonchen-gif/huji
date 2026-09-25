import 'package:huji_app/models/autoclip_models.dart';

class RemovedRoundEntry {
  final int originalIndex;
  final SegmentInfo segment;

  const RemovedRoundEntry(this.originalIndex, this.segment);
}

/// Pure helpers shared by the round editor and export preparation.
abstract final class RoundSegmentTools {
  static const minimumDurationSeconds = 0.1;

  static SegmentInfo adjustBoundary(
    SegmentInfo segment, {
    required bool adjustStart,
    required double deltaSeconds,
    required double videoDurationSeconds,
  }) {
    final duration = videoDurationSeconds.isFinite && videoDurationSeconds > 0
        ? videoDurationSeconds
        : segment.endSeconds;
    final minimum = duration < minimumDurationSeconds
        ? duration
        : minimumDurationSeconds;

    if (adjustStart) {
      final latestStart = (segment.endSeconds - minimum)
          .clamp(0.0, duration)
          .toDouble();
      return segment.copyWith(
        startSeconds: (segment.startSeconds + deltaSeconds).clamp(
          0.0,
          latestStart,
        ).toDouble(),
      );
    }

    final earliestEnd = (segment.startSeconds + minimum).clamp(0.0, duration);
    return segment.copyWith(
      endSeconds: (segment.endSeconds + deltaSeconds).clamp(
        earliestEnd,
        duration,
      ).toDouble(),
    );
  }

  static List<SegmentInfo> expandAndMerge({
    required List<SegmentInfo> segments,
    required double beforeSeconds,
    required double afterSeconds,
    required double videoDurationSeconds,
    SegmentInfo? only,
  }) {
    if (beforeSeconds < 0 || afterSeconds < 0) {
      throw ArgumentError('Expansion values must not be negative.');
    }
    final duration = videoDurationSeconds.isFinite && videoDurationSeconds >= 0
        ? videoDurationSeconds
        : 0.0;
    final expanded = segments.map((segment) {
      final shouldExpand = only == null || _sameSegment(segment, only);
      if (!shouldExpand) return segment;
      final start = (segment.startSeconds - beforeSeconds)
          .clamp(0.0, duration)
          .toDouble();
      final end = (segment.endSeconds + afterSeconds)
          .clamp(start, duration)
          .toDouble();
      return segment.copyWith(startSeconds: start, endSeconds: end);
    }).toList();

    return mergeOverlaps(expanded);
  }

  /// Returns the chronological union of overlapping same-action segments.
  /// This prevents a time range from being exported twice after expansion.
  static List<SegmentInfo> mergeOverlaps(List<SegmentInfo> segments) {
    if (segments.length < 2) return List.of(segments);
    final sorted = List<SegmentInfo>.of(segments)
      ..sort((a, b) {
        final byStart = a.startSeconds.compareTo(b.startSeconds);
        return byStart != 0 ? byStart : a.endSeconds.compareTo(b.endSeconds);
      });
    final merged = <SegmentInfo>[];
    for (final segment in sorted) {
      if (merged.isEmpty) {
        merged.add(segment);
        continue;
      }
      final previous = merged.last;
      if (previous.actionType == segment.actionType &&
          segment.startSeconds <= previous.endSeconds) {
        merged[merged.length - 1] = previous.copyWith(
          endSeconds: previous.endSeconds > segment.endSeconds
              ? previous.endSeconds
              : segment.endSeconds,
        );
      } else {
        merged.add(segment);
      }
    }
    return merged;
  }

  static List<SegmentInfo> shorterThan(
    List<SegmentInfo> segments,
    double thresholdSeconds,
  ) => segments
      .where((segment) =>
          segment.endSeconds - segment.startSeconds < thresholdSeconds)
      .toList();

  static List<RemovedRoundEntry> removeShorterThan(
    List<SegmentInfo> segments,
    double thresholdSeconds,
  ) => [
    for (var index = 0; index < segments.length; index++)
      if (segments[index].endSeconds - segments[index].startSeconds <
          thresholdSeconds)
        RemovedRoundEntry(index, segments[index]),
  ];

  static List<SegmentInfo> restoreRemovedRounds(
    List<SegmentInfo> remaining,
    List<RemovedRoundEntry> removed,
  ) {
    final restored = List<SegmentInfo>.of(remaining);
    final ordered = List<RemovedRoundEntry>.of(removed)
      ..sort((a, b) => a.originalIndex.compareTo(b.originalIndex));
    for (final entry in ordered) {
      restored.insert(
        entry.originalIndex.clamp(0, restored.length).toInt(),
        entry.segment,
      );
    }
    return restored;
  }

  static bool _sameSegment(SegmentInfo a, SegmentInfo b) =>
      a.actionType == b.actionType &&
      a.startSeconds == b.startSeconds &&
      a.endSeconds == b.endSeconds;
}
