import 'package:flutter/material.dart';
import 'package:wallex/app/chat/theme/wallex_ai_tokens.dart';

class WallexAiMarkdown extends StatelessWidget {
  const WallexAiMarkdown({
    super.key,
    required this.data,
    this.onUser = false,
    this.maxTableRows = 10,
  });

  final String data;
  final bool onUser;
  final int maxTableRows;

  static final RegExp _inlineRe = RegExp(
    r'(\*\*[^*]+\*\*)|(`[^`]+`)|(\$\s?[0-9]{1,3}(?:[.,][0-9]{3})*(?:[.,][0-9]{2})?)',
  );
  static final RegExp _pipeRow = RegExp(r'^\s*\|.*\|\s*$');
  static final RegExp _pipeSep =
      RegExp(r'^\s*\|?\s*:?-{2,}:?\s*(\|\s*:?-{2,}:?\s*)+\|?\s*$');
  static final RegExp _bulletRe = RegExp(r'^\s*(?:[-*•]|\d+[.)])\s+(.*)$');

  List<_Block> _parse(String raw) {
    final lines = raw.split(RegExp(r'\r?\n'));
    final blocks = <_Block>[];
    var i = 0;
    while (i < lines.length) {
      final l = lines[i];
      if (_pipeRow.hasMatch(l)) {
        var j = i;
        final pipeLines = <String>[];
        while (j < lines.length && _pipeRow.hasMatch(lines[j])) {
          pipeLines.add(lines[j]);
          j++;
        }
        final sepIdx = pipeLines.indexWhere((row) => _pipeSep.hasMatch(row));
        if (sepIdx > 0 && pipeLines.length - sepIdx >= 1) {
          final header = _splitRow(pipeLines[sepIdx - 1]);
          final body = <List<String>>[];
          for (var k = sepIdx + 1; k < pipeLines.length; k++) {
            if (_pipeSep.hasMatch(pipeLines[k])) continue;
            body.add(_splitRow(pipeLines[k]));
          }
          blocks.add(_TableBlock(header: header, rows: body));
          i = j;
          continue;
        }
      }
      if (_bulletRe.hasMatch(l)) {
        var j = i;
        final items = <String>[];
        while (j < lines.length && _bulletRe.hasMatch(lines[j])) {
          final m = _bulletRe.firstMatch(lines[j]);
          items.add(m?.group(1)?.trim() ?? '');
          j++;
        }
        blocks.add(_BulletBlock(items: items));
        i = j;
        continue;
      }
      if (l.trim().isEmpty) {
        i++;
        continue;
      }
      final buf = StringBuffer(l);
      var j = i + 1;
      while (j < lines.length &&
          lines[j].trim().isNotEmpty &&
          !_pipeRow.hasMatch(lines[j]) &&
          !_bulletRe.hasMatch(lines[j])) {
        buf.write('\n');
        buf.write(lines[j]);
        j++;
      }
      blocks.add(_ParagraphBlock(text: buf.toString()));
      i = j;
    }
    return blocks;
  }

  List<String> _splitRow(String row) {
    var trimmed = row.trim();
    if (trimmed.startsWith('|')) trimmed = trimmed.substring(1);
    if (trimmed.endsWith('|')) {
      trimmed = trimmed.substring(0, trimmed.length - 1);
    }
    return trimmed.split('|').map((c) => c.trim()).toList();
  }

  List<TextSpan> _spans(String text, _Styles s) {
    final spans = <TextSpan>[];
    var cursor = 0;
    for (final match in _inlineRe.allMatches(text)) {
      if (match.start > cursor) {
        spans.add(TextSpan(text: text.substring(cursor, match.start)));
      }
      final bold = match.group(1);
      final code = match.group(2);
      final currency = match.group(3);
      if (bold != null) {
        spans.add(TextSpan(
          text: bold.substring(2, bold.length - 2),
          style: s.bold,
        ));
      } else if (code != null) {
        spans.add(TextSpan(
          text: code.substring(1, code.length - 1),
          style: s.code,
        ));
      } else if (currency != null) {
        spans.add(TextSpan(text: currency, style: s.currency));
      }
      cursor = match.end;
    }
    if (cursor < text.length) {
      spans.add(TextSpan(text: text.substring(cursor)));
    }
    return spans;
  }

  @override
  Widget build(BuildContext context) {
    final tokens = WallexAiTokens.of(context);
    final base = onUser ? tokens.bubbleBodyOnUser : tokens.bubbleBody;
    final accent = tokens.accent;
    final s = _Styles(
      base: base,
      bold: base.copyWith(fontWeight: FontWeight.w800),
      code: base.copyWith(
        fontFamily: 'monospace',
        color: onUser ? tokens.textOnUser : accent,
        backgroundColor: accent.withValues(alpha: 0.1),
      ),
      currency: onUser
          ? base.copyWith(
              fontWeight: FontWeight.w800,
              color: tokens.textOnUser,
              fontFeatures: const [FontFeature.tabularFigures()],
            )
          : base.copyWith(
              color: accent,
              fontWeight: FontWeight.w700,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
    );

    final blocks = _parse(data);
    if (blocks.isEmpty) {
      return SelectableText.rich(TextSpan(style: base, children: _spans(data, s)));
    }

    final children = <Widget>[];
    for (var i = 0; i < blocks.length; i++) {
      final b = blocks[i];
      if (i > 0) children.add(const SizedBox(height: 8));
      if (b is _ParagraphBlock) {
        children.add(SelectableText.rich(
          TextSpan(style: base, children: _spans(b.text, s)),
        ));
      } else if (b is _BulletBlock) {
        children.add(_buildBullets(b, s, tokens));
      } else if (b is _TableBlock) {
        children.add(_buildTable(b, s, tokens));
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: children,
    );
  }

  Widget _buildBullets(_BulletBlock b, _Styles s, WallexAiTokens tokens) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final item in b.items)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 8, right: 8),
                  child: Container(
                    width: 4,
                    height: 4,
                    decoration: BoxDecoration(
                      color: tokens.accent,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
                Expanded(
                  child: SelectableText.rich(
                    TextSpan(style: s.base, children: _spans(item, s)),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildTable(_TableBlock b, _Styles s, WallexAiTokens tokens) {
    final displayRows = b.rows.length > maxTableRows
        ? b.rows.sublist(0, maxTableRows)
        : b.rows;
    final overflow = b.rows.length - displayRows.length;

    final kickerStyle = s.base.copyWith(
      fontSize: 11,
      fontWeight: FontWeight.w600,
      color: tokens.muted,
      letterSpacing: 0.3,
    );
    final valueStyle = s.base.copyWith(
      fontSize: 13,
      fontWeight: FontWeight.w700,
      color: tokens.text,
    );

    final rows = <Widget>[];
    for (final row in displayRows) {
      rows.add(Container(
        margin: const EdgeInsets.symmetric(vertical: 3),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: tokens.surfaceAlt.withValues(alpha: 0.4),
          border: Border.all(
            color: tokens.border.withValues(alpha: 0.4),
            width: 1,
          ),
          borderRadius: BorderRadius.circular(WallexAiTokens.innerCardRadius),
        ),
        child: _rowContent(
          header: b.header,
          cells: row,
          kickerStyle: kickerStyle,
          valueStyle: valueStyle,
          s: s,
        ),
      ));
    }
    if (overflow > 0) {
      rows.add(Padding(
        padding: const EdgeInsets.only(top: 4, left: 10),
        child: Text(
          '…y $overflow más',
          style: kickerStyle,
        ),
      ));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: rows,
    );
  }

  Widget _rowContent({
    required List<String> header,
    required List<String> cells,
    required TextStyle kickerStyle,
    required TextStyle valueStyle,
    required _Styles s,
  }) {
    if (header.length == 2 && cells.length >= 2) {
      return Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Text(
              cells[0].toUpperCase(),
              style: kickerStyle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 12),
          SelectableText.rich(
            TextSpan(style: valueStyle, children: _spans(cells[1], s)),
          ),
        ],
      );
    }
    final items = <Widget>[];
    for (var i = 0; i < cells.length; i++) {
      final label = i < header.length ? header[i] : '';
      items.add(Padding(
        padding: EdgeInsets.only(top: i == 0 ? 0 : 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (label.isNotEmpty)
              Text(
                label.toUpperCase(),
                style: kickerStyle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            SelectableText.rich(
              TextSpan(style: valueStyle, children: _spans(cells[i], s)),
            ),
          ],
        ),
      ));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: items,
    );
  }
}

sealed class _Block {}

class _ParagraphBlock extends _Block {
  final String text;
  _ParagraphBlock({required this.text});
}

class _BulletBlock extends _Block {
  final List<String> items;
  _BulletBlock({required this.items});
}

class _TableBlock extends _Block {
  final List<String> header;
  final List<List<String>> rows;
  _TableBlock({required this.header, required this.rows});
}

class _Styles {
  final TextStyle base;
  final TextStyle bold;
  final TextStyle code;
  final TextStyle currency;
  _Styles({
    required this.base,
    required this.bold,
    required this.code,
    required this.currency,
  });
}
