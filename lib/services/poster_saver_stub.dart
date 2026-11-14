import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

Future triggerPosterDownload(Uint8List bytes, String fileName) async {
  try {
    final Directory tempDir = await getTemporaryDirectory();
    final File file = File('${tempDir.path}/$fileName');
    await file.writeAsBytes(bytes);

    await Share.shareXFiles([
      XFile(file.path, mimeType: 'image/png'),
    ], text: '🎒 보따리 여행 동선표');
    return true;
  } catch (_) {
    return false;
  }
}
