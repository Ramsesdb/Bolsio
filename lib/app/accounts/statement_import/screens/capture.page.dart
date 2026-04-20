import 'dart:convert';
import 'dart:io';

import 'package:exif/exif.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:wallex/app/accounts/statement_import/statement_import_flow.dart';
import 'package:wallex/core/presentation/helpers/snackbar.dart';
import 'package:wallex/core/services/statement_import/pdf_to_image_service.dart';
import 'package:wallex/i18n/generated/translations.g.dart';

class CapturePage extends StatefulWidget {
  const CapturePage({super.key});

  @override
  State<CapturePage> createState() => _CapturePageState();
}

class _CapturePageState extends State<CapturePage> {
  bool _busy = false;

  Future<void> _onTakePhoto() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final picker = ImagePicker();
      final picked = await picker.pickImage(
        source: ImageSource.camera,
        maxWidth: 1600,
        imageQuality: 82,
      );
      if (picked == null) return;

      final bytes = await File(picked.path).readAsBytes();
      final exifDate = await _readExifDate(bytes);

      if (!mounted) return;
      final pivot = exifDate ?? await _promptDate(context);
      if (pivot == null) return;

      final resized = _resizeIfNeeded(bytes);
      final base64 = base64Encode(resized);

      if (!mounted) return;
      StatementImportFlow.of(context).goToProcessing(
        imageBase64: base64,
        pivotDate: pivot,
      );
    } catch (e, st) {
      debugPrint('CapturePage.takePhoto failed: $e\n$st');
      _showReadError();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _onPickFile() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf', 'jpg', 'jpeg', 'png'],
        withData: true,
      );
      if (result == null || result.files.isEmpty) return;

      final file = result.files.single;
      final bytes = file.bytes ?? await File(file.path!).readAsBytes();
      final ext = (file.extension ?? '').toLowerCase();

      if (ext == 'pdf') {
        await _handlePdf(bytes);
      } else {
        await _handleImageBytes(bytes);
      }
    } catch (e, st) {
      debugPrint('CapturePage.pickFile failed: $e\n$st');
      _showReadError();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _handleImageBytes(Uint8List bytes) async {
    final exifDate = await _readExifDate(bytes);

    if (!mounted) return;
    final pivot = exifDate ?? await _promptDate(context);
    if (pivot == null) return;

    final resized = _resizeIfNeeded(bytes);
    final base64 = base64Encode(resized);

    if (!mounted) return;
    StatementImportFlow.of(context).goToProcessing(
      imageBase64: base64,
      pivotDate: pivot,
    );
  }

  Future<void> _handlePdf(Uint8List bytes) async {
    final service = PdfToImageService();
    final pages = await service.pageCount(bytes);

    if (pages > 1) {
      if (!mounted) return;
      final t = Translations.of(context);
      final proceed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(t.statement_import.capture.pdf_warning_title),
          content: Text(
            t.statement_import.capture.pdf_warning_body(pages: pages),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(t.ui_actions.cancel),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(t.statement_import.capture.pdf_warning_continue),
            ),
          ],
        ),
      );
      if (proceed != true) return;
    }

    final raster = await service.rasterizeFirstPage(bytes);

    if (!mounted) return;
    final pivot = await _promptDate(context);
    if (pivot == null) return;

    final resized = _resizeIfNeeded(raster);
    final base64 = base64Encode(resized);

    if (!mounted) return;
    StatementImportFlow.of(context).goToProcessing(
      imageBase64: base64,
      pivotDate: pivot,
    );
  }

  Future<DateTime?> _readExifDate(Uint8List bytes) async {
    try {
      final tags = await readExifFromBytes(bytes);
      if (tags.isEmpty) return null;
      final raw = tags['EXIF DateTimeOriginal']?.printable ??
          tags['Image DateTime']?.printable;
      if (raw == null || raw.isEmpty) return null;
      final match = RegExp(
        r'^(\d{4}):(\d{2}):(\d{2})\s+(\d{2}):(\d{2}):(\d{2})$',
      ).firstMatch(raw.trim());
      if (match == null) return null;
      return DateTime(
        int.parse(match.group(1)!),
        int.parse(match.group(2)!),
        int.parse(match.group(3)!),
        int.parse(match.group(4)!),
        int.parse(match.group(5)!),
        int.parse(match.group(6)!),
      );
    } catch (e) {
      debugPrint('CapturePage.readExif failed: $e');
      return null;
    }
  }

  Future<DateTime?> _promptDate(BuildContext context) async {
    final now = DateTime.now();
    return showDatePicker(
      context: context,
      initialDate: now,
      firstDate: DateTime(now.year - 5),
      lastDate: now,
      helpText: Translations.of(context).statement_import.capture.date_picker_title,
    );
  }

  Uint8List _resizeIfNeeded(Uint8List bytes) {
    try {
      final decoded = img.decodeImage(bytes);
      if (decoded == null) return bytes;

      final maxDim = decoded.width > decoded.height
          ? decoded.width
          : decoded.height;
      if (maxDim <= 1600) return bytes;

      final resized = img.copyResize(
        decoded,
        width: decoded.width >= decoded.height ? 1600 : null,
        height: decoded.height > decoded.width ? 1600 : null,
        interpolation: img.Interpolation.cubic,
      );
      return Uint8List.fromList(img.encodeJpg(resized, quality: 82));
    } catch (e) {
      debugPrint('CapturePage.resize failed: $e');
      return bytes;
    }
  }

  void _showReadError() {
    final t = Translations.of(context);
    WallexSnackbar.error(SnackbarParams(t.statement_import.capture.error_read));
  }

  @override
  Widget build(BuildContext context) {
    final t = Translations.of(context);
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(t.statement_import.title),
      ),
      body: AbsorbPointer(
        absorbing: _busy,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _HeroDocument(),
              const SizedBox(height: 20),
              Text(
                t.statement_import.title,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.4,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                t.statement_import.subtitle,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: cs.onSurfaceVariant,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 12),
              _PrivacyBadge(),
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: _busy ? null : _onTakePhoto,
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(52),
                  textStyle: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                icon: _busy
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.camera_alt_outlined),
                label: Text(t.statement_import.capture.cta_camera),
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: _busy ? null : _onPickFile,
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(52),
                  textStyle: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                icon: const Icon(Icons.upload_file_outlined),
                label: Text(t.statement_import.capture.cta_file),
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  'Funciona mejor con documentos de bancos venezolanos (BDV, Mercantil, Provincial, Banesco). Podrás revisar y editar cada fila antes de importar.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: cs.onSurfaceVariant,
                    height: 1.4,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HeroDocument extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      height: 170,
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Center(
        child: Icon(
          Icons.description_outlined,
          size: 96,
          color: cs.primary,
        ),
      ),
    );
  }
}

class _PrivacyBadge extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final t = Translations.of(context);
    final cs = Theme.of(context).colorScheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.shield_outlined, size: 14, color: cs.onSurfaceVariant),
        const SizedBox(width: 6),
        Text(
          t.statement_import.ai_badge,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: cs.onSurfaceVariant,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}
