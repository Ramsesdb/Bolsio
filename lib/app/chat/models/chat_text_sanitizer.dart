String stripRedundantStructuredText(String raw) {
  if (raw.trim().isEmpty) return '';

  final lines = raw.split(RegExp(r'\r?\n'));
  final kept = <String>[];
  var i = 0;
  final sep = RegExp(r'^\s*\|?\s*:?-{2,}:?\s*(\|\s*:?-{2,}:?\s*)+\|?\s*$');
  final pipeRow = RegExp(r'^\s*\|.*\|\s*$');
  final bulletCurrency = RegExp(r'^\s*(?:[-*•]|\d+[.)])\s+.*[\$€£]\s?[\d.,]+');
  while (i < lines.length) {
    final l = lines[i];
    final isPipe = pipeRow.hasMatch(l);
    if (isPipe) {
      var j = i;
      var sawSep = false;
      while (j < lines.length && pipeRow.hasMatch(lines[j])) {
        if (sep.hasMatch(lines[j])) sawSep = true;
        j++;
      }
      if (sawSep && j - i >= 2) {
        i = j;
        continue;
      }
    }
    if (bulletCurrency.hasMatch(l)) {
      var j = i;
      while (j < lines.length && bulletCurrency.hasMatch(lines[j])) {
        j++;
      }
      if (j - i >= 4) {
        i = j;
        continue;
      }
    }
    kept.add(l);
    i++;
  }

  final joined = kept.join('\n').replaceAll(RegExp(r'\n{3,}'), '\n\n').trim();
  return joined;
}
