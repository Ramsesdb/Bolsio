import 'package:flutter/material.dart';
import 'package:nitido/app/accounts/statement_import/statement_import_flow.dart';
import 'package:nitido/app/transactions/transactions.page.dart';
import 'package:nitido/core/presentation/widgets/transaction_filter/transaction_filter_set.dart';
import 'package:nitido/core/routes/route_utils.dart';
import 'package:nitido/i18n/generated/translations.g.dart';

class SuccessPage extends StatefulWidget {
  const SuccessPage({super.key});

  @override
  State<SuccessPage> createState() => _SuccessPageState();
}

class _SuccessPageState extends State<SuccessPage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ringCtrl;

  @override
  void initState() {
    super.initState();
    _ringCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..forward();
  }

  @override
  void dispose() {
    _ringCtrl.dispose();
    super.dispose();
  }

  void _openHistory() {
    final flow = StatementImportFlow.of(context);
    final accountId = flow.account.id;
    // Cerramos el flow y abrimos la lista de tx de la cuenta.
    // v1: filtramos por accountId (no por batchId — la vista principal no
    // soporta filtrado por batchId; los batches recientes son accesibles via
    // banner "Deshacer" desde la página de detalles).
    Navigator.of(context).pop();
    RouteUtils.pushRoute(
      TransactionsPage(
        filters: TransactionFilterSet(accountsIDs: [accountId]),
      ),
    );
  }

  void _done() {
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final t = Translations.of(context);
    final flow = StatementImportFlow.of(context);
    final count = flow.committedCount ?? 0;
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _CheckRing(controller: _ringCtrl, color: cs.primary),
                    const SizedBox(height: 22),
                    Text(
                      '$count',
                      style: tt.displayLarge?.copyWith(
                        fontWeight: FontWeight.w300,
                        letterSpacing: -1.6,
                      ),
                    ),
                    const SizedBox(height: 0),
                    Text(
                      t.statement_import.success.title(n: count),
                      style: tt.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.2,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
              child: Column(
                children: [
                  FilledButton(
                    onPressed: _openHistory,
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(52),
                    ),
                    child: Text(t.statement_import.success.view_history),
                  ),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: _done,
                    style: TextButton.styleFrom(
                      minimumSize: const Size.fromHeight(46),
                      foregroundColor: cs.onSurfaceVariant,
                    ),
                    child: Text(t.statement_import.success.done),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CheckRing extends StatelessWidget {
  const _CheckRing({required this.controller, required this.color});

  final AnimationController controller;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (_, _) {
        final t = controller.value;
        final ringT = Curves.easeOutCubic.transform(t.clamp(0.0, 1.0));
        final checkT = ((t - 0.25) / 0.75).clamp(0.0, 1.0);

        return SizedBox(
          width: 104,
          height: 104,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Container(
                width: 96,
                height: 96,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.14),
                  shape: BoxShape.circle,
                ),
              ),
              CustomPaint(
                size: const Size(104, 104),
                painter: _RingPainter(progress: ringT, color: color),
              ),
              Opacity(
                opacity: checkT,
                child: Icon(
                  Icons.check_rounded,
                  color: color,
                  size: 46,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter({required this.progress, required this.color});

  final double progress;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final rect = Offset.zero & size;
    final center = rect.center;
    final radius = size.shortestSide / 2 - 2;

    // Ring trace from -90° going clockwise.
    final sweep = 2 * 3.1415926 * progress;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -3.1415926 / 2,
      sweep,
      false,
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant _RingPainter oldDelegate) =>
      oldDelegate.progress != progress;
}
