import 'package:flutter/material.dart';

/// Dimension for breaking down income data
enum BreakdownDimension { tag, category }

/// A Material 3 SegmentedButton that toggles between "Por Tag" and "Por Categoría".
class SourceDimensionToggle extends StatelessWidget {
  const SourceDimensionToggle({
    super.key,
    required this.value,
    required this.onChanged,
  });

  final BreakdownDimension value;
  final ValueChanged<BreakdownDimension> onChanged;

  @override
  Widget build(BuildContext context) {
    return SegmentedButton<BreakdownDimension>(
      segments: const [
        ButtonSegment(
          value: BreakdownDimension.tag,
          label: Text('Por Tag'), // TODO: i18n
          icon: Icon(Icons.label_rounded),
        ),
        ButtonSegment(
          value: BreakdownDimension.category,
          label: Text('Por Categoría'), // TODO: i18n
          icon: Icon(Icons.category_rounded),
        ),
      ],
      showSelectedIcon: false,
      selected: {value},
      onSelectionChanged: (newSelection) {
        onChanged(newSelection.first);
      },
    );
  }
}
