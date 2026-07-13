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
    this.transitionBuilder,
    this.onReorderStarted,
    this.onReorderFinished,
    this.onTapItem,
  });

  final List<_Item> items;
  final Axis axis;
  final double spacing;
  final FluidListDragMode dragMode;
  final bool echoReorder;
  final bool lifted;
  final FluidListTransitionBuilder? transitionBuilder;
  final void Function(_Item)? onReorderStarted;
  final void Function(FluidListReorderResult<_Item>)? onReorderFinished;
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
        reorder: FluidListReorderEnabled(
          dragMode: widget.dragMode,
          dragStartDelay: _dragDelay,
          onReorderStarted: widget.onReorderStarted,
          onReorderFinished: (result) {
            widget.onReorderFinished?.call(result);
            if (widget.echoReorder) setState(() => _items = result.items);
          },
        ),
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
}
