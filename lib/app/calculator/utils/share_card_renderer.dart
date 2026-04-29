import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:wallex/core/utils/logger.dart';

/// Captura un widget montado bajo `RepaintBoundary(key: ...)` a un PNG
/// temporal y devuelve un `XFile` listo para `SharePlus.instance.share`
/// (Tanda 5, task 5.3).
///
/// Devuelve `null` ante CUALQUIER falla (boundary no montado, OOM al
/// llamar `toImage`, IO al escribir el PNG, etc.). El caller debe caer al
/// fallback de texto plano (per spec REQ-CALC-7 "Render failure falls back
/// to text"), sin mostrar toast.
///
/// `pixelRatio`: el caller decide. Convención per design.md:
///   * `MediaQuery.of(context).size.shortestSide < 360` → `2.0`
///   * caso contrario → `3.0`
Future<XFile?> renderShareCard(
  GlobalKey boundaryKey, {
  required double pixelRatio,
}) async {
  try {
    final ctx = boundaryKey.currentContext;
    if (ctx == null) return null;

    final renderObject = ctx.findRenderObject();
    if (renderObject is! RenderRepaintBoundary) return null;

    // Si el boundary aún tiene pintado pendiente (por ejemplo recién
    // montado), `toImage` puede capturar un frame vacío. `debugNeedsPaint`
    // sólo está disponible en debug, así que nos apoyamos en el flujo
    // estándar de `toImage` que respeta el pipeline de rendering.
    final ui.Image image = await renderObject.toImage(
      pixelRatio: pixelRatio,
    );

    final ByteData? byteData =
        await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    if (byteData == null) return null;

    final bytes = byteData.buffer.asUint8List();
    final dir = await getTemporaryDirectory();
    final ts = DateTime.now().millisecondsSinceEpoch;
    final file = File('${dir.path}/wallex_calc_$ts.png');
    await file.writeAsBytes(bytes, flush: true);

    return XFile(file.path, mimeType: 'image/png');
  } catch (e, st) {
    Logger.printDebug('renderShareCard failed: $e\n$st');
    return null;
  }
}
