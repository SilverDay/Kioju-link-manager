import 'package:flutter/material.dart';

/// A custom radio tile that avoids deprecated Radio widget parameters
class CustomRadioTile<T> extends StatelessWidget {
  final T value;
  final T? groupValue;
  final ValueChanged<T?>? onChanged;
  final Widget? title;
  final Widget? subtitle;
  final bool dense;
  final EdgeInsetsGeometry? contentPadding;

  const CustomRadioTile({
    super.key,
    required this.value,
    required this.groupValue,
    required this.onChanged,
    this.title,
    this.subtitle,
    this.dense = false,
    this.contentPadding,
  });

  @override
  Widget build(BuildContext context) {
    final isSelected = value == groupValue;

    return InkWell(
      onTap: onChanged != null ? () => onChanged!(value) : null,
      child: Padding(
        padding:
            contentPadding ??
            const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
        child: Row(
          children: [
            // Custom radio button using Container and decoration
            Container(
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color:
                      isSelected
                          ? Theme.of(context).colorScheme.primary
                          : Theme.of(context).colorScheme.outline,
                  width: 2,
                ),
                color:
                    isSelected
                        ? Theme.of(context).colorScheme.primary
                        : Colors.transparent,
              ),
              child:
                  isSelected
                      ? Icon(
                        Icons.circle,
                        size: 10,
                        color: Theme.of(context).colorScheme.onPrimary,
                      )
                      : null,
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (title != null)
                    DefaultTextStyle(
                      style: Theme.of(context).textTheme.bodyLarge!,
                      child: title!,
                    ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 4),
                    DefaultTextStyle(
                      style: Theme.of(context).textTheme.bodyMedium!.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                      child: subtitle!,
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
