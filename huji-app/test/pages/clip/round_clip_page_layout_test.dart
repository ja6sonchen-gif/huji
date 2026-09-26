import 'package:flutter_test/flutter_test.dart';
import 'package:huji_app/pages/clip/round_clip_page.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Windows preview height follows window size with useful bounds', () {
    expect(roundClipDesktopPreviewHeight(768), 320);
    expect(roundClipDesktopPreviewHeight(1080), 432);
    expect(roundClipDesktopPreviewHeight(2160), 560);
  });
}

