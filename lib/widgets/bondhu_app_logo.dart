import 'package:flutter/material.dart';

/// Official Bondhu logo: gradient tile/circle with leaf icon.
class BondhuAppLogo extends StatelessWidget {
  const BondhuAppLogo({
    super.key,
    required this.size,
    this.iconScale = 0.48,
    this.circular = false,
    this.showGlow = true,
  });

  final double size;
  final double iconScale;
  final bool circular;
  final bool showGlow;

  @override
  Widget build(BuildContext context) {
    final radius = circular ? size / 2 : size * 0.285;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF00C896),
            Color(0xFF14B8A6),
          ],
        ),
        borderRadius: circular ? null : BorderRadius.circular(radius),
        shape: circular ? BoxShape.circle : BoxShape.rectangle,
        boxShadow: showGlow
            ? [
                BoxShadow(
                  color: const Color(0xFF00C896).withValues(alpha: 0.35),
                  blurRadius: size * 0.30,
                  offset: const Offset(0, 3),
                ),
              ]
            : null,
      ),
      child: Icon(
        Icons.eco_rounded,
        color: Colors.white,
        size: size * iconScale,
      ),
    );
  }
}
