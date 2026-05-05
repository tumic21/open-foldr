import 'package:flutter/material.dart';

enum ViewMode { list, grid }

class ViewModeToggle extends StatelessWidget {
  final ViewMode mode;
  final ValueChanged<ViewMode>? onChanged;

  const ViewModeToggle({super.key, required this.mode, this.onChanged});

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: mode == ViewMode.list ? 'Switch to grid view' : 'Switch to list view',
      icon: Icon(mode == ViewMode.list ? Icons.grid_view : Icons.list),
      onPressed: onChanged == null
          ? null
          : () => onChanged!(
              mode == ViewMode.list ? ViewMode.grid : ViewMode.list),
    );
  }
}
