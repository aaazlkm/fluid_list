/// A reorderable, implicitly animated, lazily built list.
///
/// `SliverFluidList` is the engine: a real sliver for a `CustomScrollView` that
/// builds only the visible and cached items, so it scales to large collections.
/// Items animate to their positions with springs, fade and scale in when added
/// and out when removed, and can be dragged to reorder — from the whole item
/// (long-press) or from a `FluidListDragHandle`. Every animation is a spring,
/// and every knob lives on `FluidListStyle`; pass a `FluidListTransitionBuilder`
/// to animate enter/exit with your own transition widgets instead.
///
/// `FluidList` is a convenience wrapper that hosts a single `SliverFluidList`
/// inside its own `CustomScrollView`.
library;

export 'src/fluid_list.dart' show FluidList;
export 'src/model/fluid_list_auto_scroll.dart' show FluidListAutoScrollConfig;
export 'src/model/fluid_list_reorder.dart' show FluidListDragMode, FluidListReorder, FluidListReorderDisabled, FluidListReorderEnabled;
export 'src/model/fluid_list_reorder_result.dart' show FluidListReorderResult;
export 'src/model/fluid_list_style.dart' show FluidListEffect, FluidListStyle, ResolvedFluidListEffect;
export 'src/sliver/sliver_fluid_list.dart' show FluidListItemBuilder, FluidListLiftedBuilder, FluidListTransitionBuilder, SliverFluidList;
export 'src/widget/fluid_list_drag_handle.dart' show FluidListDragHandle;
