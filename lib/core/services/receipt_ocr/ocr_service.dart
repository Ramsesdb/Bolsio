import 'dart:io';

import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

class OcrService {
  OcrService({TextRecognizer? recognizer})
      : _recognizer = recognizer ?? TextRecognizer(script: TextRecognitionScript.latin);

  final TextRecognizer _recognizer;

  Future<String> recognize(File imageFile) async {
    final inputImage = InputImage.fromFilePath(imageFile.path);
    final recognized = await _recognizer.processImage(inputImage);
    return recognized.text;
  }

  Future<void> close() async {
    await _recognizer.close();
  }
}
