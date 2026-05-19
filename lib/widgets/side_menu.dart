import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// 側邊選單項目
class NavItem {
  const NavItem({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.page,
    this.badge,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final Widget page;

  /// 圖示右下角數字角標（null 則不顯示）
  final String? badge;
}

/// 響應式中斷點
const double kDesktopBreakpoint = 900;
const double kTabletBreakpoint = 600;
const double kSidebarFullWidth = 280;
const double kSidebarCompactWidth = 80;

/// 回應式側邊選單
class SideMenu extends StatelessWidget {
  const SideMenu({
    super.key,
    required this.items,
    required this.selectedIndex,
    required this.onItemSelected,
    required this.isOpen,
    required this.onToggle,
    required this.mobileScaffoldKey,
    this.onDebugPrint,
  });

  final List<NavItem> items;
  final int selectedIndex;
  final ValueChanged<int> onItemSelected;
  final bool isOpen;
  final VoidCallback onToggle;
  final GlobalKey<ScaffoldState> mobileScaffoldKey;
  final void Function(String)? onDebugPrint;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        if (w < kTabletBreakpoint) {
          return _MobileSideMenu(
            items: items, selectedIndex: selectedIndex,
            onItemSelected: (i) { onItemSelected(i); onDebugPrint?.call('[HomeScreen] 手機模式 - 關閉 Drawer'); Navigator.of(context).pop(); },
            scaffoldKey: mobileScaffoldKey, onDebugPrint: onDebugPrint,
          );
        }
        return _WideSideMenu(
          items: items, selectedIndex: selectedIndex, onItemSelected: onItemSelected,
          isOpen: isOpen, onToggle: onToggle, isDesktop: w >= kDesktopBreakpoint, onDebugPrint: onDebugPrint,
        );
      },
    );
  }
}

class _WideSideMenu extends StatelessWidget {
  const _WideSideMenu({required this.items, required this.selectedIndex, required this.onItemSelected, required this.isOpen, required this.onToggle, required this.isDesktop, this.onDebugPrint});
  final List<NavItem> items;
  final int selectedIndex;
  final ValueChanged<int> onItemSelected;
  final bool isOpen;
  final VoidCallback onToggle;
  final bool isDesktop;
  final void Function(String)? onDebugPrint;

  @override
  Widget build(BuildContext context) {
    final sidebarWidth = isOpen ? kSidebarFullWidth : kSidebarCompactWidth;
    return Row(
      children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 250), curve: Curves.easeInOut,
          width: sidebarWidth, clipBehavior: Clip.hardEdge,
          decoration: const BoxDecoration(color: AppColors.surface),
          child: isOpen
              ? _SidebarColumn(items: items, selectedIndex: selectedIndex, onItemSelected: onItemSelected, compact: false, onToggle: onToggle, isOpen: isOpen, onDebugPrint: onDebugPrint)
              : _SidebarColumn(items: items, selectedIndex: selectedIndex, onItemSelected: onItemSelected, compact: true, onToggle: onToggle, isOpen: isOpen, onDebugPrint: onDebugPrint),
        ),
        const VerticalDivider(width: 1, color: AppColors.primaryDark),
        Expanded(child: IndexedStack(index: selectedIndex, children: [for (final item in items) item.page])),
      ],
    );
  }
}

class _SidebarColumn extends StatelessWidget {
  const _SidebarColumn({required this.items, required this.selectedIndex, required this.onItemSelected, required this.compact, required this.onToggle, required this.isOpen, this.onDebugPrint});
  final List<NavItem> items;
  final int selectedIndex;
  final ValueChanged<int> onItemSelected;
  final bool compact;
  final VoidCallback onToggle;
  final bool isOpen;
  final void Function(String)? onDebugPrint;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const SizedBox(height: 8),
        Center(child: _ToggleButton(isOpen: isOpen, onToggle: onToggle, onDebugPrint: onDebugPrint)),
        const SizedBox(height: 8),
        const Divider(color: AppColors.primaryDark, height: 1),
        const SizedBox(height: 4),
        Expanded(
          child: ListView(
            padding: EdgeInsets.symmetric(horizontal: compact ? 0 : 4, vertical: 4),
            children: [
              for (int i = 0; i < items.length; i++) ...[
                _SidebarMenuItem(item: items[i], index: i, isSelected: i == selectedIndex, compact: compact, onTap: () => onItemSelected(i)),
                if (i == 0 || i == 7) Padding(
                  padding: EdgeInsets.symmetric(vertical: compact ? 6 : 8),
                  child: Divider(color: AppColors.primaryDark.withValues(alpha: 0.5), indent: compact ? 12 : 0, endIndent: compact ? 12 : 0),
                ),
              ],
            ],
          ),
        ),
        SizedBox(height: compact ? 8 : 12),
      ],
    );
  }
}

class _MobileSideMenu extends StatelessWidget {
  const _MobileSideMenu({required this.items, required this.selectedIndex, required this.onItemSelected, required this.scaffoldKey, this.onDebugPrint});
  final List<NavItem> items;
  final int selectedIndex;
  final ValueChanged<int> onItemSelected;
  final GlobalKey<ScaffoldState> scaffoldKey;
  final void Function(String)? onDebugPrint;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: scaffoldKey,
      appBar: AppBar(toolbarHeight: 0, backgroundColor: Colors.transparent, elevation: 0, automaticallyImplyLeading: false),
      drawer: Drawer(
        backgroundColor: AppColors.surface,
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
            children: [
              for (int i = 0; i < items.length; i++) ...[
                _SidebarMenuItem(item: items[i], index: i, isSelected: i == selectedIndex, compact: false, onTap: () => onItemSelected(i)),
                if (i == 0 || i == 7) Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: Divider(color: AppColors.primaryDark.withValues(alpha: 0.5), height: 1)),
              ],
            ],
          ),
        ),
      ),
      body: Stack(
        children: [
          IndexedStack(index: selectedIndex, children: [for (final item in items) item.page]),
          Positioned(
            top: MediaQuery.of(context).padding.top + 4, left: 8,
            child: GestureDetector(
              onTap: () { scaffoldKey.currentState?.openDrawer(); onDebugPrint?.call('[HomeScreen] 手機模式 - 開啟側欄'); },
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(10), border: Border.all(color: AppColors.primaryDark, width: 0.6)),
                child: const Icon(Icons.menu, color: AppColors.textSecondary, size: 22),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ToggleButton extends StatelessWidget {
  const _ToggleButton({required this.isOpen, required this.onToggle, this.onDebugPrint});
  final bool isOpen;
  final VoidCallback onToggle;
  final void Function(String)? onDebugPrint;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () { onToggle(); onDebugPrint?.call('[HomeScreen] 側欄切換: ${isOpen ? "關閉" : "展開"}'); },
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(8), border: Border.all(color: AppColors.primaryDark, width: 0.6)),
        child: Icon(isOpen ? Icons.chevron_left : Icons.chevron_right, color: AppColors.textSecondary, size: 20),
      ),
    );
  }
}

class _SidebarMenuItem extends StatelessWidget {
  const _SidebarMenuItem({required this.item, required this.index, required this.isSelected, required this.compact, required this.onTap});
  final NavItem item;
  final int index;
  final bool isSelected;
  final bool compact;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: EdgeInsets.zero,
          decoration: BoxDecoration(color: isSelected ? AppColors.surfaceLight : AppColors.surface, borderRadius: BorderRadius.circular(8)),
          child: compact ? _CompactItemContent(item: item, isSelected: isSelected) : _FullItemContent(item: item, isSelected: isSelected),
        ),
      ),
    );
  }
}

class _FullItemContent extends StatelessWidget {
  const _FullItemContent({required this.item, required this.isSelected});
  final NavItem item;
  final bool isSelected;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _IconCircle(icon: item.icon, isSelected: isSelected, badge: item.badge),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(item.title, style: TextStyle(color: isSelected ? AppColors.accent : AppColors.textPrimary, fontSize: 15, fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500, decoration: TextDecoration.none)),
                const SizedBox(height: 2),
                Text(item.subtitle, style: TextStyle(color: isSelected ? AppColors.textSecondary : AppColors.textHint, fontSize: 12, decoration: TextDecoration.none)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CompactItemContent extends StatelessWidget {
  const _CompactItemContent({required this.item, required this.isSelected});
  final NavItem item;
  final bool isSelected;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: item.title,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Center(child: _IconCircle(icon: item.icon, isSelected: isSelected, badge: item.badge)),
      ),
    );
  }
}

class _IconCircle extends StatelessWidget {
  const _IconCircle({required this.icon, required this.isSelected, this.badge});
  final IconData icon;
  final bool isSelected;
  final String? badge;

  @override
  Widget build(BuildContext context) {
    final circle = Container(
      width: 36, height: 36,
      decoration: BoxDecoration(shape: BoxShape.circle, color: isSelected ? AppColors.accent : AppColors.surfaceLight),
      child: Icon(icon, color: isSelected ? AppColors.textPrimary : AppColors.textSecondary, size: 20),
    );

    if (badge == null) return circle;

    return SizedBox(
      width: 36, height: 36,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          circle,
          Positioned(
            right: -4, bottom: -4,
            child: Container(
              width: 16, height: 16,
              decoration: BoxDecoration(
                color: AppColors.primary,
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.surface, width: 1.5),
              ),
              alignment: Alignment.center,
              child: Text(
                badge!,
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                  height: 1,
                  decoration: TextDecoration.none,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
