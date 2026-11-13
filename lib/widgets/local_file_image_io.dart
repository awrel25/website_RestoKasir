import 'dart:io';
import 'package:flutter/material.dart';

Widget buildLocalFileImage(
  String path, {
  required BoxFit fit,
  required Widget Function() fallback,
}) {
  try {
    return Image.file(
      File(path),
      fit: fit,
      errorBuilder: (_, __, ___) => fallback(),
    );
  } catch (_) {
    return fallback();
  }
}

