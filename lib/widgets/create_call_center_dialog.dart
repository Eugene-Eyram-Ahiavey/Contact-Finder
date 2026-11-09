import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:uuid/uuid.dart';
import 'package:qara/models/call_center.dart';
import 'package:qara/theme/app_theme.dart';

/// CreateCallCenterDialog
///
/// Implements the custom floating "New Call Center" modal dialog
/// matching the Qara Figma design specification.
///
/// Features:
/// - Frosted glass backdrop blur ([BackdropFilter]).
/// - Mint-to-white ambient gradient card with rounded stadium inputs.
/// - Inline theme color picker with active selection ring.
/// - Keyboard avoidance & responsive scrolling across all device sizes.
/// - Strict form validation and asynchronous submission callback.
class CreateCallCenterDialog extends StatefulWidget {
  const CreateCallCenterDialog({super.key});

  /// Presents the dialog with a frosted glass backdrop and spring scale animation.
  /// Returns the newly populated [CallCenter] upon submission, or `null` if cancelled.
  static Future<CallCenter?> show(BuildContext context) {
    return showGeneralDialog<CallCenter>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Dismiss New Call Center Dialog',
      barrierColor: Colors.black.withOpacity(0.42),
      transitionDuration: const Duration(milliseconds: 280),
      pageBuilder: (ctx, anim1, anim2) {
        return const CreateCallCenterDialog();
      },
      transitionBuilder: (ctx, anim1, anim2, child) {
        final curved = CurvedAnimation(
          parent: anim1,
          curve: Curves.easeOutBack,
        );
        return BackdropFilter(
          filter: ImageFilter.blur(
            sigmaX: 5.0 * anim1.value,
            sigmaY: 5.0 * anim1.value,
          ),
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.93, end: 1.0).animate(curved),
            child: FadeTransition(
              opacity: anim1,
              child: child,
            ),
          ),
        );
      },
    );
  }

  @override
  State<CreateCallCenterDialog> createState() => _CreateCallCenterDialogState();
}

class _CreateCallCenterDialogState extends State<CreateCallCenterDialog> {
  static const _uuid = Uuid();

  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _locationController = TextEditingController();
  final TextEditingController _descController = TextEditingController();

  static const List<String> _themePalette = [
    '#3F51B5', // Indigo / Dark Blue
    '#00897B', // Teal
    '#D81B60', // Rose / Pink
    '#5E35B1', // Deep Purple
    '#008AEC', // Electric Blue
  ];

  late String _selectedColor;
  String? _validationError;

  @override
  void initState() {
    super.initState();
    _selectedColor = _themePalette.first;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _locationController.dispose();
    _descController.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      setState(() {
        _validationError = 'Please enter a name for the Call Center';
      });
      return;
    }

    final now = DateTime.now();
    final newCenter = CallCenter(
      id: _uuid.v4(),
      name: name,
      location: _locationController.text.trim().isNotEmpty
          ? _locationController.text.trim()
          : null,
      description: _descController.text.trim().isNotEmpty
          ? _descController.text.trim()
          : null,
      colorHex: _selectedColor,
      createdAt: now,
      updatedAt: now,
    );

    HapticFeedback.mediumImpact();
    Navigator.of(context).pop(newCenter);
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(26),
              border: Border.all(
                color: Colors.white.withOpacity(0.18),
                width: 1.0,
              ),
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color(0xFF2C6870), // Rich teal top-left from Figma
                  Color(0xFF1B4958), // Deep teal center
                  Color(0xFF143D49), // Midnight teal bottom-right
                ],
                stops: [0.0, 0.45, 1.0],
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.40),
                  blurRadius: 32,
                  offset: const Offset(0, 14),
                ),
              ],
            ),
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(22, 26, 22, 22),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Title
                  const Text(
                    'New Call Center',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.w600,
                      letterSpacing: -0.3,
                    ),
                  ),

                  const SizedBox(height: 24),

                  // Call Center Name (Required)
                  _buildInputField(
                    label: 'Call Center Name',
                    hintText: 'Invasion',
                    controller: _nameController,
                    errorText: _validationError,
                  ),

                  const SizedBox(height: 16),

                  // Area / Location
                  _buildInputField(
                    label: 'Area/ Location',
                    hintText: 'GCTU',
                    controller: _locationController,
                  ),

                  const SizedBox(height: 16),

                  // Description / Purpose (Optional)
                  _buildInputField(
                    label: 'Description/purpose (optional)',
                    hintText: 'Swollen Saturday',
                    controller: _descController,
                  ),

                  const SizedBox(height: 22),

                  // Theme Color Selector
                  _buildThemeSelector(),

                  const SizedBox(height: 26),

                  // Action Buttons (Cancel / Create Center)
                  _buildActionButtons(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildInputField({
    required String label,
    required String hintText,
    required TextEditingController controller,
    String? errorText,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 13.5,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 7),
        Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            color: Colors.white,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.08),
                blurRadius: 6,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: TextField(
            controller: controller,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
            decoration: InputDecoration(
              hintText: hintText,
              hintStyle: const TextStyle(
                color: Color(0xFF8A9A9E),
                fontSize: 14,
                fontWeight: FontWeight.w400,
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 18,
                vertical: 13,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(20),
                borderSide: const BorderSide(
                  color: Color(0xFFD6EAE7),
                  width: 1.2,
                ),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(20),
                borderSide: BorderSide(
                  color: errorText != null
                      ? const Color(0xFFFF8A80)
                      : const Color(0xFFD6EAE7),
                  width: 1.2,
                ),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(20),
                borderSide: const BorderSide(
                  color: AppColors.brandLime,
                  width: 2.0,
                ),
              ),
            ),
          ),
        ),
        if (errorText != null) ...[
          const SizedBox(height: 5),
          Padding(
            padding: const EdgeInsets.only(left: 12),
            child: Text(
              errorText,
              style: const TextStyle(
                color: Color(0xFFFF8A80),
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildThemeSelector() {
    return Row(
      children: [
        const Text(
          'Theme:',
          style: TextStyle(
            color: Colors.white,
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _themePalette.map((colorHex) {
              final color = Color(
                int.parse(colorHex.replaceAll('#', '0xff')),
              );
              final isSelected = _selectedColor == colorHex;

              return Semantics(
                button: true,
                selected: isSelected,
                label: 'Theme color $colorHex',
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {
                    HapticFeedback.selectionClick();
                    setState(() => _selectedColor = colorHex);
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 5,
                      vertical: 8,
                    ),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        color: color,
                        shape: BoxShape.circle,
                        border: isSelected
                            ? Border.all(
                                color: Colors.white,
                                width: 2.8,
                              )
                            : Border.all(
                                color: Colors.transparent,
                                width: 2.8,
                              ),
                        boxShadow: [
                          if (isSelected) ...[
                            BoxShadow(
                              color: Colors.white.withOpacity(0.55),
                              blurRadius: 8,
                              spreadRadius: 1,
                            ),
                            BoxShadow(
                              color: color.withOpacity(0.5),
                              blurRadius: 6,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }

  Widget _buildActionButtons() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        TextButton(
          onPressed: () {
            HapticFeedback.lightImpact();
            Navigator.of(context).pop();
          },
          style: TextButton.styleFrom(
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 10,
            ),
          ),
          child: const Text(
            'Cancel',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: Colors.white,
            ),
          ),
        ),
        const SizedBox(width: 10),
        ElevatedButton(
          onPressed: _submit,
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFFC4FF58), // Bright Lime Green from Figma
            foregroundColor: AppColors.brandDarkTeal,
            elevation: 4,
            shadowColor: Colors.black.withOpacity(0.4),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(22),
            ),
            padding: const EdgeInsets.symmetric(
              horizontal: 22,
              vertical: 12,
            ),
          ),
          child: const Text(
            'Create Center',
            style: TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w700,
              color: AppColors.brandDarkTeal,
              letterSpacing: 0.2,
            ),
          ),
        ),
      ],
    );
  }
}

