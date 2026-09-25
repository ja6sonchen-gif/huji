import 'package:flutter_test/flutter_test.dart';
import 'package:huji_app/widgets/video_trimmer/lib/managers/video_clip_segment.dart';
import 'package:huji_app/widgets/video_trimmer/lib/state/clip_segment_state.dart';

void main() {
  group('timeline to selected round mapping', () {
    final rounds = [
      const VideoClipSegment(id: 'round-1', startTime: 1000, endTime: 2000),
      const VideoClipSegment(id: 'round-2', startTime: 5000, endTime: 7000),
    ];

    test('playhead inside a round resolves that exact card', () {
      final state = ClipSegmentState(segments: rounds);

      expect(state.getActiveSegmentAt(6000)?.id, 'round-2');
    });

    test('playhead in a gap resolves no selected card', () {
      final state = ClipSegmentState(segments: rounds);

      expect(state.getActiveSegmentAt(3500), isNull);
    });
  });
}
