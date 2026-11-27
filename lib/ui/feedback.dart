import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app/strings.dart';
import '../app/strings_ui.dart';
import '../app/theme.dart';

/// Asks before something that cannot be taken back. Returns true on confirm.
Future<bool> confirmAction(
  BuildContext context, {
  required String title,
  required String message,
  String? confirmLabel,
  String? cancelLabel,
  bool destructive = true,
}) async {
  final tr = Strings.of(context);
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        // Enter must never confirm something destructive by accident.
        TextButton(autofocus: destructive, onPressed: () => Navigator.pop(ctx, false), child: Text(cancelLabel ?? tr.cancel)),
        FilledButton(
          autofocus: !destructive,
          style: destructive
              ? FilledButton.styleFrom(backgroundColor: Theme.of(ctx).colorScheme.error, foregroundColor: Theme.of(ctx).colorScheme.onError)
              : null,
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(confirmLabel ?? tr.delete),
        ),
      ],
    ),
  );
  return ok ?? false;
}

/// Replaces any visible snackbar with [message]. With [onUndo] it gets an
/// Undo button, for changes that are cheap to reverse.
void showAppSnackBar(BuildContext context, String message, {VoidCallback? onUndo}) {
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger == null) return;
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      content: Text(message),
      duration: Duration(seconds: onUndo == null ? 3 : 5),
      action: onUndo == null ? null : SnackBarAction(label: Strings.of(context).undo, onPressed: onUndo),
    ));
}

/// Settings-style bottom sheet: opens at 60 % height and drags up to nearly full.
Future<void> showDraggableSheet(BuildContext context, Widget Function(ScrollController scroll) builder) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.6,
        maxChildSize: 0.92,
        builder: (context, scroll) => builder(scroll),
      ),
    );

/// Section title inside a bottom sheet.
class SheetHeader extends StatelessWidget {
  const SheetHeader(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
        child: Text(text, style: Theme.of(context).textTheme.labelLarge?.copyWith(color: Theme.of(context).colorScheme.primary)),
      );
}

/// Light tick for long presses and selection changes (no-op on desktop).
void hapticTick() => HapticFeedback.selectionClick();

/// One row of a bottom action sheet shown by [showActionSheet].
class SheetAction<T> {
  const SheetAction({required this.value, required this.icon, required this.label, this.destructive = false});
  final T value;
  final IconData icon;
  final String label;
  final bool destructive;
}

/// Bottom sheet with a title and a list of actions; returns the chosen value.
/// Use it for long-press and "more" menus so they are reachable by thumb.
Future<T?> showActionSheet<T>(BuildContext context, {required String title, required List<SheetAction<T>> actions}) {
  return showModalBottomSheet<T>(
    context: context,
    constraints: const BoxConstraints(maxWidth: 560),
    builder: (ctx) => SafeArea(
      child: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(Gap.l, 0, Gap.l, Gap.s),
            child: Text(title, maxLines: 2, overflow: TextOverflow.ellipsis, style: Theme.of(ctx).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
          ),
          for (final a in actions)
            ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: Gap.l),
              leading: Icon(a.icon, color: a.destructive ? Theme.of(ctx).colorScheme.error : null),
              title: Text(a.label, style: a.destructive ? TextStyle(color: Theme.of(ctx).colorScheme.error) : null),
              onTap: () => Navigator.pop(ctx, a.value),
            ),
          const SizedBox(height: Gap.s),
        ]),
      ),
    ),
  );
}
