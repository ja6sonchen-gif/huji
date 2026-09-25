import 'package:flutter_test/flutter_test.dart';
import 'package:huji_app/models/autoclip_models.dart';
import 'package:huji_app/pages/clip/round_segment_tools.dart';

SegmentInfo segment(double start, double end) => SegmentInfo(
  actionType: ActionType.playBall,
  startSeconds: start,
  endSeconds: end,
);

void main() {
  group('RoundSegmentTools', () {
    test('adjusts start and end by a user supplied step without crossing', () {
      final original = segment(4, 8);
      final earlier = RoundSegmentTools.adjustBoundary(
        original,
        adjustStart: true,
        deltaSeconds: -0.5,
        videoDurationSeconds: 10,
      );
      final laterEnd = RoundSegmentTools.adjustBoundary(
        earlier,
        adjustStart: false,
        deltaSeconds: 0.5,
        videoDurationSeconds: 10,
      );

      expect(earlier.startSeconds, 3.5);
      expect(laterEnd.endSeconds, 8.5);
      expect(laterEnd.startSeconds, lessThan(laterEnd.endSeconds));
    });

    test('clamps expanded boundaries to video duration', () {
      final result = RoundSegmentTools.expandAndMerge(
        segments: [segment(0.2, 9.8)],
        beforeSeconds: 1.5,
        afterSeconds: 3,
        videoDurationSeconds: 10,
      );

      expect(result.single.startSeconds, 0);
      expect(result.single.endSeconds, 10);
    });

    test('merges overlapping expanded rounds to avoid duplicate export', () {
      final result = RoundSegmentTools.expandAndMerge(
        segments: [segment(10, 20), segment(21, 30)],
        beforeSeconds: 0.5,
        afterSeconds: 1.5,
        videoDurationSeconds: 60,
      );

      expect(result, hasLength(1));
      expect(result.single.startSeconds, 9.5);
      expect(result.single.endSeconds, 31.5);
    });

    test('supports a configurable short-round threshold and previews count', () {
      final rounds = [segment(0, 1.5), segment(2, 4), segment(5, 9)];

      expect(RoundSegmentTools.shorterThan(rounds, 2), hasLength(1));
      expect(RoundSegmentTools.shorterThan(rounds, 3), hasLength(2));
    });

    test('deletes only rounds shorter than the threshold and restores them', () {
      final rounds = [segment(0, 1.5), segment(2, 4), segment(5, 9)];
      final deletion = RoundSegmentTools.removeShorterThan(rounds, 2);
      final remaining = rounds
          .where((round) => !deletion.any((entry) => entry.segment == round))
          .toList();

      expect(deletion, hasLength(1));
      expect(remaining, [rounds[1], rounds[2]]);
      expect(
        RoundSegmentTools.restoreRemovedRounds(remaining, deletion),
        rounds,
      );
    });

    test('supports a custom threshold and previews the exact delete count', () {
      final rounds = [segment(0, 1), segment(2, 4), segment(5, 8)];

      expect(RoundSegmentTools.removeShorterThan(rounds, 2.5), hasLength(2));
      expect(RoundSegmentTools.removeShorterThan(rounds, 3.5), hasLength(3));
    });
  });
}
