import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Controller shared by the sheet and its primary scrollable content.
class ActionSheetScroll extends InheritedWidget {
  const ActionSheetScroll({
    required this.controller,
    required super.child,
    super.key,
  });
  final ScrollController controller;

  static ScrollController? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<ActionSheetScroll>()
      ?.controller;

  @override
  bool updateShouldNotify(ActionSheetScroll oldWidget) =>
      controller != oldWidget.controller;
}

/// Shows action forms as an expandable full-width sheet on narrow screens.
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
    enableDrag: false,
    backgroundColor: Colors.transparent,
    builder: (_) => _ExpandableActionSheet(builder: builder),
  );
}

class _ExpandableActionSheet extends StatefulWidget {
  const _ExpandableActionSheet({required this.builder});
  final WidgetBuilder builder;

  @override
  State<_ExpandableActionSheet> createState() => _ExpandableActionSheetState();
}

class _ExpandableActionSheetState extends State<_ExpandableActionSheet> {
  final _sheet = DraggableScrollableController();
  static const _min = .32, _initial = .68, _max = .96;

  @override
  void dispose() {
    _sheet.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final theme = Theme.of(context);
    return AnimatedPadding(
      duration: const Duration(milliseconds: 150),
      padding: EdgeInsets.only(bottom: media.viewInsets.bottom),
      child: MediaQuery.removeViewInsets(
        context: context,
        removeBottom: true,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final height = math.max(1.0, constraints.maxHeight);
            return DraggableScrollableSheet(
              controller: _sheet,
              minChildSize: _min,
              initialChildSize: _initial,
              maxChildSize: _max,
              expand: false,
              snap: true,
              snapSizes: const [_initial],
              builder: (context, scrollController) => Material(
                color: theme.colorScheme.surface,
                clipBehavior: Clip.antiAlias,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(24),
                ),
                child: SafeArea(
                  top: false,
                  child: Column(
                    children: [
                      GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onVerticalDragUpdate: (details) {
                          if (_sheet.isAttached) {
                            _sheet.jumpTo(
                              (_sheet.size - details.delta.dy / height).clamp(
                                _min,
                                _max,
                              ),
                            );
                          }
                        },
                        onVerticalDragEnd: (details) {
                          if (!_sheet.isAttached) return;
                          if (_sheet.size <= _min + .03 &&
                              details.velocity.pixelsPerSecond.dy > 0) {
                            Navigator.of(context).maybePop();
                            return;
                          }
                          final target = _sheet.size > (_initial + _max) / 2
                              ? _max
                              : _initial;
                          _sheet.animateTo(
                            target,
                            duration: const Duration(milliseconds: 200),
                            curve: Curves.easeOut,
                          );
                        },
                        child: SizedBox(
                          height: 32,
                          width: double.infinity,
                          child: Center(
                            child: Container(
                              width: 36,
                              height: 4,
                              decoration: BoxDecoration(
                                color: theme.colorScheme.onSurfaceVariant
                                    .withValues(alpha: .5),
                                borderRadius: BorderRadius.circular(4),
                              ),
                            ),
                          ),
                        ),
                      ),
                      Expanded(
                        child: ActionSheetScroll(
                          controller: scrollController,
                          child: Theme(
                            data: theme.copyWith(
                              dialogTheme: theme.dialogTheme.copyWith(
                                insetPadding: EdgeInsets.zero,
                                alignment: Alignment.topCenter,
                                constraints: BoxConstraints.tightFor(
                                  width: media.size.width,
                                ),
                                elevation: 0,
                                shape: const RoundedRectangleBorder(),
                              ),
                            ),
                            child: Builder(builder: widget.builder),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
