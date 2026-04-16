import 'bank_profile.dart';
import 'bdv_notif_profile.dart';
import 'bdv_sms_profile.dart';
import 'binance_api_profile.dart';

/// Global registry of all bank profiles.
///
/// The [CaptureOrchestrator] iterates this list to find a matching profile
/// for each incoming [RawCaptureEvent].
final List<BankProfile> bankProfilesRegistry = [
  BdvSmsProfile(),
  BdvNotifProfile(),
  BinanceApiProfile(),
  // Tanda 3C: ZinliNotifProfile
];
