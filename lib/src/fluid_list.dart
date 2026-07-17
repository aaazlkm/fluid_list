import 'package:fluid_list/src/model/fluid_list_reorder.dart';
import 'package:fluid_list/src/model/fluid_list_style.dart';
import 'package:fluid_list/src/sliver/sliver_fluid_list.dart';
import 'package:flutter/gestures.dart' show DragStartBehavior;
import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import 'package:flutter/widgets.dart';

/// A reorderable, implicitly animated, lazily built list.
///
/// A convenience wrapper that owns a [CustomScrollView] hosting a single
/// [SliverFluidList]. The scroll-related parameters mirror [ListView] so it
/// drops in the same way; to compose the list with other slivers
/// (a `SliverAppBar`, other lists), use [SliverFluidList] in your own
/// [CustomScrollView] instead.
///
/// Only the visible and cached items are built, so it scales to large
/// collections. Reordering is off by default; pass a [FluidListReorderEnabled]
/// as [reorder] to turn it on. The list is uncontrolled: dropping an item
/// reports the new ordering through [FluidListReorderEnabled.onReorderFinished]
/// and expects the caller to feed that ordering back in as [items].
class FluidList<T> extends StatelessWidget {
  const FluidList({
    required this.items,
    required this.idOf,
    required this.itemBuilder,
    this.scrollDirection = Axis.vertical,
    this.controller,
    this.primary,
    this.physics,
    this.shrinkWrap = false,
    this.padding,
    this.scrollCacheExtent,
    this.dragStartBehavior = DragStartBehavior.start,
    this.keyboardDismissBehavior = ScrollViewKeyboardDismissBehavior.manual,
    this.restorationId,
    this.clipBehavior = Clip.hardEdge,
    this.hitTestBehavior = HitTestBehavior.opaque,
    this.spacing = 0,
    this.style = const FluidListStyle(),
    this.reorder,
    this.liftedBuilder,
    this.transitionBuilder,
    super.key,
  });

  /// Items in display order.
  final List<T> items;

  /// Stable identity for an item. Must be unique across the list.
  final Object Function(T item) idOf;

  final FluidListItemBuilder<T> itemBuilder;

  /// The scroll direction. A horizontal list is laid out left-to-right
  /// regardless of text direction. (Reversed axes are not supported.)
  final Axis scrollDirection;

  final ScrollController? controller;
  final bool? primary;
  final ScrollPhysics? physics;

  /// Whether the list should size itself to its content. Setting this true is
  /// the escape hatch for embedding the list in another scrollable, and — like
  /// any shrink-wrapped lazy list — gives up the benefits of laziness.
  final bool shrinkWrap;

  final EdgeInsetsGeometry? padding;
  final ScrollCacheExtent? scrollCacheExtent;
  final DragStartBehavior dragStartBehavior;
  final ScrollViewKeyboardDismissBehavior keyboardDismissBehavior;
  final String? restorationId;
  final Clip clipBehavior;
  final HitTestBehavior hitTestBehavior;

  /// Gap between adjacent items along the main axis.
  final double spacing;

  /// Every animation knob. See [FluidListStyle].
  final FluidListStyle style;

  /// Whether and how the list can be reordered. Null (the default) disables
  /// reordering; pass a [FluidListReorderEnabled] to turn it on.
  final FluidListReorder<T>? reorder;

  /// Decorates the held item.
  final FluidListLiftedBuilder<T>? liftedBuilder;

  /// Animates entering and leaving items with your own transition widgets. See
  /// [FluidListTransitionBuilder].
  final FluidListTransitionBuilder? transitionBuilder;

  @override
  Widget build(BuildContext context) => CustomScrollView(
    scrollDirection: scrollDirection,
    controller: controller,
    primary: primary,
    physics: physics,
    shrinkWrap: shrinkWrap,
    scrollCacheExtent: scrollCacheExtent,
    dragStartBehavior: dragStartBehavior,
    keyboardDismissBehavior: keyboardDismissBehavior,
    restorationId: restorationId,
    clipBehavior: clipBehavior,
    hitTestBehavior: hitTestBehavior,
    slivers: [
      SliverPadding(
        padding: padding ?? EdgeInsets.zero,
        sliver: SliverFluidList<T>(
          items: items,
          idOf: idOf,
          itemBuilder: itemBuilder,
          spacing: spacing,
          style: style,
          reorder: reorder,
          liftedBuilder: liftedBuilder,
          transitionBuilder: transitionBuilder,
        ),
      ),
    ],
  );
}
