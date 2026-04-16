import 'package:flutter/material.dart';
import 'package:wallex/core/services/auto_import/binance/binance_api_client.dart';
import 'package:wallex/core/services/auto_import/binance/binance_api_exception.dart';
import 'package:wallex/core/services/auto_import/binance/binance_credentials_store.dart';

/// Configuration page for Binance API credentials.
///
/// Security rules:
/// - API secret is NEVER displayed -- only "configurado" / "no configurado".
/// - API key is displayed masked: only last 4 chars visible.
/// - Input fields use obscureText by default.
/// - Credentials are stored exclusively via [BinanceCredentialsStore]
///   (flutter_secure_storage).
class BinanceApiConfigPage extends StatefulWidget {
  const BinanceApiConfigPage({super.key});

  @override
  State<BinanceApiConfigPage> createState() => _BinanceApiConfigPageState();
}

class _BinanceApiConfigPageState extends State<BinanceApiConfigPage> {
  final _apiKeyController = TextEditingController();
  final _apiSecretController = TextEditingController();

  bool _obscureApiKey = true;
  bool _hasSavedCredentials = false;
  String? _maskedApiKey;
  bool _isTesting = false;
  bool _isSaving = false;
  String? _testResultMessage;
  bool? _testResultSuccess;

  @override
  void initState() {
    super.initState();
    _loadCurrentState();
  }

  Future<void> _loadCurrentState() async {
    final creds = await BinanceCredentialsStore.instance.load();
    if (creds != null && mounted) {
      setState(() {
        _hasSavedCredentials = true;
        _maskedApiKey = _maskApiKey(creds.apiKey);
      });
    }
  }

  /// Mask an API key showing only the last 4 characters.
  String _maskApiKey(String key) {
    if (key.length <= 4) return key;
    return '${'*' * (key.length - 4)}${key.substring(key.length - 4)}';
  }

  @override
  void dispose() {
    _apiKeyController.dispose();
    _apiSecretController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Configurar Binance API'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Warning card
          Card(
            color: Colors.amber.shade50,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.warning_amber_rounded,
                      color: Colors.amber.shade800),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(
                            text:
                                'Crea tu API key con SOLO permiso de Lectura. ',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Colors.amber.shade900,
                            ),
                          ),
                          TextSpan(
                            text:
                                'Nunca marques "Habilitar retiros" ni "Trading" '
                                '-- si se filtra, no podran mover tus fondos. '
                                'Las credenciales se guardan encriptadas en el dispositivo.',
                            style:
                                TextStyle(color: Colors.amber.shade900),
                          ),
                        ],
                      ),
                      style: const TextStyle(fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),

          // Current state
          if (_hasSavedCredentials) ...[
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Estado actual',
                        style: theme.textTheme.titleSmall),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        const Icon(Icons.key, size: 18),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'API Key: ${_maskedApiKey ?? '...'}',
                            style: const TextStyle(
                                fontFamily: 'monospace', fontSize: 13),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        const Icon(Icons.lock, size: 18),
                        const SizedBox(width: 8),
                        const Text('API Secret: configurado',
                            style: TextStyle(fontSize: 13)),
                      ],
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: _deleteCredentials,
                      icon: const Icon(Icons.delete_outline, size: 18),
                      label: const Text('Eliminar credenciales'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.red,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
          ],

          // Form
          Text('Nuevas credenciales',
              style: theme.textTheme.titleSmall),
          const SizedBox(height: 12),

          TextFormField(
            controller: _apiKeyController,
            obscureText: _obscureApiKey,
            decoration: InputDecoration(
              labelText: 'API Key',
              border: const OutlineInputBorder(),
              suffixIcon: IconButton(
                icon: Icon(
                    _obscureApiKey
                        ? Icons.visibility_off
                        : Icons.visibility,
                    size: 20),
                onPressed: () {
                  setState(() => _obscureApiKey = !_obscureApiKey);
                },
              ),
            ),
          ),
          const SizedBox(height: 12),

          TextFormField(
            controller: _apiSecretController,
            obscureText: true,
            decoration: const InputDecoration(
              labelText: 'API Secret',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),

          // Test connection button
          OutlinedButton.icon(
            onPressed: _isTesting ? null : _testConnection,
            icon: _isTesting
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.wifi_tethering, size: 18),
            label: Text(
                _isTesting ? 'Probando...' : 'Probar conexion'),
          ),

          // Test result
          if (_testResultMessage != null) ...[
            const SizedBox(height: 8),
            Card(
              color: _testResultSuccess == true
                  ? Colors.green.shade50
                  : Colors.red.shade50,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    Icon(
                      _testResultSuccess == true
                          ? Icons.check_circle
                          : Icons.error,
                      color: _testResultSuccess == true
                          ? Colors.green
                          : Colors.red,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _testResultMessage!,
                        style: TextStyle(
                          fontSize: 13,
                          color: _testResultSuccess == true
                              ? Colors.green.shade900
                              : Colors.red.shade900,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],

          const SizedBox(height: 20),

          // Save button
          FilledButton.icon(
            onPressed: _isSaving ? null : _saveCredentials,
            icon: _isSaving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(Icons.save),
            label: const Text('Guardar'),
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(48),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _testConnection() async {
    // Test requires saved credentials -- save first, then test
    final apiKey = _apiKeyController.text.trim();
    final apiSecret = _apiSecretController.text.trim();

    if (apiKey.isEmpty || apiSecret.isEmpty) {
      // If fields are empty but we have saved creds, test those
      if (!_hasSavedCredentials) {
        setState(() {
          _testResultMessage = 'Ingresa ambos campos antes de probar.';
          _testResultSuccess = false;
        });
        return;
      }
    } else {
      // Save credentials first so the client can use them
      await BinanceCredentialsStore.instance
          .save(apiKey: apiKey, apiSecret: apiSecret);
      setState(() {
        _hasSavedCredentials = true;
        _maskedApiKey = _maskApiKey(apiKey);
      });
    }

    setState(() {
      _isTesting = true;
      _testResultMessage = null;
    });

    try {
      final client = BinanceApiClient();
      await client.syncServerTime().timeout(const Duration(seconds: 15));
      await client.getSpotAccount().timeout(const Duration(seconds: 15));

      if (mounted) {
        setState(() {
          _testResultMessage =
              'Conexion exitosa -- cuenta Binance accesible.';
          _testResultSuccess = true;
        });
      }
    } catch (e) {
      if (mounted) {
        if (e is BinanceApiException && e.code == -1022) {
          setState(() {
            _testResultMessage =
                'Firma invalida (-1022): la API Secret no coincide con la API Key, o fue copiada con caracteres ocultos. Vuelve a crear/copiar ambas credenciales de Binance.';
            _testResultSuccess = false;
          });
          return;
        }

        final msg = e.toString();
        if (msg.contains('401') || msg.contains('invalid')) {
          setState(() {
            _testResultMessage = 'Credenciales invalidas.';
            _testResultSuccess = false;
          });
        } else {
          setState(() {
            _testResultMessage = 'Error: $msg';
            _testResultSuccess = false;
          });
        }
      }
    } finally {
      if (mounted) setState(() => _isTesting = false);
    }
  }

  Future<void> _saveCredentials() async {
    final apiKey = _apiKeyController.text.trim();
    final apiSecret = _apiSecretController.text.trim();

    if (apiKey.isEmpty || apiSecret.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ingresa API Key y Secret')),
      );
      return;
    }

    setState(() => _isSaving = true);

    try {
      await BinanceCredentialsStore.instance
          .save(apiKey: apiKey, apiSecret: apiSecret);

      if (mounted) {
        setState(() {
          _isSaving = false;
          _hasSavedCredentials = true;
          _maskedApiKey = _maskApiKey(apiKey);
          _apiKeyController.clear();
          _apiSecretController.clear();
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content:
                Text('Credenciales guardadas. Binance API listo para usar.'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSaving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al guardar: $e')),
        );
      }
    }
  }

  Future<void> _deleteCredentials() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminar credenciales'),
        content: const Text(
            'Se eliminaran las credenciales de Binance del dispositivo.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    await BinanceCredentialsStore.instance.clear();
    if (mounted) {
      setState(() {
        _hasSavedCredentials = false;
        _maskedApiKey = null;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Credenciales eliminadas')),
      );
    }
  }
}

