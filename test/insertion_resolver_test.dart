import 'package:fluid_list/src/drag/insertion_resolver.dart';
import 'package:flutter_test/flutter_test.dart';

/// Three 40-tall items, no spacing or padding. Candidate starts: 0, 40, 80, 120.
const _base = [
  ListItemSpec(id: 'a', extent: 40),
  ListItemSpec(id: 'b', extent: 40),
  ListItemSpec(id: 'c', extent: 40),
];

int _resolve(double draggedMainStart, {int? current}) => resolveInsertionIndex(
  base: _base,
  spacing: 0,
  mainLead: 0,
  draggedExtent: 40,
  draggedMainStart: draggedMainStart,
  current: current,
);

void main() {
  test(
    'picks the index whose resulting centre is nearest the dragged centre',
    () {
      // Dragged centre 95 → slot 2 (centre 100) wins over slot 1 (centre 60).
      expect(_resolve(75), 2);
      // Dragged centre 20 → slot 0.
      expect(_resolve(0), 0);
    },
  );

  test('clamps to the ends', () {
    expect(_resolve(-500), 0);
    expect(_resolve(500), 3);
  });

  test('holds the current slot until a challenger is meaningfully closer', () {
    // Dragged centre 78: slot 1 (centre 60, dist 18) is nearer than the held
    // slot 2 (centre 100, dist 22), but only by 4 — inside the 8 px hysteresis,
    // so the held slot stays.
    expect(_resolve(58, current: 2), 2);
    // With no held slot the nearer one wins outright.
    expect(_resolve(58), 1);
  });

  test('accounts for spacing between candidate slots', () {
    // Spacing 10 pushes later candidates down: start(k) = prefix + k*10.
    // Candidate starts: 0, 50, 100, 150; centres 20, 70, 120, 170.
    final index = resolveInsertionIndex(
      base: _base,
      spacing: 10,
      mainLead: 0,
      draggedExtent: 40,
      draggedMainStart: 90, // centre 110 → nearest slot 2 (centre 120).
    );
    expect(index, 2);
  });
}
