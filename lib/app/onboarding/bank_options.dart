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
  });

  /// Stable id used for [PersonalVESeeder.seedAll] selection.
  final String id;

  final String name;
  final Color color;
  final IconData icon;

  /// Matching [BankProfile.profileId] when the bank has an auto-import
  /// profile. Null for banks not yet supported by auto-import.
  final String? profileId;
}

const kBanks = <BankOption>[
  BankOption(
    id: 'bdv',
    name: 'Banco de Venezuela',
    color: Color(0xFF1A237E),
    icon: Icons.account_balance,
    profileId: 'bdv_notif',
  ),
  BankOption(
    id: 'banesco',
    name: 'Banesco',
    color: Color(0xFF003087),
    icon: Icons.account_balance,
  ),
  BankOption(
    id: 'mercantil',
    name: 'Mercantil',
    color: Color(0xFFB71C1C),
    icon: Icons.account_balance,
  ),
  BankOption(
    id: 'provincial',
    name: 'Provincial',
    color: Color(0xFF2E7D32),
    icon: Icons.account_balance,
  ),
  BankOption(
    id: 'bnc',
    name: 'BNC',
    color: Color(0xFF00838F),
    icon: Icons.account_balance,
  ),
  BankOption(
    id: 'banplus',
    name: 'Banplus',
    color: Color(0xFFEF6C00),
    icon: Icons.account_balance,
  ),
  BankOption(
    id: 'bicentenario',
    name: 'Bicentenario',
    color: Color(0xFFC62828),
    icon: Icons.account_balance,
  ),
  BankOption(
    id: 'bancamiga',
    name: 'Bancamiga',
    color: Color(0xFF6A1B9A),
    icon: Icons.account_balance,
  ),
  BankOption(
    id: 'binance',
    name: 'Binance',
    color: Color(0xFFF3BA2F),
    icon: Icons.currency_bitcoin,
    profileId: 'binance_api',
  ),
  BankOption(
    id: 'zinli',
    name: 'Zinli',
    color: Color(0xFF6A1B9A),
    icon: Icons.wallet,
    profileId: 'zinli_notif',
  ),
  BankOption(
    id: 'reserve',
    name: 'Reserve',
    color: Color(0xFF1565C0),
    icon: Icons.wallet,
  ),
  BankOption(
    id: 'paypal',
    name: 'PayPal',
    color: Color(0xFF003087),
    icon: Icons.payment,
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
