import 'package:flutter/material.dart';
import '../../services/api_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_radius.dart';
import '../theme/app_spacing.dart';
import '../theme/app_typography.dart';

/// Global Account Indicator widget for application shell.
class AppAccountIndicator extends StatelessWidget {
  final VoidCallback onSignIn;
  final ValueChanged<int> onNavigateTab;
  final bool compact;
  final double? width;

  const AppAccountIndicator({
    super.key,
    required this.onSignIn,
    required this.onNavigateTab,
    this.compact = false,
    this.width,
  });

  @override
  Widget build(BuildContext context) {
    final user = apiService.currentUser;
    final ytmAccount = apiService.ytmAccount;
    final isYtmConnected = ytmAccount?.isConnected ?? false;

    if (user == null) {
      if (compact) {
        return IconButton(
          tooltip: 'Sign In',
          onPressed: onSignIn,
          icon: const Icon(Icons.login, size: 20, color: AppColors.textSecondary),
        );
      }
      return SizedBox(
        width: width ?? 190,
        child: OutlinedButton.icon(
          onPressed: onSignIn,
          icon: const Icon(Icons.login, size: 16),
          label: const Text('Sign In'),
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.sm,
            ),
          ),
        ),
      );
    }

    final avatar = CircleAvatar(
      radius: compact ? 16 : 14,
      backgroundColor: user.isAdmin ? AppColors.primary : AppColors.info,
      child: Text(
        user.username.isNotEmpty ? user.username[0].toUpperCase() : 'U',
        style: const TextStyle(
          color: Colors.white,
          fontSize: 12,
          fontWeight: FontWeight.bold,
        ),
      ),
    );

    final popupMenu = PopupMenuButton<String>(
      tooltip: 'Account Options',
      padding: EdgeInsets.zero,
      color: AppColors.surfaceElevated,
      shape: const RoundedRectangleBorder(
        borderRadius: AppRadius.card,
        side: BorderSide(color: AppColors.borderSubtle),
      ),
      onSelected: (val) async {
        if (val == 'settings') {
          onNavigateTab(6);
        } else if (val == 'family') {
          onNavigateTab(7);
        } else if (val == 'switch') {
          onSignIn();
        } else if (val == 'logout') {
          await apiService.logout();
          onSignIn();
        }
      },
      itemBuilder: (ctx) => [
        PopupMenuItem(
          enabled: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                user.username,
                style: AppTypography.body.copyWith(fontWeight: FontWeight.bold),
              ),
              Text(
                user.role.toUpperCase(),
                style: AppTypography.caption.copyWith(
                  color: user.isAdmin ? AppColors.primaryLight : AppColors.info,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Divider(color: AppColors.borderSubtle, height: 16),
            ],
          ),
        ),
        const PopupMenuItem(
          value: 'family',
          child: Row(
            children: [
              Icon(Icons.people_outline, size: 18, color: AppColors.info),
              SizedBox(width: AppSpacing.sm),
              Text('Family Mode', style: AppTypography.bodySm),
            ],
          ),
        ),
        const PopupMenuItem(
          value: 'settings',
          child: Row(
            children: [
              Icon(Icons.settings_outlined, size: 18, color: AppColors.textSecondary),
              SizedBox(width: AppSpacing.sm),
              Text('Settings', style: AppTypography.bodySm),
            ],
          ),
        ),
        const PopupMenuItem(
          value: 'switch',
          child: Row(
            children: [
              Icon(Icons.switch_account_outlined, size: 18, color: AppColors.textSecondary),
              SizedBox(width: AppSpacing.sm),
              Text('Switch User', style: AppTypography.bodySm),
            ],
          ),
        ),
        const PopupMenuDivider(),
        const PopupMenuItem(
          value: 'logout',
          child: Row(
            children: [
              Icon(Icons.logout, size: 18, color: AppColors.error),
              SizedBox(width: AppSpacing.sm),
              Text('Log Out', style: TextStyle(color: AppColors.error, fontSize: 13)),
            ],
          ),
        ),
      ],
      child: compact
          ? Stack(
              clipBehavior: Clip.none,
              children: [
                avatar,
                Positioned(
                  right: -1,
                  bottom: -1,
                  child: Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: isYtmConnected ? AppColors.success : AppColors.textMuted,
                      shape: BoxShape.circle,
                      border: Border.all(color: AppColors.surface, width: 1.5),
                    ),
                  ),
                ),
              ],
            )
          : null,
    );

    if (compact) {
      return popupMenu;
    }

    return Container(
      width: width ?? 190,
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: AppColors.surfaceElevated,
        borderRadius: AppRadius.card,
        border: Border.all(color: AppColors.borderSubtle),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              avatar,
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      user.username,
                      style: AppTypography.label.copyWith(fontWeight: FontWeight.w700),
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      user.role.toUpperCase(),
                      style: AppTypography.caption.copyWith(
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                        color: user.isAdmin ? AppColors.primaryLight : AppColors.info,
                      ),
                    ),
                  ],
                ),
              ),
              popupMenu,
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Row(
            children: [
              Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  color: isYtmConnected ? AppColors.success : AppColors.textMuted,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  isYtmConnected
                      ? (ytmAccount?.accountName ?? 'YTM Connected')
                      : 'YTM Disconnected',
                  style: AppTypography.caption.copyWith(
                    color: isYtmConnected ? AppColors.success : AppColors.textMuted,
                    fontWeight: FontWeight.w500,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
