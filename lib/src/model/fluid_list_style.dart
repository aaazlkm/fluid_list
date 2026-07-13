import 'dart:ui' show Offset;

import 'package:flutter/foundation.dart';
import 'package:flutter/physics.dart';

/// The visual endpoint of an enter or exit animation: how an item looks when it
/// is fully hidden. The animation interpolates between this endpoint (progress
/// 0) and the item's natural, fully-shown appearance (progress 1).
///
/// - [opacity] and [scale] are the item's values at the hidden end. `1` for
///   either disables that channel.
/// - [offset] is the translation at the hidden end, in logical pixels, letting
///   an item slide in or out. It decays to [Offset.zero] as the item shows.
///
/// Because the progress is spring-driven it can overshoot 1 briefly; [scale]
/// and [offset] extrapolate through the overshoot for a subtle bounce, while
/// opacity is clamped so nothing paints above full strength.
@immutable
class FluidListEffect {
  const FluidListEffect({
    this.opacity = 0,
    this.scale = 0.94,
    this.offset = Offset.zero,
  });

  /// A pure cross-fade: no scaling or translation, only opacity.
  static const FluidListEffect fade = FluidListEffect(scale: 1);

  final double opacity;
  final double scale;
  final Offset offset;

  /// Resolves the effect at animation [progress] (0 hidden → 1 shown).
  ResolvedFluidListEffect resolve(double progress) => ResolvedFluidListEffect(
    opacity: (opacity + (1 - opacity) * progress).clamp(0.0, 1.0),
    scale: scale + (1 - scale) * progress,
    offset: offset * (1 - progress),
  );

  @override
  bool operator ==(Object other) => other is FluidListEffect && other.opacity == opacity && other.scale == scale && other.offset == offset;

  @override
  int get hashCode => Object.hash(opacity, scale, offset);
}

/// The concrete opacity, scale, and translation an item paints with this frame.
@immutable
class ResolvedFluidListEffect {
  const ResolvedFluidListEffect({
    required this.opacity,
    required this.scale,
    required this.offset,
  });

  final double opacity;
  final double scale;
  final Offset offset;
}

/// Every knob that shapes the list's motion, all spring-based.
///
/// Damping ratio of a spring is `damping / (2 * sqrt(stiffness * mass))`: below
/// 1 overshoots (lively), at 1 is critically damped (arrives without
/// overshoot).
@immutable
class FluidListStyle {
  const FluidListStyle({
    this.moveSpring = defaultMoveSpring,
    this.dropSpring = defaultDropSpring,
    this.enterSpring = defaultEnterSpring,
    this.exitSpring = defaultExitSpring,
    this.enterEffect = const FluidListEffect(),
    this.exitEffect = const FluidListEffect(),
    this.liftScale = 1.03,
  });

  /// Items sliding to new slots after a data change or to open the drop gap.
  /// Slightly underdamped (ratio ~0.85) so the motion reads as lively.
  static const SpringDescription defaultMoveSpring = SpringDescription(
    mass: 1,
    stiffness: 400,
    damping: 34,
  );

  /// The dragged item snapping into its slot on release, and the lift growing
  /// and shrinking. Critically damped (ratio ~1.0) so it never overshoots the
  /// drop target.
  static const SpringDescription defaultDropSpring = SpringDescription(
    mass: 1,
    stiffness: 550,
    damping: 47,
  );

  /// An arriving item's show progress springing 0 → 1. Slightly underdamped so
  /// the entrance has a gentle pop.
  static const SpringDescription defaultEnterSpring = SpringDescription(
    mass: 1,
    stiffness: 340,
    damping: 30,
  );

  /// A departing item's show progress springing 1 → 0. Critically damped so it
  /// fades out cleanly without a bounce.
  static const SpringDescription defaultExitSpring = SpringDescription(
    mass: 1,
    stiffness: 380,
    damping: 39,
  );

  /// Items sliding to new slots. See [defaultMoveSpring].
  final SpringDescription moveSpring;

  /// The dragged item settling in, and the lift. See [defaultDropSpring].
  final SpringDescription dropSpring;

  /// Show progress of an arriving item. See [defaultEnterSpring].
  final SpringDescription enterSpring;

  /// Show progress of a departing item. See [defaultExitSpring].
  final SpringDescription exitSpring;

  /// How an arriving item looks before it settles in.
  final FluidListEffect enterEffect;

  /// How a departing item looks as it leaves.
  final FluidListEffect exitEffect;

  /// How much the held item grows while lifted.
  final double liftScale;

  @override
  bool operator ==(Object other) =>
      other is FluidListStyle &&
      other.moveSpring == moveSpring &&
      other.dropSpring == dropSpring &&
      other.enterSpring == enterSpring &&
      other.exitSpring == exitSpring &&
      other.enterEffect == enterEffect &&
      other.exitEffect == exitEffect &&
      other.liftScale == liftScale;

  @override
  int get hashCode => Object.hash(
    moveSpring,
    dropSpring,
    enterSpring,
    exitSpring,
    enterEffect,
    exitEffect,
    liftScale,
  );
}
