import 'package:flutter/widgets.dart';

/// Disposes [controllers] only after this widget leaves the tree.
///
/// A dialog route is still building its fields when [showDialog] completes,
/// because the exit animation has not finished. Disposing the controllers at
/// that moment makes the fields listen to a dead controller and crashes with
/// `_dependents.isEmpty`. Put this widget at the root of the dialog instead.
class DisposeControllers extends StatefulWidget {
  const DisposeControllers({
    super.key,
    required this.controllers,
    required this.child,
  });

  final List<TextEditingController> controllers;
  final Widget child;

  @override
  State<DisposeControllers> createState() => _DisposeControllersState();
}

class _DisposeControllersState extends State<DisposeControllers> {
  @override
  void dispose() {
    for (final controller in widget.controllers) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
