import 'dart:async';
import 'dart:convert';
import 'dart:developer';

import 'package:huji_app/api/models/autoclip/clip_models.dart';
import 'package:huji_app/api/models/autoclip/video_models.dart';
import 'package:huji_app/core/realtime/badminton_realtime_action_segment_detector.dart';
import 'package:huji_app/core/realtime/pingpong_realtime_action_segment_detector.dart';
import 'package:huji_app/core/realtime/realtime_action_segment_detector.dart';
import 'package:huji_app/models/autoclip_models.dart';
import 'package:huji_app/models/task.dart';
import 'package:huji_app/models/video.dart';
import 'package:huji_app/services/ffmpeg/ffmpeg_runner.dart';
import 'package:huji_app/services/large_model_service.dart';
import 'package:huji_app/services/memory_stream_service.dart';
import 'package:huji_app/services/inference/image_preprocessor.dart';
import 'package:huji_app/services/inference/ncnn_model_asset_resolver.dart';
import 'package:huji_app/services/inference/ncnn_model_predictor.dart';
import 'package:huji_app/services/storage_service.dart';
import 'package:huji_app/store/task/task_manager.dart';
import 'package:huji_app/store/video.dart';
import 'package:huji_app/utils/clip_config_codec.dart';
import 'package:huji_app/utils/debounce/throttles.dart';
import 'package:huji_app/utils/logger_utils.dart';
import 'package:huji_app/utils/video_frame_chunk_pipeline.dart';
import 'package:huji_app/utils/video_utils.dart';

class VideoSegmentDetectTaskManager extends AbstractTaskManager {
  static const String videoSegmentDetectTable = 'video_segment_detect_tasks';
  static const int _fileFramesPerSecond = 6;
  static const double _fileChunkDurationSeconds = 30;
  final TaskStorage _taskStorage;
  RealtimeActionSegmentDetector? _actionSegmentDetector;
  ModelPredictor? _inferencePredictor;
  final LargeModelService _largeModelService = LargeModelService();
  StreamSubscription<Tuple<double, String>?>? _frameStreamSubscription;
  final Map<String, Completer<void>> _taskCompleters = {};
  final Set<String> _cancelRequestedTaskIds = {};
  // 用于节流进度更新的 Throttler 映射，key 为任务 ID
  final Map<String, Throttler> _progressThrottlers = {};

  /// 诊断：抽帧流到达计数与上次心跳时间（与检测器侧心跳对照定位卡点）
  int _receivedFrames = 0;
  DateTime? _lastFrameHeartbeat;

  void _maybeLogFrameHeartbeat(Tuple<double, String> frame) {
    _receivedFrames++;
    final now = DateTime.now();
    final last = _lastFrameHeartbeat;
    if (last != null && now.difference(last) < const Duration(seconds: 3)) {
      return;
    }
    _lastFrameHeartbeat = now;
    AppLogger().i(
      '抽帧心跳: 已接收 $_receivedFrames 帧'
      '(${(frame.item1).toStringAsFixed(1)}s)',
    );
  }

  VideoSegmentDetectTaskManager(this._taskStorage);

  @override
  Future<void> processTask(Task task) async {
    final currentTask = task as VideoSegmentDetectTask;
    _cancelRequestedTaskIds.remove(currentTask.id);
    Stream<Tuple<double, String>?>? frameStream;
    if (currentTask.frameStreamId != null) {
      frameStream =
          await MemoryStreamService().getStream(currentTask.frameStreamId!)
              as Stream<Tuple<double, String>?>;
    }
    await _startTask(currentTask, frameStream);
  }

  Future<void> _startTask(
    VideoSegmentDetectTask task,
    Stream<Tuple<double, String>?>? frameStream,
  ) async {
    VideoSegmentDetectTask currentTask = task.copyWith(supportsPause: false);

    try {
      currentTask =
          await _taskStorage.updateTask(
                task.id,
                (oldTask) => (oldTask as VideoSegmentDetectTask).copyWith(
                  supportsPause: false,
                ),
              )
              as VideoSegmentDetectTask;

      // 开始实时检测
      await _startRealtimeDetection(currentTask, frameStream);

      if (!_isTaskCancelled(task.id)) {
        currentTask =
            await _taskStorage.updateTask(
                task.id,
                (oldTask) => (oldTask as VideoSegmentDetectTask).copyWith(
                  status: TaskStatusEnum.completed,
                  progress: 1.0,
                ),
              )
                as VideoSegmentDetectTask;
      }
    } catch (e, stackTrace) {
      AppLogger().e('Error processing task: $e', stackTrace, e);
      if (!_isTaskCancelled(task.id)) {
        currentTask =
            await _taskStorage.updateTask(
                task.id,
                (oldTask) => (oldTask as VideoSegmentDetectTask).copyWith(
                  status: TaskStatusEnum.failed,
                  extraInfo: e.toString(),
                ),
              )
                as VideoSegmentDetectTask;
      }
    } finally {
      _cancelRequestedTaskIds.remove(task.id);
    }
  }

  bool _isTaskCancelled(String taskId) {
    if (_cancelRequestedTaskIds.contains(taskId)) return true;
    final task = _taskStorage.getTaskById(taskId);
    return task == null || task.status == TaskStatusEnum.cancelled;
  }

  // 开始实时检测
  Future<void> _startRealtimeDetection(
    VideoSegmentDetectTask task,
    Stream<Tuple<double, String>?>? frameStream,
  ) async {
    try {
      await _initializeRealtimeDetector(task);
      _receivedFrames = 0;
      _lastFrameHeartbeat = null;

      final completed = task.frameStreamId == null
          ? await _processFileVideoInChunks(task)
          : await _consumeRealtimeFrameStream(task, frameStream!);

      if (!completed || _isTaskCancelled(task.id)) {
        await _stopRealtimeDetector(force: true);
        return;
      }

      // 停止检测器
      await _stopRealtimeDetector();

      final edittingRecordId = task.edittingRecordId!;
      final record = await LocalVideoStorage().findById(edittingRecordId);
      if (record == null || record is! EdittingVideoRecord) {
        AppLogger().w(
          'EdittingVideoRecord not found for id: $edittingRecordId',
        );
        return;
      }
      final edittingRecord = record;

      double? videoDuration;
      if (task.total != null) {
        // total 的单位是毫秒（在 autoclip_page.dart 中设置为 duration * 1000）
        // 需要转换为秒
        videoDuration = task.total! / 1000.0;
      } else if (task.frameStreamId != null) {
        // 实时录制模式：total 可能为 null，尝试从视频文件获取时长
        try {
          final videoBaseInfo = await VideoUtils.getVideoBaseInfo(
            task.videoPath,
          );
          videoDuration = videoBaseInfo.duration;
          // 更新 task 的 total（毫秒）
          await _taskStorage.updateTask(
            task.id,
            (oldTask) => (oldTask as VideoSegmentDetectTask).copyWith(
              total: (videoBaseInfo.duration * 1000).toInt(),
            ),
          );
        } catch (e) {
          AppLogger().w('无法获取视频时长: $e');
          // 如果获取失败，使用最后一个片段的结束时间
          videoDuration = null;
        }
      }

      await _processSegments(
        edittingRecord,
        task.clipConfig ?? VideoClipConfigReqVo(),
        videoDuration,
      );
    } catch (e, stackTrace) {
      AppLogger().e('Error in realtime detection: $e', stackTrace, e);
      await _stopRealtimeDetector(force: _isTaskCancelled(task.id));
      rethrow;
    } finally {
      _taskCompleters.remove(task.id);
      _frameStreamSubscription = null;
      _progressThrottlers[task.id]?.dispose();
      _progressThrottlers.remove(task.id);
    }
  }

  Future<bool> _processFileVideoInChunks(
    VideoSegmentDetectTask task,
  ) async {
    final durationSeconds = task.total != null
        ? task.total! / 1000.0
        : (await VideoUtils.getVideoBaseInfo(task.videoPath)).duration;
    final taskDirectory = await storage.createTempInCleanupDirectory(
      prefix: 'detect_${task.id}_',
    );
    const pipeline = VideoFrameChunkPipeline(
      chunkDurationSeconds: _fileChunkDurationSeconds,
      framesPerSecond: _fileFramesPerSecond,
    );

    return pipeline.process(
      videoDurationSeconds: durationSeconds,
      taskDirectory: taskDirectory,
      isCancelled: () => _isTaskCancelled(task.id),
      onChunkStarted: (chunk) {
        AppLogger().i(
          '开始抽帧 chunk ${chunk.index}: '
          '${chunk.startSeconds.toStringAsFixed(3)}-'
          '${chunk.endSeconds.toStringAsFixed(3)}s',
        );
      },
      extractChunk: (chunk, directory) {
        return VideoUtils.extractRawRgbFrameChunk(
          videoPath: task.videoPath,
          framesPerSecond: _fileFramesPerSecond,
          tempDir: directory,
          startSeconds: chunk.startSeconds,
          durationSeconds: chunk.durationSeconds,
          width: ImagePreprocessor.inputSize,
          height: ImagePreprocessor.inputSize,
        );
      },
      consumeFrame: (frame) async {
        _maybeLogFrameHeartbeat(
          Tuple(item1: frame.timestampSeconds, item2: frame.filePath),
        );
        await _actionSegmentDetector?.addRgb24Prediction(
          frame.filePath,
          frame.timestampSeconds,
        );
      },
    );
  }

  Future<bool> _consumeRealtimeFrameStream(
    VideoSegmentDetectTask task,
    Stream<Tuple<double, String>?> frameStream,
  ) async {
    final completer = Completer<void>();
    _taskCompleters[task.id] = completer;
    _frameStreamSubscription = frameStream.listen(
      (frame) async {
        if (frame == null) return;
        _maybeLogFrameHeartbeat(frame);
        if (_isTaskCancelled(task.id)) {
          await _frameStreamSubscription?.cancel();
          if (!completer.isCompleted) completer.complete();
          return;
        }
        await _actionSegmentDetector?.addPrediction(
          frame.item2,
          frame.item1,
        );
      },
      onError: (Object error, StackTrace stackTrace) {
        AppLogger().e('Frame stream error: $error', stackTrace, error);
        if (!completer.isCompleted) completer.completeError(error, stackTrace);
      },
      onDone: () {
        if (!completer.isCompleted) completer.complete();
      },
      cancelOnError: false,
    );
    await completer.future;
    return !_isTaskCancelled(task.id);
  }

  // 初始化实时检测器
  Future<void> _initializeRealtimeDetector(VideoSegmentDetectTask task) async {
    // 三端统一走 ncnn：先把模型资产落盘，再构造预测器。FFI 推理在 native
    // 线程池执行，不阻塞 isolate；无 worker-messenger 需求。
    final inferenceSpec = await NcnnModelAssetResolver.resolveForTask(
      sportType: task.sportType ?? SportType.pingpong,
      matchType: task.matchType,
    );
    _inferencePredictor = NcnnModelPredictor(
      paramFilePath: inferenceSpec.paramFilePath,
      binFilePath: inferenceSpec.binFilePath,
      fallbackClassNames: inferenceSpec.classNames,
    );
    final predictor = _inferencePredictor!;

    // 根据运动类型创建相应的实时检测器
    if (task.sportType == SportType.badminton) {
      final badmintonConfig =
          ClipConfigCodec.normalize(task.clipConfig, task.sportType)
              as BadmintonVideoClipConfigReqVo? ??
          BadmintonVideoClipConfigReqVo();
      _actionSegmentDetector = BadmintonRealtimeActionSegmentDetector(
        config: badmintonConfig,
        largeModelService: _largeModelService,
        segmentDetectConfig: defaultBadmintonSegmentDetectConfig,
        modelPredictor: predictor,
      );
    } else {
      final pingPongConfig =
          ClipConfigCodec.normalize(task.clipConfig, task.sportType)
              as PingPongVideoClipConfigReqVo? ??
          PingPongVideoClipConfigReqVo();
      _actionSegmentDetector = PingPongRealtimeActionSegmentDetector(
        config: pingPongConfig,
        largeModelService: _largeModelService,
        segmentDetectConfig: defaultPingPongSegmentDetectConfig,
        modelPredictor: predictor,
      );
    }
    final edittingRecordId = task.edittingRecordId!;

    // 为当前任务创建进度更新节流器（500ms 更新一次）
    final progressThrottler = Throttler(
      tag: 'progress_${task.id}',
      duration: const Duration(milliseconds: 500),
    );
    _progressThrottlers[task.id] = progressThrottler;

    _actionSegmentDetector!.addListener((currentTime, segment) async {
      VideoSegmentDetectTask? currentTask =
          _taskStorage.getTaskById(task.id) as VideoSegmentDetectTask?;
      if (currentTask == null) {
        return;
      }
      if (segment != null) {
        final updatedRecord =
            await LocalVideoStorage().update(edittingRecordId, (record) {
                  final edittingRecord = record as EdittingVideoRecord;
                  edittingRecord.allMatchSegments.add(segment);
                  return edittingRecord;
                })
                as EdittingVideoRecord;
        log(
          'Add segment: $segment, current playBall count: ${updatedRecord.allMatchSegments.where((segment) => segment.actionType == ActionType.playBall).toList().length}, current time: $currentTime',
        );
      }

      // 使用节流器限制进度更新频率
      progressThrottler.call(() async {
        double? progress;
        int? processed;
        if (currentTime != null) {
          progress = task.frameStreamId == null && task.total != null
              ? currentTime / (task.total! / 1000.0)
              : 0;
          processed = currentTime.toInt();
        }
        currentTask =
            await _taskStorage.updateTask(
                  task.id,
                  (oldTask) => (oldTask as VideoSegmentDetectTask).copyWith(
                    progress: progress,
                    processed: processed,
                  ),
                )
                as VideoSegmentDetectTask;
      });
    });

    // 启动检测器
    await _actionSegmentDetector!.start();
  }

  // 停止实时检测器
  Future<void> _stopRealtimeDetector({bool force = false}) async {
    final detector = _actionSegmentDetector;
    final predictor = _inferencePredictor;
    _actionSegmentDetector = null;
    _inferencePredictor = null;
    try {
      if (detector != null) {
        try {
          await detector.stop(force: force);
        } finally {
          await detector.dispose();
        }
      }
    } finally {
      // Even if detector finalization fails, native inference resources must
      // still be released.
      await predictor?.dispose();
    }
  }

  /// 处理检测到的片段，应用与批量检测相同的过滤和处理逻辑
  Future<void> _processSegments(
    EdittingVideoRecord edittingRecord,
    VideoClipConfigReqVo config,
    double? videoDuration,
  ) async {
    if (edittingRecord.allMatchSegments.isEmpty) {
      return;
    }

    // 获取配置参数
    final reserveHeaderSeconds = config.reserveTimeBeforeSingleRound ?? 0;
    final reserveTailSeconds = config.reserveTimeAfterSingleRound ?? 0;
    final minimumDurationSingleRound = config.minimumDurationSingleRound ?? 2.0;

    // 如果没有提供视频时长，使用最后一个片段的结束时间
    final maxDuration =
        videoDuration ??
        (edittingRecord.allMatchSegments.isNotEmpty
            ? edittingRecord.allMatchSegments
                  .map((s) => s.endSeconds)
                  .reduce((a, b) => a > b ? a : b)
            : double.infinity);

    // 筛选出 PLAY_BALL 类型的片段并按开始时间排序
    final playBallSegments =
        edittingRecord.allMatchSegments
            .where((segment) => segment.actionType == ActionType.playBall)
            .toList()
          ..sort((a, b) => a.startSeconds.compareTo(b.startSeconds));

    // 处理后的片段列表
    final processedSegments = <SegmentInfo>[];
    double lastEndSeconds = 0;

    for (final segment in playBallSegments) {
      final playBallStartSeconds = segment.startSeconds;
      final playBallEndSeconds = segment.endSeconds;

      // 计算开始时间：取最大值（预留时间后的开始时间，0，上次结束时间）
      double startSeconds = (playBallStartSeconds - reserveHeaderSeconds).clamp(
        0.0,
        maxDuration,
      );
      startSeconds = startSeconds > lastEndSeconds
          ? startSeconds
          : lastEndSeconds;

      // 如果开始时间与上次结束时间太接近，增加0.5秒间隔
      if (startSeconds - lastEndSeconds < 0.5) {
        startSeconds = startSeconds + 0.5;
      }

      // 计算结束时间
      final endSeconds = (playBallEndSeconds + reserveTailSeconds).clamp(
        0.0,
        maxDuration,
      );

      // 如果结束时间小于上次结束时间，跳过
      if (endSeconds < lastEndSeconds) {
        continue;
      }

      final duration = endSeconds - startSeconds;

      // 检查最小时长
      if (duration >= minimumDurationSingleRound) {
        // 创建处理后的片段
        final processedSegment = SegmentInfo(
          actionType: segment.actionType,
          startSeconds: startSeconds,
          endSeconds: endSeconds,
        );

        processedSegments.add(processedSegment);
        lastEndSeconds = endSeconds;
      }
    }

    await LocalVideoStorage().update(
      edittingRecord.id,
      (record) => (record as EdittingVideoRecord).copyWith(
        allMatchSegments: processedSegments,
      ),
    );

    AppLogger().i(
      '片段处理完成: 原始片段数 ${playBallSegments.length}, 处理后片段数 ${processedSegments.length}',
    );
  }

  // 获取检测到的片段
  @override
  Future<List<Task>> loadTasks(
    List<Map<String, dynamic>> mainTasks,
    List<Map<String, dynamic>> subTasks,
  ) async {
    List<VideoSegmentDetectTask> realtimeDetectTasks = [];
    for (final mainTask in mainTasks) {
      final subTask = subTasks.firstWhere(
        (subTask) => subTask['taskId'] == mainTask['id'],
      );
      final realtimeDetectTask = VideoSegmentDetectTask.fromJson({
        ...mainTask,
        ...subTask,
      });
      realtimeDetectTasks.add(realtimeDetectTask);
    }
    return realtimeDetectTasks;
  }

  @override
  void dispose() {
    super.dispose();
    _frameStreamSubscription?.cancel();
    _frameStreamSubscription = null;
    _taskCompleters.clear();
    _stopRealtimeDetector();
  }

  /// 获取实时检测状态
  Map<String, dynamic> getRealtimeStatus() {
    if (_actionSegmentDetector == null) {
      return {
        'isRunning': false,
        'detectedSegments': 0,
        'ongoingActions': [],
        'windowStatus': {},
      };
    }

    return {
      'isRunning': _actionSegmentDetector!.isRunning,
      'detectedSegments': _actionSegmentDetector!.detectedSegmentCount,
      'ongoingActions': _actionSegmentDetector!.ongoingActions
          .map((e) => e.name)
          .toList(),
      'windowStatus': _actionSegmentDetector!.windowStatus.map(
        (key, value) => MapEntry(key.name, value),
      ),
    };
  }

  /// 获取检测到的片段详情
  List<Map<String, dynamic>> getDetectedSegmentsDetails() {
    if (_actionSegmentDetector == null) {
      return [];
    }

    return _actionSegmentDetector!.detectedSegments
        .map(
          (segment) => {
            'actionType': segment.actionType.name,
            'startSeconds': segment.startSeconds,
            'endSeconds': segment.endSeconds,
            'duration': segment.endSeconds - segment.startSeconds,
          },
        )
        .toList();
  }

  @override
  String getTableName() {
    return videoSegmentDetectTable;
  }

  @override
  Future<void> pauseTask(Task task) async {}

  @override
  Future<void> resumeTask(Task task) async {
    VideoSegmentDetectTask realtimeDetectTask = task as VideoSegmentDetectTask;
    realtimeDetectTask =
        await _taskStorage.updateTask(
              realtimeDetectTask.id,
              (oldTask) => (oldTask as VideoSegmentDetectTask).copyWith(
                status: TaskStatusEnum.pending,
              ),
            )
            as VideoSegmentDetectTask;
    _cancelRequestedTaskIds.remove(realtimeDetectTask.id);
    Stream<Tuple<double, String>?>? frameStream;
    if (realtimeDetectTask.frameStreamId != null) {
      frameStream =
          await MemoryStreamService().getStream(
                realtimeDetectTask.frameStreamId!,
              )
              as Stream<Tuple<double, String>?>;
    }
    await _startTask(realtimeDetectTask, frameStream);
  }

  @override
  Future<void> retryTask(Task task) async {
    final realtimeDetectTask = task as VideoSegmentDetectTask;
    _cancelRequestedTaskIds.remove(realtimeDetectTask.id);
    Stream<Tuple<double, String>?>? frameStream;
    if (realtimeDetectTask.frameStreamId != null) {
      frameStream =
          await MemoryStreamService().getStream(
                realtimeDetectTask.frameStreamId!,
              )
              as Stream<Tuple<double, String>?>;
    }
    await _startTask(realtimeDetectTask, frameStream);
  }

  @override
  Future<void> cancelTask(Task task) async {
    log('cancelTask: ${task.id}');
    _cancelRequestedTaskIds.add(task.id);

    // Best-effort cancellation of the current chunk extraction. If inference
    // is active, the awaited current frame finishes and the pipeline observes
    // the flag before consuming another frame or creating another chunk.
    if (task is VideoSegmentDetectTask && task.frameStreamId == null) {
      try {
        await FFmpegRunner.instance.cancel();
      } catch (error, stackTrace) {
        AppLogger().w('取消当前 FFmpeg chunk 失败，将在 chunk 边界停止: $error');
        log('FFmpeg cancel stack trace: $stackTrace');
      }
    }

    // 取消 frameStream 订阅（如果正在运行）
    await _frameStreamSubscription?.cancel();
    _frameStreamSubscription = null;

    // 完成任务的 completer（如果存在），以便中断流处理
    final completer = _taskCompleters[task.id];
    if (completer != null && !completer.isCompleted) {
      completer.complete();
    }
    _taskCompleters.remove(task.id);

    // Detector/predictor disposal is owned by the running task lifecycle so it
    // cannot race with a frame currently being inferred.
  }

  @override
  String getCreateTableSql() {
    return '''
          CREATE TABLE IF NOT EXISTS $videoSegmentDetectTable (
            taskId TEXT PRIMARY KEY,
            videoPath TEXT NOT NULL,
            clipConfig TEXT,
            sportType INTEGER,
            matchType INTEGER NOT NULL DEFAULT 1,
            edittingRecordId TEXT
          )
        ''';
  }

  @override
  Map<String, dynamic> getInsertJson(Task task) {
    VideoSegmentDetectTask realtimeDetectTask = task as VideoSegmentDetectTask;
    return {
      'taskId': realtimeDetectTask.id,
      'videoPath': realtimeDetectTask.videoPath,
      'clipConfig': realtimeDetectTask.clipConfig != null
          ? jsonEncode(realtimeDetectTask.clipConfig!.toJson())
          : '',
      'sportType': realtimeDetectTask.sportType?.value,
      'matchType': realtimeDetectTask.matchType.value,
      'edittingRecordId': realtimeDetectTask.edittingRecordId,
    };
  }

  @override
  Map<int, String> getUpgradeTableSql(int oldVersion) {
    if (oldVersion == 0) return {};
    return {
      11:
          'ALTER TABLE $videoSegmentDetectTable ADD COLUMN matchType INTEGER',
    };
  }

  @override
  bool supportsPause(Task task) => task.supportsPause;

  @override
  Task copyTask(Task task) {
    final realtimeDetectTask = task as VideoSegmentDetectTask;
    return realtimeDetectTask.copyWith();
  }
}
