import 'dart:math' as math;

import 'package:fluid_list/fluid_list.dart';
import 'package:fluid_list/src/sliver/render_sliver_fluid_list.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Fixed-extent cards keep the expected geometry easy to state.
class _Item {
  const _Item(this.id, this.extent);

  final String id;
  final double extent;
}

const _dragDelay = Duration(milliseconds: 300);

class _Harness extends StatefulWidget {
  const _Harness({
    required this.items,
    this.axis = Axis.vertical,
    this.spacing = 0,
    this.dragMode = FluidListDragMode.item,
    this.echoReorder = false,
    this.lifted = false,
    this.reorderEnabled = true,
    this.autoScroll,
    this.transitionBuilder,
    this.onReorderStarted,
    this.onReorderFinished,
    this.onReorderCanceled,
    this.onTapItem,
  });

  final List<_Item> items;
  final Axis axis;
  final double spacing;
  final FluidListDragMode dragMode;
  final bool echoReorder;
  final bool lifted;
  final bool reorderEnabled;
  final FluidListAutoScrollConfig? autoScroll;
  final FluidListTransitionBuilder? transitionBuilder;
  final void Function(_Item)? onReorderStarted;
  final void Function(FluidListReorderResult<_Item>)? onReorderFinished;
  final void Function(_Item)? onReorderCanceled;
  final void Function(_Item)? onTapItem;

  @override
  State<_Harness> createState() => _HarnessState();
}

class _HarnessState extends State<_Harness> {
  late List<_Item> _items = widget.items;

  @override
  void didUpdateWidget(_Harness oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.items != widget.items) _items = widget.items;
  }

  Widget _buildItem(BuildContext context, _Item item) {
    final body = GestureDetector(
      onTap: () => widget.onTapItem?.call(item),
      child: SizedBox(
        width: widget.axis == Axis.horizontal ? item.extent : null,
        height: widget.axis == Axis.vertical ? item.extent : null,
        child: Text(item.id),
      ),
    );

    if (widget.dragMode == FluidListDragMode.handle) {
      return Row(
        children: [
          FluidListDragHandle(
            child: Container(width: 24, height: 24, color: const Color(0xFF000000), child: const Text('grip')),
          ),
          Expanded(child: body),
        ],
      );
    }
    return body;
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    home: Scaffold(
      body: FluidList<_Item>(
        items: _items,
        scrollDirection: widget.axis,
        spacing: widget.spacing,
        idOf: (item) => item.id,
        reorder: widget.reorderEnabled
            ? FluidListReorderEnabled(
                dragMode: widget.dragMode,
                dragStartDelay: _dragDelay,
                autoScroll: widget.autoScroll ?? const FluidListAutoScrollConfig(),
                onReorderStarted: widget.onReorderStarted,
                onReorderCanceled: widget.onReorderCanceled,
                onReorderFinished: (result) {
                  widget.onReorderFinished?.call(result);
                  if (widget.echoReorder) setState(() => _items = result.items);
                },
              )
            : const FluidListReorderDisabled(),
        liftedBuilder: widget.lifted
            ? (context, item, animation, child) => DecoratedBox(
                decoration: const BoxDecoration(color: Color(0x11000000)),
                child: child,
              )
            : null,
        transitionBuilder: widget.transitionBuilder,
        itemBuilder: _buildItem,
      ),
    ),
  );
}

RenderSliverFluidList _render(WidgetTester tester) => tester.allRenderObjects.whereType<RenderSliverFluidList>().first;

/// Drives a long-press drag from [from] to [to] and releases.
Future<void> dragFromTo(WidgetTester tester, Offset from, Offset to) async {
  final gesture = await tester.startGesture(from);
  await tester.pump(_dragDelay + const Duration(milliseconds: 50));
  final delta = to - from;
  for (var step = 1; step <= 6; step++) {
    await gesture.moveTo(from + delta * (step / 6));
    await tester.pump(const Duration(milliseconds: 16));
  }
  await gesture.up();
  await tester.pumpAndSettle();
}

/// Drives an immediate handle drag from [from] down by [dy] and releases.
Future<void> handleDrag(WidgetTester tester, Offset from, double dy) async {
  final gesture = await tester.startGesture(from);
  await tester.pump(const Duration(milliseconds: 20));
  for (var step = 1; step <= 6; step++) {
    await gesture.moveTo(from + Offset(0, dy * step / 6));
    await tester.pump(const Duration(milliseconds: 16));
  }
  await gesture.up();
  await tester.pumpAndSettle();
}

void main() {
  group('layout', () {
    testWidgets('lays items out in order on the first frame', (tester) async {
      await tester.pumpWidget(
        const _Harness(items: [_Item('a', 40), _Item('b', 30), _Item('c', 20)]),
      );
      await tester.pump();

      expect(tester.getTopLeft(find.text('a')).dy, 0);
      expect(tester.getTopLeft(find.text('b')).dy, 40);
      expect(tester.getTopLeft(find.text('c')).dy, 70);
    });

    testWidgets('lays out along x when horizontal', (tester) async {
      await tester.pumpWidget(
        const _Harness(axis: Axis.horizontal, items: [_Item('a', 50), _Item('b', 60)]),
      );
      await tester.pump();

      expect(tester.getTopLeft(find.text('a')).dx, 0);
      expect(tester.getTopLeft(find.text('b')).dx, 50);
    });

    testWidgets('inserts spacing between items', (tester) async {
      await tester.pumpWidget(
        const _Harness(spacing: 8, items: [_Item('a', 40), _Item('b', 40)]),
      );
      await tester.pump();

      expect(tester.getTopLeft(find.text('b')).dy, 48);
    });
  });

  group('laziness', () {
    testWidgets('builds only a window of a large list', (tester) async {
      await tester.pumpWidget(
        _Harness(items: [for (var i = 0; i < 2000; i++) _Item('$i', 40)]),
      );
      await tester.pumpAndSettle();

      expect(find.byType(Text).evaluate().length, lessThan(60));
      expect(find.text('0'), findsOneWidget);
    });

    testWidgets('scrubs down and back over a mid-list removal without a jump', (tester) async {
      await tester.pumpWidget(
        _Harness(items: [for (var i = 0; i < 2000; i++) _Item('$i', 40)]),
      );
      await tester.pumpAndSettle();

      // Remove an off-screen item; the top must be unaffected.
      await tester.pumpWidget(
        _Harness(
          items: [
            for (var i = 0; i < 2000; i++)
              if (i != 500) _Item('$i', 40),
          ],
        ),
      );
      await tester.pumpAndSettle();

      await tester.drag(find.byType(FluidList<_Item>), const Offset(0, -8000));
      await tester.pumpAndSettle();
      await tester.drag(find.byType(FluidList<_Item>), const Offset(0, 8000));
      await tester.pumpAndSettle();

      expect(find.text('0'), findsOneWidget);
      expect(tester.getTopLeft(find.text('0')).dy, 0);
      expect(tester.takeException(), isNull);
    });
  });

  group('implicit animation', () {
    testWidgets('springs surviving items into the gap left by a removal', (tester) async {
      await tester.pumpWidget(
        const _Harness(items: [_Item('a', 40), _Item('b', 40), _Item('c', 40)]),
      );
      await tester.pump();
      expect(tester.getTopLeft(find.text('c')).dy, 80);

      await tester.pumpWidget(
        const _Harness(items: [_Item('a', 40), _Item('c', 40)]),
      );
      await tester.pump();

      final midDy = tester.getTopLeft(find.text('c')).dy;
      expect(midDy, greaterThan(40));
      expect(midDy, lessThanOrEqualTo(80));

      await tester.pumpAndSettle();
      expect(tester.getTopLeft(find.text('c')).dy, 40);
    });

    testWidgets('keeps a removed item on screen as a ghost until it fades out', (tester) async {
      await tester.pumpWidget(
        const _Harness(items: [_Item('a', 40), _Item('b', 40)]),
      );
      await tester.pump();

      await tester.pumpWidget(
        const _Harness(items: [_Item('a', 40)]),
      );
      await tester.pump();
      expect(find.text('b'), findsOneWidget);

      await tester.pumpAndSettle();
      expect(find.text('b'), findsNothing);
    });

    testWidgets('fades a newly added item in', (tester) async {
      await tester.pumpWidget(
        const _Harness(items: [_Item('a', 40)]),
      );
      await tester.pump();

      await tester.pumpWidget(
        const _Harness(items: [_Item('a', 40), _Item('b', 40)]),
      );
      await tester.pump();

      final box = _render(tester);
      expect(box.animator.visualOf('b').opacity, lessThan(1));
      expect(box.animator.visualOf('b').scale, lessThan(1));

      await tester.pumpAndSettle();
      expect(box.animator.visualOf('b').opacity, 1);
    });

    testWidgets('does not animate an item that merely scrolled into view', (tester) async {
      await tester.pumpWidget(
        _Harness(items: [for (var i = 0; i < 200; i++) _Item('$i', 40)]),
      );
      await tester.pumpAndSettle();

      await tester.drag(find.byType(FluidList<_Item>), const Offset(0, -2000));
      await tester.pump();

      // A freshly scrolled-in item is fully shown, not entering.
      final box = _render(tester);
      final visibleId = box.builtItemOrder.last;
      expect(box.animator.visualOf(visibleId).opacity, 1);
    });
  });

  group('reorder', () {
    testWidgets('a long-press drag reports the new order', (tester) async {
      FluidListReorderResult<_Item>? result;
      await tester.pumpWidget(
        _Harness(
          items: const [_Item('a', 40), _Item('b', 40), _Item('c', 40)],
          onReorderFinished: (r) => result = r,
        ),
      );
      await tester.pump();

      final from = tester.getCenter(find.text('a'));
      await dragFromTo(tester, from, from + const Offset(0, 90));

      expect(result, isNotNull);
      expect(result!.item.id, 'a');
      expect(result!.toIndex, 2);
      expect(result!.items.map((item) => item.id).toList(), ['b', 'c', 'a']);
    });

    testWidgets('fires onReorderStarted at lift', (tester) async {
      _Item? started;
      await tester.pumpWidget(
        _Harness(
          items: const [_Item('a', 40), _Item('b', 40)],
          onReorderStarted: (item) => started = item,
        ),
      );
      await tester.pump();

      final gesture = await tester.startGesture(tester.getCenter(find.text('a')));
      await tester.pump(_dragDelay + const Duration(milliseconds: 50));
      await gesture.moveBy(const Offset(0, 10));
      await tester.pump();

      expect(started?.id, 'a');

      await gesture.up();
      await tester.pumpAndSettle();
    });

    testWidgets('commits to the new order when the caller echoes it back', (tester) async {
      await tester.pumpWidget(
        const _Harness(items: [_Item('a', 40), _Item('b', 40), _Item('c', 40)], echoReorder: true),
      );
      await tester.pump();

      final from = tester.getCenter(find.text('a'));
      await dragFromTo(tester, from, from + const Offset(0, 90));

      expect(tester.getTopLeft(find.text('a')).dy, 80);
      expect(tester.getTopLeft(find.text('b')).dy, 0);
      expect(tester.getTopLeft(find.text('c')).dy, 40);
    });

    testWidgets('a quick tap still fires with reorder enabled', (tester) async {
      _Item? tapped;
      await tester.pumpWidget(
        _Harness(
          items: const [_Item('a', 40), _Item('b', 40)],
          onTapItem: (item) => tapped = item,
        ),
      );
      await tester.pump();

      await tester.tap(find.text('a'));
      await tester.pump();

      expect(tapped?.id, 'a');
    });
  });

  group('reorder lifecycle', () {
    testWidgets('does not cancel after finishing when the item leaves during settle', (tester) async {
      var finished = 0;
      var canceled = 0;
      Widget harness(List<_Item> items) => _Harness(
        items: items,
        onReorderFinished: (_) => finished++,
        onReorderCanceled: (_) => canceled++,
      );

      await tester.pumpWidget(harness(const [_Item('a', 40), _Item('b', 40), _Item('c', 40)]));
      await tester.pump();

      // Drag 'a' down and release, then pump just one frame so it is settling.
      final from = tester.getCenter(find.text('a'));
      final gesture = await tester.startGesture(from);
      await tester.pump(_dragDelay + const Duration(milliseconds: 50));
      for (var step = 1; step <= 6; step++) {
        await gesture.moveTo(from + Offset(0, 90.0 * step / 6));
        await tester.pump(const Duration(milliseconds: 16));
      }
      await gesture.up();
      await tester.pump(const Duration(milliseconds: 16));
      expect(finished, 1);

      // The dragged item leaves the data mid-settle (e.g. deleted elsewhere).
      await tester.pumpWidget(harness(const [_Item('b', 40), _Item('c', 40)]));
      await tester.pumpAndSettle();

      expect(finished, 1);
      expect(canceled, 0, reason: 'no cancel after a finish for the same gesture');
    });

    testWidgets('fires onReorderCanceled when disposed mid-drag', (tester) async {
      _Item? canceled;
      await tester.pumpWidget(
        _Harness(
          items: const [_Item('a', 40), _Item('b', 40)],
          onReorderCanceled: (item) => canceled = item,
        ),
      );
      await tester.pump();

      final gesture = await tester.startGesture(tester.getCenter(find.text('a')));
      await tester.pump(_dragDelay + const Duration(milliseconds: 50));
      await gesture.moveBy(const Offset(0, 12));
      await tester.pump();

      // Tear the list down while the drag is active.
      await tester.pumpWidget(const SizedBox());
      expect(canceled?.id, 'a');

      await gesture.up();
    });

    testWidgets('stops the drag when reorder is disabled mid-gesture', (tester) async {
      var finished = 0;
      var canceled = 0;
      await tester.pumpWidget(
        _Harness(
          items: const [_Item('a', 40), _Item('b', 40), _Item('c', 40)],
          onReorderFinished: (_) => finished++,
          onReorderCanceled: (_) => canceled++,
        ),
      );
      await tester.pump();

      final from = tester.getCenter(find.text('a'));
      final gesture = await tester.startGesture(from);
      await tester.pump(_dragDelay + const Duration(milliseconds: 50));
      await gesture.moveBy(const Offset(0, 60));
      await tester.pump();

      // Turn reordering off while dragging: the item settles back to its slot
      // and the started gesture is balanced with exactly one cancel.
      await tester.pumpWidget(
        const _Harness(items: [_Item('a', 40), _Item('b', 40), _Item('c', 40)], reorderEnabled: false),
      );
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(find.text('a')).dy, moreOrLessEquals(0, epsilon: 2));
      expect(canceled, 1, reason: 'the captured cancel balances onReorderStarted');

      await gesture.moveBy(const Offset(0, 60));
      await gesture.up();
      await tester.pumpAndSettle();
      expect(finished, 0);
      expect(canceled, 1);
    });

    testWidgets('a canceled drag lowers the lift before clearing the held item', (tester) async {
      await tester.pumpWidget(
        const _Harness(items: [_Item('a', 40), _Item('b', 40), _Item('c', 40)], lifted: true),
      );
      await tester.pump();

      final from = tester.getCenter(find.text('a'));
      final gesture = await tester.startGesture(from);
      await tester.pump(_dragDelay + const Duration(milliseconds: 50));
      // Drive a few frames so the lift spring has visibly risen off zero.
      for (var step = 1; step <= 5; step++) {
        await gesture.moveBy(const Offset(0, 8));
        await tester.pump(const Duration(milliseconds: 16));
      }
      final box = _render(tester);
      expect(box.animator.lift.value, greaterThan(0), reason: 'lifted while dragging');

      // Cancel the gesture: the lift must animate down, not snap, and only after
      // it rests is the held item released.
      await gesture.cancel();
      await tester.pump(const Duration(milliseconds: 16));
      expect(box.animator.lift.value, greaterThan(0), reason: 'still lowering, not snapped to 0');

      await tester.pumpAndSettle();
      expect(box.animator.lift.value, moreOrLessEquals(0, epsilon: 0.01));
      expect(tester.getTopLeft(find.text('a')).dy, moreOrLessEquals(0, epsilon: 2));
    });
  });

  group('drag handle mode', () {
    testWidgets('the item body does not start a drag', (tester) async {
      _Item? started;
      await tester.pumpWidget(
        _Harness(
          items: const [_Item('a', 40), _Item('b', 40)],
          dragMode: FluidListDragMode.handle,
          onReorderStarted: (item) => started = item,
        ),
      );
      await tester.pump();

      final gesture = await tester.startGesture(tester.getCenter(find.text('a')));
      await tester.pump(_dragDelay + const Duration(milliseconds: 50));
      await gesture.moveBy(const Offset(0, 20));
      await tester.pump();

      expect(started, isNull);

      await gesture.up();
      await tester.pumpAndSettle();
    });

    testWidgets('a handle drag reorders, even with a liftedBuilder restructuring the item', (tester) async {
      FluidListReorderResult<_Item>? result;
      await tester.pumpWidget(
        _Harness(
          items: const [_Item('a', 40), _Item('b', 40), _Item('c', 40)],
          dragMode: FluidListDragMode.handle,
          lifted: true,
          onReorderFinished: (r) => result = r,
        ),
      );
      await tester.pump();

      await handleDrag(tester, tester.getCenter(find.text('grip').first), 90);

      expect(result, isNotNull);
      expect(result!.item.id, 'a');
      expect(result!.items.map((item) => item.id).toList(), ['b', 'c', 'a']);
    });
  });

  group('transition builder', () {
    Widget fade(BuildContext context, Animation<double> animation, Widget child) => FadeTransition(opacity: animation, child: child);

    FadeTransition fadeOf(WidgetTester tester, String id) => tester.widget<FadeTransition>(find.ancestor(of: find.text(id), matching: find.byType(FadeTransition)).first);

    testWidgets('drives an arriving item from hidden to shown (forward)', (tester) async {
      await tester.pumpWidget(
        _Harness(items: const [_Item('a', 40)], transitionBuilder: fade),
      );
      await tester.pumpAndSettle();

      await tester.pumpWidget(
        _Harness(items: const [_Item('a', 40), _Item('b', 40)], transitionBuilder: fade),
      );
      await tester.pump();

      final entering = fadeOf(tester, 'b').opacity;
      expect(entering.value, lessThan(1));
      expect(entering.status, AnimationStatus.forward);

      await tester.pumpAndSettle();
      expect(fadeOf(tester, 'b').opacity.value, 1);
    });

    testWidgets('runs a leaving item in reverse while its ghost fades', (tester) async {
      await tester.pumpWidget(
        _Harness(items: const [_Item('a', 40), _Item('b', 40)], transitionBuilder: fade),
      );
      await tester.pumpAndSettle();

      await tester.pumpWidget(
        _Harness(items: const [_Item('a', 40)], transitionBuilder: fade),
      );
      await tester.pump();

      final leaving = fadeOf(tester, 'b').opacity;
      expect(leaving.status, AnimationStatus.reverse);
      expect(leaving.value, lessThan(1));

      await tester.pumpAndSettle();
      expect(find.text('b'), findsNothing);
    });
  });

  group('autoscroll', () {
    /// Lifts item 'a' and holds it [holdAt] with the pointer never moving again,
    /// so only the autoscroll loop can advance the list.
    Future<(TestGesture, ScrollPosition)> holdAtEdge(
      WidgetTester tester,
      Offset holdAt, {
      FluidListAutoScrollConfig? autoScroll,
    }) async {
      await tester.pumpWidget(
        _Harness(
          items: [for (var i = 0; i < 60; i++) _Item(i == 0 ? 'a' : '$i', 100)],
          autoScroll: autoScroll,
        ),
      );
      await tester.pumpAndSettle();

      final gesture = await tester.startGesture(tester.getCenter(find.text('a')));
      await tester.pump(_dragDelay + const Duration(milliseconds: 50));
      await gesture.moveTo(holdAt);
      await tester.pump(const Duration(milliseconds: 16));

      return (gesture, tester.state<ScrollableState>(find.byType(Scrollable)).position);
    }

    testWidgets('keeps scrolling while the finger holds still at the edge', (tester) async {
      // Autoscroll is driven from the drag ticker, which fires every frame and
      // recomputes the edge overshoot from the finger-pinned item — so holding
      // the finger still keeps scrolling, with no stored rect that could go
      // stale and stall the loop.
      final (gesture, position) = await holdAtEdge(tester, const Offset(400, 580));

      final samples = <double>[];
      for (var i = 0; i < 12; i++) {
        await tester.pump(const Duration(milliseconds: 40));
        samples.add(position.pixels);
      }

      expect(samples.first, greaterThan(0), reason: 'autoscroll never started');
      // Strictly increasing: velocity stays positive once engaged, so any stall
      // would repeat an offset.
      for (var i = 1; i < samples.length; i++) {
        expect(samples[i], greaterThan(samples[i - 1]), reason: 'autoscroll stalled at step $i: $samples');
      }

      await gesture.up();
      await tester.pumpAndSettle();
    });

    testWidgets('eases in: accelerates instead of jumping to full speed', (tester) async {
      final (gesture, position) = await holdAtEdge(tester, const Offset(400, 580));

      // One tick per pump (dt clamped to 1/30 s), so the per-step deltas are
      // deterministic. The default ramp is long relative to this window, so the
      // first several steps are still speeding up toward the depth target.
      final samples = <double>[];
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 40));
        samples.add(position.pixels);
      }
      final deltas = [for (var i = 1; i < samples.length; i++) samples[i] - samples[i - 1]];

      // Each early step travels farther than the last — acceleration, not a
      // constant speed. (The pre-ramp implementation moved a fixed amount each
      // step, so these deltas would be equal and the test would fail.)
      for (var i = 1; i <= 4; i++) {
        expect(deltas[i], greaterThan(deltas[i - 1]), reason: 'not accelerating at step $i: $deltas');
      }
      expect(deltas.first, lessThan(deltas[4]), reason: 'no ramp: $deltas');

      await gesture.up();
      await tester.pumpAndSettle();
    });

    testWidgets('within the trigger zone, scrolls faster nearer the edge', (tester) async {
      // A wide trigger zone (200px) with a short ramp so both holds — one just
      // inside the zone, one near the edge — saturate quickly at their position's
      // speed. Items are 100px grabbed at centre, so itemEnd ≈ holdY + 50.
      const config = FluidListAutoScrollConfig(startVelocity: 60, maxVelocity: 1500, edgeTriggerDistance: 200, rampDuration: Duration(milliseconds: 200));

      Future<double> saturatedStep(Offset holdAt) async {
        // Unmount any previous run so this one starts from a fresh scroll offset
        // (a keyless _Harness would otherwise reuse the prior scroll position).
        await tester.pumpWidget(const SizedBox());
        final (gesture, position) = await holdAtEdge(tester, holdAt, autoScroll: config);
        for (var i = 0; i < 20; i++) {
          await tester.pump(const Duration(milliseconds: 40));
        }
        final before = position.pixels;
        await tester.pump(const Duration(milliseconds: 40));
        final step = position.pixels - before;
        await gesture.up();
        await tester.pumpAndSettle();
        return step;
      }

      final farFromEdge = await saturatedStep(const Offset(400, 360)); // itemEnd ≈ 410, ~190px from edge
      final nearEdge = await saturatedStep(const Offset(400, 540)); // itemEnd ≈ 590, ~10px from edge

      // Nearer the edge scrolls markedly faster. (A position-independent model
      // would make these equal.)
      expect(nearEdge, greaterThan(farFromEdge * 2), reason: 'proximity did not increase speed: far=$farFromEdge near=$nearEdge');
    });

    testWidgets('respects a configured max velocity', (tester) async {
      const maxVelocity = 200.0;
      // The y=580 hold is past the edge (itemEnd ≈ 630 > viewport bottom), so the
      // target is the true max.
      final (gesture, position) = await holdAtEdge(tester, const Offset(400, 580), autoScroll: const FluidListAutoScrollConfig(maxVelocity: maxVelocity));

      // Pump long enough for the ramp to saturate, then check no step ever
      // exceeded the cap. One tick per pump (dt clamped to 1/30 s), so a step at
      // the cap is maxVelocity / 30.
      var previous = position.pixels;
      var maxStep = 0.0;
      for (var i = 0; i < 100; i++) {
        await tester.pump(const Duration(milliseconds: 40));
        maxStep = math.max(maxStep, position.pixels - previous);
        previous = position.pixels;
      }

      const cappedStep = maxVelocity / 30;
      // No step ever exceeds the configured cap (with a little slack), and it
      // actually reaches it — far below the ~33px the default 1000 px/s max gives.
      expect(maxStep, lessThan(cappedStep + 1), reason: 'exceeded the configured max: $maxStep');
      expect(maxStep, greaterThan(cappedStep - 1), reason: 'never reached the configured max: $maxStep');

      await gesture.up();
      await tester.pumpAndSettle();
    });

    testWidgets('respects a configured start velocity', (tester) async {
      // A high start velocity means the very first autoscroll step is already
      // fast, rather than crawling up from a gentle floor.
      const startVelocity = 600.0;
      final (gesture, position) = await holdAtEdge(tester, const Offset(400, 580), autoScroll: const FluidListAutoScrollConfig(startVelocity: startVelocity));

      final before = position.pixels;
      await tester.pump(const Duration(milliseconds: 40));
      final firstStep = position.pixels - before;

      // The first step is near start / 30 — well above the ~3px a default 90 px/s
      // start would give.
      expect(firstStep, greaterThan(startVelocity / 30 - 1), reason: 'first step slower than the start velocity: $firstStep');

      await gesture.up();
      await tester.pumpAndSettle();
    });

    testWidgets('respects the ramp duration — zero tracks the target immediately', (tester) async {
      // Zero ramp with the y=580 hold past the edge (target = max) so the very
      // first step is already at full speed, with no ease-in.
      const config = FluidListAutoScrollConfig(maxVelocity: 1000, rampDuration: Duration.zero);
      final (gesture, position) = await holdAtEdge(tester, const Offset(400, 580), autoScroll: config);

      final before = position.pixels;
      await tester.pump(const Duration(milliseconds: 40));
      final firstStep = position.pixels - before;

      // Already at 1000 px/s → ~33px per 1/30 s tick, not a gentle ramped first step.
      expect(firstStep, greaterThan(1000 / 30 - 2), reason: 'did not jump to the depth target with a zero ramp: $firstStep');

      await gesture.up();
      await tester.pumpAndSettle();
    });

    testWidgets('stops autoscrolling once the item is dropped', (tester) async {
      final (gesture, position) = await holdAtEdge(tester, const Offset(400, 580));

      await tester.pump(const Duration(milliseconds: 40));
      expect(position.pixels, greaterThan(0));

      await gesture.up();
      await tester.pumpAndSettle();

      // Re-arming on scroll must not outlive the drag.
      final settled = position.pixels;
      await tester.pump(const Duration(milliseconds: 200));
      expect(position.pixels, settled);
    });

    testWidgets('does not autoscroll away from an item held mid-viewport', (tester) async {
      final (gesture, position) = await holdAtEdge(tester, const Offset(400, 300));

      await tester.pump(const Duration(milliseconds: 200));
      expect(position.pixels, 0);

      await gesture.up();
      await tester.pumpAndSettle();
    });
  });

  group('overlay drag proxy', () {
    /// Lifts [id] and leaves the finger down; returns the live gesture.
    Future<TestGesture> lift(WidgetTester tester, String id) async {
      final gesture = await tester.startGesture(tester.getCenter(find.text(id)));
      await tester.pump(_dragDelay + const Duration(milliseconds: 50));
      await gesture.moveBy(const Offset(0, 8));
      await tester.pump();
      return gesture;
    }

    /// The lifted item lives in the overlay, not in the scroll view.
    Finder inScrollView(String id) => find.descendant(of: find.byType(CustomScrollView), matching: find.text(id));

    testWidgets('renders the lifted item above an earlier sliver', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CustomScrollView(
              slivers: [
                SliverToBoxAdapter(
                  child: Container(key: const ValueKey('header'), height: 100, color: const Color(0xFF223344)),
                ),
                SliverFluidList<_Item>(
                  items: const [_Item('a', 40), _Item('b', 40), _Item('c', 40)],
                  idOf: (item) => item.id,
                  itemBuilder: (context, item) => SizedBox(height: item.extent, child: Text(item.id)),
                  reorder: FluidListReorderEnabled(dragStartDelay: _dragDelay, onReorderFinished: (_) {}),
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pump();

      // 'a' sits just below the 100px header. Lift it and drag up over the header.
      final gesture = await tester.startGesture(tester.getCenter(find.text('a')));
      await tester.pump(_dragDelay + const Duration(milliseconds: 50));
      await gesture.moveBy(const Offset(0, -90));
      await tester.pump();

      // The lifted copy floats in the overlay, not inside the scroll view (an
      // in-sliver child could not paint above the earlier header sliver).
      expect(find.text('a'), findsOneWidget);
      expect(inScrollView('a'), findsNothing);

      // And it overlaps the header it was dragged over.
      final proxyRect = tester.getRect(find.text('a'));
      final headerRect = tester.getRect(find.byKey(const ValueKey('header')));
      expect(proxyRect.top, lessThan(headerRect.bottom));
      expect(proxyRect.bottom, greaterThan(headerRect.top));

      await gesture.up();
      await tester.pumpAndSettle();
    });

    testWidgets('swaps the in-list child for a placeholder while lifted, and restores it on drop', (tester) async {
      await tester.pumpWidget(const _Harness(items: [_Item('a', 40), _Item('b', 40)]));
      await tester.pump();

      final gesture = await lift(tester, 'a');
      expect(find.text('a'), findsOneWidget, reason: 'exactly one copy — the proxy');
      expect(inScrollView('a'), findsNothing, reason: 'the in-list child is a bare placeholder');

      await gesture.up();
      await tester.pumpAndSettle();
      expect(inScrollView('a'), findsOneWidget, reason: 'back in the list, proxy gone');
    });

    testWidgets('the proxy tracks the pointer', (tester) async {
      await tester.pumpWidget(const _Harness(items: [_Item('a', 40), _Item('b', 40), _Item('c', 40)]));
      await tester.pump();

      final gesture = await lift(tester, 'a');
      final before = tester.getTopLeft(find.text('a'));
      await gesture.moveBy(const Offset(0, 40));
      await tester.pump();
      final after = tester.getTopLeft(find.text('a'));

      // The item is pinned to the finger, so the proxy moves with it exactly.
      expect(after.dy - before.dy, moreOrLessEquals(40, epsilon: 1));

      await gesture.up();
      await tester.pumpAndSettle();
    });

    testWidgets('the lifted builder decorates the overlay proxy', (tester) async {
      await tester.pumpWidget(const _Harness(items: [_Item('a', 40), _Item('b', 40)], lifted: true));
      await tester.pump();

      final gesture = await lift(tester, 'a');
      // The DecoratedBox from the liftedBuilder wraps the proxy's copy.
      expect(find.ancestor(of: find.text('a'), matching: find.byType(DecoratedBox)), findsOneWidget);

      await gesture.up();
      await tester.pumpAndSettle();
    });

    testWidgets('removing the held item mid-drag tears down the proxy and cancels', (tester) async {
      var canceled = 0;
      Widget harness(List<_Item> items) => _Harness(items: items, onReorderCanceled: (_) => canceled++);

      await tester.pumpWidget(harness(const [_Item('a', 40), _Item('b', 40), _Item('c', 40)]));
      await tester.pump();

      final gesture = await lift(tester, 'a');
      expect(find.text('a'), findsOneWidget);

      // 'a' leaves the data while held.
      await tester.pumpWidget(harness(const [_Item('b', 40), _Item('c', 40)]));
      await tester.pumpAndSettle();

      expect(find.text('a'), findsNothing, reason: 'proxy removed with the item');
      expect(canceled, 1);

      await gesture.up();
    });

    testWidgets('reorders a horizontal list through the proxy', (tester) async {
      FluidListReorderResult<_Item>? result;
      await tester.pumpWidget(
        _Harness(
          axis: Axis.horizontal,
          items: const [_Item('a', 50), _Item('b', 60), _Item('c', 40)],
          onReorderFinished: (r) => result = r,
        ),
      );
      await tester.pump();

      final from = tester.getCenter(find.text('a'));
      await dragFromTo(tester, from, from + const Offset(120, 0));

      expect(result?.item.id, 'a');
      expect(result!.toIndex, greaterThan(0));
    });

    testWidgets('falls back to in-sliver painting without an Overlay', (tester) async {
      var finished = 0;
      Widget tree(List<_Item> items) => Directionality(
        textDirection: TextDirection.ltr,
        child: MediaQuery(
          data: const MediaQueryData(),
          child: CustomScrollView(
            slivers: [
              SliverFluidList<_Item>(
                items: items,
                idOf: (item) => item.id,
                itemBuilder: (context, item) => SizedBox(height: item.extent, child: Text(item.id)),
                reorder: FluidListReorderEnabled(dragStartDelay: _dragDelay, onReorderFinished: (_) => finished++),
              ),
            ],
          ),
        ),
      );

      await tester.pumpWidget(tree(const [_Item('a', 40), _Item('b', 40), _Item('c', 40)]));
      await tester.pump();

      final from = tester.getCenter(find.text('a'));
      final gesture = await tester.startGesture(from);
      await tester.pump(_dragDelay + const Duration(milliseconds: 50));
      await gesture.moveBy(const Offset(0, 30));
      await tester.pump();

      // No overlay in scope → no proxy; the lifted item stays in the scroll view.
      expect(inScrollView('a'), findsOneWidget);

      // And a full drag still reorders without throwing.
      for (var step = 1; step <= 6; step++) {
        await gesture.moveTo(from + Offset(0, 90.0 * step / 6));
        await tester.pump(const Duration(milliseconds: 16));
      }
      await gesture.up();
      await tester.pumpAndSettle();
      expect(finished, 1);
    });
  });
}
