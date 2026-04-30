import 'package:flutter/material.dart';
import 'package:kilatex/app/home/widgets/decorative_sparkline.dart';
import 'package:kilatex/core/presentation/widgets/number_ui_formatters/ui_number_formatter.dart';

class BalanceDeltaPill extends StatelessWidget {
  const BalanceDeltaPill({
    super.key,
    required this.percentage,
    this.markNanAsZero = true,
  });

  final double percentage;
  final bool markNanAsZero;

  @override
  Widget build(BuildContext context) {
    double toDisplay = percentage;
    if (toDisplay.isNaN && markNanAsZero) {
      toDisplay = 0;
    }

    final bool? isPositive = toDisplay == 0
        ? null
        : toDisplay > 0
        ? true
        : false;

    final Color bgColor = isPositive == null
        ? Colors.white.withValues(alpha: 0.08)
        : isPositive
        ? const Color(0x1F4CAF50)
        : const Color(0x1FF75959);

    final Color textColor = isPositive == null
        ? Colors.white.withValues(alpha: 0.7)
        : isPositive
        ? const Color(0xFF4CAF50)
        : const Color(0xFFF75959);

    final TextStyle textStyle = TextStyle(
      fontSize: 11,
      fontWeight: FontWeight.w800,
      color: textColor,
    );

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(9999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          DecorativeSparkline(isPositive: isPositive, color: textColor),
          const SizedBox(width: 6),
          UINumberFormatter.percentage(
            amountToConvert: toDisplay,
            integerStyle: textStyle,
          ).getTextWidget(context),
        ],
      ),
    );
  }
}
