import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Shows action forms as a full-width sheet on narrow screens.
Future<T?> showAdaptiveAction<T>({
  required BuildContext context,
  required WidgetBuilder builder,
}) {
  if (MediaQuery.sizeOf(context).width >= 560) {
    return showDialog<T>(context: context, builder: builder);
  }
  return showModalBottomSheet<T>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: Theme.of(context).colorScheme.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (sheetContext) {
      final media = MediaQuery.of(sheetContext);
      final theme = Theme.of(sheetContext);
      final availableHeight = math.max(
        0.0,
        math.min(
          media.size.height * .88,
          media.size.height - media.viewInsets.bottom - media.padding.top - 32,
        ),
      );
      return AnimatedPadding(
        duration: const Duration(milliseconds: 150),
        padding: EdgeInsets.only(bottom: media.viewInsets.bottom),
        child: SafeArea(
          top: false,
          child: MediaQuery.removeViewInsets(
            context: sheetContext,
            removeBottom: true,
            child: Theme(
              data: theme.copyWith(
                dialogTheme: theme.dialogTheme.copyWith(
                  insetPadding: EdgeInsets.zero,
                  alignment: Alignment.bottomCenter,
                  constraints: BoxConstraints.tightFor(width: media.size.width),
                  elevation: 0,
                  shape: const RoundedRectangleBorder(),
                ),
              ),
              child: ConstrainedBox(
                constraints: BoxConstraints(maxHeight: availableHeight),
                child: builder(sheetContext),
              ),
            ),
          ),
        ),
      );
    },
  );
}
