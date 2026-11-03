import 'package:flutter/material.dart';

/// Matches operator portal and login wide layout.
const kManagerWideBreakpoint = 900.0;

bool managerWideLayout(BuildContext context) =>
    MediaQuery.sizeOf(context).width >= kManagerWideBreakpoint;

EdgeInsets managerPagePadding(BuildContext context) {
  final width = MediaQuery.sizeOf(context).width;
  if (width >= kManagerWideBreakpoint) {
    return const EdgeInsets.all(24);
  }
  if (width >= 600) {
    return const EdgeInsets.all(16);
  }
  return const EdgeInsets.symmetric(horizontal: 12, vertical: 16);
}

double managerDialogWidth(BuildContext context, {double preferred = 440}) {
  final max = MediaQuery.sizeOf(context).width - 48;
  if (max <= 0) {
    return preferred;
  }
  return preferred.clamp(280.0, max);
}
