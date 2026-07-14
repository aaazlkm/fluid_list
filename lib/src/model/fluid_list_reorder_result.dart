import 'package:flutter/foundation.dart';

/// Describes a completed drag: which item moved, where it came from, where it
/// landed, and the resulting order of the whole list.
///
/// The list is uncontrolled, so nothing is mutated for you: feed [items] back
/// in as the widget's `items` to commit the move.
@immutable
class FluidListReorderResult<T> {
  const FluidListReorderResult({
    required this.item,
    required this.fromIndex,
    required this.toIndex,
    required this.items,
  });

  /// The item that was dragged.
  final T item;

  /// Its index before the drag.
  final int fromIndex;

  /// Its index after the drop.
  final int toIndex;

  /// The full list in its new display order, including the moved item.
  final List<T> items;

  /// Whether the drop actually changed the item's position.
  bool get moved => fromIndex != toIndex;
}
