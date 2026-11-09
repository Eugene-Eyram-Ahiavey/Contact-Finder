import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qara/theme/app_theme.dart';

/// WelcomeCallCenterView
///
/// Implements the high-fidelity Welcome / Onboarding Empty State according
/// to the Qara Figma design specification.
///
/// Engineering Highlights:
/// - Decoupled, modular component architecture.
/// - Fluid responsiveness with [SingleChildScrollView] and [ConstrainedBox]
///   preventing RenderFlex overflows across all device screen sizes & Dynamic Type.
/// - Accessible tap targets (44x44pt+) and [Semantics] screen-reader tags.
/// - High-performance 60/120fps entrance animations with strict lifecycle disposal.
class WelcomeCallCenterView extends StatefulWidget {
  final VoidCallback onCreateCenterPressed;
  final VoidCallback onSyncPressed;
  final bool isSyncing;

  const WelcomeCallCenterView({
    super.key,
    required this.onCreateCenterPressed,
    required this.onSyncPressed,
    this.isSyncing = false,
  });

  @override
  State<WelcomeCallCenterView> createState() => _WelcomeCallCenterViewState();
}

class _WelcomeCallCenterViewState extends State<WelcomeCallCenterView>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animController;
  late final Animation<double> _fadeAnimation;
  late final Animation<Offset> _slideAnimation;
  bool _isButtonHovered = false;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 650),
    );

    _fadeAnimation = CurvedAnimation(
      parent: _animController,
      curve: Curves.easeOutCubic,
    );

    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.08),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _animController,
      curve: Curves.easeOutCubic,
    ));

    _animController.forward();
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: AppColors.welcomeGradient,
      ),
      child: SafeArea(
        child: Column(
          children: [
            // Top Navigation Bar (Badge & Sync)
            _buildTopBar(context),

            // Scrollable & Responsive Center Content
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  return SingleChildScrollView(
                    physics: const BouncingScrollPhysics(),
                    child: Center(
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          minHeight: constraints.maxHeight,
                          maxWidth: 500,
                        ),
                        child: IntrinsicHeight(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 24),
                          child: FadeTransition(
                            opacity: _fadeAnimation,
                            child: SlideTransition(
                              position: _slideAnimation,
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  const Spacer(flex: 3),

                                  // Central Hero Lime "Q"
                                  _buildHeroBrandmark(),

                                  const SizedBox(height: 28),

                                  // Headline
                                  const Text(
                                    'Welcome to Qara',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      color: AppColors.textPrimary,
                                      fontSize: 25,
                                      fontWeight: FontWeight.w600,
                                      letterSpacing: -0.4,
                                    ),
                                  ),

                                  const SizedBox(height: 12),

                                  // Universal Onboarding Copy
                                  ConstrainedBox(
                                    constraints: const BoxConstraints(maxWidth: 320),
                                    child: const Text(
                                      'Start by creating your first Call Center. Contacts are organized into dedicated campaigns or project centers (like Gems or Projects) so you can paste, import, and follow up with clarity.',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        color: AppColors.textSecondary,
                                        fontSize: 13.5,
                                        height: 1.48,
                                        fontWeight: FontWeight.w400,
                                      ),
                                    ),
                                  ),

                                  const SizedBox(height: 38),

                                  // Primary Call to Action Button
                                  _buildCreateCenterButton(),

                                  const Spacer(flex: 4),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTopBar(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // App Squircle Icon Badge
          Semantics(
            label: 'Qara App Icon',
            child: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: AppColors.brandDarkTeal,
                borderRadius: BorderRadius.circular(13),
                boxShadow: AppShadows.badgeSquircle,
              ),
              child: Center(
                child: Image.asset(
                  'assets/images/q_brandmark.png',
                  width: 24,
                  height: 26,
                  fit: BoxFit.contain,
                ),
              ),
            ),
          ),

          // Refresh / Sync Caller ID Button
          Semantics(
            button: true,
            label: 'Refresh and Synchronize Caller ID Directory',
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () {
                  HapticFeedback.lightImpact();
                  widget.onSyncPressed();
                },
                borderRadius: BorderRadius.circular(22),
                child: Container(
                  width: 44,
                  height: 44,
                  alignment: Alignment.center,
                  child: widget.isSyncing
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.2,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              AppColors.brandDarkTeal,
                            ),
                          ),
                        )
                      : const Icon(
                          Icons.sync_rounded,
                          size: 24,
                          color: AppColors.brandDarkTeal,
                        ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeroBrandmark() {
    return Semantics(
      label: 'Qara Brandmark',
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Ambient lime glow aura
          Container(
            width: 68,
            height: 68,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: AppColors.brandLime.withOpacity(0.24),
                  blurRadius: 30,
                  spreadRadius: 6,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
          ),
          // Foreground sharp brandmark
          Image.asset(
            'assets/images/q_brandmark.png',
            width: 66,
            height: 74,
            fit: BoxFit.contain,
          ),
        ],
      ),
    );
  }

  Widget _buildCreateCenterButton() {
    return Semantics(
      button: true,
      label: 'Create A Call Center',
      child: AnimatedScale(
        scale: _isButtonHovered ? 0.97 : 1.0,
        duration: const Duration(milliseconds: 120),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(30),
            boxShadow: AppShadows.buttonFloating,
          ),
          child: Material(
            color: AppColors.brandDarkTeal,
            borderRadius: BorderRadius.circular(30),
            child: InkWell(
              onTap: () {
                HapticFeedback.mediumImpact();
                widget.onCreateCenterPressed();
              },
              onHighlightChanged: (isPressed) {
                setState(() => _isButtonHovered = isPressed);
              },
              borderRadius: BorderRadius.circular(30),
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.add,
                        size: 19,
                        color: Colors.white,
                      ),
                      SizedBox(width: 8),
                      Text(
                        'Create A Call Center',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 14.5,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.2,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
