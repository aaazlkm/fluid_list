import 'package:fluid_list/fluid_list.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluid_list_example/main.dart';

void main() {
  testWidgets('the demo adds, shuffles, and removes tasks without error', (tester) async {
    await tester.pumpWidget(const ExampleApp());
    await tester.pumpAndSettle();

    expect(find.text('Design the spring curves'), findsOneWidget);

    // Add a task: it fades and springs in.
    await tester.tap(find.byTooltip('Add task'));
    await tester.pumpAndSettle();

    // Shuffle: every card springs to a new slot.
    await tester.tap(find.byTooltip('Shuffle'));
    await tester.pumpAndSettle();

    // Remove the first card: it ghosts out while the rest close the gap.
    await tester.tap(find.byIcon(Icons.close).first);
    await tester.pumpAndSettle();

    // Switch to handle mode and back — the list rebuilds cleanly.
    await tester.tap(find.byTooltip('Drag: whole item'));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.drag_indicator), findsWidgets);

    expect(tester.takeException(), isNull);
  });

  testWidgets('a long-press drag reorders the task list', (tester) async {
    await tester.pumpWidget(const ExampleApp());
    await tester.pumpAndSettle();

    final firstTitle = find.text('Design the spring curves');
    final from = tester.getCenter(firstTitle);

    final gesture = await tester.startGesture(from);
    await tester.pump(kLongPressTimeout + const Duration(milliseconds: 60));
    for (var step = 1; step <= 6; step++) {
      await gesture.moveTo(from + Offset(0, 30.0 * step));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await gesture.up();
    await tester.pumpAndSettle();

    // The dragged card left the top slot.
    expect(tester.getCenter(firstTitle).dy, greaterThan(from.dy));
    expect(tester.takeException(), isNull);
  });

  testWidgets('a handle drag reorders in handle mode (with the lift decoration)', (tester) async {
    await tester.pumpWidget(const ExampleApp());
    await tester.pumpAndSettle();

    // Switch to handle mode so the cards expose drag handles.
    await tester.tap(find.byTooltip('Drag: whole item'));
    await tester.pumpAndSettle();

    final firstTitle = find.text('Design the spring curves');
    final startY = tester.getCenter(firstTitle).dy;

    // Grab the first card's handle and drag it down past a couple of cards.
    final from = tester.getCenter(find.byType(FluidListDragHandle).first);
    final gesture = await tester.startGesture(from);
    await tester.pump(const Duration(milliseconds: 20));
    for (var step = 1; step <= 8; step++) {
      await gesture.moveTo(from + Offset(0, 160.0 * step / 8));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await gesture.up();
    await tester.pumpAndSettle();

    // The card actually moved — it did not merely float in place.
    expect(tester.getCenter(firstTitle).dy, greaterThan(startY));
    expect(tester.takeException(), isNull);
  });

  testWidgets('the 1000-item list scrolls lazily without error', (tester) async {
    await tester.pumpWidget(const ExampleApp());
    await tester.pumpAndSettle();

    // Toggle to the big list, then fling through it.
    await tester.tap(find.byTooltip('4 items'));
    await tester.pumpAndSettle();

    await tester.fling(find.byType(CustomScrollView).first, const Offset(0, -3000), 3000);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    await tester.fling(find.byType(CustomScrollView).first, const Offset(0, 6000), 3000);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
