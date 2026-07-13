import 'package:fluid_list/src/animation/list_animator.dart';
import 'package:fluid_list/src/drag/drag_session.dart';
import 'package:fluid_list/src/drag/insertion_resolver.dart';
import 'package:fluid_list/src/model/fluid_list_reorder.dart';
import 'package:fluid_list/src/model/fluid_list_reorder_result.dart';
import 'package:fluid_list/src/model/fluid_list_style.dart';
import 'package:fluid_list/src/sliver/render_sliver_fluid_list.dart';
import 'package:fluid_list/src/widget/fluid_list_drag_handle.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

/// Builds the widget shown for an item.
typedef FluidListItemBuilder<T> = Widget Function(BuildContext context, T item);

/// Decorates the item while it is held by the pointer, e.g. with a shadow.
///
/// [animation] is the drag lift: it runs 0 → 1 as the item rises under the
/// finger and 1 → 0 as it settles or the drag is cancelled, so the decoration
/// can animate with the lift (drive an `AnimatedBuilder` or a transition from
/// it). It mirrors the paint-time scale the list already applies to the held
/// item.
typedef FluidListLiftedBuilder<T> = Widget Function(BuildContext context, T item, Animation<double> animation, Widget child);

/// Wraps an entering or leaving item so you can animate it with your own
/// transition widgets. The animation runs 0 → 1 entering (status forward) and
/// 1 → 0 leaving (status reverse). Supplying a builder bypasses the built-in
/// [FluidListStyle] enter/exit effect for that item; use fixed-size transitions.
typedef FluidListTransitionBuilder = Widget Function(BuildContext context, Animation<double> animation, Widget child);

/// A lazy, reorderable, implicitly animated sliver for a [CustomScrollView].
///
/// Only the visible and cached items are built, so it scales to large
/// collections. Items animate to their positions with springs, fade and scale
/// in when added and out when removed, and can be dragged to reorder. Every
/// animation is a spring; all of the knobs live on [FluidListStyle].
///
/// The sliver is uncontrolled: dropping an item reports the new ordering through
/// [FluidListReorderEnabled.onReorderFinished] and expects the caller to feed
/// that ordering back in as [items].
///
/// Enter animations play only for ids newly added to [items], not for items
/// scrolling into view; exit animations play only when the removed item is
/// currently on screen.
class SliverFluidList<T> extends StatefulWidget {
  const SliverFluidList({
    required this.items,
    required this.idOf,
    required this.itemBuilder,
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

  /// Gap between adjacent items along the main axis.
  final double spacing;

  /// Every animation knob. See [FluidListStyle].
  final FluidListStyle style;

  /// Whether and how the list can be reordered. Null (the default) disables
  /// reordering; pass a [FluidListReorderEnabled] to turn it on with drag
  /// options and callbacks (including the autoscroll speed).
  final FluidListReorder<T>? reorder;

  /// Decorates the held item.
  final FluidListLiftedBuilder<T>? liftedBuilder;

  /// Animates entering and leaving items with your own transition widgets. See
  /// [FluidListTransitionBuilder]. Null (the default) uses the built-in spring
  /// effect from [FluidListStyle].
  final FluidListTransitionBuilder? transitionBuilder;

  @override
  State<SliverFluidList<T>> createState() => _SliverFluidListState<T>();
}

/// A removed item still fading out: its snapshot, frozen size, and the surviving
/// id it should follow in the composite order (null → the front of the list).
class _Ghost<T> {
  const _Ghost({required this.item, required this.size, required this.anchorId});

  final T item;
  final Size size;
  final Object? anchorId;
}

typedef _CompositeEntry = ({Object id, bool ghost});

class _SliverFluidListState<T> extends State<SliverFluidList<T>> with SingleTickerProviderStateMixin {
  final GlobalKey _bodyKey = GlobalKey();

  late final ListAnimator _animator = ListAnimator(style: widget.style);
  late final Ticker _ticker;
  Duration _lastTick = Duration.zero;

  DragSession<T>? _drag;
  MultiDragGestureRecognizer? _dragRecognizer;

  /// The most recent pointer-down we armed a recognizer for. Held only to reject
  /// the second of the two listeners that see the *same* down event (the
  /// handle's inner one and the body's outer one) — compared by identity, so a
  /// later down that happens to reuse a pointer id (mouse, tests) is never
  /// blocked.
  PointerDownEvent? _lastHandledDown;

  EdgeDraggingAutoScroller? _autoScroller;
  ScrollableState? _scrollable;

  final Map<Object, _Ghost<T>> _ghosts = {};
  final Map<Object, T> _itemsById = {};
  final Map<Object, _ProgressAnimation> _transitions = {};

  /// The drag lift (0 at rest, 1 fully lifted) surfaced to the `liftedBuilder`.
  final _ProgressAnimation _liftAnimation = _ProgressAnimation(0, AnimationStatus.dismissed);

  /// The id order of [SliverFluidList.items] at the previous reconcile, used to
  /// find a removed item's surviving predecessor (its ghost anchor).
  List<Object> _lastOrder = [];

  /// The composite (items + ghosts) display list built this frame, and a lookup
  /// from a child's key value to its composite index for delegate reconciliation.
  List<_CompositeEntry> _composite = const [];
  Map<(String, Object), int> _indexByKeyValue = const {};

  RenderSliverFluidList? get _renderBox => _bodyKey.currentContext?.findRenderObject() as RenderSliverFluidList?;

  /// The reorder options if reordering is enabled, else null (also null when
  /// `reorder` is omitted or `FluidListReorderDisabled`).
  FluidListReorderEnabled<T>? get _reorder => widget.reorder is FluidListReorderEnabled<T> ? widget.reorder! as FluidListReorderEnabled<T> : null;

  bool get _reorderEnabled => _reorder != null;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick);
    _indexItems();
    _lastOrder = [for (final item in widget.items) widget.idOf(item)];
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final scrollable = Scrollable.maybeOf(context);
    if (scrollable != _scrollable) {
      _scrollable = scrollable;
      _rebuildAutoScroller();
    }
  }

  double _scalarOf(FluidListReorder<T>? reorder) => reorder is FluidListReorderEnabled<T> ? reorder.autoScrollVelocityScalar : kFluidListDefaultAutoScrollVelocityScalar;

  void _rebuildAutoScroller() {
    final scrollable = _scrollable;
    _autoScroller = scrollable == null
        ? null
        : EdgeDraggingAutoScroller(
            scrollable,
            onScrollViewScrolled: _onScrollViewScrolled,
            velocityScalar: _scalarOf(widget.reorder),
          );
  }

  @override
  void didUpdateWidget(covariant SliverFluidList<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    _animator.style = widget.style;
    if (_scalarOf(oldWidget.reorder) != _scalarOf(widget.reorder)) _rebuildAutoScroller();
    _reconcile();
  }

  @override
  void dispose() {
    _dragRecognizer?.dispose();
    _ticker.dispose();
    super.dispose();
  }

  // --- Data reconciliation ---

  void _indexItems() {
    _itemsById
      ..clear()
      ..addEntries([for (final item in widget.items) MapEntry(widget.idOf(item), item)]);
  }

  /// Diff by identity: arrivals mark pending-enter, on-screen departures become
  /// ghosts anchored to their surviving predecessor, revivals cancel their exit.
  /// Off-screen changes are silent.
  void _reconcile() {
    final previous = Map<Object, T>.of(_itemsById);
    final previousOrder = _lastOrder;
    _indexItems();
    _lastOrder = [for (final item in widget.items) widget.idOf(item)];

    final box = _renderBox;
    for (var i = 0; i < previousOrder.length; i++) {
      final id = previousOrder[i];
      if (_itemsById.containsKey(id) || _ghosts.containsKey(id)) continue;
      if (!previous.containsKey(id)) continue;

      final size = box?.itemSizes[id];
      final offset = _animator.offsetOf(id);
      if (size == null || offset == null) {
        // Removed while off-screen: no animation, just forget it.
        _animator.remove(id);
        _transitions.remove(id);
        continue;
      }

      _ghosts[id] = _Ghost(item: previous[id] as T, size: size, anchorId: _survivingPredecessor(previousOrder, i));
      _animator.beginExit(id, offset & size);
      if (widget.transitionBuilder != null) {
        _transitions[id] = _ProgressAnimation(_animator.progressOf(id), AnimationStatus.reverse);
      }
    }

    for (final id in _itemsById.keys) {
      if (_ghosts.remove(id) != null) {
        _animator.revive(id);
        _transitions[id]?.update(_animator.progressOf(id), AnimationStatus.forward);
      }
    }

    // Brand-new ids: mark to play the enter animation on first layout.
    for (final id in _itemsById.keys) {
      if (previous.containsKey(id)) continue;
      _animator.markPendingEnter(id);
      if (widget.transitionBuilder != null) {
        _transitions.putIfAbsent(id, () => _ProgressAnimation(0, AnimationStatus.forward));
      }
    }
    // Forget pending-enter marks that never materialized this frame.
    SchedulerBinding.instance.addPostFrameCallback((_) => _animator.clearPendingEnter());

    final drag = _drag;
    if (drag != null) {
      if (!_itemsById.containsKey(drag.id)) {
        _abortDrag(notify: true);
      } else {
        drag.hypothesisIndex = drag.hypothesisIndex.clamp(0, _baseOrder().length);
      }
    }

    _startTicker();
  }

  /// The nearest id before index [i] in [order] that survives into the new data.
  Object? _survivingPredecessor(List<Object> order, int i) {
    for (var j = i - 1; j >= 0; j--) {
      if (_itemsById.containsKey(order[j])) return order[j];
    }
    return null;
  }

  // --- Ordering ---

  /// Live ids in display order, with the dragged item taken out.
  List<Object> _baseOrder() => [
    for (final item in widget.items)
      if (widget.idOf(item) != _drag?.id) widget.idOf(item),
  ];

  /// Live ids with the dragged item spliced into its current hypothesis.
  List<Object> _displayOrder() {
    final drag = _drag;
    if (drag == null) return [for (final item in widget.items) widget.idOf(item)];
    final base = _baseOrder();
    return [...base]..insert(drag.hypothesisIndex.clamp(0, base.length), drag.id);
  }

  /// Interleaves ghosts into the display order after their anchors.
  List<_CompositeEntry> _computeComposite() {
    final order = _displayOrder();
    final byAnchor = <Object?, List<Object>>{};
    for (final entry in _ghosts.entries) {
      byAnchor.putIfAbsent(entry.value.anchorId, () => <Object>[]).add(entry.key);
    }

    final result = <_CompositeEntry>[];
    for (final id in byAnchor[null] ?? const <Object>[]) {
      result.add((id: id, ghost: true));
    }
    for (final id in order) {
      result.add((id: id, ghost: false));
      for (final ghost in byAnchor[id] ?? const <Object>[]) {
        result.add((id: ghost, ghost: true));
      }
    }
    return result;
  }

  // --- Ticker ---

  void _startTicker() {
    if (_ticker.isActive) return;
    _lastTick = Duration.zero;
    _ticker.start();
  }

  void _onTick(Duration elapsed) {
    final dtRaw = _lastTick == Duration.zero ? 1 / 60 : (elapsed - _lastTick).inMicroseconds / Duration.microsecondsPerSecond;
    _lastTick = elapsed;
    final dt = dtRaw.clamp(0.0, 1 / 30);

    final result = _animator.tick(dt);
    if (_transitions.isNotEmpty) _driveTransitions(result.exited);
    _driveLift();

    final drag = _drag;
    if (drag != null && drag.isActive) {
      _applyPointer();
    }

    if (result.exited.isNotEmpty) {
      setState(() {
        for (final id in result.exited) {
          _ghosts.remove(id);
        }
      });
    }

    _renderBox?.markNeedsPaint();

    // Wait for the lift to fall back to 0 too, not just the position spring —
    // a drop into the same slot has nothing to settle positionally, but the
    // lift (and the liftedBuilder decoration) must still animate 1 → 0.
    if (drag != null && drag.phase == DragPhase.settling && !_animator.isSettling && !_animator.lift.isAnimating) {
      _finishSettle();
      return;
    }

    if (!result.active && _drag == null) {
      _ticker.stop();
    }
  }

  void _driveLift() {
    final value = _animator.lift.value;
    final rising = _drag?.isActive ?? false;
    final status = value >= 0.999
        ? AnimationStatus.completed
        : value <= 0.001
        ? AnimationStatus.dismissed
        : rising
        ? AnimationStatus.forward
        : AnimationStatus.reverse;
    _liftAnimation.update(value, status);
  }

  void _driveTransitions(List<Object> exited) {
    for (final id in exited) {
      _transitions.remove(id);
    }
    for (final entry in _transitions.entries) {
      final progress = _animator.progressOf(entry.key);
      final exiting = _ghosts.containsKey(entry.key);
      final status = exiting ? (progress <= 0.001 ? AnimationStatus.dismissed : AnimationStatus.reverse) : (progress >= 0.999 ? AnimationStatus.completed : AnimationStatus.forward);
      entry.value.update(progress, status);
    }
  }

  // --- Drag ---

  double _mainOf(Offset offset) => (_renderBox?.axis ?? Axis.vertical) == Axis.vertical ? offset.dy : offset.dx;
  double _mainExtentOf(Size size) => (_renderBox?.axis ?? Axis.vertical) == Axis.vertical ? size.height : size.width;

  /// Maps a global pointer position into content (scroll-offset) space, where
  /// the animator's springs live. Uses the current scroll offset, so autoscroll
  /// keeps the dragged item under the finger for free.
  Offset _globalToContent(Offset global) {
    final box = _renderBox!;
    // A RenderSliver is not a RenderBox, so map through its paint transform.
    final inverse = Matrix4.tryInvert(box.getTransformTo(null)) ?? Matrix4.identity();
    final local = MatrixUtils.transformPoint(inverse, global);
    final scroll = box.scrollOffset;
    return box.axis == Axis.vertical ? Offset(local.dx, local.dy + scroll) : Offset(local.dx + scroll, local.dy);
  }

  Offset _contentToGlobal(Offset content) {
    final box = _renderBox!;
    final scroll = box.scrollOffset;
    final local = box.axis == Axis.vertical ? Offset(content.dx, content.dy - scroll) : Offset(content.dx - scroll, content.dy);
    return MatrixUtils.transformPoint(box.getTransformTo(null), local);
  }

  void _startDragRecognition(Object id, PointerDownEvent event, Duration delay) {
    if (!_reorderEnabled || event.buttons != kPrimaryButton) return;
    if (_drag != null) return;
    // The same down reaches both the handle's inner listener and the body's
    // outer one; the deeper (handle) call fires first and wins, so ignore the
    // second call for the same event.
    if (identical(event, _lastHandledDown)) return;
    _lastHandledDown = event;

    _dragRecognizer?.dispose();
    _dragRecognizer = (delay == Duration.zero ? ImmediateMultiDragGestureRecognizer(debugOwner: this) : DelayedMultiDragGestureRecognizer(delay: delay, debugOwner: this))
      ..gestureSettings = MediaQuery.maybeGestureSettingsOf(context)
      ..onStart = ((position) => _onDragStart(id, position))
      ..addPointer(event);
  }

  Drag? _onDragStart(Object id, Offset globalPosition) {
    if (!_reorderEnabled || _drag != null) return null;

    final box = _renderBox;
    final item = _itemsById[id];
    if (box == null || item == null) return null;

    final topLeft = _animator.offsetOf(id);
    final size = box.itemSizes[id];
    if (topLeft == null || size == null) return null;

    final index = _locate(id);
    if (index < 0) return null;

    _drag = DragSession<T>(
      id: id,
      item: item,
      fromIndex: index,
      grabOffset: _globalToContent(globalPosition) - topLeft,
      pointer: globalPosition,
      crossExtent: box.crossAxisExtent,
      hypothesisIndex: index,
    );

    _animator
      ..draggedId = id
      ..lift.retarget(1, widget.style.dropSpring);

    _startTicker();
    _reorder?.onReorderStarted?.call(item);
    setState(() {});

    return ListDrag(
      onUpdate: _onDragUpdate,
      onEnd: _onDragEnd,
      onCancel: () => _abortDrag(notify: true),
    );
  }

  int _locate(Object id) => widget.items.indexWhere((item) => widget.idOf(item) == id);

  void _onDragUpdate(Offset globalPosition) {
    final drag = _drag;
    final box = _renderBox;
    if (drag == null || box == null) return;

    if ((box.crossAxisExtent - drag.crossExtent).abs() > 0.5) {
      _abortDrag(notify: true);
      return;
    }

    drag.pointer = globalPosition;
    _applyPointer();

    final size = box.itemSizes[drag.id];
    final topLeft = _animator.offsetOf(drag.id);
    if (size != null && topLeft != null) {
      _autoScroller?.startAutoScrollIfNecessary(_contentToGlobal(topLeft) & size);
    }
  }

  void _onScrollViewScrolled() {
    if (_drag?.isActive ?? false) _applyPointer();
  }

  /// Pin the item under the finger and re-resolve where it would land among the
  /// currently built items.
  void _applyPointer() {
    final drag = _drag;
    final box = _renderBox;
    if (drag == null || box == null) return;

    final topLeft = _globalToContent(drag.pointer) - drag.grabOffset;
    _animator.setDragOffset(topLeft);
    box.markNeedsPaint();

    final draggedSize = box.itemSizes[drag.id];
    final firstBuiltOffset = box.firstBuiltItemOffset;
    if (draggedSize == null || firstBuiltOffset == null) return;

    final baseIds = [
      for (final id in box.builtItemOrder)
        if (id != drag.id) id,
    ];
    if (baseIds.isEmpty) return;

    final fullBase = _baseOrder();
    final firstBaseGlobalIndex = fullBase.indexOf(baseIds.first);
    if (firstBaseGlobalIndex < 0) return;

    final localCurrent = drag.hypothesisIndex - firstBaseGlobalIndex;
    final localIndex = resolveInsertionIndex(
      base: [
        for (final id in baseIds) ListItemSpec(id: id, extent: _mainExtentOf(box.itemSizes[id] ?? Size.zero)),
      ],
      spacing: widget.spacing,
      mainLead: firstBuiltOffset,
      draggedExtent: _mainExtentOf(draggedSize),
      draggedMainStart: _mainOf(topLeft),
      current: localCurrent >= 0 && localCurrent <= baseIds.length ? localCurrent : null,
    );

    final globalIndex = firstBaseGlobalIndex + localIndex;
    if (globalIndex != drag.hypothesisIndex) {
      setState(() => drag.hypothesisIndex = globalIndex);
    }
  }

  void _onDragEnd() {
    final drag = _drag;
    final box = _renderBox;
    if (drag == null) return;

    _autoScroller?.stopAutoScroll();

    final target = box == null ? null : _animator.offsetOf(drag.id);
    // Settle toward the dragged slot's content position: the layout has already
    // opened the gap at the hypothesis, so the item's own laid-out offset is it.
    if (target != null && box != null) {
      final slot = box.itemSizes.containsKey(drag.id) ? _slotContentOffset(box, drag) : null;
      _animator.settleDragged(slot ?? target);
    }
    _animator.lift.retarget(0, widget.style.dropSpring);

    setState(() => drag.phase = DragPhase.settling);

    final order = _displayOrder();
    _reorder?.onReorderFinished?.call(
      FluidListReorderResult<T>(
        item: drag.item,
        fromIndex: drag.fromIndex,
        toIndex: order.indexOf(drag.id),
        items: [for (final id in order) ?_itemsById[id]],
      ),
    );

    _startTicker();
  }

  /// The content-space top-left of the gap the dragged item should settle into,
  /// derived from the built neighbours' layout offsets.
  Offset? _slotContentOffset(RenderSliverFluidList box, DragSession<T> drag) {
    final firstBuiltOffset = box.firstBuiltItemOffset;
    if (firstBuiltOffset == null) return null;
    final baseIds = [
      for (final id in box.builtItemOrder)
        if (id != drag.id) id,
    ];
    final fullBase = _baseOrder();
    final firstBaseGlobalIndex = baseIds.isEmpty ? 0 : fullBase.indexOf(baseIds.first);
    final localIndex = drag.hypothesisIndex - (firstBaseGlobalIndex < 0 ? 0 : firstBaseGlobalIndex);

    var main = firstBuiltOffset;
    for (var i = 0; i < localIndex && i < baseIds.length; i++) {
      main += _mainExtentOf(box.itemSizes[baseIds[i]] ?? Size.zero) + widget.spacing;
    }
    return box.axis == Axis.vertical ? Offset(0, main) : Offset(main, 0);
  }

  void _abortDrag({required bool notify}) {
    final drag = _drag;
    if (drag == null) return;

    _autoScroller?.stopAutoScroll();
    _animator.lift.retarget(0, widget.style.dropSpring);
    if (notify) _reorder?.onReorderCanceled?.call(drag.item);

    _animator.draggedId = null;
    _drag = null;
    if (mounted) setState(() {});
    _startTicker();
  }

  void _finishSettle() {
    _animator.draggedId = null;
    _drag = null;
    if (mounted) setState(() {});
  }

  // --- Transitions ---

  Animation<double> _animationOf(Object id) => _transitions[id] ?? kAlwaysCompleteAnimation;

  Widget _wrapTransition(Object id, Widget child) {
    final builder = widget.transitionBuilder;
    if (builder == null) return child;
    return builder(context, _animationOf(id), child);
  }

  // --- Build ---

  @override
  Widget build(BuildContext context) {
    _composite = _computeComposite();
    _indexByKeyValue = {
      for (var i = 0; i < _composite.length; i++) (_composite[i].ghost ? 'ghost' : 'item', _composite[i].id): i,
    };

    return _FluidListAdaptor(
      key: _bodyKey,
      animator: _animator,
      spacing: widget.spacing,
      style: widget.style,
      applyEffects: widget.transitionBuilder == null,
      composite: _composite,
      totalItems: _itemsById.length,
      delegate: SliverChildBuilderDelegate(
        _buildChild,
        childCount: _composite.length,
        findChildIndexCallback: (key) => key is ValueKey && key.value is (String, Object) ? _indexByKeyValue[key.value as (String, Object)] : null,
        addAutomaticKeepAlives: false,
        addRepaintBoundaries: false,
        addSemanticIndexes: false,
      ),
    );
  }

  Widget? _buildChild(BuildContext context, int index) {
    if (index < 0 || index >= _composite.length) return null;
    final entry = _composite[index];
    final id = entry.id;

    if (entry.ghost) {
      final ghost = _ghosts[id];
      if (ghost == null) return null;
      return _SliverListChild(
        key: ValueKey(('ghost', id)),
        id: id,
        role: ListChildRole.ghost,
        child: RepaintBoundary(
          child: IgnorePointer(child: _wrapTransition(id, widget.itemBuilder(context, ghost.item))),
        ),
      );
    }

    final item = _itemsById[id];
    if (item == null) return null;
    final isDragged = _drag?.id == id;

    var child = widget.itemBuilder(context, item);
    if (isDragged && widget.liftedBuilder != null) {
      child = widget.liftedBuilder!(context, item, _liftAnimation, child);
    }
    child = _wrapTransition(id, child);
    final reorder = _reorder;
    child = FluidListItemDragScope(
      enabled: reorder != null,
      startDrag: (event, delay) => _startDragRecognition(id, event, delay),
      child: reorder != null && reorder.dragMode == FluidListDragMode.item ? Listener(onPointerDown: (event) => _startDragRecognition(id, event, reorder.dragStartDelay), child: child) : child,
    );

    return _SliverListChild(
      key: ValueKey(('item', id)),
      id: id,
      role: ListChildRole.item,
      child: RepaintBoundary(child: child),
    );
  }
}

/// The adaptor widget that owns the child element lifecycle for the sliver.
class _FluidListAdaptor extends SliverMultiBoxAdaptorWidget {
  const _FluidListAdaptor({
    required super.delegate,
    required this.animator,
    required this.spacing,
    required this.style,
    required this.applyEffects,
    required this.composite,
    required this.totalItems,
    super.key,
  });

  final ListAnimator animator;
  final double spacing;
  final FluidListStyle style;
  final bool applyEffects;
  final List<_CompositeEntry> composite;
  final int totalItems;

  @override
  SliverMultiBoxAdaptorElement createElement() => SliverMultiBoxAdaptorElement(this, replaceMovedChildren: true);

  @override
  RenderSliverFluidList createRenderObject(BuildContext context) => RenderSliverFluidList(
    childManager: context as SliverMultiBoxAdaptorElement,
    animator: animator,
    spacing: spacing,
    style: style,
    applyEffects: applyEffects,
  );

  @override
  void updateRenderObject(BuildContext context, RenderSliverFluidList renderObject) {
    renderObject
      ..animator = animator
      ..spacing = spacing
      ..style = style
      ..applyEffects = applyEffects;
  }

  /// Estimates the scroll extent counting only items, so zero-extent ghosts do
  /// not dilute the average or inflate the remaining count.
  @override
  double? estimateMaxScrollOffset(
    SliverConstraints? constraints,
    int firstIndex,
    int lastIndex,
    double leadingScrollOffset,
    double trailingScrollOffset,
  ) {
    var builtItems = 0;
    for (var i = firstIndex; i <= lastIndex && i < composite.length; i++) {
      if (!composite[i].ghost) builtItems += 1;
    }
    if (builtItems == 0) return null;

    var itemsUpToLast = 0;
    for (var i = 0; i <= lastIndex && i < composite.length; i++) {
      if (!composite[i].ghost) itemsUpToLast += 1;
    }
    final remainingItems = totalItems - itemsUpToLast;
    if (remainingItems <= 0) return trailingScrollOffset;

    final averageExtent = (trailingScrollOffset - leadingScrollOffset) / builtItems;
    return trailingScrollOffset + remainingItems * averageExtent;
  }
}

/// Attaches identity and role to a sliver child, without invalidating layout on
/// the null→value initialization that happens inside the sliver's own layout.
class _SliverListChild extends ParentDataWidget<SliverFluidListParentData> {
  const _SliverListChild({
    required this.id,
    required this.role,
    required super.child,
    super.key,
  });

  final Object id;
  final ListChildRole role;

  @override
  void applyParentData(RenderObject renderObject) {
    final data = renderObject.parentData! as SliverFluidListParentData;
    final initialized = data.id != null;
    final changed = initialized && (data.id != id || data.role != role);
    data
      ..id = id
      ..role = role;
    if (changed) renderObject.parent?.markNeedsLayout();
  }

  @override
  Type get debugTypicalAncestorWidgetClass => SliverMultiBoxAdaptorWidget;
}

/// An [Animation] view over one item's show progress, handed to
/// [FluidListTransitionBuilder]. Driven each frame from the animator's spring.
class _ProgressAnimation extends Animation<double> with AnimationLocalListenersMixin, AnimationLocalStatusListenersMixin {
  _ProgressAnimation(this._value, this._status);

  double _value;
  AnimationStatus _status;

  @override
  double get value => _value;

  @override
  AnimationStatus get status => _status;

  void update(double value, AnimationStatus status) {
    if (value != _value) {
      _value = value;
      notifyListeners();
    }
    if (status != _status) {
      _status = status;
      notifyStatusListeners(status);
    }
  }

  @override
  void didRegisterListener() {}

  @override
  void didUnregisterListener() {}
}
