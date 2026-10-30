import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import 'theme.dart';

/// A plane model's side-view picture from the plane gallery, facing right.
/// The art is 2:1 (260 x 130); give it a [height] and it takes twice that
/// in width. A model with no picture yet shows a plain plane icon.
class PlaneArt extends StatelessWidget {
  const PlaneArt(this.modelId, {this.height = 48, super.key});

  final String modelId;
  final double height;

  static const aspectRatio = 2.0;

  /// The asset for [modelId]'s picture: `assets/planes/<model id>.svg`.
  static String assetFor(String modelId) => 'assets/planes/$modelId.svg';

  @override
  Widget build(BuildContext context) => SizedBox(
    width: height * aspectRatio,
    height: height,
    child: SvgPicture.asset(
      assetFor(modelId),
      fit: BoxFit.contain,
      excludeFromSemantics: true,
      errorBuilder: (context, error, stack) =>
          Icon(Icons.flight, color: Board.amber, size: height * 0.6),
    ),
  );
}
