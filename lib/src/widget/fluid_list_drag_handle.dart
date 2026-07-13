import 'package:flutter/widgets.dart';

/// Exposes an item's drag starter to descendants, so a [FluidListDragHandle]
/// nested anywhere inside the item can begin the reorder.
///
/// Looked up without registering a dependency (the handle reads it only when a
/// pointer goes down, not at build time), so a rebuild of the item does not
/// churn the handle.
///
/// [startDrag] hands the raw pointer-down event to the list, which owns the
/// gesture recognizer that drives the drag. Keeping the recognizer on the
/// long-lived list — rather than on this transient handle — is what lets the
/// item's subtree restructure (e.g. a lift decoration) mid-drag without
/// orphaning the gesture.
class FluidListItemDragScope extends InheritedWidget {
  const FluidListItemDragScope({
    required this.startDrag,
    required this.enabled,
    required super.child,
    super.key,
  });

  /// Begins recognising a drag of this item from the given pointer-down event.
  /// The delay is how long the pointer must be held before the drag starts
  /// (zero starts immediately).
  final void Function(PointerDownEvent event, Duration delay) startDrag;

  final bool enabled;

  static FluidListItemDragScope? maybeOf(BuildContext context) => context.getInheritedWidgetOfExactType<FluidListItemDragScope>();

  @override
  bool updateShouldNotify(FluidListItemDragScope oldWidget) => false;
}

/// A grip that starts a reorder drag of the enclosing `FluidList` item as soon
/// as it is pressed (or after [delay]).
///
/// Wrap whatever should be draggable — a handle icon, or the whole tile — in
/// this widget. It must sit inside a `FluidList` item. Pair it with
/// `dragMode: FluidListDragMode.handle` to make the handle the *only* way to
/// start a drag; under the default `FluidListDragMode.item` the handle still
/// works and simply offers an immediate-drag affordance next to the long-press.
///
/// The handle only forwards the pointer-down to the list; it owns no gesture
/// state, so it is safe to rebuild or unmount mid-drag (which happens as soon
/// as a `liftedBuilder` wraps the dragged item).
class FluidListDragHandle extends StatelessWidget {
  const FluidListDragHandle({
    required this.child,
    this.delay = Duration.zero,
    this.enabled = true,
    super.key,
  });

  final Widget child;

  /// How long the pointer must be held on the handle before the drag begins.
  /// Zero (the default) starts immediately, since a dedicated handle is not
  /// competing with a scroll gesture.
  final Duration delay;

  final bool enabled;

  @override
  Widget build(BuildContext context) {
    if (!enabled) return child;

    return Listener(
      onPointerDown: (event) {
        final scope = FluidListItemDragScope.maybeOf(context);
        if (scope != null && scope.enabled) scope.startDrag(event, delay);
      },
      child: child,
    );
  }
}
