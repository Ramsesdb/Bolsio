import 'dart:developer' as developer;

import 'package:flutter/material.dart';
import 'package:wallex/app/transactions/auto_import/proposal_review.page.dart';
import 'package:wallex/app/transactions/auto_import/widgets/pending_import_tile.dart';
import 'package:wallex/core/database/app_db.dart';
import 'package:wallex/core/database/services/pending_import/pending_import_service.dart';
import 'package:wallex/core/models/auto_import/transaction_proposal_status.dart';
import 'package:wallex/app/settings/pages/auto_import/auto_import_settings.page.dart';
import 'package:wallex/core/routes/route_utils.dart';
import 'package:wallex/core/services/auto_import/orchestrator/capture_orchestrator.dart';

/// Page showing the inbox of auto-imported transaction proposals.
///
/// Two tabs:
/// - "Por revisar": pending proposals awaiting user action.
/// - "Historial": confirmed + rejected proposals.
class PendingImportsPage extends StatefulWidget {
  const PendingImportsPage({super.key});

  @override
  State<PendingImportsPage> createState() => _PendingImportsPageState();
}

class _PendingImportsPageState extends State<PendingImportsPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _onRefresh() async {
    try {
      await CaptureOrchestrator.instance.pollNow();
    } catch (e) {
      developer.log('pollNow error: $e', name: 'PendingImportsPage');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Bandeja de auto-import'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Forzar sincronizacion',
            onPressed: () async {
              await _onRefresh();
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Sincronizacion completada'),
                    duration: Duration(seconds: 2),
                  ),
                );
              }
            },
          ),
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: 'Configuracion auto-import',
            onPressed: () {
              RouteUtils.pushRoute(
                const AutoImportSettingsPage(),
              );
            },
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Por revisar'),
            Tab(text: 'Historial'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _PendingList(
            statusFilter: const [
              TransactionProposalStatus.pending,
            ],
            emptyMessage:
                'No hay movimientos por revisar.\nLas capturas apareceran aqui.',
            onRefresh: _onRefresh,
          ),
          _PendingList(
            statusFilter: const [
              TransactionProposalStatus.confirmed,
              TransactionProposalStatus.rejected,
            ],
            emptyMessage: 'No hay historial de propuestas.',
            onRefresh: _onRefresh,
          ),
        ],
      ),
    );
  }
}

class _PendingList extends StatelessWidget {
  const _PendingList({
    required this.statusFilter,
    required this.emptyMessage,
    required this.onRefresh,
  });

  final List<TransactionProposalStatus> statusFilter;
  final String emptyMessage;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    // We use the first status to stream and combine manually
    // Since PendingImportService streams by single status, we
    // get all and filter client-side for multi-status tabs.
    return StreamBuilder<List<PendingImportInDB>>(
      stream: PendingImportService.instance.getPendingImports(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        final allItems = snapshot.data ?? [];
        final items = allItems
            .where((item) => statusFilter
                .map((s) => s.dbValue)
                .contains(item.status))
            .toList();

        if (items.isEmpty) {
          return RefreshIndicator(
            onRefresh: onRefresh,
            child: ListView(
              children: [
                const SizedBox(height: 120),
                Icon(
                  Icons.inbox_outlined,
                  size: 64,
                  color: Theme.of(context)
                      .colorScheme
                      .onSurface
                      .withValues(alpha: 0.3),
                ),
                const SizedBox(height: 16),
                Text(
                  emptyMessage,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        color: Theme.of(context)
                            .colorScheme
                            .onSurface
                            .withValues(alpha: 0.5),
                      ),
                ),
              ],
            ),
          );
        }

        return RefreshIndicator(
          onRefresh: onRefresh,
          child: ListView.builder(
            padding: const EdgeInsets.only(top: 8, bottom: 80),
            itemCount: items.length,
            itemBuilder: (context, index) {
              final item = items[index];
              return _buildDismissibleTile(context, item);
            },
          ),
        );
      },
    );
  }

  Widget _buildDismissibleTile(
      BuildContext context, PendingImportInDB item) {
    final isPending = item.status ==
            TransactionProposalStatus.pending.dbValue ||
        item.status == TransactionProposalStatus.duplicate.dbValue;

    if (!isPending) {
      return PendingImportTile(
        pendingImport: item,
        onTap: () => _openReview(context, item),
      );
    }

    return Dismissible(
      key: ValueKey(item.id),
      direction: DismissDirection.horizontal,
      confirmDismiss: (direction) async {
        if (direction == DismissDirection.startToEnd) {
          // Swipe right -> reject
          await PendingImportService.instance.updatePendingImportStatus(
            item.id,
            TransactionProposalStatus.rejected,
          );
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: const Text('Propuesta rechazada'),
                action: SnackBarAction(
                  label: 'Deshacer',
                  onPressed: () {
                    PendingImportService.instance.updatePendingImportStatus(
                      item.id,
                      TransactionProposalStatus.pending,
                    );
                  },
                ),
              ),
            );
          }
          return true;
        } else {
          // Swipe left -> open review
          _openReview(context, item);
          return false;
        }
      },
      background: Container(
        color: Colors.red.shade400,
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.only(left: 24),
        child: const Icon(Icons.block, color: Colors.white),
      ),
      secondaryBackground: Container(
        color: Colors.blue.shade400,
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 24),
        child: const Icon(Icons.rate_review_outlined, color: Colors.white),
      ),
      child: PendingImportTile(
        pendingImport: item,
        onTap: () => _openReview(context, item),
      ),
    );
  }

  void _openReview(BuildContext context, PendingImportInDB item) {
    RouteUtils.pushRoute(ProposalReviewPage(pendingImport: item));
  }
}

