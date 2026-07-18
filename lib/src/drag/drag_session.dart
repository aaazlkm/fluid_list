import 'dart:ui' show Offset, Size, VoidCallback;

import 'package:flutter/gestures.dart';

enum DragPhase {
  /// The pointer is down and the item tracks it.
  dragging,

  /// The pointer is up and the item springs into its slot. The working order is
  /// frozen so the list does not flicker before the parent echoes the new data.
  settling,
}

/// Everything known about the drag in flight.
class DragSession<T> {
  DragSession({
    required this.id,
    required this.item,
    required this.fromIndex,
    required this.grabOffset,
    required this.pointer,
    required this.crossExtent,
    required this.itemSize,
    required this.hypothesisIndex,
    this.onCanceled,
  });

  final Object id;
  final T item;
  final int fromIndex;

  /// The cancel callback captured at lift, so a drag that is aborted after the
  /// reorder config was swapped out (e.g. reordering turned off mid-gesture)
  /// still balances the `onReorderStarted` it emitted.
  final void Function(T item)? onCanceled;

  /// Pointer position minus the item's top-left, captured at lift and held
  /// constant so the item stays put under the finger.
  final Offset grabOffset;

  /// Content cross-axis extent at lift. A change means the list was resized and
  /// all cached geometry is stale.
  final double crossExtent;

  /// The dragged item's size, captured at lift. Held constant for the drag's
  /// lifetime and used to size the overlay drag proxy; a cross-extent change
  /// already aborts the drag, so this can never go stale under the finger.
  final Size itemSize;

  Offset pointer;

  /// The index the dragged item would land at right now.
  int hypothesisIndex;

  DragPhase phase = DragPhase.dragging;

  bool get isActive => phase == DragPhase.dragging;
}

/// Bridges the gesture recognizer's [Drag] contract to plain callbacks.
class ListDrag extends Drag {
  ListDrag({
    required this.onUpdate,
    required this.onEnd,
    required this.onCancel,
  });

  final void Function(Offset globalPosition) onUpdate;
  final VoidCallback onEnd;
  final VoidCallback onCancel;

  @override
  void update(DragUpdateDetails details) => onUpdate(details.globalPosition);

  @override
  void end(DragEndDetails details) => onEnd();

  @override
  void cancel() => onCancel();
}
