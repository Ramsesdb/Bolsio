import 'package:flutter/material.dart';

/// Descriptor for a bank option shown in slide 4 (selectable) and slide 8
/// (per-profile toggle). Static list maintained in-repo; placeholders are
/// rendered geometrically so no SVG assets are required.
class BankOption {
  const BankOption({
    required this.id,
    required this.name,
    required this.color,
    required this.icon,
    this.profileId,
    this.autoImportSupported = true,
    this.defaultCurrency = 'VES',
    this.supportsBoth = false,
  });

  /// Stable id used for [PersonalVESeeder.seedAll] selection.
  final String id;

  final String name;
  final Color color;
  final IconData icon;

  /// Matching [BankProfile.profileId] when the bank has an auto-import
  /// profile. Null for banks not yet supported by auto-import.
  final String? profileId;

  /// Whether this bank/app has a dedicated regex/API parser implemented.
  /// When `true`, a specific [BankProfile] handles parsing directly.
  /// When `false`, the generic LLM fallback ([GenericLlmProfile]) is used
  /// instead — all apps are effectively supported, just with different parsers.
  ///
  /// BDV, Zinli and Binance have `true` (dedicated parsers); all others
  /// rely on the AI fallback and also have `true` now that [GenericLlmProfile]
  /// is production-ready.
  final bool autoImportSupported;

  /// Native currency for the bank/wallet. Used by the seeder to decide the
  /// `currencyId` of the always-on account. `'VES'` for Venezuelan banks,
  /// `'USD'` for international wallets/fintech.
  final String defaultCurrency;

  /// Whether this bank also offers a USD-denominated account (custodios
  /// or equivalent). When true AND the user picked DUAL in s02, the s04
  /// tile renders a sub-row "Cuenta en USD también" toggle that, when
  /// enabled, makes the seeder create a second USD account in addition to
  /// the native-currency one.
  final bool supportsBoth;
}

const kBanks = <BankOption>[
  // ── Banca venezolana — con parser real ──
  BankOption(
    id: 'bdv',
    name: 'Banco de Venezuela',
    color: Color(0xFF1A237E),
    icon: Icons.account_balance,
    profileId: 'bdv_notif',
    autoImportSupported: true,
    defaultCurrency: 'VES',
    supportsBoth: true,
  ),
  BankOption(
    id: 'zinli',
    name: 'Zinli',
    color: Color(0xFF6A1B9A),
    icon: Icons.wallet,
    profileId: 'zinli_notif',
    autoImportSupported: true,
    defaultCurrency: 'USD',
  ),
  BankOption(
    id: 'binance',
    name: 'Binance',
    color: Color(0xFFF3BA2F),
    icon: Icons.currency_bitcoin,
    profileId: 'binance_api',
    autoImportSupported: true,
    defaultCurrency: 'USD',
  ),

  // ── Banca venezolana — sin parser todavía ──
  BankOption(
    id: 'banesco',
    name: 'Banesco',
    color: Color(0xFF0066CC),
    icon: Icons.account_balance,
    profileId: 'banesco_notif',
    defaultCurrency: 'VES',
    supportsBoth: true,
  ),
  BankOption(
    id: 'mercantil',
    name: 'Mercantil',
    color: Color(0xFF003F87),
    icon: Icons.account_balance,
    profileId: 'mercantil_notif',
    defaultCurrency: 'VES',
    supportsBoth: true,
  ),
  BankOption(
    id: 'provincial',
    name: 'BBVA Provincial',
    color: Color(0xFF004481),
    icon: Icons.account_balance,
    profileId: 'provincial_notif',
    defaultCurrency: 'VES',
    supportsBoth: true,
  ),
  BankOption(
    id: 'bnc',
    name: 'BNC',
    color: Color(0xFF005A9C),
    icon: Icons.account_balance,
    profileId: 'bnc_notif',
    defaultCurrency: 'VES',
    supportsBoth: true,
  ),
  BankOption(
    id: 'banplus',
    name: 'Banplus',
    color: Color(0xFFE30613),
    icon: Icons.account_balance,
    profileId: 'banplus_notif',
    defaultCurrency: 'VES',
    supportsBoth: true,
  ),
  BankOption(
    id: 'bicentenario',
    name: 'Bicentenario',
    color: Color(0xFFC8102E),
    icon: Icons.account_balance,
    profileId: 'bicentenario_notif',
    defaultCurrency: 'VES',
    supportsBoth: true,
  ),
  BankOption(
    id: 'bancamiga',
    name: 'Bancamiga',
    color: Color(0xFFFF6F00),
    icon: Icons.account_balance,
    profileId: 'bancamiga_notif',
    defaultCurrency: 'VES',
    supportsBoth: true,
  ),
  BankOption(
    id: 'bancaribe',
    name: 'Bancaribe',
    color: Color(0xFFE30613),
    icon: Icons.account_balance,
    profileId: 'bancaribe_notif',
    defaultCurrency: 'VES',
    supportsBoth: true,
  ),
  BankOption(
    id: 'plaza',
    name: 'Banco Plaza',
    color: Color(0xFF005EB8),
    icon: Icons.account_balance,
    profileId: 'plaza_notif',
    defaultCurrency: 'VES',
    supportsBoth: true,
  ),
  BankOption(
    id: 'exterior',
    name: 'Banco Exterior',
    color: Color(0xFF1A5490),
    icon: Icons.account_balance,
    profileId: 'exterior_notif',
    defaultCurrency: 'VES',
    supportsBoth: true,
  ),
  BankOption(
    id: 'activo',
    name: 'Banco Activo',
    color: Color(0xFFE30613),
    icon: Icons.account_balance,
    profileId: 'activo_notif',
    defaultCurrency: 'VES',
    supportsBoth: true,
  ),
  BankOption(
    id: 'tesoro',
    name: 'Banco del Tesoro',
    color: Color(0xFFF7B500),
    icon: Icons.account_balance,
    profileId: 'tesoro_notif',
    defaultCurrency: 'VES',
    supportsBoth: true,
  ),
  BankOption(
    id: 'sofitasa',
    name: 'Sofitasa',
    color: Color(0xFF0033A0),
    icon: Icons.account_balance,
    profileId: 'sofitasa_notif',
    defaultCurrency: 'VES',
    supportsBoth: true,
  ),
  BankOption(
    id: 'caroni',
    name: 'Banco Caroní',
    color: Color(0xFF003DA5),
    icon: Icons.account_balance,
    profileId: 'caroni_notif',
    defaultCurrency: 'VES',
    supportsBoth: true,
  ),
  BankOption(
    id: 'bvc',
    name: 'Venezolano de Crédito',
    color: Color(0xFF003478),
    icon: Icons.account_balance,
    profileId: 'bvc_notif',
    defaultCurrency: 'VES',
    supportsBoth: true,
  ),
  BankOption(
    id: 'bfc',
    name: 'Banco Fondo Común',
    color: Color(0xFF00A99D),
    icon: Icons.account_balance,
    profileId: 'bfc_notif',
    defaultCurrency: 'VES',
    supportsBoth: true,
  ),

  // ── Pagos digitales — sin parser todavía ──
  BankOption(
    id: 'gpay',
    name: 'Google Pay',
    color: Color(0xFF5F6368),
    icon: Icons.payment,
    profileId: 'gpay_notif',
    defaultCurrency: 'USD',
  ),
  BankOption(
    id: 'mercadopago',
    name: 'Mercado Pago',
    color: Color(0xFFFFE600),
    icon: Icons.payment,
    profileId: 'mercadopago_notif',
    defaultCurrency: 'USD',
  ),
  BankOption(
    id: 'paypal',
    name: 'PayPal',
    color: Color(0xFF003087),
    icon: Icons.payment,
    profileId: 'paypal_notif',
    defaultCurrency: 'USD',
  ),

  // ── Fintech globales — sin parser todavía ──
  BankOption(
    id: 'nubank',
    name: 'Nubank',
    color: Color(0xFF820AD1),
    icon: Icons.account_balance_wallet,
    profileId: 'nubank_notif',
    defaultCurrency: 'USD',
  ),
  BankOption(
    id: 'wise',
    name: 'Wise',
    color: Color(0xFF9FE870),
    icon: Icons.account_balance_wallet,
    profileId: 'wise_notif',
    defaultCurrency: 'USD',
  ),
  BankOption(
    id: 'revolut',
    name: 'Revolut',
    color: Color(0xFF0666EB),
    icon: Icons.account_balance_wallet,
    profileId: 'revolut_notif',
    defaultCurrency: 'USD',
  ),
  BankOption(
    id: 'venmo',
    name: 'Venmo',
    color: Color(0xFF3D95CE),
    icon: Icons.payment,
    profileId: 'venmo_notif',
    defaultCurrency: 'USD',
  ),
  BankOption(
    id: 'cashapp',
    name: 'Cash App',
    color: Color(0xFF00D632),
    icon: Icons.payment,
    profileId: 'cashapp_notif',
    defaultCurrency: 'USD',
  ),
  BankOption(
    id: 'n26',
    name: 'N26',
    color: Color(0xFF36A18B),
    icon: Icons.account_balance_wallet,
    profileId: 'n26_notif',
    defaultCurrency: 'USD',
  ),
  BankOption(
    id: 'coinbase',
    name: 'Coinbase',
    color: Color(0xFF0052FF),
    icon: Icons.account_balance_wallet,
    profileId: 'coinbase_notif',
    defaultCurrency: 'USD',
  ),
  BankOption(
    id: 'cryptocom',
    name: 'Crypto.com',
    color: Color(0xFF001F5C),
    icon: Icons.account_balance_wallet,
    profileId: 'cryptocom_notif',
    defaultCurrency: 'USD',
  ),
  BankOption(
    id: 'westernunion',
    name: 'Western Union',
    color: Color(0xFFFFDD00),
    icon: Icons.payment,
    profileId: 'westernunion_notif',
    defaultCurrency: 'USD',
  ),
  BankOption(
    id: 'remitly',
    name: 'Remitly',
    color: Color(0xFF003366),
    icon: Icons.payment,
    profileId: 'remitly_notif',
    defaultCurrency: 'USD',
  ),
  BankOption(
    id: 'skrill',
    name: 'Skrill',
    color: Color(0xFF862165),
    icon: Icons.payment,
    profileId: 'skrill_notif',
    defaultCurrency: 'USD',
  ),

  // ── Otros (sin profileId ni detección) ──
  BankOption(
    id: 'reserve',
    name: 'Reserve',
    color: Color(0xFF1565C0),
    icon: Icons.wallet,
    defaultCurrency: 'USD',
  ),
];

/// Maps a [BankProfile.profileId] to the matching [BankOption]. Used by
/// slide 8 to render a tile for each detected bank app.
BankOption? bankOptionByProfileId(String profileId) {
  for (final b in kBanks) {
    if (b.profileId == profileId) return b;
  }
  return null;
}
