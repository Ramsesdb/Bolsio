import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:wallex/app/chat/wallex_chat.page.dart';
import 'package:wallex/core/database/services/user-setting/user_setting_service.dart';
import 'package:wallex/core/models/date-utils/date_period_state.dart';
import 'package:wallex/core/routes/route_utils.dart';
import 'package:wallex/core/services/ai/spending_insights_service.dart';

class AiHubPage extends StatefulWidget {
  const AiHubPage({super.key});

  @override
  State<AiHubPage> createState() => _AiHubPageState();
}

class _AiHubPageState extends State<AiHubPage> {
  late Future<SpendingInsightsResult?> _insightsFuture;

  @override
  void initState() {
    super.initState();
    _insightsFuture = _loadInsights();
  }

  Future<SpendingInsightsResult?> _loadInsights() {
    return SpendingInsightsService.instance.generateInsights(
      periodState: const DatePeriodState(),
    );
  }

  void _refresh() {
    setState(() {
      _insightsFuture = _loadInsights();
    });
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final aiEnabled = appStateSettings[SettingKey.nexusAiEnabled] == '1';

    return Scaffold(
      appBar: AppBar(
        title: Row(
          spacing: 10,
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: cs.primaryContainer,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(Icons.auto_awesome_rounded, size: 20, color: cs.primary),
            ),
            const Text('Wallex AI'),
          ],
        ),
        actions: [
          IconButton(
            onPressed: _refresh,
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Actualizar insights',
          ),
        ],
      ),
      body: !aiEnabled
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  spacing: 16,
                  children: [
                    Icon(Icons.auto_awesome_outlined, size: 64, color: cs.outlineVariant),
                    Text(
                      'IA deshabilitada',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    Text(
                      'Activa Wallex AI en Configuracion para ver insights y usar el chat.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: cs.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
            )
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // Chat card
                _buildChatCard(cs),
                const SizedBox(height: 20),
                // Insights section
                _buildInsightsSection(cs),
              ],
            ),
    );
  }

  Widget _buildChatCard(ColorScheme cs) {
    return Card(
      elevation: 0,
      color: cs.primaryContainer,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => RouteUtils.pushRoute(const WallexChatPage()),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: cs.primary,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(Icons.chat_rounded, color: cs.onPrimary, size: 24),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Chat financiero',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                        color: cs.onPrimaryContainer,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Pregunta sobre tus cuentas, gastos y transacciones',
                      style: TextStyle(
                        fontSize: 13,
                        color: cs.onPrimaryContainer.withValues(alpha: 0.7),
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.arrow_forward_ios_rounded, size: 16, color: cs.onPrimaryContainer),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInsightsSection(ColorScheme cs) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 12),
          child: Row(
            spacing: 8,
            children: [
              Icon(Icons.insights_rounded, size: 20, color: cs.primary),
              Text(
                'Insights del mes',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: cs.onSurface,
                ),
              ),
            ],
          ),
        ),
        FutureBuilder<SpendingInsightsResult?>(
          future: _insightsFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return Card(
                elevation: 0,
                color: cs.surfaceContainerHighest,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Padding(
                  padding: EdgeInsets.symmetric(vertical: 32),
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      spacing: 12,
                      children: [
                        CircularProgressIndicator(strokeWidth: 2),
                        Text('Analizando tus gastos...'),
                      ],
                    ),
                  ),
                ),
              );
            }

            final result = snapshot.data;
            if (result == null) {
              return Card(
                elevation: 0,
                color: cs.surfaceContainerHighest,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Row(
                    spacing: 12,
                    children: [
                      Icon(Icons.info_outline_rounded, color: cs.onSurfaceVariant),
                      Expanded(
                        child: Text(
                          'No hay suficientes datos para generar insights este mes.',
                          style: TextStyle(color: cs.onSurfaceVariant),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }

            return Card(
              elevation: 0,
              color: cs.surfaceContainerHighest,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: MarkdownBody(
                  data: result.text,
                  styleSheet: MarkdownStyleSheet(
                    p: TextStyle(
                      color: cs.onSurface,
                      fontSize: 15,
                      height: 1.5,
                    ),
                    strong: TextStyle(
                      color: cs.onSurface,
                      fontWeight: FontWeight.w700,
                    ),
                    tableHead: TextStyle(
                      color: cs.onSurface,
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                    tableBody: TextStyle(color: cs.onSurfaceVariant, fontSize: 13),
                    tableBorder: TableBorder.all(color: cs.outlineVariant, width: 0.5),
                    tableCellsPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    listBullet: TextStyle(color: cs.primary, fontSize: 15),
                    blockSpacing: 8,
                  ),
                ),
              ),
            );
          },
        ),
      ],
    );
  }
}
