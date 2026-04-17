import 'package:flutter/material.dart';

extension ColorHex on Color {
  /// Return a color instance from an hex string
  static Color get(String hex) {
    hex = hex.toUpperCase().replaceAll('#', '');

    if (hex.length == 6) {
      hex = 'FF$hex';
    }

    // Parser will return errors on invalid strings, so we don't need error catching here
    return Color(int.parse(hex, radix: 16));
  }

  String toHex({
    bool leadingHashSign = false,
    bool enableAlpha = false,
    bool toUpperCase = true,
  }) {
    final String hex =
        (leadingHashSign ? '#' : '') +
        (enableAlpha ? _padRadix((a * 255).round()) : '') +
        _padRadix((r * 255).round()) +
        _padRadix((g * 255).round()) +
        _padRadix((b * 255).round());
    return toUpperCase ? hex.toUpperCase() : hex;
  }

  // Shorthand for padLeft of RadixString, DRY.
  String _padRadix(int value) => value.toRadixString(16).padLeft(2, '0');
}

extension ColorBrightness on Color {
  Color darken([double amount = .1]) {
    assert(amount >= -1 && amount <= 1);

    if (amount < 0) {
      return lighten(amount.abs());
    }

    var f = 1 - amount;

    final alphaInt = (a * 255).round();
    final redInt = (r * 255).round();
    final greenInt = (g * 255).round();
    final blueInt = (b * 255).round();

    return Color.fromARGB(
      alphaInt,
      (redInt * f).round(),
      (greenInt * f).round(),
      (blueInt * f).round(),
    );
  }

  Color lighten([double amount = .1]) {
    assert(amount >= -1 && amount <= 1);

    if (amount < 0) {
      return darken(amount.abs());
    }

    final alphaInt = (a * 255).round();
    final redInt = (r * 255).round();
    final greenInt = (g * 255).round();
    final blueInt = (b * 255).round();

    return Color.fromARGB(
      alphaInt,
      redInt + ((255 - redInt) * amount).round(),
      greenInt + ((255 - greenInt) * amount).round(),
      blueInt + ((255 - blueInt) * amount).round(),
    );
  }

  Color lightenPastel({double amount = 0.1}) {
    assert(amount >= -1 && amount <= 1);

    if (amount < 0) {
      return darkenPastel(amount: amount.abs());
    }

    return Color.alphaBlend(Colors.white.withValues(alpha: amount), this);
  }

  Color darkenPastel({double amount = 0.1}) {
    assert(amount >= -1 && amount <= 1);

    if (amount < 0) {
      return lightenPastel(amount: amount.abs());
    }

    return Color.alphaBlend(Colors.black.withValues(alpha: amount), this);
  }

  Color getContrastColor() {
    return computeLuminance() < 0.5 ? Colors.white : Colors.black;
  }
}
