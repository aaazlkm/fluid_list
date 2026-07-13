import 'dart:ui' show Offset, Rect;

import 'package:fluid_list/src/animation/spring_value.dart';
import 'package:fluid_list/src/model/fluid_list_style.dart';

enum _Phase { steady, entering, exiting }

class _ItemAnimation {
  _ItemAnimation({required Offset origin, required double progress}) : x = SpringValue(origin.dx), y = SpringValue(origin.dy), progress = SpringValue(progress);

  final SpringValue x;
  final SpringValue y;

  /// Show progress: 0 fully hidden, 1 fully shown. Spring-driven, so it can
  /// briefly overshoot 1 on entry for a gentle pop.
  final SpringValue progress;

  _Phase phase = _Phase.steady;

  Offset get offset => Offset(x.value, y.value);

  bool get isAnimating => x.isAnimating || y.isAnimating || progress.isAnimating || phase != _Phase.steady;
}

/// Owns every animated quantity in the list and advances them from a single
/// ticker.
///
/// Positions, show progress, and the drag lift are all paint-only: the sliver
/// render object reads them at paint time and never relayouts for them. Layout
/// (the dead-reckoned child offsets) is driven separately by the sliver, which
/// calls [placeItem] for each child it lays out.
class ListAnimator {
  ListAnimator({required this.style});

  FluidListStyle style;

  final Map<Object, _ItemAnimation> _items = {};

  /// Frozen rects (in content/scroll-offset space) of items that were removed
  /// and are fading out, so the render object can still place and size them.
  final Map<Object, Rect> _ghostRects = {};

  /// Ids that just arrived in the data and should play the enter animation the
  /// first time they are laid out. An id that never materializes (added
  /// off-screen) is simply forgotten at the end of the frame — it should not
  /// animate when later scrolled into view.
  final Set<Object> _pendingEnter = {};

  /// The item currently held by the pointer, exempt from target syncing.
  Object? draggedId;

  /// 0 at rest, 1 fully lifted. Drives the dragged item's scale.
  final SpringValue lift = SpringValue(0);

  Map<Object, Rect> get ghostRects => _ghostRects;

  Offset? offsetOf(Object id) => _items[id]?.offset;

  /// Show progress of [id]: 0 hidden, 1 shown. Missing items read as shown.
  double progressOf(Object id) => _items[id]?.progress.value ?? 1;

  /// The opacity, scale, and translation [id] should paint with this frame,
  /// resolved from its phase (enter effect while arriving, exit effect while
  /// leaving) and its current show progress. A steady or unknown item paints at
  /// full strength.
  ResolvedFluidListEffect visualOf(Object id) {
    final item = _items[id];
    if (item == null) return _shown;
    return switch (item.phase) {
      _Phase.entering => style.enterEffect.resolve(item.progress.value),
      _Phase.exiting => style.exitEffect.resolve(item.progress.value),
      _Phase.steady => _shown,
    };
  }

  static const ResolvedFluidListEffect _shown = ResolvedFluidListEffect(opacity: 1, scale: 1, offset: Offset.zero);

  bool get isSettling {
    final id = draggedId;
    return id != null && (_items[id]?.isAnimating ?? false);
  }

  bool containsItem(Object id) => _items.containsKey(id);

  /// Marks [id] to play the enter animation when it is next laid out.
  void markPendingEnter(Object id) => _pendingEnter.add(id);

  /// Forgets pending-enter marks that were never materialized this frame, so an
  /// item added while off-screen does not animate when later scrolled to.
  void clearPendingEnter() => _pendingEnter.clear();

  /// Pin the dragged item under the pointer without spring lag.
  void setDragOffset(Offset offset) {
    final item = _items[draggedId];
    if (item == null) return;
    item.x.jumpTo(offset.dx);
    item.y.jumpTo(offset.dy);
  }

  /// Point [id]'s position spring at [target] (in content/scroll-offset space),
  /// as computed by the sliver's layout. A surviving item glides there; a
  /// brand-new id is created at the target — springing its show progress up
  /// from 0 if it was a fresh data arrival ([markPendingEnter]), or appearing
  /// in place (progress 1) if it merely scrolled into view.
  void placeItem(Object id, Offset target) {
    final existing = _items[id];
    if (existing != null) {
      if (id == draggedId) return;
      existing.x.retarget(target.dx, style.moveSpring);
      existing.y.retarget(target.dy, style.moveSpring);
      return;
    }

    final enter = _pendingEnter.remove(id);
    final fresh = _ItemAnimation(origin: target, progress: enter ? 0 : 1);
    if (enter) {
      fresh.phase = _Phase.entering;
      fresh.progress.retarget(1, style.enterSpring);
    }
    _items[id] = fresh;
  }

  /// Settle the dragged item into [target] with the drop spring.
  void settleDragged(Offset target) {
    final item = _items[draggedId];
    if (item == null) return;
    item.x.retarget(target.dx, style.dropSpring);
    item.y.retarget(target.dy, style.dropSpring);
  }

  /// Begin fading [id] out from [lastRect]; its rect is retained so it can still
  /// paint and size itself while its progress springs to 0.
  void beginExit(Object id, Rect lastRect) {
    final item = _items[id];
    if (item == null) return;
    item.phase = _Phase.exiting;
    item.progress.retarget(0, style.exitSpring);
    _ghostRects[id] = lastRect;
  }

  /// An id that was exiting has reappeared in the data: send it back to shown
  /// with the enter spring and drop its ghost, so no flicker shows.
  void revive(Object id) {
    final item = _items[id];
    if (item == null) return;
    item.phase = _Phase.entering;
    item.progress.retarget(1, style.enterSpring);
    _ghostRects.remove(id);
  }

  /// Forget an item entirely (its exit finished, it scrolled out of the built
  /// window, or it was never animated).
  void remove(Object id) {
    _items.remove(id);
    _ghostRects.remove(id);
    _pendingEnter.remove(id);
  }

  /// Advance every channel. Returns the ids whose exit completed this tick, and
  /// whether anything is still moving.
  ({bool active, List<Object> exited}) tick(double dt) {
    var active = false;
    final exited = <Object>[];

    if (lift.tick(dt)) active = true;

    for (final entry in _items.entries) {
      final item = entry.value;
      if (item.x.tick(dt)) active = true;
      if (item.y.tick(dt)) active = true;
      final progressMoving = item.progress.tick(dt);
      if (progressMoving) active = true;

      switch (item.phase) {
        case _Phase.entering:
          if (!progressMoving) item.phase = _Phase.steady;
        case _Phase.exiting:
          if (!progressMoving) exited.add(entry.key);
        case _Phase.steady:
          break;
      }
    }

    for (final id in exited) {
      remove(id);
    }

    return (active: active, exited: exited);
  }

  /// True while any spring or progress is live.
  bool get isAnimating => lift.isAnimating || _items.values.any((item) => item.isAnimating);
}
