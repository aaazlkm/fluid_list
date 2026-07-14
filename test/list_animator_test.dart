import 'dart:ui';

import 'package:fluid_list/src/animation/list_animator.dart';
import 'package:fluid_list/src/model/fluid_list_style.dart';
import 'package:flutter_test/flutter_test.dart';

const double _dt = 1 / 60;

/// Advances the animator until nothing is moving, returning the ids that exited.
List<Object> settle(ListAnimator animator, {int maxFrames = 1200}) {
  final exited = <Object>[];
  var frames = 0;
  while (true) {
    final result = animator.tick(_dt);
    exited.addAll(result.exited);
    if (!result.active) break;
    if (++frames > maxFrames) fail('animator did not settle within $maxFrames frames');
  }
  return exited;
}

ListAnimator _animator() => ListAnimator(style: const FluidListStyle());

void main() {
  test('a freshly materialized item appears in place, fully shown', () {
    final animator = _animator()..placeItem('a', const Offset(0, 40));
    expect(animator.offsetOf('a'), const Offset(0, 40));
    expect(animator.visualOf('a').opacity, 1);
    expect(animator.isAnimating, isFalse);
  });

  test('a pending-enter item starts hidden and settles fully shown', () {
    final animator = _animator()
      ..markPendingEnter('a')
      ..placeItem('a', Offset.zero);

    expect(animator.visualOf('a').opacity, 0);
    expect(animator.visualOf('a').scale, lessThan(1));

    settle(animator);

    expect(animator.visualOf('a').opacity, 1);
    expect(animator.visualOf('a').scale, 1);
    expect(animator.progressOf('a'), moreOrLessEquals(1));
  });

  test('re-placing an existing item glides it to the new target', () {
    final animator = _animator()..placeItem('a', Offset.zero);
    expect(animator.offsetOf('a'), Offset.zero);

    animator.placeItem('a', const Offset(0, 100));
    for (var i = 0; i < 3; i++) {
      animator.tick(_dt);
    }
    final dy = animator.offsetOf('a')!.dy;
    expect(dy, greaterThan(0));
    expect(dy, lessThan(100));

    settle(animator);
    expect(animator.offsetOf('a')!.dy, moreOrLessEquals(100));
  });

  test('an exit fades out, is reported once, and then forgotten', () {
    final animator = _animator()
      ..placeItem('a', Offset.zero)
      ..beginExit('a', const Rect.fromLTWH(0, 0, 100, 40));
    expect(animator.ghostRects.containsKey('a'), isTrue);

    final exited = settle(animator);

    expect(exited, ['a']);
    expect(animator.containsItem('a'), isFalse);
    expect(animator.ghostRects.containsKey('a'), isFalse);
  });

  test('reviving a mid-exit item cancels the exit', () {
    final animator = _animator()
      ..placeItem('a', Offset.zero)
      ..beginExit('a', const Rect.fromLTWH(0, 0, 100, 40));
    for (var i = 0; i < 5; i++) {
      animator.tick(_dt);
    }
    expect(animator.progressOf('a'), lessThan(1));

    animator.revive('a');
    expect(animator.ghostRects.containsKey('a'), isFalse);

    final exited = settle(animator);
    expect(exited, isEmpty);
    expect(animator.containsItem('a'), isTrue);
    expect(animator.progressOf('a'), moreOrLessEquals(1));
  });

  test('the dragged item is pinned and exempt from placement', () {
    final animator = _animator()
      ..placeItem('a', Offset.zero)
      ..placeItem('b', const Offset(0, 40))
      ..draggedId = 'a'
      ..setDragOffset(const Offset(20, 200));
    expect(animator.offsetOf('a'), const Offset(20, 200));

    animator
      ..placeItem('a', Offset.zero)
      ..placeItem('b', const Offset(0, 40));
    expect(animator.offsetOf('a'), const Offset(20, 200));
  });

  test('a never-materialized pending-enter mark does not animate later', () {
    // The item scrolled into view only after the mark was cleared.
    final animator = _animator()
      ..markPendingEnter('a')
      ..clearPendingEnter()
      ..placeItem('a', Offset.zero);
    expect(animator.visualOf('a').opacity, 1);
    expect(animator.isAnimating, isFalse);
  });
}
