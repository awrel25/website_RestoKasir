import 'package:flutter/material.dart';

Widget buildLocalFileImage(
  String path, {
  required BoxFit fit,
  required Widget Function() fallback,
}) {
  return fallback();
}

