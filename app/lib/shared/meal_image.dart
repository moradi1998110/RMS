import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../core/theme.dart';

/// A meal photo kept on the phone after its first download, so reopening the app
/// does not fetch it again, and decoded at the width it is shown, not its full size.
class MealImage extends StatelessWidget {
  const MealImage({super.key, required this.url});

  final String url;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth.isFinite ? constraints.maxWidth : MediaQuery.sizeOf(context).width;
        return CachedNetworkImage(
          imageUrl: url,
          fit: BoxFit.cover,
          width: double.infinity,
          memCacheWidth: (width * MediaQuery.devicePixelRatioOf(context)).round(),
          fadeInDuration: const Duration(milliseconds: 150),
          placeholder: (_, __) => const ColoredBox(color: AppColors.imagePlaceholder),
          errorWidget: (_, __, ___) => const ColoredBox(color: AppColors.imagePlaceholder),
        );
      },
    );
  }
}
