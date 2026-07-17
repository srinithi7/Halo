import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../theme/app_theme.dart';

/// Custom 5-slot bottom nav: Feed / Search / [center action] / SafeWalk /
/// Me. The center slot isn't a real tab — it's a raised gold button that
/// opens the give-recognition modal, so [selectedIndex] only ever covers
/// the 4 real destinations (0=Feed, 1=Search, 2=SafeWalk, 3=Me).
class CustomBottomNav extends StatelessWidget {
  const CustomBottomNav({
    super.key,
    required this.selectedIndex,
    required this.onTabSelected,
    required this.onCenterTap,
  });

  final int selectedIndex;
  final ValueChanged<int> onTabSelected;
  final VoidCallback onCenterTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 78,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.topCenter,
        children: [
          Positioned.fill(
            top: 14,
            child: DecoratedBox(
              decoration: const BoxDecoration(
                color: bgSurface,
                border: Border(top: BorderSide(color: borderColor, width: 1)),
              ),
              child: Row(
                children: [
                  _NavItem(
                    icon: LucideIcons.home,
                    label: 'Feed',
                    selected: selectedIndex == 0,
                    onTap: () => onTabSelected(0),
                  ),
                  _NavItem(
                    icon: LucideIcons.search,
                    label: 'Search',
                    selected: selectedIndex == 1,
                    onTap: () => onTabSelected(1),
                  ),
                  const Expanded(child: SizedBox()),
                  _NavItem(
                    icon: LucideIcons.mapPin,
                    label: 'SafeWalk',
                    selected: selectedIndex == 2,
                    onTap: () => onTabSelected(2),
                  ),
                  _NavItem(
                    icon: LucideIcons.userCircle,
                    label: 'Me',
                    selected: selectedIndex == 3,
                    onTap: () => onTabSelected(3),
                  ),
                ],
              ),
            ),
          ),
          Positioned(
            top: 0,
            child: GestureDetector(
              onTap: onCenterTap,
              child: Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: accentGold,
                  boxShadow: [
                    BoxShadow(
                      color: accentGold.withValues(alpha: 0.45),
                      blurRadius: 16,
                      spreadRadius: 1,
                    ),
                  ],
                ),
                child: const Icon(LucideIcons.plus, color: bgPrimary, size: 26),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected ? accentGold : textMuted;
    return Expanded(
      child: InkWell(
        onTap: onTap,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              height: 3,
              width: 3,
              child: selected
                  ? const DecoratedBox(
                      decoration: BoxDecoration(color: accentGold, shape: BoxShape.circle),
                    )
                  : null,
            ),
            const SizedBox(height: 6),
            Icon(icon, color: color, size: 22),
            const SizedBox(height: 2),
            Text(label, style: TextStyle(color: color, fontSize: 10)),
          ],
        ),
      ),
    );
  }
}
