import 'dart:io';

/// Validates the persisted source used by offline video export.
///
/// Offline export intentionally accepts only a currently readable file path.
/// Content URIs need a retained Android URI grant/native descriptor and must
/// never be passed to dart:io or FFmpeg as if they were filesystem paths.
abstract final class LocalExportSource {
  static Future<String> requireExistingFile(String? sourcePath) async {
    if (sourcePath == null ||
        sourcePath.isEmpty ||
        sourcePath.startsWith('content://') ||
        sourcePath.startsWith('http://') ||
        sourcePath.startsWith('https://') ||
        !await File(sourcePath).exists()) {
      throw FileSystemException(
        'Local export source is missing or is not a filesystem path',
        sourcePath,
      );
    }
    return sourcePath;
  }
}
