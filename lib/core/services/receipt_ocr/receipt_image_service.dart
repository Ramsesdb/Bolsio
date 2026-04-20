import 'dart:io';

import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class ReceiptImageService {
  ReceiptImageService({ImagePicker? picker}) : _picker = picker ?? ImagePicker();

  final ImagePicker _picker;

  Future<File?> pickAndCompress({required ImageSource source}) async {
    final picked = await _picker.pickImage(source: source);
    if (picked == null) return null;

    return compressToTemp(File(picked.path));
  }

  Future<File> compressToTemp(File sourceFile) async {
    final bytes = await sourceFile.readAsBytes();
    final decoded = img.decodeImage(bytes);

    if (decoded == null) {
      throw const FormatException('error.image_corrupt');
    }

    final resized = img.copyResize(
      decoded,
      width: decoded.width >= decoded.height ? 1600 : null,
      height: decoded.height > decoded.width ? 1600 : null,
      interpolation: img.Interpolation.cubic,
    );

    final encoded = img.encodeJpg(resized, quality: 82);
    final tmpDir = await getTemporaryDirectory();
    final ocrDir = Directory(p.join(tmpDir.path, 'receipt_ocr'));
    await ocrDir.create(recursive: true);

    final outPath = p.join(
      ocrDir.path,
      'receipt_${DateTime.now().microsecondsSinceEpoch}.jpg',
    );
    final outFile = File(outPath);
    await outFile.writeAsBytes(encoded, flush: true);
    return outFile;
  }
}
