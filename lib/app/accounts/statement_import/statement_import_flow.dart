import 'package:flutter/material.dart';
import 'package:kilatex/app/accounts/statement_import/screens/capture.page.dart';
import 'package:kilatex/app/accounts/statement_import/screens/confirm.page.dart';
import 'package:kilatex/app/accounts/statement_import/screens/processing.page.dart';
import 'package:kilatex/app/accounts/statement_import/screens/review.page.dart';
import 'package:kilatex/app/accounts/statement_import/screens/success.page.dart';
import 'package:kilatex/core/database/services/account/account_service.dart';
import 'package:kilatex/core/models/account/account.dart';
import 'package:kilatex/core/services/statement_import/models/extracted_row.dart';
import 'package:kilatex/core/services/statement_import/models/matching_result.dart';

class StatementImportFlow extends StatefulWidget {
  const StatementImportFlow({super.key, required this.account});

  final Account account;

  @override
  State<StatementImportFlow> createState() => StatementImportFlowState();

  static StatementImportFlowState of(BuildContext context) {
    final scope = context
        .dependOnInheritedWidgetOfExactType<_StatementImportFlowScope>();
    assert(scope != null, 'StatementImportFlow.of called outside of the flow');
    return scope!.state;
  }
}

class StatementImportFlowState extends State<StatementImportFlow> {
  final _controller = PageController();

  String? imageBase64;
  DateTime? pivotDate;
  List<ExtractedRow>? extractedRows;
  List<MatchingResult>? matchingResults;
  List<MatchingResult>? approvedResults;
  Set<String> activeModes = <String>{};
  String? batchId;
  int? committedCount;

  int _currentIndex = 0;
  Account? _refreshedAccount;

  Account get account => _refreshedAccount ?? widget.account;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void goToProcessing({
    required String imageBase64,
    required DateTime pivotDate,
  }) {
    setState(() {
      this.imageBase64 = imageBase64;
      this.pivotDate = pivotDate;
      extractedRows = null;
      matchingResults = null;
      approvedResults = null;
      activeModes = <String>{};
      batchId = null;
      committedCount = null;
    });
    _goTo(1);
  }

  void backToCapture() {
    setState(() {
      imageBase64 = null;
      pivotDate = null;
      extractedRows = null;
      matchingResults = null;
      approvedResults = null;
      activeModes = <String>{};
    });
    _goTo(0);
  }

  void onRowsExtracted(List<ExtractedRow> rows) {
    setState(() => extractedRows = rows);
  }

  void onMatchingComplete(List<MatchingResult> results) {
    setState(() => matchingResults = results);
  }

  void goToReview() {
    _goTo(2);
  }

  void backToReview() {
    _goTo(2);
  }

  void goToConfirm({
    required List<MatchingResult> approved,
    required Set<String> modes,
  }) {
    setState(() {
      approvedResults = approved;
      activeModes = Set<String>.from(modes);
    });
    _goTo(3);
  }

  void goToSuccess({required String batchId, required int count}) {
    setState(() {
      this.batchId = batchId;
      committedCount = count;
    });
    _goTo(4);
  }

  /// Refresca la cuenta desde el servicio (por ejemplo tras editar
  /// trackedSince desde el flow).
  Future<void> refreshAccount() async {
    final updated =
        await AccountService.instance.getAccountById(widget.account.id).first;
    if (!mounted) return;
    if (updated != null) {
      setState(() => _refreshedAccount = updated);
    }
  }

  void _goTo(int index) {
    if (!mounted) return;
    _currentIndex = index;
    _controller.animateToPage(
      index,
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
    );
  }

  Future<bool> _onWillPop() async {
    if (_currentIndex == 4) {
      return true;
    }
    if (_currentIndex == 3) {
      backToReview();
      return false;
    }
    if (_currentIndex == 2 || _currentIndex == 1) {
      backToCapture();
      return false;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    return _StatementImportFlowScope(
      state: this,
      child: PopScope(
        canPop: _currentIndex == 0 || _currentIndex == 4,
        onPopInvokedWithResult: (didPop, _) async {
          if (didPop) return;
          await _onWillPop();
        },
        child: Scaffold(
          body: PageView(
            controller: _controller,
            physics: const NeverScrollableScrollPhysics(),
            children: const [
              CapturePage(),
              ProcessingPage(),
              ReviewPage(),
              ConfirmPage(),
              SuccessPage(),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatementImportFlowScope extends InheritedWidget {
  const _StatementImportFlowScope({
    required this.state,
    required super.child,
  });

  final StatementImportFlowState state;

  @override
  bool updateShouldNotify(_StatementImportFlowScope oldWidget) =>
      state != oldWidget.state;
}
