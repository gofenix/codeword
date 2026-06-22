import 'package:flutter/material.dart';

/// Phone-shaped frame for desktop windows.
///
/// On macOS the app opens in a 1280×800 window, but the UX is designed
/// for a mobile device. This widget constrains its child to a phone-
/// shaped column (max-width [maxWidth], default 480) and centers it,
/// so the rest of the window reads as "bezel" rather than empty space.
class MobileFrame extends StatelessWidget {
  final Widget child;
  final double maxWidth;
  final Color background;

  const MobileFrame({
    super.key,
    required this.child,
    this.maxWidth = 480,
    this.background = const Color(0xFFEDEAE0),
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: background,
      alignment: Alignment.topCenter,
      child: SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth),
          child: child,
        ),
      ),
    );
  }
}
