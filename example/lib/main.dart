import 'dart:ui' as ui;

import 'package:fluid_list/fluid_list.dart';
import 'package:flutter/material.dart';

void main() => runApp(const ExampleApp());

class ExampleApp extends StatelessWidget {
  const ExampleApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'fluid_list',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(colorSchemeSeed: const Color(0xFF6C5CE7), brightness: Brightness.light, useMaterial3: true),
    home: const TaskListPage(),
  );
}

/// A task with a stable id and a hue used to tint its card.
class Task {
  const Task({required this.id, required this.title, required this.hue});

  final int id;
  final String title;
  final double hue;
}

class TaskListPage extends StatefulWidget {
  const TaskListPage({super.key});

  @override
  State<TaskListPage> createState() => _TaskListPageState();
}

class _TaskListPageState extends State<TaskListPage> {
  static const _titles = [
    'Design the spring curves',
    'Measure every item exactly',
    'Ghost the departures',
    'Pin the dragged card',
    'Resolve the drop slot',
    'Autoscroll near the edges',
    'Fade the arrivals in',
    'Ship the example',
  ];

  int _nextId = 0;
  late List<Task> _tasks = [for (var i = 0; i < 4; i++) _makeTask(_titles[i])];
  List<String> _tags = ['physics', 'reorder', 'implicit'];

  bool _handleMode = false;
  bool _bigList = false;
  int _transitionIndex = 6;

  /// A menu of enter/exit transitions for the task list, showing how a
  /// `transitionBuilder` lets you animate items with your own widgets. A null
  /// builder falls back to the built-in `FluidListStyle` effect.
  static final List<({String label, FluidListTransitionBuilder? builder})> _transitions = [
    (label: 'Default (built-in)', builder: null),
    (label: 'Fade', builder: (context, a, child) => FadeTransition(opacity: a, child: child)),
    (
      label: 'Fade + scale',
      builder: (context, a, child) => FadeTransition(
        opacity: a,
        child: ScaleTransition(scale: a, child: child),
      ),
    ),
    (
      label: 'Slide in',
      builder: (context, a, child) => FadeTransition(
        opacity: a,
        child: SlideTransition(
          position: Tween(begin: const Offset(0.25, 0), end: Offset.zero).animate(a),
          child: child,
        ),
      ),
    ),
    (
      label: 'Slide up',
      builder: (context, a, child) => FadeTransition(
        opacity: a,
        child: SlideTransition(
          position: Tween(begin: const Offset(0, 0.4), end: Offset.zero).animate(a),
          child: child,
        ),
      ),
    ),
    (
      label: 'Rotate',
      builder: (context, a, child) => FadeTransition(
        opacity: a,
        child: RotationTransition(
          turns: Tween(begin: -0.06, end: 0.0).animate(a),
          child: ScaleTransition(scale: a, child: child),
        ),
      ),
    ),
    (label: 'Blur + fade + scale', builder: _blurFadeScale),
  ];

  /// Blur + fade + scale: the item resolves out of a blur as it settles.
  /// Blur needs a fresh `ImageFilter` each frame, so it rebuilds under an
  /// `AnimatedBuilder` rather than a layer-based transition widget.
  static Widget _blurFadeScale(BuildContext context, Animation<double> animation, Widget child) => AnimatedBuilder(
    animation: animation,
    child: child,
    builder: (context, child) {
      final t = animation.value.clamp(0.0, 1.0);
      final sigma = (1 - t) * 24;
      final scaled = Transform.scale(scale: 0.9 + 0.1 * t, child: child);
      return Opacity(
        opacity: t,
        child: sigma < 0.05
            ? scaled
            : ImageFiltered(
                imageFilter: ui.ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
                child: scaled,
              ),
      );
    },
  );

  Task _makeTask(String title) {
    final id = _nextId++;
    return Task(id: id, title: title, hue: (id * 57) % 360);
  }

  void _addTask() {
    final title = _titles[_nextId % _titles.length];
    setState(() => _tasks = [_makeTask(title), ..._tasks]);
  }

  void _removeTask(Task task) {
    setState(() => _tasks = _tasks.where((t) => t.id != task.id).toList());
  }

  void _shuffle() {
    setState(() => _tasks = _tasks.reversed.toList());
  }

  void _toggleBigList() {
    setState(() {
      _bigList = !_bigList;
      _tasks = _bigList ? [for (var i = 0; i < 1000; i++) _makeTask(_titles[i % _titles.length])] : [for (var i = 0; i < 4; i++) _makeTask(_titles[i])];
    });
  }

  void _addTag() {
    const pool = ['spring', 'masonry', 'ticker', 'render', 'diff', 'lift'];
    final tag = pool[_tags.length % pool.length];
    setState(() => _tags = [..._tags, '$tag${_tags.length}']);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      // One CustomScrollView: a SliverAppBar, the tag strip, then the lazy
      // SliverFluidList of tasks — all sharing a single scroll position.
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            floating: true,
            backgroundColor: theme.colorScheme.surface,
            surfaceTintColor: Colors.transparent,
            title: const Text('fluid_list', style: TextStyle(fontWeight: FontWeight.bold)),
            actions: [
              IconButton(tooltip: _bigList ? '1000 items' : '4 items', onPressed: _toggleBigList, icon: Icon(_bigList ? Icons.filter_1 : Icons.filter_9_plus)),
              IconButton(
                tooltip: _handleMode ? 'Drag: handle' : 'Drag: whole item',
                onPressed: () => setState(() => _handleMode = !_handleMode),
                icon: Icon(_handleMode ? Icons.drag_indicator : Icons.pan_tool_alt_outlined),
              ),
              PopupMenuButton<int>(
                tooltip: 'Transition: ${_transitions[_transitionIndex].label}',
                icon: const Icon(Icons.animation),
                initialValue: _transitionIndex,
                onSelected: (i) => setState(() => _transitionIndex = i),
                itemBuilder: (context) => [for (var i = 0; i < _transitions.length; i++) PopupMenuItem(value: i, child: Text(_transitions[i].label))],
              ),
              IconButton(tooltip: 'Shuffle', onPressed: _shuffle, icon: const Icon(Icons.shuffle)),
              IconButton(tooltip: 'Add task', onPressed: _addTask, icon: const Icon(Icons.add)),
            ],
          ),
          SliverToBoxAdapter(child: _sectionLabel(context, 'Tags · horizontal FluidList')),
          SliverToBoxAdapter(
            child: SizedBox(
              height: 52,
              // A horizontal FluidList is its own scrollable, so it drops
              // straight into a box adapter.
              child: FluidList<String>(
                items: _tags,
                scrollDirection: Axis.horizontal,
                spacing: 8,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                idOf: (tag) => tag,
                reorder: FluidListReorder.enabled(onReorderFinished: (result) => setState(() => _tags = result.items)),
                // Custom enter/exit motion by widget: chips fade and slide in.
                transitionBuilder: (context, animation, child) => FadeTransition(
                  opacity: animation,
                  child: SlideTransition(
                    position: Tween(begin: const Offset(0.35, 0), end: Offset.zero).animate(animation),
                    child: child,
                  ),
                ),
                itemBuilder: (context, tag) => _TagChip(tag: tag, onDelete: () => setState(() => _tags = _tags.where((t) => t != tag).toList())),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
              child: Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(onPressed: _addTag, icon: const Icon(Icons.add, size: 18), label: const Text('Add tag')),
              ),
            ),
          ),
          SliverToBoxAdapter(child: _sectionLabel(context, 'Tasks · transition: ${_transitions[_transitionIndex].label}')),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
            sliver: SliverFluidList<Task>(
              items: _tasks,
              spacing: 10,
              idOf: (task) => task.id,
              reorder: FluidListReorder.enabled(dragMode: _handleMode ? FluidListDragMode.handle : FluidListDragMode.item, onReorderFinished: (result) => setState(() => _tasks = result.items)),
              liftedBuilder: (context, task, animation, child) => _lifted(animation, child),
              // Pick the enter/exit transition from the app-bar menu.
              transitionBuilder: _transitions[_transitionIndex].builder,
              itemBuilder: (context, task) => _TaskCard(task: task, handleMode: _handleMode, onDelete: () => _removeTask(task)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionLabel(BuildContext context, String text) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
    child: Text(
      text.toUpperCase(),
      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.8, color: Theme.of(context).colorScheme.outline),
    ),
  );

  // The shadow grows and fades in with the lift, then eases back out as the
  // card settles — driven by the `lift` animation the list hands the builder.
  // The drop shadow grows and fades in with the lift, then eases back out as
  // the card settles — every channel is driven by the `lift` animation the list
  // hands the builder. Two layers (a soft ambient cast + a tighter contact
  // shadow) read as the card rising off the surface.
  Widget _lifted(Animation<double> animation, Widget child) => AnimatedBuilder(
    animation: animation,
    child: child,
    builder: (context, child) {
      final t = animation.value.clamp(0.0, 1.0);
      return DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.16 * t),
              blurRadius: 36 * t,
              spreadRadius: 2 * t,
              offset: Offset(0, 18 * t),
            ),
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.20 * t),
              blurRadius: 8 * t,
              offset: Offset(0, 4 * t),
            ),
          ],
        ),
        child: child,
      );
    },
  );
}

class _TaskCard extends StatelessWidget {
  const _TaskCard({required this.task, required this.handleMode, required this.onDelete});

  final Task task;
  final bool handleMode;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final color = HSLColor.fromAHSL(1, task.hue, 0.55, 0.62).toColor();
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: LinearGradient(colors: [color, HSLColor.fromAHSL(1, (task.hue + 24) % 360, 0.55, 0.55).toColor()]),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.25), borderRadius: BorderRadius.circular(10)),
            child: Text(
              '#${task.id}',
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              task.title,
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 15),
            ),
          ),
          IconButton(
            onPressed: onDelete,
            icon: Icon(Icons.close, color: Colors.white.withValues(alpha: 0.9)),
            visualDensity: VisualDensity.compact,
          ),
          // In handle mode only this grip starts the drag; the rest of the card
          // stays free for taps and the delete button.
          if (handleMode)
            FluidListDragHandle(
              child: Padding(
                padding: const EdgeInsets.only(left: 4),
                child: Icon(Icons.drag_indicator, color: Colors.white.withValues(alpha: 0.9)),
              ),
            ),
        ],
      ),
    );
  }
}

class _TagChip extends StatelessWidget {
  const _TagChip({required this.tag, required this.onDelete});

  final String tag;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.only(left: 14, right: 6),
      decoration: BoxDecoration(color: scheme.primaryContainer, borderRadius: BorderRadius.circular(999)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            tag,
            style: TextStyle(color: scheme.onPrimaryContainer, fontWeight: FontWeight.w600),
          ),
          IconButton(
            onPressed: onDelete,
            iconSize: 16,
            visualDensity: VisualDensity.compact,
            icon: Icon(Icons.close, color: scheme.onPrimaryContainer),
          ),
        ],
      ),
    );
  }
}
