import 'package:flutter/material.dart';

import '../tokens.dart';
import 'pressable_scale.dart';

/// A restrained bronze command surface with subtle depth and press feedback.
class EditorialPrimaryButton extends StatelessWidget {
  final VoidCallback? onPressed;
  final Widget label;
  final Widget? icon;
  final double minHeight;

  const EditorialPrimaryButton({
    super.key,
    required this.onPressed,
    required this.label,
    this.icon,
    this.minHeight = 50,
  });

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    final palette = AppColors.of(context);
    final foreground = enabled ? AppColors.onPrimary : palette.inkSubtle;

    return Semantics(
      button: true,
      enabled: enabled,
      child: PressableScale(
        onTap: onPressed,
        scaleFactor: 0.985,
        pressedOpacity: 0.92,
        child: AnimatedContainer(
          duration: AppMotion.fast,
          constraints: BoxConstraints(minHeight: minHeight),
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.x6,
            vertical: AppSpacing.x3,
          ),
          decoration: BoxDecoration(
            color: enabled ? null : palette.surfaceMuted,
            gradient: enabled ? AppMaterials.bronze : null,
            borderRadius: BorderRadius.circular(AppRadii.md),
            border: Border.all(
              color: enabled ? const Color(0x70E8DBC4) : palette.divider,
              width: AppBorders.hairline,
            ),
            boxShadow: enabled ? AppShadows.bronze : null,
          ),
          child: DefaultTextStyle.merge(
            style: TextStyle(
              color: foreground,
              fontSize: 16,
              fontWeight: FontWeight.w600,
              // Slight negative tracking tightens the w600 label so it
              // reads as deliberate rather than default-spaced.
              letterSpacing: -0.16,
            ),
            child: IconTheme(
              data: IconThemeData(color: foreground, size: 19),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (icon != null) ...[
                    icon!,
                    const SizedBox(width: AppSpacing.x2),
                  ],
                  Flexible(child: label),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
