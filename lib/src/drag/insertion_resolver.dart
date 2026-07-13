import 'package:flutter/foundation.dart';

/// One item's contribution to insertion resolution: an identity and its measured
/// main-axis extent.
@immutable
class ListItemSpec {
  const ListItemSpec({required this.id, required this.extent});

  final Object id;
  final double extent;
}

/// Finds the index whose resulting position sits closest to where the dragged
/// item currently floats.
///
/// A linear list has a closed-form inverse — positions are a running sum of
/// extents — so no solver replay is needed. Inserting the dragged item at index
/// `k` would place its main-axis start at `mainLead + Σ_{j<k} extent_j +
/// k * spacing`; the index whose resulting centre is nearest the dragged item's
/// centre wins. Hysteresis holds the current index until a challenger is
/// meaningfully closer, so the gap does not flap between two near-equidistant
/// slots.
///
/// [base] is the list order with the dragged item already removed, so the
/// returned index is in `[0, base.length]`.
int resolveInsertionIndex({
  required List<ListItemSpec> base,
  required double spacing,
  required double mainLead,
  required double draggedExtent,
  required double draggedMainStart,
  int? current,
  double hysteresis = 8,
}) {
  final draggedCentre = draggedMainStart + draggedExtent / 2;

  // start(k) = mainLead + prefix[k] + k * spacing, where prefix[k] is the sum
  // of the extents of the first k base items.
  var prefix = 0.0;
  var best = 0;
  var bestDistance = double.infinity;
  var currentDistance = double.infinity;

  for (var k = 0; k <= base.length; k++) {
    final start = mainLead + prefix + k * spacing;
    final centre = start + draggedExtent / 2;
    final distance = (centre - draggedCentre).abs();

    if (distance < bestDistance) {
      bestDistance = distance;
      best = k;
    }
    if (k == current) currentDistance = distance;

    if (k < base.length) prefix += base[k].extent;
  }

  if (current != null && currentDistance.isFinite && currentDistance - bestDistance <= hysteresis) {
    return current;
  }
  return best;
}
