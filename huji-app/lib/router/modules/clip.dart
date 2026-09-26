import 'dart:io';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:huji_app/api/models/autoclip/video_models.dart';
import 'package:huji_app/models/video.dart'
    show RawVideoRecord, ClipMode, EdittingVideoRecord;
import 'package:huji_app/pages/clip/autoclip_page.dart';
import 'package:huji_app/pages/clip/clip_type_selection_page.dart';
import 'package:huji_app/pages/clip/round_clip_page.dart';
import 'package:huji_app/pages/clip/sport_selection_page.dart';
import 'package:huji_app/pages/clip/video_post_edit_page.dart';
import 'package:huji_app/router/types.dart';
import 'package:huji_app/store/video.dart';

class ClipRoute implements RouteModule {
  const ClipRoute({this.offlineBadminton = false});

  final bool offlineBadminton;

  static const String clipTypeSelection = '/clip/type-selection';
  static const String sportSelection = '/clip/sport-selection';
  static const String videoEditConfig = '/video/edit-config';
  static const String videoPostEdit = '/clip/post-edit';
  static const String roundClip = '/clip/round-clip';
  static const String clipPreview = '/clip/:id/preview';

  static String clipPreviewPath(String clipId) =>
      '/clip/${Uri.encodeComponent(clipId)}/preview';

  @override
  List<GoRoute> getRoutes() {
    return [
      // 视频编辑配置页
      GoRoute(
        path: videoEditConfig,
        name: 'videoEditConfig',
        builder: (context, state) {
          final extra = state.extra;
          final routeArgs = extra is VideoEditConfigRouteArgs ? extra : null;
          final rawVideoRecord = routeArgs?.rawVideoRecord ??
              (extra is RawVideoRecord ? extra : null);
          if (rawVideoRecord == null) {
            return const Scaffold(
              body: Center(child: Text('Missing rawVideoRecord parameter')),
            );
          }
          return VideoEditConfigPage(
            rawVideoRecord: rawVideoRecord,
            autoStartLocal: routeArgs?.autoStartLocal ?? false,
          );
        },
      ),

      // 剪辑类型选择页
      if (!offlineBadminton) GoRoute(
        path: clipTypeSelection,
        name: 'clipTypeSelection',
        builder: (context, state) {
          final extra = state.extra as Map<String, dynamic>?;
          final sportType = extra?['sportType'] as SportType?;
          return ClipTypeSelectionPage(sportType: sportType);
        },
      ),

      // 运动类型选择页
      if (!offlineBadminton) GoRoute(
        path: sportSelection,
        name: 'sportSelection',
        builder: (context, state) {
          final extra = state.extra as Map<String, dynamic>?;
          return SportSelectionPage(
            videoPath: extra?['videoPath'] as String?,
            videoName: extra?['videoName'] as String?,
            clipMode: extra?['clipMode'] as ClipMode?,
          );
        },
      ),

      // 视频后期编辑页
      if (!offlineBadminton) GoRoute(
        path: videoPostEdit,
        name: 'videoPostEdit',
        builder: (context, state) {
          final videoUrl = state.uri.queryParameters['videoUrl'] ?? '';
          return VideoPostEditPage(videoUrl: videoUrl);
        },
      ),

      // 回合剪辑页
      GoRoute(
        path: roundClip,
        name: 'roundClip',
        builder: (context, state) {
          final videoRecord = state.extra as EdittingVideoRecord?;
          return RoundClipPage(videoRecord: videoRecord);
        },
      ),
      if (offlineBadminton)
        GoRoute(
          path: clipPreview,
          name: 'clipPreviewByRecordId',
          builder: (context, state) => ClipPreviewRecordRoutePage(
            recordId: state.pathParameters['id']!,
          ),
        ),
    ];
  }
}

/// Loads the persisted edit record by id so desktop task navigation does not
/// depend on an in-memory `extra` value being present.
class ClipPreviewRecordRoutePage extends StatefulWidget {
  const ClipPreviewRecordRoutePage({super.key, required this.recordId});

  final String recordId;

  @override
  State<ClipPreviewRecordRoutePage> createState() =>
      _ClipPreviewRecordRoutePageState();
}

class _ClipPreviewRecordRoutePageState extends State<ClipPreviewRecordRoutePage> {
  late final Future<EdittingVideoRecord?> _record = _loadRecord();

  Future<EdittingVideoRecord?> _loadRecord() async {
    final record = await LocalVideoStorage().findById(widget.recordId);
    if (record is! EdittingVideoRecord) return null;
    final filePath = record.filePath;
    if (filePath == null ||
        filePath.isEmpty ||
        !await File(filePath).exists()) {
      return null;
    }
    return record;
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<EdittingVideoRecord?>(
      future: _record,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        final record = snapshot.data;
        if (snapshot.hasError || record == null) {
          return Scaffold(
            appBar: AppBar(
              leading: IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () {
                  if (context.canPop()) {
                    context.pop();
                  } else {
                    context.go('/offline-badminton');
                  }
                },
              ),
            ),
            body: const Center(child: Text('原视频文件不存在或已移动')),
          );
        }
        return RoundClipPage(videoRecord: record);
      },
    );
  }
}

class VideoEditConfigRouteArgs {
  const VideoEditConfigRouteArgs({
    required this.rawVideoRecord,
    this.autoStartLocal = false,
  });

  final RawVideoRecord rawVideoRecord;
  final bool autoStartLocal;
}

