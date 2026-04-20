import 'package:flutter/material.dart';

class DecorativeSparkline extends StatelessWidget {
  const DecorativeSparkline({super.key, required this.isPositive, this.color});

  final bool? isPositive;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    if (isPositive == null) {
      return const SizedBox(width: 38, height: 12);
    }

    return SizedBox(
      width: 38,
      height: 12,
      child: CustomPaint(
        painter: _SparklinePainter(
          isPositive: isPositive!,
          color: color ?? (isPositive! ? const Color(0xFF4CAF50) : const Color(0xFFF75959)),
        ),
      ),
    );
  }
}

class _SparklinePainter extends CustomPainter {
  _SparklinePainter({required this.isPositive, required this.color});

  final bool isPositive;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final ys = isPositive
        ? const [10.0, 8.0, 9.0, 6.0, 7.0, 4.0, 2.0]
        : const [2.0, 4.0, 3.0, 6.0, 5.0, 8.0, 10.0];

    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.6
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final path = Path();
    final step = size.width / (ys.length - 1);
    for (var i = 0; i < ys.length; i++) {
      final dx = step * i;
      final dy = ys[i];
      if (i == 0) {
        path.moveTo(dx, dy);
      } else {
        path.lineTo(dx, dy);
      }
    }

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _SparklinePainter oldDelegate) =>
      oldDelegate.isPositive != isPositive || oldDelegate.color != color;
}
