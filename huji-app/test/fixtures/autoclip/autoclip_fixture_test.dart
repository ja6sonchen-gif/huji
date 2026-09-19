import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../helpers/autoclip_fixtures.dart';

void _expectGoldenSelfConsistent(Map<String, dynamic> golden) {
  expect(golden['sport'], isA<String>());
  expect(golden['match_type'], isA<String>());
  expect(golden['all_match_segment_count'], isA<int>());
  expect(golden['great_match_segment_count'], isA<int>());

  final segments = goldenAllMatchSegments(golden);
  expect(segments.length, golden['all_match_segment_count']);

  for (final segment in segments) {
    final start = (segment['start'] as num).toDouble();
    final end = (segment['end'] as num).toDouble();
    expect(start, greaterThanOrEqualTo(0));
    expect(end, greaterThan(start));
    expect(segment['action'], isA<String>());
  }
}

void main() {
  group('Autoclip fixtures — ping pong', () {
    late Directory appRoot;

    setUp(() {
      appRoot = findAppRoot();
    });

    test('test video exists in huji-app', () {
      final video = resolveFixtureFile(pingPongTestVideoRel, appRoot: appRoot);
      expect(video.lengthSync(), greaterThan(1000000));
    });

    test('golden JSON is valid and self-consistent', () {
      final golden = loadPingPongGolden(appRoot: appRoot);
      expect(golden['sport'], 'ping_pong');
      expect(golden['match_type'], 'profession');
      _expectGoldenSelfConsistent(golden);
    });

    test('golden video path resolves to bundled test.mp4', () {
      final golden = loadPingPongGolden(appRoot: appRoot);
      final videoPath = resolveGoldenVideoPath(golden, appRoot: appRoot);
      final bundled = resolvePingPongTestVideo(appRoot: appRoot);

      expect(File(videoPath).existsSync(), isTrue);
      expect(
        File(videoPath).resolveSymbolicLinksSync(),
        File(bundled).resolveSymbolicLinksSync(),
      );
    });

    test('algorithm golden expects three play_ball segments', () {
      final golden = loadPingPongGolden(appRoot: appRoot);
      final segments = goldenAllMatchSegments(golden);

      expect(golden['all_match_segment_count'], 3);
      expect(golden['great_match_segment_count'], 0);
      expect(
        segments.every(
          (s) => normalizeActionName(s['action'] as String) == 'playball',
        ),
        isTrue,
      );
    });
  });

  group('lenientGoldenTimingFailure', () {
    const pingPongGoldens = <GoldenTimingWindow>[
      (start: 0.0, end: 2.33),
      (start: 8.17, end: 15.83),
      (start: 22.33, end: 23.17),
    ];

    test('CI center-crop miss of sub-min-duration rally is accepted', () {
      expect(
        lenientGoldenTimingFailure(
          expected: pingPongGoldens,
          actual: const [
            (start: 0.0, end: 2.5),
            (start: 8.166666666666671, end: 15.8),
          ],
          toleranceSeconds: 2.0,
          minDurationSeconds: 2.0,
        ),
        isNull,
      );
    });

    test('missing a long golden rally still fails', () {
      expect(
        lenientGoldenTimingFailure(
          expected: pingPongGoldens,
          actual: const [(start: 0.0, end: 2.5)],
          toleranceSeconds: 2.0,
          minDurationSeconds: 2.0,
        ),
        contains('8.17-15.83'),
      );
    });

    test('merged actual window covers a later golden start', () {
      expect(
        lenientGoldenTimingFailure(
          expected: pingPongGoldens,
          actual: const [(start: 0.0, end: 16.0)],
          toleranceSeconds: 2.0,
          minDurationSeconds: 2.0,
        ),
        isNull,
      );
    });
  });

  group('Autoclip fixtures — badminton', () {
    late Directory appRoot;

    setUp(() {
      appRoot = findAppRoot();
    });

    test('blue.mp4 exists in huji-app', () {
      final video = resolveFixtureFile(badmintonTestVideoRel, appRoot: appRoot);
      expect(video.lengthSync(), greaterThan(1000000));
    });

    test('golden JSON is valid and self-consistent', () {
      final golden = loadBadmintonGolden(appRoot: appRoot);
      expect(golden['sport'], 'badminton');
      expect(golden['match_type'], 'singles');
      _expectGoldenSelfConsistent(golden);
    });

    test('golden video path resolves to bundled blue.mp4', () {
      final golden = loadBadmintonGolden(appRoot: appRoot);
      final videoPath = resolveGoldenVideoPath(golden, appRoot: appRoot);
      final bundled = resolveBadmintonTestVideo(appRoot: appRoot);

      expect(File(videoPath).existsSync(), isTrue);
      expect(
        File(videoPath).resolveSymbolicLinksSync(),
        File(bundled).resolveSymbolicLinksSync(),
      );
    });

    test('algorithm golden expects four play_ball segments', () {
      final golden = loadBadmintonGolden(appRoot: appRoot);
      final segments = goldenAllMatchSegments(golden);

      expect(golden['all_match_segment_count'], 4);
      expect(golden['great_match_segment_count'], 0);
      expect(
        segments.every(
          (s) => normalizeActionName(s['action'] as String) == 'playball',
        ),
        isTrue,
      );
    });
  });
}
