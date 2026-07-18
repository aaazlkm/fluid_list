# Changelog

## 0.5.0

- **Breaking:** the reorder settings are now one sealed `reorder` parameter instead of the separate
  `reorderEnabled` / `dragMode` / `dragStartDelay` / autoscroll speed / `onReorderStarted`
  / `onReorderFinished` / `onReorderCanceled` fields.
  - Pass `FluidListReorderEnabled(dragMode: ..., onReorderFinished: ...)` to turn reordering on, or
    `FluidListReorderDisabled` (the default when `reorder` is omitted) to keep it off. Factory
    constructors `FluidListReorder.enabled(...)` / `FluidListReorder.disabled()` are also available.
  - The autoscroll behavior moved onto `FluidListReorderEnabled` as a single `autoScroll`
    (`FluidListAutoScrollConfig`) object (it only applies while dragging).
  - **Reordering is now off by default** (was on): add `reorder: FluidListReorderEnabled(...)` to
    lists that should reorder.
- `FluidList`'s scroll parameters now mirror `ListView`: added `primary`, `scrollCacheExtent`,
  `dragStartBehavior`, `keyboardDismissBehavior`, `restorationId`, `clipBehavior`, and
  `hitTestBehavior`; `padding` is now an `EdgeInsetsGeometry?`. (Reversed axes remain unsupported.)
- Fixed autoscroll stalling after a step or two when an item was held at a viewport edge without
  moving the finger; it now scrolls continuously until the finger leaves the edge.
- Autoscroll now engages once the held item's edge comes within a trigger distance of a viewport
  edge (not only after it crosses), and the speed scales with proximity to the edge — slower where
  the item enters the zone, fastest at and past the edge — easing toward that target rather than
  jumping to it. All of its knobs live on `FluidListAutoScrollConfig` (passed as
  `FluidListReorderEnabled(autoScroll: ...)`): `startVelocity` (speed entering the zone),
  `maxVelocity` (speed at the edge), `edgeTriggerDistance` (how far from the edge it engages), and
  `rampDuration` (`Duration.zero` tracks the position immediately). It resets when the item leaves
  the zone.
- The dragged item now renders in the app's `Overlay`, so it floats above every sibling sliver and
  the app bar instead of slipping under whatever the viewport paints on top of the list. Falls back
  to painting the lifted item in place when no `Overlay` is in scope. Note: the held item's widget
  `State` is rebuilt when it lifts and again when it drops (same trade-off as `ReorderableList`).

## 0.4.0

- **Breaking:** `liftedBuilder` now receives the lift as an `Animation<double>` —
  `(context, item, lift, child)`. It runs 0 → 1 as the held item rises and 1 → 0 as it settles, so
  the held-item decoration (a shadow, elevation, glow) can animate with the lift instead of snapping
  on and off. Add the `lift` parameter to existing `liftedBuilder`s.

## 0.3.0

- **Lazy sliver engine (breaking).** The list is now built on a real `RenderSliver` that builds
  only the visible and cached items, so it scales to large collections.
  - New `SliverFluidList<T>` — drop it into any `CustomScrollView` alongside a `SliverAppBar` or
    other slivers. It takes its axis from the enclosing viewport.
  - `FluidList<T>` is now a convenience wrapper that owns its own `CustomScrollView` (gains
    `scrollDirection`, `controller`, `physics`, `shrinkWrap`). It is no longer an embeddable box —
    replace `axis:` with `scrollDirection:`, and remove any surrounding `ListView`/scrollable.
  - Enter animations play only for newly added ids (not items scrolling into view); exit animations
    play only for on-screen removals. The total extent is estimated, so `scrollExtent` jumps on
    insert/remove rather than gliding.
  - Springs, drag-to-reorder (long-press + `FluidListDragHandle`), `FluidListStyle`,
    `transitionBuilder`, and the uncontrolled reorder contract are unchanged.

## 0.2.0

- Add `transitionBuilder`: animate entering and leaving items with your own transition widgets
  (`FadeTransition`, `SlideTransition`, custom) via a spring-driven `Animation<double>`, alongside
  the built-in `FluidListEffect`.
- Fix: a drag started from a `FluidListDragHandle` no longer stalls (item lifting but not moving)
  when a `liftedBuilder` restructures the item mid-gesture — the drag recognizer is now owned by
  the list, not the handle.

## 0.1.0

- Initial release: a reorderable, implicitly animated list with spring-driven motion.
  - Implicit enter / exit / move animations driven by item identity.
  - Drag-to-reorder from the whole item (long-press) or a `FluidListDragHandle`.
  - Every animation runs on `SpringSimulation`; all knobs live on `FluidListStyle`.
  - Vertical and horizontal axes.
