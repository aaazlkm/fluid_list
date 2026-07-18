import 'package:fluid_list/src/model/fluid_list_auto_scroll.dart';
import 'package:fluid_list/src/model/fluid_list_reorder_result.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart' show kLongPressTimeout;

/// How a reorder drag is initiated.
enum FluidListDragMode {
  /// A long-press anywhere on the item starts the drag. A `FluidListDragHandle`
  /// inside the item still works too.
  item,

  /// Only a `FluidListDragHandle` inside the item starts the drag.
  handle,
}

/// Whether, and how, a fluid list can be reordered.
///
/// Pass [FluidListReorderDisabled] (the default when omitted) to turn reordering
/// off, or [FluidListReorderEnabled] to turn it on and carry the drag options
/// and callbacks. Making it a sealed type keeps the disabled state and the
/// options that only make sense while enabled from being mixed up.
///
/// Construct it either with the subclasses directly or with the
/// [FluidListReorder.disabled] / [FluidListReorder.enabled] factories.
@immutable
sealed class FluidListReorder<T> {
  const FluidListReorder();

  /// Reordering is disabled. Same as [FluidListReorderDisabled].
  const factory FluidListReorder.disabled() = FluidListReorderDisabled<T>;

  /// Reordering is enabled with these options. Same as
  /// [FluidListReorderEnabled].
  const factory FluidListReorder.enabled({
    FluidListDragMode dragMode,
    Duration dragStartDelay,
    FluidListAutoScrollConfig autoScroll,
    void Function(T item)? onReorderStarted,
    void Function(FluidListReorderResult<T> result)? onReorderFinished,
    void Function(T item)? onReorderCanceled,
  }) = FluidListReorderEnabled<T>;
}

/// Reordering is disabled. Equivalent to omitting the config entirely.
final class FluidListReorderDisabled<T> extends FluidListReorder<T> {
  const FluidListReorderDisabled();
}

/// Reordering is enabled, with these drag options and callbacks.
final class FluidListReorderEnabled<T> extends FluidListReorder<T> {
  const FluidListReorderEnabled({
    this.dragMode = FluidListDragMode.item,
    this.dragStartDelay = kLongPressTimeout,
    this.autoScroll = const FluidListAutoScrollConfig(),
    this.onReorderStarted,
    this.onReorderFinished,
    this.onReorderCanceled,
  });

  /// How a drag is started. See [FluidListDragMode].
  final FluidListDragMode dragMode;

  /// How long a press must be held before an item-body drag begins. Only
  /// applies to [FluidListDragMode.item].
  final Duration dragStartDelay;

  /// How the list auto-scrolls when the held item nears a viewport edge — its
  /// speeds, distance sensitivity, and acceleration. See [FluidListAutoScrollConfig].
  final FluidListAutoScrollConfig autoScroll;

  final void Function(T item)? onReorderStarted;

  /// Fired when a drag is dropped. The list is uncontrolled: feed
  /// [FluidListReorderResult.items] back in as the list's items to commit.
  final void Function(FluidListReorderResult<T> result)? onReorderFinished;

  final void Function(T item)? onReorderCanceled;
}
