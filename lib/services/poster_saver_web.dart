// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;
import 'dart:typed_data';

Future<bool> triggerPosterDownload(Uint8List bytes, String fileName) async {
  try {
    final blob = html.Blob([bytes], 'image/png');

    // 1. 즉시 파일 다운로드 트리거 (PC 크롬 및 iOS 사파리 다운로드 팝업)
    final url = html.Url.createObjectUrlFromBlob(blob);
    final anchor = html.AnchorElement(href: url)
      ..setAttribute('download', fileName)
      ..style.display = 'none';
    html.document.body?.children.add(anchor);
    anchor.click();
    anchor.remove();
    Future.delayed(const Duration(seconds: 2), () {
      html.Url.revokeObjectUrl(url);
    });
    return true;
  } catch (_) {
    return false;
  }
}
