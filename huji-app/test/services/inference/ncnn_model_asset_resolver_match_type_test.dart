import 'package:flutter_test/flutter_test.dart';
import 'package:huji_app/api/models/autoclip/clip_models.dart';
import 'package:huji_app/api/models/autoclip/video_models.dart';
import 'package:huji_app/services/inference/ncnn_model_asset_resolver.dart';

void main() {
  test('badminton singles and doubles resolve different bundled model paths', () {
    final singles = NcnnModelAssetResolver.assetKeysForTask(
      sportType: SportType.badminton,
      matchType: MatchType.singlesMatch,
    );
    final doubles = NcnnModelAssetResolver.assetKeysForTask(
      sportType: SportType.badminton,
      matchType: MatchType.doublesMatch,
    );

    expect(
      singles['model.ncnn.param'],
      'assets/models/badminton/singles/model.ncnn.param',
    );
    expect(
      doubles['model.ncnn.param'],
      'assets/models/badminton/doubles/model.ncnn.param',
    );
    expect(singles['model.ncnn.param'], isNot(doubles['model.ncnn.param']));
    expect(singles['model.ncnn.bin'], isNot(doubles['model.ncnn.bin']));
  });
}
