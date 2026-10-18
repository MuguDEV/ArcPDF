import 'package:flutter/material.dart';
import '../../theme/arc_colors.dart';

class AppBottomSheet extends StatelessWidget {
  const AppBottomSheet({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
        decoration: const BoxDecoration(
          color: ArcColors.surfaceToken,
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(ArcColors.sheetRadius),
          ),
        ),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: ArcColors.space12),
              Container(
                width: 100,
                height: ArcColors.space4,
                decoration: const BoxDecoration(
                  color: ArcColors.handle,
                  borderRadius:
                      BorderRadius.all(Radius.circular(ArcColors.space4)),
                ),
              ),
              const SizedBox(height: ArcColors.space12),
              Flexible(child: child),
              SizedBox(height: MediaQuery.paddingOf(context).bottom),
            ],
          ),
        ),
      );
}

class SheetSectionHeader extends StatelessWidget {
  const SheetSectionHeader({super.key, required this.title, this.first = false});
  final String title;
  final bool first;

  @override
  Widget build(BuildContext context) => Container(
        decoration: first
            ? null
            : const BoxDecoration(
                border: Border(top: BorderSide(color: ArcColors.divider)),
              ),
        padding: const EdgeInsets.fromLTRB(
          ArcColors.screenPadding,
          ArcColors.space16,
          ArcColors.screenPadding,
          ArcColors.space8,
        ),
        alignment: Alignment.centerLeft,
        child: Text(title, style: Theme.of(context).textTheme.titleMedium),
      );
}

class SheetActionRow extends StatelessWidget {
  const SheetActionRow({
    super.key,
    required this.icon,
    required this.label,
    this.onTap,
    this.trailing,
    this.destructive = false,
  });
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final Widget? trailing;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final color = destructive ? Theme.of(context).colorScheme.error : null;
    return InkWell(
      onTap: onTap,
      child: SizedBox(
        height: ArcColors.minRowHeight,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: ArcColors.screenPadding),
          child: Row(
            children: [
              Icon(icon, size: 28, color: color),
              const SizedBox(width: ArcColors.space12),
              Expanded(
                child: Text(
                  label,
                  style: Theme.of(context)
                      .textTheme
                      .bodyLarge
                      ?.copyWith(color: color),
                ),
              ),
              if (trailing != null) trailing!,
            ],
          ),
        ),
      ),
    );
  }
}

class SheetRadioRow<T> extends StatelessWidget {
  const SheetRadioRow({
    super.key,
    required this.value,
    required this.groupValue,
    required this.label,
    required this.onChanged,
  });
  final T value;
  final T groupValue;
  final String label;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final selected = value == groupValue;
    return InkWell(
      onTap: () => onChanged(value),
      child: SizedBox(
        height: ArcColors.minRowHeight,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: ArcColors.screenPadding),
          child: Row(
            children: [
              Icon(
                selected
                    ? Icons.radio_button_checked
                    : Icons.radio_button_unchecked,
                size: 24,
                color: selected ? ArcColors.active : ArcColors.outlineToken,
              ),
              const SizedBox(width: ArcColors.space12),
              Text(label, style: Theme.of(context).textTheme.bodyLarge),
            ],
          ),
        ),
      ),
    );
  }
}

class AppDialog extends StatelessWidget {
  const AppDialog({
    super.key,
    required this.title,
    required this.child,
    this.actions = const [],
  });
  final String title;
  final Widget child;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(title, style: Theme.of(context).textTheme.titleMedium),
        content: child,
        actions: actions,
      );
}

Future<T?> showAppDialog<T>({
  required BuildContext context,
  required WidgetBuilder builder,
}) =>
    showDialog<T>(context: context, builder: builder);

class AppCard extends StatelessWidget {
  const AppCard({super.key, required this.child, this.onTap});
  final Widget child;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Card(
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(ArcColors.cardRadius),
          child: Padding(
            padding: const EdgeInsets.all(ArcColors.space16),
            child: child,
          ),
        ),
      );
}

class AppTextField extends StatelessWidget {
  const AppTextField({super.key, this.controller, this.hintText});
  final TextEditingController? controller;
  final String? hintText;

  @override
  Widget build(BuildContext context) => TextField(
        controller: controller,
        decoration: InputDecoration(hintText: hintText),
      );
}

class AppSearchBar extends StatelessWidget {
  const AppSearchBar({super.key, required this.controller, this.hintText});
  final TextEditingController controller;
  final String? hintText;

  @override
  Widget build(BuildContext context) => TextField(
        controller: controller,
        decoration: InputDecoration(
          hintText: hintText,
          prefixIcon: const Icon(Icons.search),
        ),
      );
}

class AppSwitch extends StatelessWidget {
  const AppSwitch({super.key, required this.value, required this.onChanged});
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) =>
      Switch(value: value, onChanged: onChanged);
}

class AppCheckbox extends StatelessWidget {
  const AppCheckbox({super.key, required this.value, required this.onChanged});
  final bool value;
  final ValueChanged<bool?> onChanged;

  @override
  Widget build(BuildContext context) =>
      Checkbox(value: value, onChanged: onChanged);
}

class AppChip extends StatelessWidget {
  const AppChip({super.key, required this.label, this.onSelected});
  final String label;
  final ValueChanged<bool>? onSelected;

  @override
  Widget build(BuildContext context) => FilterChip(
        label: Text(label),
        selected: false,
        onSelected: onSelected,
      );
}
