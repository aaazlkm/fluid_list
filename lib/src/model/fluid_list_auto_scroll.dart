import 'package:flutter/foundation.dart';

/// How the list auto-scrolls while a reorder drag holds an item near a viewport
/// edge.
///
/// Auto-scroll engages once the held item's leading edge comes within
/// [edgeTriggerDistance] of a viewport edge. Across that zone the speed scales
/// with proximity to the edge — [startVelocity] where the item first enters the
/// zone, up to [maxVelocity] once its edge reaches (or passes) the viewport
/// edge — and the velocity eases toward that target over [rampDuration]. Setting
/// [rampDuration] to [Duration.zero] drops the ease-in so the speed tracks the
/// position immediately.
@immutable
class FluidListAutoScrollConfig {
  const FluidListAutoScrollConfig({
    this.startVelocity = 100,
    this.maxVelocity = 3000,
    this.edgeTriggerDistance = 100,
    this.rampDuration = const Duration(milliseconds: 3000),
  });

  /// Speed (logical px/s) auto-scroll runs at when the held item first enters the
  /// trigger zone ([edgeTriggerDistance] from the edge). It scales up toward
  /// [maxVelocity] as the item nears the edge.
  final double startVelocity;

  /// Top speed (logical px/s) auto-scroll reaches once the held item's edge is at
  /// (or past) the viewport edge.
  final double maxVelocity;

  /// How far (logical px) from a viewport edge the held item's leading edge must
  /// come for auto-scroll to engage. Within this zone the speed ramps from
  /// [startVelocity] (at this distance) to [maxVelocity] (at the edge).
  final double edgeTriggerDistance;

  /// How long the item must stay at a given position for the speed to ease up to
  /// that position's target. [Duration.zero] makes the speed track the position
  /// at once (no ease-in).
  final Duration rampDuration;

  @override
  bool operator ==(Object other) => other is FluidListAutoScrollConfig && other.startVelocity == startVelocity && other.maxVelocity == maxVelocity && other.edgeTriggerDistance == edgeTriggerDistance && other.rampDuration == rampDuration;

  @override
  int get hashCode => Object.hash(startVelocity, maxVelocity, edgeTriggerDistance, rampDuration);
}
