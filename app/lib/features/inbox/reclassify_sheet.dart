import 'package:flutter/material.dart';

import '../../core/theme/tokens.dart';
import '../../data/models.dart';
import '../../widgets/category_style.dart';

Future<EmailCategory?> showReclassifySheet(
  BuildContext context,
  EmailCategory current,
) {
  return showModalBottomSheet<EmailCategory>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (context) => _ReclassifySheet(current: current),
  );
}

class _ReclassifySheet extends StatelessWidget {
  const _ReclassifySheet({required this.current});

  final EmailCategory current;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        Space.gutter(context),
        Space.s2,
        Space.gutter(context),
        Space.s6,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Reclassify email',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: Space.s4),
          RadioGroup<EmailCategory>(
            groupValue: current,
            onChanged: (val) {
              if (val != null) Navigator.of(context).pop(val);
            },
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: EmailCategory.values.map((category) {
                final style = CategoryStyle.of(context, category);
                final isSelected = category == current;
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(style.icon, color: style.color),
                  title: Text(
                    style.label,
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      fontWeight: isSelected
                          ? FontWeight.w600
                          : FontWeight.w400,
                    ),
                  ),
                  trailing: Radio<EmailCategory>(
                    value: category,
                    activeColor: style.color,
                  ),
                  onTap: () => Navigator.of(context).pop(category),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }
}
