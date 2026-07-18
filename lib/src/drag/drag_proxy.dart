import 'package:flutter/widgets.dart';

/// A [Listenable] the [DragProxy] rebuilds its geometry from. The list state
/// pings it every tick and pointer update so the overlay proxy re-reads the
/// dragged item's position and lift scale from the live springs, without
/// rebuilding the (potentially expensive) item subtree.
class DragProxyRepaint extends ChangeNotifier {
  void ping() => notifyListeners();
}

/// Renders the lifted item inside the app's [Overlay] so it floats above the
/// whole scroll view — every sibling sliver, the app bar, everything.
///
/// A `RenderSliverFluidList` can only paint the lifted item within its own
/// sliver, and the viewport paints earlier slivers on top of later ones, so a
/// held item dragged upward would slip under whatever sits above the list. This
/// mirrors Flutter's own `SliverReorderableList`: at lift the list inserts an
/// [OverlayEntry] that draws a copy of the item and hides the in-list original,
/// then removes the entry once the drop settles.
///
/// All drag geometry still lives in the list state's springs (content/scroll
/// space). The proxy pulls from them at build time through the [globalTopLeft],
/// [liftScale], and [size] closures, so autoscroll and the settle spring keep
/// the proxy glued to the finger and then to its slot for free.
class DragProxy {
  DragProxy({
    required BuildContext listContext,
    required this.overlay,
    required this.globalTopLeft,
    required this.liftScale,
    required this.size,
    required this.contentBuilder,
    required this.repaint,
  }) : _themes = InheritedTheme.capture(from: listContext, to: overlay.context) {
    _entry = OverlayEntry(builder: _build);
  }

  final OverlayState overlay;

  /// The dragged item's top-left in global (screen) coordinates, or null when it
  /// momentarily cannot be resolved (e.g. the sliver detached this frame). A
  /// null keeps the last known position rather than snapping the card to (0, 0).
  final Offset? Function() globalTopLeft;

  /// The paint scale from the lift (1 at rest, growing to the style's liftScale
  /// fully lifted), applied around the item's centre to match the in-sliver
  /// paint the proxy replaces.
  final double Function() liftScale;

  /// The item's frozen size, used to lay the proxy out at its natural extent.
  final Size Function() size;

  /// Builds the item content (item builder wrapped by any lifted builder). Run
  /// once per entry build, not per geometry tick.
  final WidgetBuilder contentBuilder;

  /// Pinged each tick/pointer update to rebuild only the proxy's geometry.
  final Listenable repaint;

  final CapturedThemes _themes;
  late final OverlayEntry _entry;

  /// The last resolved position, retained so a transient null from
  /// [globalTopLeft] holds the card in place instead of jumping it to the
  /// overlay origin.
  Offset _lastTopLeft = Offset.zero;

  void insert() => overlay.insert(_entry);

  /// Rebuilds the whole entry, including the item subtree — call only when the
  /// item's data or builders may have changed, not for mere movement.
  void markNeedsBuild() => _entry.markNeedsBuild();

  void dispose() {
    // The overlay entry may already be gone if the whole tree is being torn
    // down (the overlay unmounts in the same frame); removing then would assert.
    if (_entry.mounted) _entry.remove();
    _entry.dispose();
  }

  Widget _build(BuildContext context) => _themes.wrap(
    MediaQuery(
      // Drop the top padding so a nested scrollable inside the item does not
      // inherit the scaffold's padding again through the overlay (SDK parity).
      data: MediaQuery.of(context).removePadding(removeTop: true),
      child: ListenableBuilder(
        listenable: repaint,
        // Built once per entry build; the geometry-only rebuilds below reuse it.
        child: IgnorePointer(child: contentBuilder(context)),
        builder: (context, child) {
          final overlayBox = overlay.context.findRenderObject()! as RenderBox;
          final origin = overlayBox.localToGlobal(Offset.zero);
          final global = globalTopLeft() ?? _lastTopLeft;
          _lastTopLeft = global;
          final local = global - origin;
          final scale = liftScale();
          return Positioned(
            left: local.dx,
            top: local.dy,
            child: SizedBox.fromSize(
              size: size(),
              child: Transform.scale(
                scale: scale,
                alignment: Alignment.center,
                child: child,
              ),
            ),
          );
        },
      ),
    ),
  );
}
