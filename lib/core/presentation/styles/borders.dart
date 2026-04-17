import 'package:flutter/material.dart';
import 'package:wallex/core/presentation/app_colors.dart';

Radius get inputBorderRadius => Radius.circular(6);

UnderlineInputBorder get appInputBorder => UnderlineInputBorder(
  borderSide: BorderSide.none,
  borderRadius: BorderRadius.only(
    topLeft: inputBorderRadius,
    topRight: inputBorderRadius,
    bottomLeft: inputBorderRadius,
    bottomRight: inputBorderRadius,
  ),
);

List<BoxShadow> boxShadowGeneral(BuildContext context) {
  final isDark = Theme.of(context).brightness == Brightness.dark;

  if (isDark) return [];

  return [
    BoxShadow(
      color: AppColors.of(context).shadowColorLight.withValues(alpha: 0.12),
      blurRadius: 10,
      offset: Offset(0, 0),
      spreadRadius: 4,
    ),
  ];
}
