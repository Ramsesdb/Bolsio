import 'package:flutter/material.dart';

class SettingsSearchBar extends StatelessWidget {
  const SettingsSearchBar({super.key, required this.onChanged});

  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SearchBar(
      leading: const Icon(Icons.search),
      hintText: 'Buscar en ajustes…',
      onChanged: onChanged,
      elevation: const WidgetStatePropertyAll(0),
      backgroundColor: WidgetStatePropertyAll(theme.cardColor),
      shape: WidgetStatePropertyAll(
        RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: theme.dividerColor),
        ),
      ),
    );
  }
}
