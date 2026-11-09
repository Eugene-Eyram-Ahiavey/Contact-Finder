import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qara/database/app_database.dart';
import 'package:qara/screens/call_centers_screen.dart';

/// LandingSplashScreen
///
/// Elegant, brand-centric splash / landing screen based on the Figma design.
///
/// Features:
/// 1. Deep moody teal ambient gradient with subtle glowing aura.
/// 2. Signature "Qara" logo with neon chartreuse "Q" and ivory typography.
/// 3. Synchronized micro-animation (scale + fade-in + subtle breathing glow).
/// 4. Background database pre-warming while the 1.4s animation plays.
/// 5. Smooth cross-fade route transition into the main CallCentersScreen.
class LandingSplashScreen extends StatefulWidget {
  final AppDatabase database;

  const LandingSplashScreen({super.key, required this.database});

  @override
  State<LandingSplashScreen> createState() => _LandingSplashScreenState();
}

class _LandingSplashScreenState extends State<LandingSplashScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _fadeAnimation;
  late Animation<double> _scaleAnimation;
  late Animation<double> _glowAnimation;

  @override
  void initState() {
    super.initState();

    // Configure system status bar for dark moody background
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.dark,
      ),
    );

    // Initialize animation controller: 1400ms total duration
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );

    // Fade-in animation: 0.0 -> 1.0 in the first 500ms
    _fadeAnimation = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.0, 0.45, curve: Curves.easeOut),
    );

    // Subtle scale animation: 0.88 -> 1.0 with an organic spring curve
    _scaleAnimation = Tween<double>(begin: 0.88, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.1, 0.7, curve: Curves.easeOutBack),
      ),
    );

    // Soft glow pulse
    _glowAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.3, 0.85, curve: Curves.easeInOut),
      ),
    );

    _controller.forward();

    // Start background data warming and navigate when animation completes
    _warmupAndNavigate();
  }

  Future<void> _warmupAndNavigate() async {
    final startTime = DateTime.now();

    // Pre-warm database in parallel
    try {
      await widget.database.getAllCallCenters();
    } catch (_) {
      // Continue even if database is empty on first launch
    }

    // Ensure the animation has at least 1400ms to play smoothly
    final elapsed = DateTime.now().difference(startTime).inMilliseconds;
    final remaining = 1400 - elapsed;
    if (remaining > 0) {
      await Future.delayed(Duration(milliseconds: remaining));
    }

    if (!mounted) return;

    // Smooth cinematic cross-fade into CallCentersScreen
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 400),
        pageBuilder: (context, animation, secondaryAnimation) =>
            CallCentersScreen(database: widget.database),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(opacity: animation, child: child);
        },
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF071E22),
      body: Stack(
        fit: StackFit.expand,
        children: [
          // 1. Procedural Ambient Mesh Gradient (guarantees coverage on all screen aspect ratios)
          Container(
            decoration: const BoxDecoration(
              gradient: RadialGradient(
                center: Alignment(-0.8, -0.7),
                radius: 1.2,
                colors: [
                  Color(0xFF26736A), // Teal highlight glow (top-left)
                  Color(0xFF0F3B3E), // Mid deep teal
                  Color(0xFF061A1D), // Dark base
                ],
                stops: [0.0, 0.55, 1.0],
              ),
            ),
          ),

          // Secondary bottom-right emerald glow
          Positioned(
            right: -60,
            bottom: -60,
            width: 320,
            height: 320,
            child: Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    const Color(0xFF0F7C73).withOpacity(0.55),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),

          // 2. High-fidelity clean background asset from Figma
          Image.asset(
            'assets/images/landing_bg_clean.png',
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => const SizedBox.shrink(),
          ),

          // 3. Centered Brand Logo with coordinated scale & glow animation
          Center(
            child: AnimatedBuilder(
              animation: _controller,
              builder: (context, child) {
                return Opacity(
                  opacity: _fadeAnimation.value,
                  child: Transform.scale(
                    scale: _scaleAnimation.value,
                    child: child,
                  ),
                );
              },
              child: Stack(
                alignment: Alignment.center,
                children: [
                  // Subtle ambient aura behind the logo
                  AnimatedBuilder(
                    animation: _glowAnimation,
                    builder: (context, _) {
                      return Container(
                        width: 180,
                        height: 70,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(40),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFF9EE83C).withOpacity(
                                0.18 * _glowAnimation.value,
                              ),
                              blurRadius: 36,
                              spreadRadius: 4,
                            ),
                            BoxShadow(
                              color: const Color(0xFF14B8A6).withOpacity(
                                0.15 * _glowAnimation.value,
                              ),
                              blurRadius: 48,
                              spreadRadius: 8,
                            ),
                          ],
                        ),
                      );
                    },
                  ),

                  // The exact high-resolution logo from Figma
                  Image.asset(
                    'assets/images/qara_logo.png',
                    width: 175,
                    fit: BoxFit.contain,
                    errorBuilder: (_, __, ___) {
                      // High-fidelity fallback rendering using rich typography
                      return Row(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.baseline,
                        textBaseline: TextBaseline.alphabetic,
                        children: [
                          Text(
                            'Q',
                            style: TextStyle(
                              fontSize: 56,
                              fontWeight: FontWeight.w700,
                              color: const Color(0xFF9EE83C),
                              letterSpacing: -1.0,
                              shadows: [
                                Shadow(
                                  color: Colors.black.withOpacity(0.5),
                                  blurRadius: 16,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                          ),
                          Text(
                            'ara',
                            style: TextStyle(
                              fontSize: 44,
                              fontWeight: FontWeight.w500,
                              color: const Color(0xFFF2F5ED),
                              letterSpacing: -0.5,
                              shadows: [
                                Shadow(
                                  color: Colors.black.withOpacity(0.5),
                                  blurRadius: 16,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

