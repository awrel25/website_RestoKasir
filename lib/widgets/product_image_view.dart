import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:my_app/core/theme/theme_controller.dart';
import 'package:my_app/widgets/local_file_image_stub.dart'
    if (dart.library.io) 'package:my_app/widgets/local_file_image_io.dart';

class ProductImageView extends StatelessWidget {
  final String? imageUrl;
  final IconData fallbackIcon;
  final double iconSize;
  final BoxFit fit;
  final BorderRadius? borderRadius;

  const ProductImageView({
    super.key,
    required this.imageUrl,
    this.fallbackIcon = Icons.fastfood_rounded,
    this.iconSize = 32,
    this.fit = BoxFit.cover,
    this.borderRadius,
  });

  @override
  Widget build(BuildContext context) {
    Widget fallbackWidget() {
      return Center(
        child: Icon(
          fallbackIcon,
          size: iconSize,
          color: AppColors.primary,
        ),
      );
    }

    final rawUrl = imageUrl?.trim();
    if (rawUrl == null || rawUrl.isEmpty) {
      return fallbackWidget();
    }

    Widget content;

    // 1. Base64 Data URI
    if (rawUrl.startsWith('data:image')) {
      try {
        final commaIdx = rawUrl.indexOf(',');
        final base64Data =
            commaIdx != -1 ? rawUrl.substring(commaIdx + 1) : rawUrl;
        final bytes = base64Decode(base64Data);
        content = Image.memory(
          bytes,
          fit: fit,
          errorBuilder: (_, __, ___) => fallbackWidget(),
        );
      } catch (_) {
        content = fallbackWidget();
      }
    }
    // 2. HTTP / HTTPS Network URL
    else if (rawUrl.startsWith('http://') || rawUrl.startsWith('https://')) {
      content = Image.network(
        rawUrl,
        fit: fit,
        loadingBuilder: (context, child, loadingProgress) {
          if (loadingProgress == null) return child;
          return Center(
            child: SizedBox(
              width: iconSize * 0.7,
              height: iconSize * 0.7,
              child: const CircularProgressIndicator(strokeWidth: 2),
            ),
          );
        },
        errorBuilder: (_, __, ___) => fallbackWidget(),
      );
    }
    // 3. Local File Path (Mobile / Desktop)
    else if (!kIsWeb &&
        (rawUrl.startsWith('/') ||
            rawUrl.contains(':\\') ||
            rawUrl.contains(':/'))) {
      content = buildLocalFileImage(
        rawUrl,
        fit: fit,
        fallback: fallbackWidget,
      );
    }
    // 4. Default Fallback
    else {
      content = fallbackWidget();
    }

    if (borderRadius != null) {
      return ClipRRect(
        borderRadius: borderRadius!,
        child: content,
      );
    }

    return content;
  }
}
