import 'package:flutter/material.dart';

enum SortField { name, size, date, type }

enum SortOrder { asc, desc }

class SortMenu extends StatelessWidget {
  final SortField sortBy;
  final SortOrder sortOrder;
  final void Function(SortField field, SortOrder order)? onChanged;

  const SortMenu({
    super.key,
    required this.sortBy,
    required this.sortOrder,
    this.onChanged,
  });

  String _fieldLabel(SortField f) => switch (f) {
        SortField.name => 'Name',
        SortField.size => 'Size',
        SortField.date => 'Date',
        SortField.type => 'Type',
      };

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      tooltip: 'Sort',
      icon: const Icon(Icons.sort),
      itemBuilder: (_) {
        return SortField.values.map((field) {
          final isActive = sortBy == field;
          return PopupMenuItem<String>(
            value: 'field_${field.name}',
            child: Row(
              children: [
                SizedBox(
                  width: 24,
                  child: isActive
                      ? const Icon(Icons.check, size: 16)
                      : null,
                ),
                const SizedBox(width: 4),
                Text(_fieldLabel(field)),
                if (isActive) ...[
                  const Spacer(),
                  Icon(
                    sortOrder == SortOrder.asc
                        ? Icons.arrow_upward
                        : Icons.arrow_downward,
                    size: 14,
                  ),
                ],
              ],
            ),
          );
        }).toList();
      },
      onSelected: (value) {
        if (onChanged == null) return;
        final field = SortField.values
            .firstWhere((f) => 'field_${f.name}' == value);
        final newOrder = sortBy == field
            ? (sortOrder == SortOrder.asc ? SortOrder.desc : SortOrder.asc)
            : SortOrder.asc;
        onChanged!(field, newOrder);
      },
    );
  }
}
