import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Breakpoint & helper responsif (hanya UI).
class Responsive {
  static const double tabletMin = 600;   // >= 600  : tablet
  static const double desktopMin = 1024; // >= 1024 : tablet landscape besar / desktop / web

  static double _w(BuildContext c) => MediaQuery.sizeOf(c).width;

  static bool isPhone(BuildContext c) => _w(c) < tabletMin;
  static bool isTablet(BuildContext c) => _w(c) >= tabletMin && _w(c) < desktopMin;
  static bool isTabletUp(BuildContext c) => _w(c) >= tabletMin;
  static bool isDesktop(BuildContext c) => _w(c) >= desktopMin;

  /// Pilih nilai sesuai ukuran layar.
  static T pick<T>(BuildContext c, {required T phone, T? tablet, T? desktop}) {
    final w = _w(c);
    if (w >= desktopMin) return desktop ?? tablet ?? phone;
    if (w >= tabletMin) return tablet ?? phone;
    return phone;
  }

  /// Padding horizontal agar konten terpusat dengan lebar maksimum [maxContent].
  static double sidePadding(double availableWidth,
      {double maxContent = 900, double min = 16}) {
    return math.max(min, (availableWidth - maxContent) / 2);
  }
}

/// Membatasi lebar konten & memusatkannya (agar tidak terlalu melebar di tablet/desktop).
class MaxWidthBox extends StatelessWidget {
  final double maxWidth;
  final EdgeInsetsGeometry? padding;
  final Widget child;

  const MaxWidthBox({
    super.key,
    this.maxWidth = 1200,
    this.padding,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    Widget content = ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: child,
    );
    if (padding != null) {
      content = Padding(padding: padding!, child: content);
    }
    return Align(
      alignment: Alignment.topCenter,
      child: content,
    );
  }
}