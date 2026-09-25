import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:path/path.dart' as path;
import 'package:shared_ui/shared_ui.dart';

import 'package:huji_app/api/models/autoclip/clip_models.dart';
import 'package:huji_app/api/models/autoclip/video_models.dart';
import 'package:huji_app/l10n/l10n_extensions.dart';
import 'package:huji_app/pages/clip/types.dart';
import 'package:huji_app/router/modules/clip.dart';
import 'package:huji_app/router/modules/main.dart';
import 'package:huji_app/store/video.dart';
import 'package:huji_app/theme/themed_mobile.dart';
import 'package:huji_app/widgets/file_picker/file_selection_page.dart';

class OfflineBadmintonHomePage extends StatefulWidget {
  const OfflineBadmintonHomePage({super.key});

  @override
  State<OfflineBadmintonHomePage> createState() =>
      _OfflineBadmintonHomePageState();
}

class _OfflineBadmintonHomePageState
    extends State<OfflineBadmintonHomePage> {
  String? _videoPath;
  MatchType _matchType = MatchType.singlesMatch;
  bool _preparing = false;

  Future<void> _selectVideo() async {
    final result = await FileSelection.selectVideos(
      context: context,
      allowMultiple: false,
    );
    if (!mounted || result == null || result.isEmpty) return;
    setState(() => _videoPath = result.first.path);
  }

  Future<void> _startAnalysis() async {
    final videoPath = _videoPath;
    if (videoPath == null || videoPath.isEmpty) {
      TpToast.show(
        context,
        message: context.hujiL10n.selectVideoFileFirst,
        variant: TpToastVariant.warning,
      );
      return;
    }

    setState(() => _preparing = true);
    try {
      final config = getDefaultConfig(
        SportType.badminton,
        matchType: _matchType,
      );
      final rawRecord = await createRawVideoRecord(
        videoPath,
        SportType.badminton,
        config,
        l10n: context.hujiL10n,
      );
      await LocalVideoStorage().add(rawRecord);
      if (mounted) {
        context.push(
          ClipRoute.videoEditConfig,
          extra: VideoEditConfigRouteArgs(
            rawVideoRecord: rawRecord,
            autoStartLocal: true,
          ),
        );
      }
    } catch (error) {
      if (mounted) {
        TpToast.show(
          context,
          message: context.hujiL10n.prepareVideoFailed(error.toString()),
          variant: TpToastVariant.error,
        );
      }
    } finally {
      if (mounted) setState(() => _preparing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    final styles = TpTextStyles.of(context);
    final selectedName = _videoPath == null ? null : path.basename(_videoPath!);

    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: Text(context.hujiL10n.appTitle),
        centerTitle: true,
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  OutlinedButton.icon(
                    onPressed: _preparing ? null : _selectVideo,
                    icon: const Icon(Icons.video_library_outlined),
                    label: Text(context.hujiL10n.selectVideosTitle),
                  ),
                  if (selectedName != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      selectedName,
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: styles.sm.copyWith(color: cs.onSurfaceVariant),
                    ),
                  ],
                  const SizedBox(height: 32),
                  SegmentedButton<MatchType>(
                    segments: [
                      ButtonSegment(
                        value: MatchType.singlesMatch,
                        label: Text(
                          context.hujiL10n.offlineBadmintonSingles,
                        ),
                        icon: const Icon(Icons.person_outline),
                      ),
                      ButtonSegment(
                        value: MatchType.doublesMatch,
                        label: Text(
                          context.hujiL10n.offlineBadmintonDoubles,
                        ),
                        icon: const Icon(Icons.groups_outlined),
                      ),
                    ],
                    selected: {_matchType},
                    onSelectionChanged: _preparing
                        ? null
                        : (selection) {
                            setState(() => _matchType = selection.single);
                          },
                  ),
                  const SizedBox(height: 32),
                  FilledButton.icon(
                    onPressed: _preparing ? null : _startAnalysis,
                    icon: _preparing
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.auto_awesome),
                    label: Text(
                      context.hujiL10n.offlineBadmintonStartAnalysis,
                    ),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: _preparing
                        ? null
                        : () => context.go(MainRoute.mainTask),
                    icon: const Icon(Icons.history),
                    label: Text(context.hujiL10n.historyClips),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
