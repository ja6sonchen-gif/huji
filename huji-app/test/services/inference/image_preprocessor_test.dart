import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:huji_app/services/inference/image_preprocessor.dart';
import 'package:image/image.dart' as img;

Uint8List _png16x9Bars() {
  const w = 320;
  const h = 180;
  final src = img.Image(width: w, height: h);
  img.fill(src, color: img.ColorRgb8(0, 255, 0));
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < 20; x++) {
      src.setPixelRgb(x, y, 255, 0, 0);
      src.setPixelRgb(w - 1 - x, y, 0, 0, 255);
    }
  }
  return Uint8List.fromList(img.encodePng(src));
}

void main() {
  test('16:9 classify preprocess is center-crop, not letterbox pad 114', () {
    const size = 64;
    final out = ImagePreprocessor.decodeAndLetterbox(
      _png16x9Bars(),
      size: size,
    );
    expect(out.length, size * size * 3);

    int pixel(int x, int y) => (y * size + x) * 3;
    final cx = pixel(size ~/ 2, size ~/ 2);
    expect(
      out[cx + 1],
      greaterThan(200),
      reason: 'center should stay green court',
    );
    expect(out[cx], lessThan(40));

    var leftRed = 0;
    for (var y = 0; y < size; y++) {
      final i = pixel(0, y);
      if (out[i] > 200 && out[i + 1] < 40) leftRed++;
    }
    expect(
      leftRed,
      lessThan(size ~/ 2),
      reason: 'left edge is red — letterbox kept the side bars',
    );

    var topSum = 0;
    for (var x = 0; x < size; x++) {
      final i = pixel(x, 0);
      topSum += out[i] + out[i + 1] + out[i + 2];
    }
    final topMean = topSum / (size * 3);
    expect(
      (topMean - 114).abs(),
      greaterThan(20),
      reason: 'top row looks like letterbox pad 114',
    );
  });

  test('ffmpeg classify filter covers then crops, does not pad', () {
    final vf = ImagePreprocessor.ffmpegClassifyVf(fps: 6);
    expect(vf, contains('force_original_aspect_ratio=increase'));
    expect(vf, contains('crop=640:640'));
    expect(vf, isNot(contains('decrease')));
    expect(vf, isNot(contains('pad=')));
  });
}
