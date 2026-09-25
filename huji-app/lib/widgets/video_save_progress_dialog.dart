import 'dart:io';

import 'package:flutter/material.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:intl/intl.dart';
import 'package:open_file/open_file.dart';
import 'package:path/path.dart' as path;
import 'package:huji_app/api/models/autoclip/video_models.dart';
import 'package:huji_app/services/video_library_registrar.dart';
import 'package:huji_app/services/local_export_source.dart';
import 'package:huji_app/utils/debounce/throttles.dart';
import 'package:huji_app/utils/file_utils.dart' as path_utils;
import 'package:huji_app/utils/logger_utils.dart';
import 'package:huji_app/utils/video_export_utils.dart';
import 'package:huji_app/pages/clip/round_segment_tools.dart';
import 'package:huji_app/widgets/video_player/video_player_page.dart';

import '../models/autoclip_models.dart';
import '../models/ffmpeg.dart';
import 'package:huji_app/l10n/l10n_extensions.dart';

class VideoSaveProgressDialog extends StatefulWidget {
  final String videoPath;
  final List<SegmentInfo> segments;
  final String fileName;
  final VideoCompressQuality? quality;
  final SportType? sportType;
  final VideoProcessType? videoProcessType;

  const VideoSaveProgressDialog({
    super.key,
    required this.videoPath,
    required this.segments,
    required this.fileName,
    this.quality,
    this.sportType,
    this.videoProcessType,
  });

  @override
  State<VideoSaveProgressDialog> createState() =>
      _VideoSaveProgressDialogState();
}

class _VideoSaveProgressDialogState extends State<VideoSaveProgressDialog> {
  double _progress = 0.0;
  String _status = '';
  bool _isCompleted = false;
  String? _errorMessage;
  String? _savedVideoPath;
  int _fileSize = 0;
  String _formattedFileSize = '0 B';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _saveVideo());
  }

  Future<void> _saveVideo() async {
    final l10n = context.hujiL10n;
    try {
      await LocalExportSource.requireExistingFile(widget.videoPath);
      if (!mounted) return;
      setState(() {
        _status = l10n.savePreparingInProgress;
        _progress = 0.1;
      });

      // 获取保存目录
      final downloadsDir = await path_utils.getDownloadsDirectory();
      final videoDir = path.join(downloadsDir.path, 'Videos');
      await Directory(videoDir).create(recursive: true);

      // 生成文件名（简化格式以便相册识别）
      final timestamp = DateFormat('yyyyMMddHHmmss').format(DateTime.now());
      // 截断原始文件名，避免过长（保留前30个字符）
      final baseFileName = widget.fileName.length > 30
          ? widget.fileName.substring(0, 30)
          : widget.fileName;
      final fileName = '${baseFileName}_$timestamp.mp4';
      final targetPath = path.join(videoDir, fileName);

      if (!mounted) return;
      setState(() {
        _progress = 0.2;
        _status = l10n.saveProcessingSegmentsStart;
      });

      final qualityConfig = widget.quality == null
          ? null
          : VideoCompressConfig.fromQuality(
              quality: widget.quality!,
              includeAudio: true,
              optimizeForWeb: true,
            );
      final exportSegments = RoundSegmentTools.mergeOverlaps(widget.segments);
      await runConcatVideoExport(
        videoPath: await LocalExportSource.requireExistingFile(widget.videoPath),
        segments: exportSegments,
        quality: VideoExportQualities.original,
        outputPath: targetPath,
        crfOverride: qualityConfig?.crfValue,
        preset: qualityConfig?.presetString,
        audioBitrate: qualityConfig?.audioBitrate,
        onProgress: (progress) {
          if (!mounted) return;
          setState(() {
            _progress = 0.2 + progress * 0.7;
            _status = l10n.saveTrimmingSegmentsProgress(
              (progress * 100).toStringAsFixed(1),
            );
          });
        },
      );

      // 检查文件是否生成成功
      final file = File(targetPath);
      if (await file.exists()) {
        _fileSize = await file.length();
        _formattedFileSize = _formatFileSize(_fileSize);

        if (!mounted) return;
        setState(() {
          _progress = 0.92;
          _status = l10n.saveSavingMetadata;
        });

        // 持久化视频元数据到本地数据库 + （移动端）保存到相册 —— 统一入口。
        final registered = await VideoLibraryRegistrar.instance.register(
          VideoLibraryEntry(
            outputPath: targetPath,
            processType:
                widget.videoProcessType ?? VideoProcessType.allMatchMerged,
            sourceVideoPath: widget.videoPath,
            sportTypeHint: widget.sportType,
          ),
        );
        AppLogger().i('视频库注册结果: $registered');

        if (!mounted) return;
        setState(() {
          _progress = 0.95;
          _status = l10n.saveSavingToGallery;
        });

        if (!mounted) return;
        setState(() {
          _progress = 1.0;
          _status = l10n.saveComplete;
          _isCompleted = true;
          _savedVideoPath = targetPath;
        });
      } else {
        throw Exception(l10n.videoFileNotGenerated);
      }
    } catch (e, stackTrace) {
      AppLogger().e('保存视频失败', stackTrace, e);
      if (!mounted) return;
      setState(() {
        _errorMessage = l10n.videoSaveFailed;
        _status = l10n.saveFailedShort;
      });
    }
  }

  String _formatFileSize(int bytes) {
    if (bytes < 1024) {
      return '$bytes B';
    } else if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    } else if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    } else {
      return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
    }
  }

  Future<void> _openFolder(BuildContext context) async {
    try {
      if (_savedVideoPath != null) {
        final file = File(_savedVideoPath!);
        if (await file.exists()) {
          await OpenFile.open(file.parent.path);
        } else {
          if (context.mounted) {
            TpToast.show(
              context,
              message: context.hujiL10n.videoPlayerFileNotFound,
              variant: TpToastVariant.error,
            );
          }
        }
      }
    } catch (e) {
      if (context.mounted) {
        TpToast.show(
          context,
          message: context.hujiL10n.openFolderFailed(e.toString()),
          variant: TpToastVariant.error,
        );
      }
    }
  }

  Future<void> _openFile(BuildContext context) async {
    try {
      if (_savedVideoPath != null) {
        final file = File(_savedVideoPath!);
        if (await file.exists()) {
          // 使用VideoPlayerPage播放视频
          final fileName = path.basename(_savedVideoPath!);
          if (context.mounted) {
            VideoPlayerPage.show(context, _savedVideoPath!, fileName);
          }
        } else {
          if (context.mounted) {
            TpToast.show(
              context,
              message: context.hujiL10n.videoPlayerFileNotFound,
              variant: TpToastVariant.error,
            );
          }
        }
      }
    } catch (e) {
      if (context.mounted) {
        TpToast.show(
          context,
          message: context.hujiL10n.openFileFailed(e.toString()),
          variant: TpToastVariant.error,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.hujiL10n;
    final cs = Theme.of(context).colorScheme;
    final title = _errorMessage != null
        ? l10n.saveFailedShort
        : l10n.saveProgressTitle;
    final statusIcon = Icon(
      _isCompleted ? Icons.check_circle : Icons.video_library,
      color: _isCompleted ? Colors.green : cs.primary,
      size: 24,
    );
    final completedMenu = _isCompleted && _savedVideoPath != null
        ? TpActionMenuButton(
            icon: const Icon(Icons.more_vert),
            specs: [
              TpActionMenuSpec.item(
                value: 'open_file',
                icon: Icons.play_arrow,
                label: l10n.playVideo,
              ),
              TpActionMenuSpec.item(
                value: 'open_folder',
                icon: Icons.folder_open,
                label: l10n.openFolder,
              ),
            ],
            onSelected: (value) {
              switch (value) {
                case 'open_file':
                  _openFile(context);
                  break;
                case 'open_folder':
                  _openFolder(context);
                  break;
              }
            },
          )
        : null;

    return TpDialog(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TpDialogHeader(
            title: title,
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [statusIcon, if (completedMenu != null) completedMenu],
            ),
            onClose: () => Navigator.of(context).pop(),
          ),
          SizedBox(height: context.tpSpacing.lg),
          Text(
            l10n.fileNameWithSegmentCount(
              widget.fileName,
              widget.segments.length,
            ),
            style: TextStyle(
              color: cs.onSurface,
              fontSize: 14,
              fontWeight: FontWeight.bold,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 16),
          if (_errorMessage != null) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: cs.error.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(Icons.error, color: cs.error, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _errorMessage!,
                      style: TextStyle(color: cs.error, fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
          ] else ...[
            LinearProgressIndicator(
              value: _progress,
              backgroundColor: cs.surfaceContainerHighest,
              valueColor: AlwaysStoppedAnimation<Color>(cs.primary),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '${(_progress * 100).toStringAsFixed(1)}%',
                  style: TextStyle(
                    color: cs.onSurface,
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  _status,
                  style: TextStyle(color: cs.onSurface, fontSize: 12),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (_isCompleted && _savedVideoPath != null) ...[
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          l10n.fileInfoLabel,
                          style: TextStyle(
                            color: cs.onSurfaceVariant,
                            fontSize: 10,
                          ),
                        ),
                        Text(
                          _formattedFileSize,
                          style: TextStyle(color: cs.onSurface, fontSize: 10),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      l10n.saveLocationLabel,
                      style: TextStyle(
                        color: cs.onSurfaceVariant,
                        fontSize: 10,
                      ),
                    ),
                    Text(
                      path.dirname(_savedVideoPath!),
                      style: TextStyle(color: cs.onSurface, fontSize: 11),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ],
          TpDialogActions(
            children: [
              if (_isCompleted && _savedVideoPath != null)
                TpButton(
                  variant: TpButtonVariant.ghost,
                  onPressed: () {
                    Throttles.throttle(
                      'video_save_play',
                      const Duration(milliseconds: 500),
                      () => _openFile(context),
                    );
                  },
                  child: Text(l10n.playVideo),
                ),
              TpButton(
                onPressed: () {
                  Throttles.throttle(
                    'video_save_close',
                    const Duration(milliseconds: 500),
                    () => Navigator.of(context).pop(),
                  );
                },
                child: Text(
                  _errorMessage != null
                      ? l10n.actionConfirm
                      : (_isCompleted ? l10n.actionDone : l10n.actionClose),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
