import 'package:flutter/material.dart';
import 'package:nitido/core/models/budget/budget.dart';
import 'package:nitido/core/services/ai/budget_prediction_service.dart';

class BudgetPredictionWidget extends StatefulWidget {
  const BudgetPredictionWidget({super.key, required this.budget});

  final Budget budget;

  @override
  State<BudgetPredictionWidget> createState() => _BudgetPredictionWidgetState();
}

class _BudgetPredictionWidgetState extends State<BudgetPredictionWidget> {
  bool _isLoading = true;
  BudgetPredictionResult? _result;

  @override
  void initState() {
    super.initState();
    _loadPrediction();
  }

  @override
  void didUpdateWidget(covariant BudgetPredictionWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.budget.id != widget.budget.id) {
      _loadPrediction();
    }
  }

  Future<void> _loadPrediction() async {
    setState(() {
      _isLoading = true;
      _result = null;
    });

    final prediction =
        await BudgetPredictionService.instance.getPrediction(widget.budget);

    if (!mounted) return;

    setState(() {
      _result = prediction;
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Padding(
        padding: EdgeInsets.only(top: 8),
        child: LinearProgressIndicator(minHeight: 2),
      );
    }

    if (_result == null) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Text(
        _result!.text,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
      ),
    );
  }
}
