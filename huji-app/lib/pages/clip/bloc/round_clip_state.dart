import 'package:equatable/equatable.dart';
import '../../../models/video.dart';
import '../../../models/autoclip_models.dart';
import '../../../widgets/multi_video_player/models/video_playback_item.dart';

class DeletedRoundForUndo {
  final int originalIndex;
  final SegmentInfo segment;
  final bool wasFavorite;

  const DeletedRoundForUndo({
    required this.originalIndex,
    required this.segment,
    required this.wasFavorite,
  });
}

/// 回合编辑页面状态
class RoundClipState extends Equatable {
  final EdittingVideoRecord? videoRecord;
  final SegmentInfo? currentPlayingSegment;
  final bool isSegmentPlaying;
  final List<VideoPlaybackItem> playbackItems;
  final bool isLoading;
  final String? errorMessage;
  final bool isSaving;
  final String? successMessage;
  final double videoDurationSeconds;
  final List<DeletedRoundForUndo> lastDeletedRounds;

  const RoundClipState({
    this.videoRecord,
    this.currentPlayingSegment,
    this.isSegmentPlaying = false,
    this.playbackItems = const [],
    this.isLoading = false,
    this.errorMessage,
    this.isSaving = false,
    this.successMessage,
    this.videoDurationSeconds = 0,
    this.lastDeletedRounds = const [],
  });

  /// 获取所有playBall片段
  List<SegmentInfo> get playBallSegments {
    if (videoRecord == null) return [];

    // 直接返回 allMatchSegments 中的 playBall 片段，保持原有顺序
    return videoRecord!.allMatchSegments
        .where((segment) => segment.actionType == ActionType.playBall)
        .toList();
  }

  /// 获取收藏的playBall片段
  List<SegmentInfo> get favoriteSegments {
    if (videoRecord == null) return [];

    return videoRecord!.favoritesMatchSegments
        .where((segment) => segment.actionType == ActionType.playBall)
        .toList();
  }

  /// 检查片段是否为收藏
  bool isSegmentFavorite(SegmentInfo segment) {
    if (videoRecord == null) return false;

    return videoRecord!.favoritesMatchSegments.any(
      (favoriteSegment) =>
          favoriteSegment.startSeconds == segment.startSeconds &&
          favoriteSegment.endSeconds == segment.endSeconds,
    );
  }

  /// 复制状态
  RoundClipState copyWith({
    EdittingVideoRecord? videoRecord,
    SegmentInfo? currentPlayingSegment,
    bool clearCurrentPlayingSegment = false,
    bool? isSegmentPlaying,
    List<VideoPlaybackItem>? playbackItems,
    bool? isLoading,
    String? errorMessage,
    bool? isSaving,
    String? successMessage,
    double? videoDurationSeconds,
    List<DeletedRoundForUndo>? lastDeletedRounds,
  }) {
    return RoundClipState(
      videoRecord: videoRecord ?? this.videoRecord,
      currentPlayingSegment: clearCurrentPlayingSegment
          ? null
          : (currentPlayingSegment ?? this.currentPlayingSegment),
      isSegmentPlaying: isSegmentPlaying ?? this.isSegmentPlaying,
      playbackItems: playbackItems ?? this.playbackItems,
      isLoading: isLoading ?? this.isLoading,
      errorMessage: errorMessage ?? this.errorMessage,
      isSaving: isSaving ?? this.isSaving,
      successMessage: successMessage ?? this.successMessage,
      videoDurationSeconds: videoDurationSeconds ?? this.videoDurationSeconds,
      lastDeletedRounds: lastDeletedRounds ?? this.lastDeletedRounds,
    );
  }

  @override
  List<Object?> get props => [
    videoRecord,
    currentPlayingSegment,
    isSegmentPlaying,
    playbackItems,
    isLoading,
    errorMessage,
    isSaving,
    successMessage,
    videoDurationSeconds,
    lastDeletedRounds,
  ];
}
