import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_radius.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';

class AppAccountCard extends StatelessWidget {
  final String username;
  final String? accountName;
  final String? accountEmail;
  final bool isConnected;
  final bool isSelf;
  final String? role;
  final Widget? trailing;
  final VoidCallback? onTap;

  const AppAccountCard({
    super.key,
    required this.username,
    this.accountName,
    this.accountEmail,
    this.isConnected = false,
    this.isSelf = false,
    this.role,
    this.trailing,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: AppRadius.card,
        border: Border.all(color: AppColors.borderSubtle),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: AppRadius.card,
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 20,
                  backgroundColor: isConnected ? AppColors.primary.withValues(alpha: 0.15) : AppColors.surfaceElevated,
                  child: Icon(
                    Icons.person,
                    color: isConnected ? AppColors.primary : AppColors.textMuted,
                    size: 20,
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              username,
                              style: AppTypography.body.copyWith(fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (isSelf) ...[
                            const SizedBox(width: AppSpacing.xs),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: AppColors.info.withValues(alpha: 0.2),
                                borderRadius: AppRadius.badge,
                              ),
                              child: Text(
                                'You',
                                style: AppTypography.caption.copyWith(color: AppColors.info, fontWeight: FontWeight.bold),
                              ),
                            ),
                          ],
                          if (role != null) ...[
                            const SizedBox(width: AppSpacing.xs),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: AppColors.surfaceElevated,
                                borderRadius: AppRadius.badge,
                                border: Border.all(color: AppColors.borderSubtle),
                              ),
                              child: Text(
                                role!,
                                style: AppTypography.caption.copyWith(color: AppColors.textMuted),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        accountName ?? accountEmail ?? (isConnected ? 'Connected to YouTube Music' : 'Not Connected'),
                        style: AppTypography.caption.copyWith(
                          color: isConnected ? AppColors.textSecondary : AppColors.textMuted,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                ?trailing,
              ],
            ),
          ),
        ),
      ),
    );
  }
}
