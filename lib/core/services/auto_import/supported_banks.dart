import 'package:flutter/foundation.dart';

/// Single source of truth for one bank/app supported by nitido auto-import.
///
/// One entry per bank — package aliases (legacy or platform-variant) are
/// listed in [packageNames] so a single [profileId] covers them all.
@immutable
class SupportedBank {
  const SupportedBank({
    required this.profileId,
    required this.displayName,
    required this.packageNames,
    required this.hasDedicatedParser,
    this.playStoreUrlAliases = const <String>[],
    this.defaultCurrency = 'VES',
  });

  /// Stable profile ID, e.g. 'bdv_notif', 'banesco_notif'.
  final String profileId;

  /// Human-readable bank name, e.g. 'Banco de Venezuela', 'Banesco'.
  final String displayName;

  /// All Android package names this bank can be detected under at runtime.
  /// These are the packages enumerated by `installed_apps` and the ones
  /// mirrored into AndroidManifest.xml `<queries>` for HyperOS / MIUI
  /// visibility. Multiple entries cover legacy + new app variants.
  final List<String> packageNames;

  /// Additional package names that may appear in a Play Store URL but are
  /// NOT what the app reports at runtime (e.g. the public store listing
  /// uses a different package than the installed APK on some banks). Used
  /// only by the onboarding "Agregar manualmente" URL parser. These are
  /// NOT required to be present in AndroidManifest.xml `<queries>` — the
  /// URL parsing happens before any device enumeration.
  final List<String> playStoreUrlAliases;

  /// True if there is a dedicated regex parser (BDV, Zinli, Binance).
  /// False means the GenericLlmProfile fallback will be used.
  final bool hasDedicatedParser;

  /// Default currency hint for the LLM when ambiguous.
  final String defaultCurrency;
}

/// Single source of truth for all banks/apps supported by nitido auto-import.
/// Update this list to add new banks. The package names here are kept in sync
/// with AndroidManifest.xml `<queries>` via a test in
/// `test/auto_import/supported_banks_manifest_sync_test.dart`.
const List<SupportedBank> kSupportedBanks = [
  // ── Banca venezolana — con parser dedicado ──
  SupportedBank(
    profileId: 'bdv_notif',
    displayName: 'Banco de Venezuela',
    packageNames: [
      'com.bancodevenezuela.bdvdigital',
      'com.tralix.bdvmovil',
    ],
    hasDedicatedParser: true,
  ),
  SupportedBank(
    profileId: 'zinli_notif',
    displayName: 'Zinli',
    packageNames: [
      'com.zinli.app',
      'com.zinli.wallet',
    ],
    hasDedicatedParser: true,
    defaultCurrency: 'USD',
  ),
  SupportedBank(
    profileId: 'binance_api',
    displayName: 'Binance',
    packageNames: ['com.binance.dev'],
    hasDedicatedParser: true,
    defaultCurrency: 'USD',
  ),

  // ── Banca venezolana — sin parser todavía (LLM fallback) ──
  SupportedBank(
    profileId: 'banesco_notif',
    displayName: 'Banesco',
    packageNames: ['com.banesco.samfbancamovilunificada'],
    playStoreUrlAliases: ['com.banesco.banescomovilpersonas'],
    hasDedicatedParser: false,
  ),
  SupportedBank(
    profileId: 'mercantil_notif',
    displayName: 'Mercantil',
    packageNames: [
      'com.mercantilbanco.mercantilmovil',
      'com.mercantilbanco.mme.mercantilmovil',
    ],
    playStoreUrlAliases: ['com.mercantil.movil'],
    hasDedicatedParser: false,
  ),
  SupportedBank(
    profileId: 'provincial_notif',
    displayName: 'BBVA Provincial',
    packageNames: [
      'com.totaltexto.bancamovil',
      'com.dinerorapido.bancamovil',
    ],
    playStoreUrlAliases: ['com.bbva.bbvacontigove'],
    hasDedicatedParser: false,
  ),
  SupportedBank(
    profileId: 'bnc_notif',
    displayName: 'BNC',
    packageNames: ['bnc.bncnet.mobile2'],
    hasDedicatedParser: false,
  ),
  SupportedBank(
    profileId: 'banplus_notif',
    displayName: 'Banplus',
    packageNames: ['com.asociadosgerenciales.banpluspay'],
    hasDedicatedParser: false,
  ),
  SupportedBank(
    profileId: 'bicentenario_notif',
    displayName: 'Banco Bicentenario',
    packageNames: ['com.unidigital.bicentenario.p2p'],
    playStoreUrlAliases: ['com.bicentenariobu.android'],
    hasDedicatedParser: false,
  ),
  SupportedBank(
    profileId: 'bancamiga_notif',
    displayName: 'Bancamiga',
    packageNames: [
      'com.bancamiga',
      'com.bancamiga.bapos',
    ],
    playStoreUrlAliases: ['com.bancamiga.movil'],
    hasDedicatedParser: false,
  ),
  SupportedBank(
    profileId: 'bancaribe_notif',
    displayName: 'Bancaribe',
    packageNames: [
      'bancaribe.miconexion',
      'bancaribe.mipago',
    ],
    playStoreUrlAliases: ['com.bancaribe.movil'],
    hasDedicatedParser: false,
  ),
  SupportedBank(
    profileId: 'plaza_notif',
    displayName: 'Banco Plaza',
    packageNames: ['com.bancoplaza.app'],
    hasDedicatedParser: false,
  ),
  SupportedBank(
    profileId: 'exterior_notif',
    displayName: 'Banco Exterior',
    packageNames: [
      'com.bancoexterior',
      'com.bancoexterior.nexomobile2',
    ],
    hasDedicatedParser: false,
  ),
  SupportedBank(
    profileId: 'activo_notif',
    displayName: 'Banco Activo',
    packageNames: ['activodigital.bancoactivo.com'],
    hasDedicatedParser: false,
  ),
  SupportedBank(
    profileId: 'tesoro_notif',
    displayName: 'Banco del Tesoro',
    packageNames: ['com.otronodo.btmovil'],
    hasDedicatedParser: false,
  ),
  SupportedBank(
    profileId: 'sofitasa_notif',
    displayName: 'Sofitasa',
    packageNames: ['com.ionicframework.st201716'],
    hasDedicatedParser: false,
  ),
  SupportedBank(
    profileId: 'caroni_notif',
    displayName: 'Banco Caroní',
    packageNames: [
      'com.click.caroni.normal.app.click',
      'com.ionicframework.bc938299',
    ],
    hasDedicatedParser: false,
  ),
  SupportedBank(
    profileId: 'bvc_notif',
    displayName: 'Venezolano de Crédito',
    packageNames: ['com.venezolano.vol_app'],
    hasDedicatedParser: false,
  ),
  SupportedBank(
    profileId: 'bfc_notif',
    displayName: 'Banco Fondo Común',
    packageNames: ['com.bfcmobile.app'],
    hasDedicatedParser: false,
  ),

  // ── Pagos digitales — sin parser todavía ──
  SupportedBank(
    profileId: 'gpay_notif',
    displayName: 'Google Pay',
    packageNames: ['com.google.android.apps.walletnfcrel'],
    hasDedicatedParser: false,
    defaultCurrency: 'USD',
  ),
  SupportedBank(
    profileId: 'mercadopago_notif',
    displayName: 'Mercado Pago',
    packageNames: [
      'com.mercadolibre',
      'com.mercadopago.wallet',
    ],
    hasDedicatedParser: false,
    defaultCurrency: 'USD',
  ),
  SupportedBank(
    profileId: 'paypal_notif',
    displayName: 'PayPal',
    packageNames: ['com.paypal.android.p2pmobile'],
    hasDedicatedParser: false,
    defaultCurrency: 'USD',
  ),

  // ── Fintech globales — sin parser todavía ──
  SupportedBank(
    profileId: 'nubank_notif',
    displayName: 'Nubank',
    packageNames: ['com.nu.production'],
    hasDedicatedParser: false,
    defaultCurrency: 'USD',
  ),
  SupportedBank(
    profileId: 'wise_notif',
    displayName: 'Wise',
    packageNames: ['com.transferwise.android'],
    hasDedicatedParser: false,
    defaultCurrency: 'USD',
  ),
  SupportedBank(
    profileId: 'revolut_notif',
    displayName: 'Revolut',
    packageNames: ['com.revolut.revolut'],
    hasDedicatedParser: false,
    defaultCurrency: 'USD',
  ),
  SupportedBank(
    profileId: 'venmo_notif',
    displayName: 'Venmo',
    packageNames: ['com.venmo'],
    hasDedicatedParser: false,
    defaultCurrency: 'USD',
  ),
  SupportedBank(
    profileId: 'cashapp_notif',
    displayName: 'Cash App',
    packageNames: ['com.squareup.cash'],
    hasDedicatedParser: false,
    defaultCurrency: 'USD',
  ),
  SupportedBank(
    profileId: 'n26_notif',
    displayName: 'N26',
    packageNames: ['de.number26.android'],
    hasDedicatedParser: false,
    defaultCurrency: 'USD',
  ),
  SupportedBank(
    profileId: 'coinbase_notif',
    displayName: 'Coinbase',
    packageNames: ['com.coinbase.android'],
    hasDedicatedParser: false,
    defaultCurrency: 'USD',
  ),
  SupportedBank(
    profileId: 'cryptocom_notif',
    displayName: 'Crypto.com',
    packageNames: ['co.mona.android'],
    hasDedicatedParser: false,
    defaultCurrency: 'USD',
  ),
  SupportedBank(
    profileId: 'cryptocom_wallet_notif',
    displayName: 'Crypto.com DeFi',
    packageNames: ['com.defi.wallet'],
    hasDedicatedParser: false,
    defaultCurrency: 'USD',
  ),
  SupportedBank(
    profileId: 'westernunion_notif',
    displayName: 'Western Union',
    packageNames: ['com.westernunion.android.mtapp'],
    hasDedicatedParser: false,
    defaultCurrency: 'USD',
  ),
  SupportedBank(
    profileId: 'remitly_notif',
    displayName: 'Remitly',
    packageNames: ['com.remitly.androidapp'],
    hasDedicatedParser: false,
    defaultCurrency: 'USD',
  ),
  SupportedBank(
    profileId: 'skrill_notif',
    displayName: 'Skrill',
    packageNames: ['com.moneybookers.skrillpayments'],
    hasDedicatedParser: false,
    defaultCurrency: 'USD',
  ),
];

// ── Derived helpers ────────────────────────────────────────────────────────

/// Map runtime package name → profileId. Used by [BankDetectionService] to
/// resolve installed apps and by [CaptureOrchestrator] to recognize known
/// bank notifications (even before a regex parser exists).
final Map<String, String> kPackageToProfileId = {
  for (final b in kSupportedBanks)
    for (final pkg in b.packageNames) pkg: b.profileId,
};

/// Map ANY package alias (runtime + Play Store URL) → profileId. Used by
/// the onboarding "Agregar manualmente" URL parser to resolve a Play Store
/// link to a known bank.
final Map<String, String> kAnyPackageToProfileId = {
  for (final b in kSupportedBanks) ...{
    for (final pkg in b.packageNames) pkg: b.profileId,
    for (final pkg in b.playStoreUrlAliases) pkg: b.profileId,
  },
};

/// Map runtime package name → human-readable display name. Used by the
/// Generic LLM profile to give the model a hint about which bank sent
/// the notification.
final Map<String, String> kPackageToDisplayName = {
  for (final b in kSupportedBanks)
    for (final pkg in b.packageNames) pkg: b.displayName,
};

/// Runtime packages of banks WITHOUT a dedicated parser (LLM fallback set).
final List<String> kPackagesWithoutDedicatedParser = [
  for (final b in kSupportedBanks)
    if (!b.hasDedicatedParser) ...b.packageNames,
];

/// All runtime packages — validated against AndroidManifest.xml `<queries>`
/// by `test/auto_import/supported_banks_manifest_sync_test.dart`.
final List<String> kAllSupportedPackages = [
  for (final b in kSupportedBanks) ...b.packageNames,
];
