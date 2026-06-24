import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

enum UserRole { systemAdmin, coordinator, lecturer, student }

class _NavItem {
  final String label;
  final IconData icon;
  final IconData activeIcon;
  const _NavItem(this.label, this.icon, this.activeIcon);
}

class CustomBottomNavigation extends StatelessWidget {
  final UserRole role;
  final int currentIndex;
  final ValueChanged<int> onTap;

  const CustomBottomNavigation({
    super.key,
    required this.role,
    required this.currentIndex,
    required this.onTap,
  });

  List<_NavItem> get _items {
    switch (role) {
      case UserRole.student:
        return const [
          _NavItem('Home', Icons.home_outlined, Icons.home),
          _NavItem('Timetable', Icons.calendar_month_outlined, Icons.calendar_month),
          _NavItem('Map', Icons.map_outlined, Icons.map),
          _NavItem('Alerts', Icons.notifications_outlined, Icons.notifications),
          _NavItem('Profile', Icons.person_outlined, Icons.person),
        ];
      case UserRole.lecturer:
        return const [
          _NavItem('Home', Icons.home_outlined, Icons.home),
          _NavItem('Timetable', Icons.calendar_month_outlined, Icons.calendar_month),
          _NavItem('Sessions', Icons.meeting_room_outlined, Icons.meeting_room),
          _NavItem('Map', Icons.map_outlined, Icons.map),
          _NavItem('Alerts', Icons.notifications_outlined, Icons.notifications),
          _NavItem('Profile', Icons.person_outlined, Icons.person),
        ];
      case UserRole.coordinator:
        return const [
          _NavItem('Home', Icons.home_outlined, Icons.home),
          _NavItem('Timetable', Icons.calendar_month_outlined, Icons.calendar_month),
          _NavItem('Venues', Icons.location_city_outlined, Icons.location_city),
          _NavItem('Users', Icons.group_outlined, Icons.group),
          _NavItem('Alerts', Icons.notifications_outlined, Icons.notifications),
          _NavItem('Profile', Icons.person_outlined, Icons.person),
        ];
      case UserRole.systemAdmin:
        return const [
          _NavItem('Home', Icons.home_outlined, Icons.home),
          _NavItem('Users', Icons.manage_accounts_outlined, Icons.manage_accounts),
          _NavItem('Settings', Icons.settings_outlined, Icons.settings),
          _NavItem('Audit', Icons.security_outlined, Icons.security),
          _NavItem('Profile', Icons.person_outlined, Icons.person),
        ];
    }
  }

  @override
  Widget build(BuildContext context) {
    final items = _items;
    return NavigationBar(
      selectedIndex: currentIndex.clamp(0, items.length - 1),
      onDestinationSelected: onTap,
      backgroundColor: AppColors.surface,
      indicatorColor: AppColors.primary.withAlpha(26),
      labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      destinations: items.map((item) {
        final index = items.indexOf(item);
        final isSelected = index == currentIndex;
        return NavigationDestination(
          icon: Icon(
            isSelected ? item.activeIcon : item.icon,
            color: isSelected ? AppColors.primary : AppColors.textSecondary,
          ),
          selectedIcon: Icon(item.activeIcon, color: AppColors.primary),
          label: item.label,
        );
      }).toList(),
    );
  }
}
