import 'dart:async';

import 'package:flutter/material.dart';
import 'package:wallex/core/utils/debouncer.dart';

class WallexTileSwitch extends StatefulWidget {
  const WallexTileSwitch({
    super.key,
    required this.title,
    this.subtitle,
    this.initialValue = false,
    this.icon,
    required this.onSwitch,
    this.syncWithInitialValue = true,
    this.disabled = false,
    this.onSwitchDebounceMs = 0,
    this.restoreValueOnSwitchError = true,
    this.onSwitchError,
  });

  final String title;
  final String? subtitle;
  final bool initialValue;
  final Widget? icon;

  /// Callback triggered when the switch value changes.
  ///
  /// The callback provides the new value as a parameter.
  final Function(bool)? onSwitch;

  /// Callback triggered when an error occurs during [onSwitch].
  final Function()? onSwitchError;

  /// Whether the switch toggle value should be restored to its previous state if [onSwitch] throws an error.
  final bool restoreValueOnSwitchError;

  /// The debounce duration in milliseconds before [onSwitch] is triggered.
  final int onSwitchDebounceMs;

  final bool syncWithInitialValue;

  /// Whether the switch is disabled and cannot be interacted with
  final bool disabled;

  @override
  State<WallexTileSwitch> createState() => _WallexTileSwitchState();
}

class _WallexTileSwitchState extends State<WallexTileSwitch> {
  bool value = true;
  late final Debouncer _debouncer;

  @override
  void initState() {
    super.initState();
    value = widget.initialValue;
    _debouncer = Debouncer(milliseconds: widget.onSwitchDebounceMs);
  }

  @override
  void didUpdateWidget(WallexTileSwitch oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (widget.initialValue != value && widget.syncWithInitialValue) {
      setState(() {
        value = widget.initialValue;
      });
    }
  }

  Future<void> toggleSwitch() async {
    if (widget.onSwitch == null) {
      return;
    }

    value = !value;

    setState(() {});

    _debouncer.run(() async {
      try {
        await widget.onSwitch!(value);
      } catch (e) {
        if (widget.onSwitchError != null) {
          widget.onSwitchError!();
        }

        if (widget.restoreValueOnSwitchError) {
          value = !value;
          setState(() {});
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return SwitchListTile(
      title: Text(widget.title),
      subtitle: widget.subtitle == null ? null : Text(widget.subtitle!),
      secondary: widget.icon,
      value: value,
      onChanged: widget.disabled
          ? null
          : (_) {
              toggleSwitch();
            },
    );
  }
}
