import 'package:fluid_list/src/animation/spring_value.dart';
import 'package:fluid_list/src/model/fluid_list_style.dart';
import 'package:flutter/physics.dart';
import 'package:flutter_test/flutter_test.dart';

const SpringDescription _spring = FluidListStyle.defaultMoveSpring;
const double _dt = 1 / 60;

/// Runs the spring until it comes to rest, returning the frames it took.
int settle(SpringValue value, {int maxFrames = 600}) {
  var frames = 0;
  while (value.tick(_dt)) {
    frames++;
    if (frames > maxFrames) fail('spring did not settle within $maxFrames frames');
  }
  return frames;
}

void main() {
  test('starts at rest', () {
    final value = SpringValue(5)..tick(_dt);
    expect(value.value, 5);
    expect(value.isAnimating, isFalse);
  });

  test('jumpTo moves immediately and cancels motion', () {
    final value = SpringValue(0)
      ..retarget(100, _spring)
      ..tick(_dt)
      ..jumpTo(42);

    expect(value.value, 42);
    expect(value.target, 42);
    expect(value.velocity, 0);
    expect(value.isAnimating, isFalse);
  });

  test('converges on its target and stops', () {
    final value = SpringValue(0)..retarget(100, _spring);
    expect(value.isAnimating, isTrue);

    settle(value);

    expect(value.value, 100);
    expect(value.velocity, 0);
    expect(value.isAnimating, isFalse);
  });

  test('a retarget within tolerance snaps rather than animating', () {
    final value = SpringValue(0)..retarget(0.01, _spring);
    expect(value.isAnimating, isFalse);
    expect(value.value, 0.01);
  });

  test('retargeting to the same value does not restart the simulation', () {
    final value = SpringValue(0)..retarget(100, _spring);
    for (var i = 0; i < 10; i++) {
      value.tick(_dt);
    }
    final midway = value.value;
    value.retarget(100, _spring);
    expect(value.value, midway);
  });

  test('retarget mid-flight preserves velocity', () {
    final value = SpringValue(0)..retarget(100, _spring);
    for (var i = 0; i < 10; i++) {
      value.tick(_dt);
    }
    final speedBefore = value.velocity;
    expect(speedBefore, greaterThan(0));

    // Redirect to a new target; the carried velocity keeps it moving that way.
    value.retarget(120, _spring);
    expect(value.velocity, speedBefore);
  });
}
