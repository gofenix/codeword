import 'package:flutter/material.dart';
import '../theme.dart';
import '../tokens.dart';

/// A friendly empty-state placeholder: muted icon + message + optional CTA.
///
/// The entire column is wrapped with merged semantics so screen readers
/// announce the state as a single unit instead of reading the icon,
/// message, and CTA as disconnected nodes.
class EmptyHint extends StatelessWidget {
  final IconData icon;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  const EmptyHint({
    super.key,
    required this.icon,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    final showAction = actionLabel != null && onAction != null;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.x5),
      child: MergeSemantics(
        child: Semantics(
          label: message,
          hint: showAction ? actionLabel : null,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 40, color: AppColors.inkSubtle),
              const SizedBox(height: AppSpacing.x3),
              Text(
                message,
                style: AppTheme.mutedCaption(size: 14).copyWith(height: 1.4),
                textAlign: TextAlign.center,
              ),
              if (showAction) ...[
                const SizedBox(height: AppSpacing.x3),
                TextButton(
                  onPressed: onAction,
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.primary,
                    textStyle: AppTheme.rowTitle().copyWith(fontSize: 13),
                  ),
                  child: Text(actionLabel!),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
