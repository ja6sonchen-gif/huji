import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:huji_app/services/local_export_source.dart';

void main() {
  group('LocalExportSource', () {
    test('accepts the current readable local video path unchanged', () async {
      final source = await Directory.systemTemp.createTemp('huji_export_source_');
      final video = File('${source.path}${Platform.pathSeparator}source.mp4');
      await video.writeAsBytes([0, 1, 2]);
      addTearDown(() => source.delete(recursive: true));

      expect(await LocalExportSource.requireExistingFile(video.path), video.path);
    });

    test('rejects content URIs and does not disguise them as file paths', () async {
      await expectLater(
        LocalExportSource.requireExistingFile('content://media/video/1'),
        throwsA(isA<FileSystemException>()),
      );
    });

    test('rejects a source that was removed before export', () async {
      final source = await Directory.systemTemp.createTemp('huji_export_source_');
      final video = File('${source.path}${Platform.pathSeparator}source.mp4');
      await video.writeAsBytes([0, 1, 2]);
      await video.delete();
      addTearDown(() => source.delete(recursive: true));

      await expectLater(
        LocalExportSource.requireExistingFile(video.path),
        throwsA(isA<FileSystemException>()),
      );
    });
  });
}
