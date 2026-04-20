import 'dart:io';

import 'package:flutter/material.dart';
import 'package:wallex/core/presentation/helpers/snackbar.dart';
import 'package:wallex/core/services/attachments/attachments_service.dart';
import 'package:wallex/i18n/generated/translations.g.dart';

class AttachmentViewer extends StatefulWidget {
  const AttachmentViewer({super.key, required this.file, this.attachmentId});

  final File file;
  final String? attachmentId;

  @override
  State<AttachmentViewer> createState() => _AttachmentViewerState();
}

class _AttachmentViewerState extends State<AttachmentViewer> {
  bool _isDeleting = false;

  Future<void> _delete() async {
    final id = widget.attachmentId;
    if (id == null || _isDeleting) return;

    setState(() => _isDeleting = true);
    try {
      await AttachmentsService.instance.deleteById(id);
      if (!mounted) return;

      WallexSnackbar.success(
        SnackbarParams(Translations.of(context).attachments.remove),
      );
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      WallexSnackbar.error(SnackbarParams.fromError(e));
    } finally {
      if (mounted) {
        setState(() => _isDeleting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Translations.of(context);

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(t.attachments.view),
        actions: [
          if (widget.attachmentId != null)
            IconButton(
              onPressed: _isDeleting ? null : _delete,
              tooltip: t.attachments.remove,
              icon: _isDeleting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.delete_outline),
            ),
        ],
      ),
      body: Center(
        child: InteractiveViewer(
          minScale: 0.6,
          maxScale: 6,
          child: Image.file(
            widget.file,
            fit: BoxFit.contain,
            errorBuilder: (_, _, _) {
              return const Icon(
                Icons.broken_image_outlined,
                size: 56,
                color: Colors.white70,
              );
            },
          ),
        ),
      ),
    );
  }
}
