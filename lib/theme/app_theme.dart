import 'package:flutter/material.dart';

/// AppColors & Design Tokens
///
/// Centralized styling constants reflecting the modern Qara design system.
/// Designed for high visual fidelity, multi-church adaptability, and accessibility.
class AppColors {
  // Brand Obsidian Teal & Lime
  static const Color brandDarkTeal = Color(0xFF0C242E);
  static const Color brandDarkTealElevated = Color(0xFF14343F);
  static const Color brandLime = Color(0xFF9EE83C);
  static const Color brandLimeAccent = Color(0xFFB5F63E);

  // Background Wash & Ambient Canvas (Ice-Mint)
  static const Color mintBackgroundTop = Color(0xFFDCF8F5);
  static const Color mintBackgroundCenter = Color(0xFFF8FCFA);
  static const Color mintBackgroundBottom = Color(0xFFDEF7F3);

  // High-Contrast & Accessible Typography
  static const Color textPrimary = Color(0xFF102024);
  static const Color textSecondary = Color(0xFF55696E);
  static const Color textMuted = Color(0xFF85989E);

  // Surface & Accents
  static const Color cardBackground = Colors.white;
  static const Color divider = Color(0xFFE5EDED);
  static const Color surfaceBorder = Color(0xFFD6E8E6);

  // Welcome Ambient Mesh Gradient
  static const LinearGradient welcomeGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [
      mintBackgroundTop,
      mintBackgroundCenter,
      mintBackgroundBottom,
    ],
    stops: [0.0, 0.48, 1.0],
  );
}

/// AppShadows
///
/// Tactile elevation profiles conforming to iOS HIG and Material 3 guidelines.
class AppShadows {
  static List<BoxShadow> get buttonFloating => [
        BoxShadow(
          color: AppColors.brandDarkTeal.withOpacity(0.28),
          blurRadius: 18,
          offset: const Offset(0, 8),
        ),
        BoxShadow(
          color: Colors.black.withOpacity(0.06),
          blurRadius: 4,
          offset: const Offset(0, 2),
        ),
      ];

  static List<BoxShadow> get badgeSquircle => [
        BoxShadow(
          color: Colors.black.withOpacity(0.18),
          blurRadius: 10,
          offset: const Offset(0, 4),
        ),
      ];

  static List<BoxShadow> get heroLogoAura => [
        BoxShadow(
          color: AppColors.brandLime.withOpacity(0.18),
          blurRadius: 28,
          spreadRadius: 4,
          offset: const Offset(0, 10),
        ),
        BoxShadow(
          color: Colors.black.withOpacity(0.14),
          blurRadius: 16,
          offset: const Offset(0, 8),
        ),
      ];
}

