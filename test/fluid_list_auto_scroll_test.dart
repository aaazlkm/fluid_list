import 'package:fluid_list/fluid_list.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('FluidListAutoScrollConfig constructor validation', () {
    test('accepts the defaults', () {
      expect(FluidListAutoScrollConfig.new, returnsNormally);
    });

    test('accepts zero velocities and distances', () {
      expect(
        () => const FluidListAutoScrollConfig(startVelocity: 0, maxVelocity: 0, edgeTriggerDistance: 0, rampDuration: Duration.zero),
        returnsNormally,
      );
    });

    test('rejects a negative startVelocity', () {
      expect(() => FluidListAutoScrollConfig(startVelocity: -1), throwsAssertionError);
    });

    test('rejects a NaN startVelocity', () {
      expect(() => FluidListAutoScrollConfig(startVelocity: double.nan), throwsAssertionError);
    });

    test('rejects an infinite startVelocity', () {
      expect(() => FluidListAutoScrollConfig(startVelocity: double.infinity), throwsAssertionError);
    });

    test('rejects a negative maxVelocity', () {
      expect(() => FluidListAutoScrollConfig(maxVelocity: -1), throwsAssertionError);
    });

    test('rejects a NaN maxVelocity', () {
      expect(() => FluidListAutoScrollConfig(maxVelocity: double.nan), throwsAssertionError);
    });

    test('rejects an infinite maxVelocity', () {
      expect(() => FluidListAutoScrollConfig(maxVelocity: double.infinity), throwsAssertionError);
    });

    test('rejects a negative edgeTriggerDistance', () {
      expect(() => FluidListAutoScrollConfig(edgeTriggerDistance: -1), throwsAssertionError);
    });

    test('rejects a NaN edgeTriggerDistance', () {
      expect(() => FluidListAutoScrollConfig(edgeTriggerDistance: double.nan), throwsAssertionError);
    });

    test('rejects an infinite edgeTriggerDistance', () {
      expect(() => FluidListAutoScrollConfig(edgeTriggerDistance: double.infinity), throwsAssertionError);
    });
  });
}
