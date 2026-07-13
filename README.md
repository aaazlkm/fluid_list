# fluid_list

A reorderable, implicitly animated, **lazy** list with spring-driven motion.

Think `implicitly_animated_reorderable_list`, but every animation is a spring rather than a
fixed-duration curve: items **show**, **hide**, and **move** with physics, an interrupted
animation carries its momentum into the next, and all of the knobs live on one `FluidListStyle`.
Under the hood it is a real sliver — only the visible and cached items are built, so it scales to
large collections, and its motion is applied at paint time so the animation never rebuilds the
tree.

A runnable demo (spring show/hide/move, long-press and handle reorder, a horizontal strip, and a
1000-item toggle) lives in [`example/`](example/) — `cd example && fvm flutter run`.

## Usage

`FluidList` is a convenience wrapper that owns its own `CustomScrollView`:

```dart
FluidList<Task>(
  items: tasks,                       // display order — echo reorders back
  idOf: (task) => task.id,            // stable identity, unique across the list
  spacing: 10,
  padding: const EdgeInsets.all(16),
  itemBuilder: (context, task) => TaskCard(task),
  // Reordering is off by default; opt in with a FluidListReorderEnabled.
  reorder: FluidListReorderEnabled(
    onReorderFinished: (result) => setState(() => tasks = result.items),
  ),
)
```

To compose the list with other slivers — a `SliverAppBar`, other lists — drop the engine,
`SliverFluidList`, straight into your own `CustomScrollView`:

```dart
CustomScrollView(
  slivers: [
    const SliverAppBar(title: Text('Tasks')),
    SliverFluidList<Task>(
      items: tasks,
      idOf: (task) => task.id,
      itemBuilder: (context, task) => TaskCard(task),
      reorder: FluidListReorderEnabled(
        onReorderFinished: (result) => setState(() => tasks = result.items),
      ),
    ),
  ],
)
```

## Behaviour

**Implicitly animated.** Feed in a new `items` list and the widget diffs it by identity:
survivors spring to their new slots, arrivals fade and scale in, departures become ghosts that
fade out in place while the rest close the gap. No `AnimatedList`, no manual insert/remove calls —
just hand it the new list.

**Uncontrolled reorder.** Reordering is configured with one sealed `reorder` parameter — pass
`FluidListReorderEnabled(...)` to turn it on (omitting it, or passing `FluidListReorderDisabled`,
leaves it off). Dropping an item reports the new ordering through the config's `onReorderFinished`
and expects the caller to feed that ordering back in as `items`. The drop position is held until
the caller does, so an optimistic state update produces no visual jump.

**Two ways to start a drag.** By default a long-press anywhere on the item lifts it
(`FluidListReorderEnabled(dragMode: FluidListDragMode.item)`). Wrap part of the item in a
`FluidListDragHandle` for an immediate-drag grip; pass `dragMode: FluidListDragMode.handle` to make
the handle the *only* way to start a drag, leaving the rest of the item free for taps and buttons.

**Either axis.** `scrollDirection: Axis.horizontal` lays the list out left-to-right; everything
else is the same. (`SliverFluidList` takes its axis from the enclosing viewport.)

**Lazy.** Only the on-screen and cached items are built, so a 10k-item list is as cheap as a short
one. Two consequences follow: enter animations play only for ids newly added to `items` (not for
items scrolling into view), and exit animations play only when the removed item is currently on
screen — an off-screen removal just disappears. Because the total extent is estimated rather than
measured, `scrollExtent` jumps on insert/remove instead of gliding.

## Styling the motion

Every animation is a spring, and every knob is on `FluidListStyle`:

```dart
FluidList<Task>(
  style: FluidListStyle(
    moveSpring: SpringDescription(mass: 1, stiffness: 400, damping: 34),  // sliding to new slots
    dropSpring: SpringDescription(mass: 1, stiffness: 550, damping: 47),  // settling after a drop
    enterSpring: FluidListStyle.defaultEnterSpring,                       // show progress 0 → 1
    exitSpring: FluidListStyle.defaultExitSpring,                         // show progress 1 → 0
    enterEffect: const FluidListEffect(opacity: 0, scale: 0.94),          // how an arrival looks hidden
    exitEffect: const FluidListEffect(opacity: 0, scale: 0.94, offset: Offset(0, 8)),
    liftScale: 1.03,                                                      // how much the held item grows
  ),
  // ...
)
```

A `FluidListEffect` is the *hidden* endpoint of an enter or exit — its opacity, scale, and
translation when fully off-screen. The animation interpolates between that endpoint and the item's
natural appearance, so `FluidListEffect(offset: Offset(0, 8))` slides an item in from below while
`FluidListEffect.fade` is a pure cross-fade. Because the progress is spring-driven it can overshoot
slightly, giving scale and offset a subtle bounce.

### Custom transitions by widget

When opacity/scale/translation aren't enough, pass a `transitionBuilder` and animate entering and
leaving items with your own transition widgets — the same shape as `AnimatedList` or
`implicitly_animated_reorderable_list`:

```dart
FluidList<Tag>(
  // animation runs 0→1 entering (status forward) and 1→0 leaving (status reverse)
  transitionBuilder: (context, animation, child) => FadeTransition(
    opacity: animation,
    child: SlideTransition(
      position: Tween(begin: const Offset(0.3, 0), end: Offset.zero).animate(animation),
      child: child,
    ),
  ),
  // ...
)
```

The `animation` is the item's spring-driven show progress surfaced as an `Animation<double>`, so
any transition widget (`FadeTransition`, `ScaleTransition`, `SlideTransition`, `RotationTransition`,
or a custom one) works, and you can branch on `animation.status` to make the entrance and exit
differ. Supplying a builder bypasses the `FluidListEffect` for that item — **move and reorder motion
still runs on the springs**, and only the handful of animating items rebuild per frame. The one
constraint is that it does not change the item's laid-out size, so use fixed-size transitions rather
than size-collapsing ones (`SizeTransition`).

## Design

- **A real lazy sliver, but motion at paint time.** `RenderSliverFluidList` forks
  `RenderSliverList`'s dead-reckoned layout — only the visible and cached items are materialized —
  but overrides `paint`, hit testing, and `applyPaintTransform` to place each child at its
  spring-driven position rather than its layout offset. Layout gives each item a stable content
  offset; the springs animate the *visual* position toward it, so scrolling never disturbs a
  settled item and a data change animates without a relayout.

- **Springs, stepped by hand.** Each item owns scalar spring channels for position and show
  progress. Retargeting mid-flight restarts the simulation from the current position *and
  velocity*, so an interrupted animation carries its momentum into the new target — this is why the
  package drives `SpringSimulation` directly rather than using `AnimationController.animateWith`,
  whose unitless 0..1 domain cannot express a velocity handoff between two different targets, and
  during a drag the target changes many times per second. A single `Ticker` advances every channel
  and marks the sliver for repaint.

- **No diffing algorithm.** Items are keyed by a caller-supplied id, so reconciliation is set
  arithmetic: arrivals fade in, on-screen departures become zero-extent "ghosts" that fade at their
  frozen rect while survivors reflow past them, and an id that reappears mid-exit is revived in
  place. A Myers diff buys nothing once you have identity.

- **Constant spacing folds into flow extent.** Each item's dead-reckoning extent is its measured
  size plus one `spacing`, and ghosts contribute zero — so forward and backward scrolling share one
  arithmetic and never disagree about where index 0 sits.

- **Drop targets in closed form.** The slot under the dragged item is found arithmetically over the
  currently built window (a running sum of measured extents), with hysteresis so the gap does not
  flap between two near-equidistant slots. Autoscroll extends the window as you drag toward an edge.

- **Gestures via multi-drag recognizers**, owned by the list State (not the item), the same shape
  as Flutter's `ReorderableDragStartListener`. They join the gesture arena, so an item-body
  long-press loses cleanly to the scroll if the user scrolls first and to a tap if they release
  first, and the drag survives the item's subtree being rebuilt mid-gesture.

## Limitations

- Reordering is drag-only, so it is not reachable by switch or screen-reader users. Semantic
  reorder actions are a known gap.
- Forward, non-reversed axes only for now (`AxisDirection.down` / `right`): no `reverse: true`, no
  RTL horizontal, no centered slivers.
- A cross-axis resize mid-drag (rotation, resize) cancels the drag rather than remapping stale
  geometry.
