import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// PNG/JPEG decode + YOLO classify preprocess for ncnn models.
///
/// Matches ultralytics classify / torchvision:
/// Resize(short side = size, long side int-truncated, bilinear) →
/// CenterCrop(size). Normalization (/255) happens natively inside the ncnn
/// shim (`Mat::substract_mean_normalize`), so the engine consumes RGB24
/// bytes directly.
class ImagePreprocessor {
  ImagePreprocessor._();

  static const inputSize = 640;

  /// Expected byte length of a classified RGB24 frame.
  static int rgb24ByteLength(int width, int height) => width * height * 3;

  /// FFmpeg vf that covers then center-crops to [size]×[size] (no pad 114).
  ///
  /// `force_original_aspect_ratio=increase` is the same geometry as
  /// ultralytics Resize(short side = size); default `crop` is centered.
  static String ffmpegClassifyVf({required num fps, int size = inputSize}) {
    return 'fps=$fps,'
        'scale=$size:$size:force_original_aspect_ratio=increase:flags=bilinear,'
        'crop=$size:$size';
  }

  /// Decode PNG/JPEG bytes, classify-crop to [size]×[size], return RGB HWC bytes.
  static Uint8List decodeAndLetterbox(
    Uint8List imageBytes, {
    int size = inputSize,
  }) {
    final decoded = img.decodeImage(imageBytes);
    if (decoded == null) {
      throw ArgumentError(
        'Unable to decode image (${imageBytes.length} bytes)',
      );
    }

    final rgb = _ensureRgb(decoded);
    final w = rgb.width;
    final h = rgb.height;
    late final int newW;
    late final int newH;
    if (w < h) {
      newW = size;
      newH = (size * h / w).toInt().clamp(1, 1 << 20);
    } else {
      newW = (size * w / h).toInt().clamp(1, 1 << 20);
      newH = size;
    }

    final resized = img.copyResize(
      rgb,
      width: newW,
      height: newH,
      interpolation: img.Interpolation.linear,
    );
    final cropped = img.copyCrop(
      resized,
      x: (newW - size) ~/ 2,
      y: (newH - size) ~/ 2,
      width: size,
      height: size,
    );

    return cropped.getBytes(order: img.ChannelOrder.rgb);
  }

  static img.Image _ensureRgb(img.Image src) {
    if (src.numChannels == 3) return src;

    final out = img.Image(width: src.width, height: src.height, numChannels: 3);
    for (var y = 0; y < src.height; y++) {
      for (var x = 0; x < src.width; x++) {
        final pixel = src.getPixel(x, y);
        out.setPixelRgb(x, y, pixel.r, pixel.g, pixel.b);
      }
    }
    return out;
  }
}
