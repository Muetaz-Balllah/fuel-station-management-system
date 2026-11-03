import 'package:flutter/material.dart';

/// Wraps a fixed-width row/table layout so it scrolls horizontally on narrow viewports.
class HorizontalDataTable extends StatelessWidget {
  const HorizontalDataTable({
    super.key,
    required this.minWidth,
    required this.child,
  });

  final double minWidth;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final table = SizedBox(width: minWidth, child: child);
        if (constraints.maxWidth >= minWidth) {
          return table;
        }
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          clipBehavior: Clip.hardEdge,
          child: table,
        );
      },
    );
  }
}
