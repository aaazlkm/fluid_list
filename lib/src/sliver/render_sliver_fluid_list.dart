// performLayout is a fork of the SDK's RenderSliverList algorithm; its internal
// invariant asserts and dead-reckoning locals follow the original's style.
// ignore_for_file: prefer_asserts_with_message, prefer_initializing_formals

import 'package:fluid_list/src/animation/list_animator.dart';
import 'package:fluid_list/src/model/fluid_list_style.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';

/// What a child contributes to the sliver's flow.
enum ListChildRole {
  /// A normal, in-flow item.
  item,

  /// A removed item painted at its frozen rect while it fades out. It is laid
  /// out (so it can paint) but contributes zero flow extent, so its successors
  /// close the gap.
  ghost,
}

/// Parent data for [RenderSliverFluidList] children: the standard sliver
/// bookkeeping (index, layoutOffset, keepAlive) plus our identity and role.
class SliverFluidListParentData extends SliverMultiBoxAdaptorParentData {
  Object? id;
  ListChildRole role = ListChildRole.item;
}

/// A lazy sliver that lays box children in a linear array along the main axis
/// like [RenderSliverList], but applies its motion (spring positions, enter /
/// exit effects, the drag lift) at paint time, and threads removed items
/// through as zero-extent "ghosts" that fade in place while survivors reflow.
///
/// Only the visible + cached children are built; everything else is dead
/// reckoned. Constant [spacing] and ghost transparency are folded into a single
/// per-child flow extent so the forward and backward dead reckoning stay
/// symmetric.
class RenderSliverFluidList extends RenderSliverMultiBoxAdaptor {
  RenderSliverFluidList({
    required super.childManager,
    required ListAnimator animator,
    required double spacing,
    required FluidListStyle style,
    required bool applyEffects,
    required bool dragProxyActive,
  }) : _animator = animator,
       _spacing = spacing,
       _style = style,
       _applyEffects = applyEffects,
       _dragProxyActive = dragProxyActive;

  ListAnimator _animator;
  ListAnimator get animator => _animator;
  set animator(ListAnimator value) {
    if (_animator == value) return;
    _animator = value;
    markNeedsLayout();
  }

  double _spacing;
  set spacing(double value) {
    if (_spacing == value) return;
    _spacing = value;
    markNeedsLayout();
  }

  FluidListStyle _style;
  set style(FluidListStyle value) {
    if (_style == value) return;
    _style = value;
    markNeedsPaint();
  }

  bool _applyEffects;
  set applyEffects(bool value) {
    if (_applyEffects == value) return;
    _applyEffects = value;
    markNeedsPaint();
  }

  /// Whether an overlay drag proxy is currently rendering the held item. While
  /// it is, the in-list dragged child is a zero-content placeholder: this render
  /// object skips painting and hit-testing it and drops the lift scale, leaving
  /// the overlay as the single source of the lifted pixels. Only affects paint,
  /// not layout, so a plain `markNeedsPaint` on change is enough.
  bool _dragProxyActive;
  set dragProxyActive(bool value) {
    if (_dragProxyActive == value) return;
    _dragProxyActive = value;
    markNeedsPaint();
  }

  // --- Built-window bookkeeping, read by the widget State ---

  final Map<Object, Size> _itemSizes = {};
  Map<Object, Size> get itemSizes => Map.unmodifiable(_itemSizes);

  final List<Object> _builtItemOrder = [];
  List<Object> get builtItemOrder => List.unmodifiable(_builtItemOrder);

  double? _firstBuiltItemOffset;

  /// Layout offset (content space) of the first built item — the base offset the
  /// drag insertion resolver measures from.
  double? get firstBuiltItemOffset => _firstBuiltItemOffset;

  double get crossAxisExtent => constraints.crossAxisExtent;

  /// The current scroll offset, exposed so the widget State can map global
  /// pointer positions into the content (scroll-offset) space the springs use.
  double get scrollOffset => constraints.scrollOffset;

  Axis get axis => constraints.axis;

  @override
  void setupParentData(covariant RenderObject child) {
    if (child.parentData is! SliverFluidListParentData) {
      child.parentData = SliverFluidListParentData();
    }
  }

  // --- Axis helpers ---

  Axis get _axis => constraints.axis;
  Offset _composePaint(double main, double cross) => _axis == Axis.vertical ? Offset(cross, main) : Offset(main, cross);
  Offset _composeContent(double main) => _axis == Axis.vertical ? Offset(0, main) : Offset(main, 0);
  double _mainOf(Offset o) => _axis == Axis.vertical ? o.dy : o.dx;
  double _crossOf(Offset o) => _axis == Axis.vertical ? o.dx : o.dy;

  SliverFluidListParentData _dataOf(RenderBox child) => child.parentData! as SliverFluidListParentData;

  /// The main-axis distance a child advances the flow: a ghost contributes
  /// nothing, an item its measured extent plus one [spacing]. Folding spacing in
  /// keeps forward and backward dead reckoning identical; the single trailing
  /// spacing is trimmed from the reported scroll extent when the end is reached.
  double _flowExtentOf(RenderBox child) => _dataOf(child).role == ListChildRole.ghost ? 0.0 : paintExtentOf(child) + _spacing;

  @override
  void performLayout() {
    final constraints = this.constraints;
    assert(
      constraints.growthDirection == GrowthDirection.forward && (constraints.axisDirection == AxisDirection.down || constraints.axisDirection == AxisDirection.right),
      'SliverFluidList supports only forward, non-reversed axes (down / right).',
    );
    childManager
      ..didStartLayout()
      ..setDidUnderflow(false);

    final scrollOffset = constraints.scrollOffset + constraints.cacheOrigin;
    assert(scrollOffset >= 0.0);
    final remainingExtent = constraints.remainingCacheExtent;
    assert(remainingExtent >= 0.0);
    final targetEndScrollOffset = scrollOffset + remainingExtent;
    final childConstraints = constraints.asBoxConstraints();
    var leadingGarbage = 0;
    var trailingGarbage = 0;
    var reachedEnd = false;

    if (firstChild == null) {
      if (!addInitialChild()) {
        geometry = SliverGeometry.zero;
        childManager.didFinishLayout();
        return;
      }
    }

    RenderBox? leadingChildWithLayout;
    RenderBox? trailingChildWithLayout;
    var earliestUsefulChild = firstChild;

    // Recover from null layout offsets left by a reorder of the delegate.
    if (childScrollOffset(firstChild!) == null) {
      var leadingChildrenWithoutLayoutOffset = 0;
      while (earliestUsefulChild != null && childScrollOffset(earliestUsefulChild) == null) {
        earliestUsefulChild = childAfter(earliestUsefulChild);
        leadingChildrenWithoutLayoutOffset += 1;
      }
      _dropSpringsForGarbage(leadingChildrenWithoutLayoutOffset, 0);
      collectGarbage(leadingChildrenWithoutLayoutOffset, 0);
      if (firstChild == null) {
        if (!addInitialChild()) {
          geometry = SliverGeometry.zero;
          childManager.didFinishLayout();
          return;
        }
      }
    }

    // Find the last child at or before the scrollOffset, inserting leading
    // children as needed.
    earliestUsefulChild = firstChild;
    for (var earliestScrollOffset = childScrollOffset(earliestUsefulChild!)!; earliestScrollOffset > scrollOffset; earliestScrollOffset = childScrollOffset(earliestUsefulChild)!) {
      earliestUsefulChild = insertAndLayoutLeadingChild(childConstraints, parentUsesSize: true);
      if (earliestUsefulChild == null) {
        _dataOf(firstChild!).layoutOffset = 0.0;
        if (scrollOffset == 0.0) {
          firstChild!.layout(childConstraints, parentUsesSize: true);
          earliestUsefulChild = firstChild;
          leadingChildWithLayout = earliestUsefulChild;
          trailingChildWithLayout ??= earliestUsefulChild;
          break;
        } else {
          geometry = SliverGeometry(scrollOffsetCorrection: -scrollOffset);
          return;
        }
      }

      final firstChildScrollOffset = earliestScrollOffset - _flowExtentOf(firstChild!);
      if (firstChildScrollOffset < -precisionErrorTolerance) {
        geometry = SliverGeometry(scrollOffsetCorrection: -firstChildScrollOffset);
        _dataOf(firstChild!).layoutOffset = 0.0;
        return;
      }

      _dataOf(earliestUsefulChild).layoutOffset = firstChildScrollOffset;
      assert(earliestUsefulChild == firstChild);
      leadingChildWithLayout = earliestUsefulChild;
      trailingChildWithLayout ??= earliestUsefulChild;
    }

    assert(childScrollOffset(firstChild!)! > -precisionErrorTolerance);

    // If at the very start, make sure we truly begin at index 0.
    if (scrollOffset < precisionErrorTolerance) {
      while (indexOf(firstChild!) > 0) {
        final earliestScrollOffset = childScrollOffset(firstChild!)!;
        earliestUsefulChild = insertAndLayoutLeadingChild(childConstraints, parentUsesSize: true);
        assert(earliestUsefulChild != null);
        final firstChildScrollOffset = earliestScrollOffset - _flowExtentOf(firstChild!);
        _dataOf(firstChild!).layoutOffset = 0.0;
        if (firstChildScrollOffset < -precisionErrorTolerance) {
          geometry = SliverGeometry(scrollOffsetCorrection: -firstChildScrollOffset);
          return;
        }
      }
    }

    assert(earliestUsefulChild == firstChild);
    assert(childScrollOffset(earliestUsefulChild!)! <= scrollOffset);

    if (leadingChildWithLayout == null) {
      earliestUsefulChild!.layout(childConstraints, parentUsesSize: true);
      leadingChildWithLayout = earliestUsefulChild;
      trailingChildWithLayout = earliestUsefulChild;
    }

    var inLayoutRange = true;
    var child = earliestUsefulChild;
    var index = indexOf(child!);
    var endScrollOffset = childScrollOffset(child)! + _flowExtentOf(child);
    bool advance() {
      assert(child != null);
      if (child == trailingChildWithLayout) {
        inLayoutRange = false;
      }
      child = childAfter(child!);
      if (child == null) {
        inLayoutRange = false;
      }
      index += 1;
      if (!inLayoutRange) {
        if (child == null || indexOf(child!) != index) {
          child = insertAndLayoutChild(childConstraints, after: trailingChildWithLayout, parentUsesSize: true);
          if (child == null) {
            return false;
          }
        } else {
          child!.layout(childConstraints, parentUsesSize: true);
        }
        trailingChildWithLayout = child;
      }
      assert(child != null);
      _dataOf(child!).layoutOffset = endScrollOffset;
      assert(_dataOf(child!).index == index);
      endScrollOffset = childScrollOffset(child!)! + _flowExtentOf(child!);
      return true;
    }

    // Skip children that end before the scroll offset.
    while (endScrollOffset < scrollOffset) {
      leadingGarbage += 1;
      if (!advance()) {
        assert(leadingGarbage == childCount);
        assert(child == null);
        _dropSpringsForGarbage(leadingGarbage - 1, 0);
        collectGarbage(leadingGarbage - 1, 0);
        assert(firstChild == lastChild);
        final extent = childScrollOffset(lastChild!)! + paintExtentOf(lastChild!);
        geometry = SliverGeometry(scrollExtent: extent, maxPaintExtent: extent);
        _recordBuiltWindow();
        // Balance the didStartLayout() above: this is a terminal return, not a
        // scroll-offset-correction redo, so the child manager must finish too.
        childManager.didFinishLayout();
        return;
      }
    }

    // Fill down to the target end.
    while (endScrollOffset < targetEndScrollOffset) {
      if (!advance()) {
        reachedEnd = true;
        break;
      }
    }

    // Everything after `child` is garbage.
    if (child != null) {
      child = childAfter(child!);
      while (child != null) {
        trailingGarbage += 1;
        child = childAfter(child!);
      }
    }

    _dropSpringsForGarbage(leadingGarbage, trailingGarbage);
    collectGarbage(leadingGarbage, trailingGarbage);
    assert(debugAssertChildListIsNonEmptyAndContiguous());

    // Trim the single trailing spacing folded into the last item's flow extent.
    final lastIsItem = _dataOf(lastChild!).role == ListChildRole.item;
    final contentEnd = reachedEnd && lastIsItem ? endScrollOffset - _spacing : endScrollOffset;

    final double estimatedMaxScrollOffset;
    if (reachedEnd) {
      estimatedMaxScrollOffset = contentEnd;
    } else {
      estimatedMaxScrollOffset = childManager.estimateMaxScrollOffset(
        constraints,
        firstIndex: indexOf(firstChild!),
        lastIndex: indexOf(lastChild!),
        leadingScrollOffset: childScrollOffset(firstChild!),
        trailingScrollOffset: endScrollOffset,
      );
      assert(estimatedMaxScrollOffset >= endScrollOffset - childScrollOffset(firstChild!)!);
    }
    final paintExtent = calculatePaintOffset(constraints, from: childScrollOffset(firstChild!)!, to: contentEnd);
    final cacheExtent = calculateCacheOffset(constraints, from: childScrollOffset(firstChild!)!, to: contentEnd);
    final targetEndScrollOffsetForPaint = constraints.scrollOffset + constraints.remainingPaintExtent;
    geometry = SliverGeometry(
      scrollExtent: estimatedMaxScrollOffset,
      paintExtent: paintExtent,
      cacheExtent: cacheExtent,
      maxPaintExtent: estimatedMaxScrollOffset,
      hasVisualOverflow: contentEnd > targetEndScrollOffsetForPaint || constraints.scrollOffset > 0.0,
    );

    if (estimatedMaxScrollOffset == contentEnd) {
      childManager.setDidUnderflow(true);
    }
    _recordBuiltWindow();
    childManager.didFinishLayout();
  }

  /// After layout, snapshot the built items and point each one's position spring
  /// at its (scroll-independent) layout offset.
  void _recordBuiltWindow() {
    _itemSizes.clear();
    _builtItemOrder.clear();
    _firstBuiltItemOffset = null;
    var child = firstChild;
    while (child != null) {
      final data = _dataOf(child);
      final id = data.id;
      if (id != null && data.role == ListChildRole.item) {
        _itemSizes[id] = child.size;
        _builtItemOrder.add(id);
        final offset = childScrollOffset(child) ?? 0.0;
        _firstBuiltItemOffset ??= offset;
        _animator.placeItem(id, _composeContent(offset));
      }
      child = childAfter(child);
    }
  }

  /// Drops the springs of item children about to be garbage-collected, so an id
  /// that later re-materializes by scrolling snaps into place instead of gliding
  /// from a stale off-window position. The dragged item is never garbage.
  void _dropSpringsForGarbage(int leadingGarbage, int trailingGarbage) {
    var dropped = 0;
    var child = firstChild;
    while (child != null && dropped < leadingGarbage) {
      _maybeDropSpring(child);
      child = childAfter(child);
      dropped += 1;
    }
    dropped = 0;
    child = lastChild;
    while (child != null && dropped < trailingGarbage) {
      _maybeDropSpring(child);
      child = childBefore(child);
      dropped += 1;
    }
  }

  void _maybeDropSpring(RenderBox child) {
    final data = _dataOf(child);
    final id = data.id;
    if (id != null && data.role == ListChildRole.item && id != _animator.draggedId) {
      _animator.remove(id);
    }
  }

  // --- Painting ---

  /// A child's top-left in content (scroll-offset) space, including the built-in
  /// enter/exit translation unless a transition builder owns the look.
  Offset _contentOffsetOf(SliverFluidListParentData data, RenderBox child) {
    final id = data.id;
    if (id == null) return _composeContent(childScrollOffset(child) ?? 0.0);
    final base = data.role == ListChildRole.ghost ? (_animator.ghostRects[id]?.topLeft ?? Offset.zero) : (_animator.offsetOf(id) ?? _composeContent(childScrollOffset(child) ?? 0.0));
    return _applyEffects ? base + _animator.visualOf(id).offset : base;
  }

  /// A child's top-left in the sliver's paint space (content offset with the
  /// scroll offset removed from the main axis).
  Offset _slotPaintOffset(RenderBox child) {
    final content = _contentOffsetOf(_dataOf(child), child);
    return _composePaint(_mainOf(content) - constraints.scrollOffset, _crossOf(content));
  }

  double _effectScaleOf(SliverFluidListParentData data) {
    final id = data.id;
    return id == null || !_applyEffects ? 1.0 : _animator.visualOf(id).scale;
  }

  /// The dragged item's extra paint scale from the lift (1 at rest, growing to
  /// [FluidListStyle.liftScale] fully lifted). Shared by paint, hit testing, and
  /// [applyPaintTransform] so the interactive area tracks the visible one.
  double get _dragLiftScale => 1 + (_style.liftScale - 1) * _animator.lift.value;

  /// A child's effective opacity, matching what [_paintChild] would render.
  double _effectiveOpacityOf(SliverFluidListParentData data) {
    final id = data.id;
    return id == null || !_applyEffects ? 1.0 : _animator.visualOf(id).opacity.clamp(0.0, 1.0);
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    if (firstChild == null) return;

    RenderBox? dragged;
    var child = firstChild;
    while (child != null) {
      final data = _dataOf(child);
      if (data.role == ListChildRole.item && data.id == _animator.draggedId) {
        dragged = child;
      } else {
        _paintChild(context, offset, child);
      }
      child = childAfter(child);
    }
    // While the overlay proxy owns the lifted pixels the in-list dragged child
    // is an empty placeholder, so there is nothing to paint on top; painting it
    // would only allocate a needless transform/opacity layer around a blank box.
    if (dragged != null && !_dragProxyActive) {
      _paintChild(context, offset, dragged, extraScale: _dragLiftScale);
    }
  }

  void _paintChild(PaintingContext context, Offset offset, RenderBox child, {double extraScale = 1}) {
    final data = _dataOf(child);
    final childOffset = _slotPaintOffset(child) + offset;

    final opacity = _effectiveOpacityOf(data);
    if (opacity <= 0) return;

    final scale = _effectScaleOf(data) * extraScale;

    void core(PaintingContext innerContext, Offset innerOffset) {
      if (scale == 1) {
        innerContext.paintChild(child, innerOffset);
        return;
      }
      final centre = child.size.center(innerOffset);
      final transform = Matrix4.identity()
        ..translateByDouble(centre.dx, centre.dy, 0, 1)
        ..scaleByDouble(scale, scale, 1, 1)
        ..translateByDouble(-centre.dx, -centre.dy, 0, 1);
      innerContext.pushTransform(needsCompositing, Offset.zero, transform, (ctx, _) => ctx.paintChild(child, innerOffset));
    }

    if (opacity < 1) {
      context.pushOpacity(childOffset, (opacity * 255).round(), core);
    } else {
      core(context, childOffset);
    }
  }

  // --- Hit testing & transforms ---

  @override
  bool hitTestChildren(SliverHitTestResult result, {required double mainAxisPosition, required double crossAxisPosition}) {
    final boxResult = BoxHitTestResult.wrap(result);
    final hitPoint = _composePaint(mainAxisPosition, crossAxisPosition);

    // The dragged child paints on top, so test it first — with the same lift
    // scale it paints with, so its interactive area matches its pixels. Skipped
    // when the overlay proxy is active: the in-list child is then an empty,
    // non-interactive placeholder (the live pointer is already owned by the drag
    // recognizer), matching the SDK's non-hittable lifted item.
    final draggedId = _animator.draggedId;
    if (draggedId != null && !_dragProxyActive) {
      var child = firstChild;
      while (child != null) {
        final data = _dataOf(child);
        if (data.role == ListChildRole.item && data.id == draggedId) {
          if (_effectiveOpacityOf(data) > 0 && _hitTestChild(boxResult, child, hitPoint, extraScale: _dragLiftScale)) return true;
          break;
        }
        child = childAfter(child);
      }
    }

    var child = lastChild;
    while (child != null) {
      final data = _dataOf(child);
      // Skip ghosts, the dragged child (tested above), and anything painted
      // fully transparent so an invisible row cannot absorb a tap.
      if (data.role != ListChildRole.ghost && data.id != draggedId && _effectiveOpacityOf(data) > 0) {
        if (_hitTestChild(boxResult, child, hitPoint)) return true;
      }
      child = childBefore(child);
    }
    return false;
  }

  bool _hitTestChild(BoxHitTestResult result, RenderBox child, Offset hitPoint, {double extraScale = 1}) {
    final transform = _paintTransformOf(child, extraScale: extraScale);
    return result.addWithPaintTransform(
      transform: transform,
      position: hitPoint,
      hitTest: (innerResult, position) => child.hitTest(innerResult, position: position),
    );
  }

  /// The matrix mapping [child]-local coordinates into the sliver's paint space,
  /// used by both hit testing and [applyPaintTransform] so pointer geometry
  /// agrees with pixels.
  Matrix4 _paintTransformOf(RenderBox child, {double extraScale = 1}) {
    final slot = _slotPaintOffset(child);
    final scale = _effectScaleOf(_dataOf(child)) * extraScale;
    final transform = Matrix4.identity()..translateByDouble(slot.dx, slot.dy, 0, 1);
    if (scale != 1) {
      final centre = child.size.center(Offset.zero);
      transform
        ..translateByDouble(centre.dx, centre.dy, 0, 1)
        ..scaleByDouble(scale, scale, 1, 1)
        ..translateByDouble(-centre.dx, -centre.dy, 0, 1);
    }
    return transform;
  }

  @override
  void applyPaintTransform(RenderBox child, Matrix4 transform) {
    final extraScale = !_dragProxyActive && _dataOf(child).id == _animator.draggedId ? _dragLiftScale : 1.0;
    transform.multiply(_paintTransformOf(child, extraScale: extraScale));
  }

  @override
  double childMainAxisPosition(RenderBox child) => _mainOf(_contentOffsetOf(_dataOf(child), child)) - constraints.scrollOffset;

  @override
  double childCrossAxisPosition(RenderBox child) => _crossOf(_contentOffsetOf(_dataOf(child), child));
}
