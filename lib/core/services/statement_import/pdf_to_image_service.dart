import 'dart:typed_data';

import 'package:pdfx/pdfx.dart';

class PdfToImageService {
  Future<int> pageCount(Uint8List pdfBytes) async {
    final doc = await PdfDocument.openData(pdfBytes);
    try {
      return doc.pagesCount;
    } finally {
      await doc.close();
    }
  }

  Future<Uint8List> rasterizeFirstPage(
    Uint8List pdfBytes, {
    double scale = 2.0,
  }) async {
    final doc = await PdfDocument.openData(pdfBytes);
    PdfPage? page;
    try {
      page = await doc.getPage(1);
      final image = await page.render(
        width: page.width * scale,
        height: page.height * scale,
        format: PdfPageImageFormat.png,
      );
      if (image == null) {
        throw StateError('pdfx render returned null for first page');
      }
      return image.bytes;
    } finally {
      if (page != null && !page.isClosed) {
        await page.close();
      }
      await doc.close();
    }
  }
}
