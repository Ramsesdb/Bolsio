import 'package:flutter/foundation.dart';
import 'package:wallex/core/models/auto_import/capture_channel.dart';
import 'package:wallex/core/models/auto_import/raw_capture_event.dart';
import 'package:wallex/core/models/auto_import/transaction_proposal.dart';

/// Outcome of a [BankProfile.tryParseWithDetails] invocation.
///
/// Carries either a parsed [TransactionProposal] (on success) or a
/// human-readable [failureReason] (on failure), so the capture diagnostics
/// surface can tell the user exactly why a message was rejected.
@immutable
class ParseResult {
  final bool success;
  final TransactionProposal? transaction;
  final String? failureReason;

  const ParseResult._({
    required this.success,
    this.transaction,
    this.failureReason,
  });

  factory ParseResult.parsed(TransactionProposal proposal) =>
      ParseResult._(success: true, transaction: proposal);

  factory ParseResult.failed(String reason) =>
      ParseResult._(success: false, failureReason: reason);
}

/// Abstract interface for a bank-specific message parser.
///
/// Each bank (and each channel within a bank) has its own profile that knows
/// how to extract transaction data from raw SMS or notification text.
///
/// Profiles are registered in [bankProfilesRegistry] and matched by
/// [channel] + [knownSenders].
abstract class BankProfile {
  /// Human-readable bank name (e.g. 'Banco de Venezuela').
  String get bankName;

  /// Name used to match against [Account.name] in the database.
  ///
  /// This must exactly match the account name as created by the user or seeder.
  String get accountMatchName;

  /// Which capture channel this profile handles.
  CaptureChannel get channel;

  /// Known sender identifiers for this profile.
  ///
  /// For SMS profiles: shortcodes like `['2661']`.
  /// For notification profiles: package names like `['com.bdv.personas']`.
  List<String> get knownSenders;

  /// Profile version number for evolution without breaking existing data.
  ///
  /// Increment when regex patterns change significantly.
  int get profileVersion;

  /// Attempt to parse a [RawCaptureEvent] into a [TransactionProposal].
  ///
  /// The [accountId] is pre-resolved by the orchestrator (looked up by
  /// [accountMatchName]) so the profile does not need database access.
  ///
  /// Returns `null` if the event does not match any known transaction pattern
  /// (e.g. OTP codes, verification messages).
  TransactionProposal? tryParse(
    RawCaptureEvent event, {
    required String? accountId,
  });

  /// Same as [tryParse] but returns a structured [ParseResult] carrying a
  /// human-readable reason on failure.
  ///
  /// Profiles that want to expose granular diagnostics should override this.
  /// The default implementation just delegates to [tryParse] and reports a
  /// generic failure reason — which keeps existing profiles functional.
  ParseResult tryParseWithDetails(
    RawCaptureEvent event, {
    required String? accountId,
  }) {
    final proposal = tryParse(event, accountId: accountId);
    if (proposal != null) {
      return ParseResult.parsed(proposal);
    }
    return ParseResult.failed('El perfil no pudo extraer una transacción');
  }
}
