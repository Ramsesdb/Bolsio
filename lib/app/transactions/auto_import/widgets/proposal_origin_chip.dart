import 'package:flutter/material.dart';
import 'package:bolsio/core/models/auto_import/capture_channel.dart';

/// Chip displaying the origin of a captured proposal (SMS, Notification, API).
class ProposalOriginChip extends StatelessWidget {
  const ProposalOriginChip({
    super.key,
    required this.channel,
    this.sender,
  });

  final String channel;
  final String? sender;

  @override
  Widget build(BuildContext context) {
    final channelEnum = CaptureChannel.fromDbValue(channel);
    final (icon, label) = _channelData(channelEnum);

    return Chip(
      avatar: Icon(icon, size: 16),
      label: Text(
        label,
        style: const TextStyle(fontSize: 12),
      ),
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      padding: EdgeInsets.zero,
      side: BorderSide(
        color: Theme.of(context).colorScheme.outlineVariant,
      ),
    );
  }

  (IconData, String) _channelData(CaptureChannel ch) {
    switch (ch) {
      case CaptureChannel.sms:
        final senderSuffix =
            sender != null ? ' ($sender)' : '';
        return (Icons.sms_outlined, 'SMS BDV$senderSuffix');
      case CaptureChannel.notification:
        final bankName = _bankNameFromSender(sender);
        return (Icons.notifications_outlined, 'Notif $bankName');
      case CaptureChannel.api:
        final apiName = _apiNameFromSender(sender);
        return (Icons.sync, '$apiName API');
      case CaptureChannel.receiptImage:
        return (Icons.receipt_long, 'Comprobante');
      case CaptureChannel.voice:
        return (Icons.mic_none_rounded, 'Voz');
    }
  }

  String _bankNameFromSender(String? sender) {
    if (sender == null) return '';
    if (sender.contains('bdv')) return 'BDV';
    if (sender.contains('binance')) return 'Binance';
    if (sender.contains('zinli')) return 'Zinli';
    return sender;
  }

  String _apiNameFromSender(String? sender) {
    if (sender == null) return 'API';
    if (sender.contains('binance')) return 'Binance';
    return sender;
  }
}
