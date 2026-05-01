import 'dart:io';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:nitido/app/layout/page_framework.dart';
import 'package:nitido/app/settings/pages/backup/export_page.dart';
import 'package:nitido/app/settings/pages/backup/import_csv.page.dart';
import 'package:nitido/core/database/app_db.dart';
import 'package:nitido/core/database/backup/backup_database_service.dart';
import 'package:nitido/core/extensions/numbers.extensions.dart';
import 'package:nitido/core/presentation/helpers/snackbar.dart';
import 'package:nitido/core/presentation/widgets/confirm_dialog.dart';
import 'package:nitido/core/routes/destinations.dart';
import 'package:nitido/core/routes/route_utils.dart';
import 'package:nitido/core/services/attachments/attachments_service.dart';
import 'package:nitido/core/utils/unique_app_widgets_keys.dart';
import 'package:nitido/i18n/generated/translations.g.dart';

import 'package:nitido/core/database/services/category/category_service.dart';
import '../../widgets/settings_list_utils.dart';
import 'package:nitido/core/services/firebase_sync_service.dart';

class BackupSettingsPage extends StatefulWidget {
  const BackupSettingsPage({super.key});

  @override
  State<BackupSettingsPage> createState() => _BackupSettingsPageState();
}

class _BackupSettingsPageState extends State<BackupSettingsPage> {
  @override
  Widget build(BuildContext context) {
    final t = Translations.of(context);

    return PageFramework(
      title: t.more.data.display,
      body: SingleChildScrollView(
        padding: const EdgeInsets.only(top: 0),
        child: ListTileTheme(
          data: getSettingListTileStyle(context),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              createListSeparator(context, t.backup.import.title),
              ListTile(
                title: Text(t.backup.import.restore_backup),
                subtitle: Text(t.backup.import.restore_backup_descr),
                minVerticalPadding: 16,
                onTap: () {
                  confirmDialog(
                    context,
                    icon: Icons.warning_rounded,
                    dialogTitle: t.backup.import.restore_backup_warn_title,
                    contentParagraphs: [
                      Text(t.backup.import.restore_backup_warn_description),
                    ],
                  ).then((value) {
                    if (value == null || !value) {
                      return;
                    }

                    BackupDatabaseService()
                        .importDatabase()
                        .then((value) {
                          if (!value) {
                            RouteUtils.popRoute();

                            NitidoSnackbar.info(
                              SnackbarParams(t.backup.no_file_selected),
                            );

                            return;
                          }

                          RouteUtils.popAllRoutesExceptFirst();

                          tabsPageKey.currentState!.changePage(
                            AppMenuDestinationsID.dashboard,
                          );

                          NitidoSnackbar.success(
                            SnackbarParams(t.backup.import.success),
                          );
                        })
                        .catchError((err) {
                          RouteUtils.popRoute();

                          NitidoSnackbar.error(SnackbarParams.fromError(err));
                        });
                  });
                },
              ),
              ListTile(
                title: Text(t.backup.import.manual_import.title),
                subtitle: Text(t.backup.import.manual_import.descr),
                minVerticalPadding: 16,
                onTap: () {
                  RouteUtils.pushRoute(const ImportCSVPage());
                },
              ),
              createListSeparator(context, t.backup.export.title_short),
              ListTile(
                title: Text(t.backup.export.title),
                subtitle: Text(t.backup.export.description),
                minVerticalPadding: 16,
                onTap: () {
                  RouteUtils.pushRoute(const ExportDataPage());
                },
              ),
              createListSeparator(context, t.backup.about.title),
              ListTile(
                title: Text(t.backup.about.modify_date),
                trailing: FutureBuilder(
                  future: AppDB.instance.databasePath,
                  builder: (context, snapshot) {
                    final path = snapshot.data;

                    if (path == null || path.isEmpty) {
                      return const Text('----');
                    }

                    return Text(
                      DateFormat.yMMMd().add_Hm().format(
                        File(path).lastModifiedSync(),
                      ),
                    );
                  },
                ),
              ),
              ListTile(
                title: Text(t.backup.about.size),
                trailing: FutureBuilder(
                  future: AppDB.instance.databasePath.then(
                    (value) => File(value).stat(),
                  ),
                  builder: (context, snapshot) {
                    final fileStats = snapshot.data;

                    if (fileStats == null) {
                      return const Text('----');
                    }

                    return Text(fileStats.size.readableFileSize());
                  },
                ),
              ),
              ListTile(
                title: const Text('Limpieza de adjuntos huerfanos'),
                subtitle: const Text(
                  'Eliminar archivos o registros de adjuntos inconsistentes',
                ),
                leading: const Icon(Icons.cleaning_services_outlined),
                onTap: () async {
                  final removed = await AttachmentsService.instance
                      .purgeOrphans();

                  if (!context.mounted) return;
                  NitidoSnackbar.success(
                    SnackbarParams('Limpieza completada: $removed elementos'),
                  );
                },
              ),

              ListTile(
                title: const Text('Reparar Datos'),
                subtitle: const Text('Reinicializar categorías por defecto'),
                leading: const Icon(Icons.build_rounded, color: Colors.orange),
                onTap: () async {
                  final confirmed = await showDialog<bool>(
                    context: context,
                    builder: (context) => AlertDialog(
                      title: const Text('¿Reparar datos?'),
                      content: const Text(
                        'Esto intentará crear las categorías predeterminadas nuevamente. No borrará tus datos actuales.',
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.of(context).pop(false),
                          child: const Text('Cancelar'),
                        ),
                        FilledButton(
                          onPressed: () => Navigator.of(context).pop(true),
                          child: const Text('Reparar'),
                        ),
                      ],
                    ),
                  );

                  if (confirmed == true) {
                    try {
                      await CategoryService.instance.initializeCategories();

                      if (context.mounted) {
                        NitidoSnackbar.success(
                          SnackbarParams(
                            'Datos reparados exitosamente. Reinicia la app.',
                          ),
                        );
                      }
                    } catch (e) {
                      if (context.mounted) {
                        NitidoSnackbar.error(SnackbarParams('Error: $e'));
                      }
                    }
                  }
                },
              ),
              createListSeparator(context, 'Sincronización Multi-Dispositivo'),
              ListTile(
                title: const Text('Subir Datos a la Nube'),
                subtitle: const Text(
                  'Enviar todos tus datos a Firebase para compartir',
                ),
                leading: const Icon(Icons.cloud_upload, color: Colors.blue),
                onTap: () async {
                  final confirmed = await showDialog<bool>(
                    context: context,
                    builder: (context) => AlertDialog(
                      title: const Text('¿Subir datos?'),
                      content: const Text(
                        'Esto enviará todas tus cuentas, categorías y '
                        'transacciones a la nube. Los datos existentes '
                        'en la nube serán actualizados.',
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.of(context).pop(false),
                          child: const Text('Cancelar'),
                        ),
                        FilledButton(
                          onPressed: () => Navigator.of(context).pop(true),
                          child: const Text('Subir'),
                        ),
                      ],
                    ),
                  );

                  if (confirmed == true) {
                    try {
                      await FirebaseSyncService.instance.pushAllData();

                      if (context.mounted) {
                        NitidoSnackbar.success(
                          SnackbarParams(
                            'Datos subidos exitosamente a la nube',
                          ),
                        );
                      }
                    } catch (e) {
                      if (context.mounted) {
                        NitidoSnackbar.error(SnackbarParams('Error: $e'));
                      }
                    }
                  }
                },
              ),
              ListTile(
                title: const Text('Descargar Datos de la Nube'),
                subtitle: const Text(
                  'Obtener datos compartidos desde Firebase',
                ),
                leading: const Icon(Icons.cloud_download, color: Colors.teal),
                onTap: () async {
                  final confirmed = await showDialog<bool>(
                    context: context,
                    builder: (context) => AlertDialog(
                      title: const Text('¿Descargar datos?'),
                      content: const Text(
                        'Esto descargará las cuentas, categorías y '
                        'transacciones desde la nube. Los registros '
                        'existentes serán actualizados si tienen el mismo ID.',
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.of(context).pop(false),
                          child: const Text('Cancelar'),
                        ),
                        FilledButton(
                          onPressed: () => Navigator.of(context).pop(true),
                          child: const Text('Descargar'),
                        ),
                      ],
                    ),
                  );

                  if (confirmed == true) {
                    try {
                      final result = await FirebaseSyncService.instance
                          .pullAllData();

                      if (context.mounted) {
                        final errors = result['errors'] as int? ?? 0;
                        final firstErr = result['firstError'] as String? ?? '';
                        final msg =
                            'Descargados: '
                                    '${result['accounts']} cuentas, '
                                    '${result['categories']} categorías, '
                                    '${result['transactions']} transacciones. '
                                    '${errors > 0 ? 'Errores: $errors. $firstErr' : ''}'
                                .trim();
                        if (errors > 0) {
                          NitidoSnackbar.error(SnackbarParams(msg));
                        } else {
                          NitidoSnackbar.success(
                            SnackbarParams('$msg Reinicia la app para verlos.'),
                          );
                        }
                      }
                    } catch (e) {
                      if (context.mounted) {
                        NitidoSnackbar.error(SnackbarParams('Error: $e'));
                      }
                    }
                  }
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
