import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../theme/app_colors.dart';
import 'cert_view_screen.dart';
import 'create_key_screen.dart';
import 'self_ca_screen.dart';
import 'create_csr_screen.dart';
import 'issue_cert_screen.dart';
import 'export_screen.dart';
import 'key_manager_screen.dart';

/// 側邊選單項目
class _NavItem {
  const _NavItem({
    required this.title,
    required this.subtitle,
    required this.icon,
    this.step,
    required this.page,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final int? step;
  final Widget page;
}

/// 響應式中斷點
const double _kDesktopBreakpoint = 900;
const double _kTabletBreakpoint = 600;
const double _kSidebarFullWidth = 280;
const double _kSidebarCompactWidth = 80;

/// 主畫面 - 響應式側邊選單（支援展開／關閉）
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _selectedIndex = 0;
  bool _sidebarOpen = true;
  List<_NavItem>? _items;
  final GlobalKey<ScaffoldState> _mobileScaffoldKey = GlobalKey<ScaffoldState>();

  /// 用於避免重複輸出相同尺寸
  double? _lastWidth;
  double? _lastHeight;

  List<_NavItem> get items => _items ??= _buildItems();

  List<_NavItem> _buildItems() {
    final l10n = AppLocalizations.of(context);
    return [
      _NavItem(
        title: l10n.menuViewCert,
        subtitle: l10n.menuViewCertDesc,
        icon: Icons.visibility_outlined,
        page: const CertViewScreen(),
      ),
      _NavItem(
        title: l10n.menuCreateKey,
        subtitle: l10n.menuCreateKeyDesc,
        icon: Icons.vpn_key_outlined,
        step: 1,
        page: const CreateKeyScreen(),
      ),
      _NavItem(
        title: l10n.menuSelfCA,
        subtitle: l10n.menuSelfCADesc,
        icon: Icons.verified_user_outlined,
        step: 2,
        page: const SelfCAScreen(),
      ),
      _NavItem(
        title: l10n.menuCreateCSR,
        subtitle: l10n.menuCreateCSRDesc,
        icon: Icons.description_outlined,
        step: 3,
        page: const CreateCSRScreen(),
      ),
      _NavItem(
        title: l10n.menuIssueCert,
        subtitle: l10n.menuIssueCertDesc,
        icon: Icons.assignment_turned_in_outlined,
        step: 4,
        page: const IssueCertScreen(),
      ),
      _NavItem(
        title: l10n.menuExport,
        subtitle: l10n.menuExportDesc,
        icon: Icons.file_download_outlined,
        page: const ExportScreen(),
      ),
      _NavItem(
        title: l10n.menuKeyManager,
        subtitle: l10n.menuKeyManagerDesc,
        icon: Icons.folder_outlined,
        page: const KeyManagerScreen(),
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        final h = constraints.maxHeight;

        // 即時輸出視窗尺寸至主控台
        if (w != _lastWidth || h != _lastHeight) {
          _lastWidth = w;
          _lastHeight = h;
          debugPrint(
            '[HomeScreen] 視窗尺寸: ${w.toInt()} x ${h.toInt()}  |  '
            '模式: ${_layoutLabel(w)}  |  側欄: ${_sidebarOpen ? "展開" : "關閉"}',
          );
        }

        final isDesktop = w >= _kDesktopBreakpoint;
        final isMobile = w < _kTabletBreakpoint;

        if (isMobile) {
          return _buildMobileLayout();
        } else {
          return _buildWideLayout(isDesktop: isDesktop);
        }
      },
    );
  }

  String _layoutLabel(double width) {
    if (width >= _kDesktopBreakpoint) return '桌面';
    if (width >= _kTabletBreakpoint) return '平板';
    return '手機';
  }

  // ═══════════════════════════════════════════
  // 寬屏佈局（桌面 / 平板）
  // ═══════════════════════════════════════════

  Widget _buildWideLayout({required bool isDesktop}) {
    final sidebarWidth =
        _sidebarOpen ? _kSidebarFullWidth : _kSidebarCompactWidth;

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(gradient: AppColors.backgroundGradient),
        child: Row(
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeInOut,
              width: sidebarWidth,
              clipBehavior: Clip.hardEdge,
              decoration: const BoxDecoration(color: AppColors.surface),
              child: _sidebarOpen
                  ? _buildFullSidebar(isDesktop: isDesktop)
                  : _buildCompactSidebar(),
            ),
            const VerticalDivider(width: 1, color: AppColors.primaryDark),
            Expanded(child: items[_selectedIndex].page),
          ],
        ),
      ),
    );
  }

  /// 展開的完整側邊欄
  Widget _buildFullSidebar({required bool isDesktop}) {
    return Column(
      children: [
        const SizedBox(height: 8),
        Center(child: _buildToggleButton()),
        const SizedBox(height: 8),
        const Divider(color: AppColors.primaryDark, height: 1),
        const SizedBox(height: 4),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
            children: [
              for (int i = 0; i < items.length; i++) ...[
                _buildSidebarItem(i, compact: false),
                if (i == 4)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Divider(
                      color: AppColors.primaryDark.withValues(alpha: 0.5),
                      height: 1,
                    ),
                  ),
              ],
            ],
          ),
        ),
        _buildSidebarFooter(),
        const SizedBox(height: 12),
      ],
    );
  }

  /// 關閉的緊湊側邊欄（僅圖示）
  Widget _buildCompactSidebar() {
    return Column(
      children: [
        const SizedBox(height: 8),
        Center(child: _buildToggleButton()),
        const SizedBox(height: 8),
        const Divider(color: AppColors.primaryDark, height: 1),
        const SizedBox(height: 4),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.symmetric(vertical: 4),
            children: [
              for (int i = 0; i < items.length; i++) ...[
                _buildSidebarItem(i, compact: true),
                if (i == 4)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Divider(
                      color: AppColors.primaryDark.withValues(alpha: 0.5),
                      indent: 12,
                      endIndent: 12,
                    ),
                  ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 8),
      ],
    );
  }

  // ═══════════════════════════════════════════
  // 窄屏佈局（手機）
  // ═══════════════════════════════════════════

  Widget _buildMobileLayout() {
    return Scaffold(
      key: _mobileScaffoldKey,
      // AppBar 高度設為 0 避免與子頁面 AppBar 疊加
      appBar: AppBar(
        toolbarHeight: 0,
        backgroundColor: Colors.transparent,
        elevation: 0,
        automaticallyImplyLeading: false,
      ),
      drawer: Drawer(
        backgroundColor: AppColors.surface,
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
            children: [
              for (int i = 0; i < items.length; i++) ...[
                _buildSidebarItem(i, compact: false),
                if (i == 4)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Divider(
                      color: AppColors.primaryDark.withValues(alpha: 0.5),
                      height: 1,
                    ),
                  ),
              ],
            ],
          ),
        ),
      ),
      body: Container(
        decoration: const BoxDecoration(gradient: AppColors.backgroundGradient),
        child: Stack(
          children: [
            items[_selectedIndex].page,
            // 浮動漢堡按鈕 — 一鍵開啟 Drawer
            Positioned(
              top: MediaQuery.of(context).padding.top + 4,
              left: 8,
              child: GestureDetector(
                onTap: () {
                  _mobileScaffoldKey.currentState?.openDrawer();
                  debugPrint('[HomeScreen] 手機模式 - 開啟側欄');
                },
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppColors.primaryDark, width: 0.6),
                  ),
                  child: const Icon(Icons.menu, color: AppColors.textSecondary, size: 22),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════
  // 共用元件
  // ═══════════════════════════════════════════

  /// 展開／關閉切換按鈕
  Widget _buildToggleButton() {
    return GestureDetector(
      onTap: () => setState(() {
            _sidebarOpen = !_sidebarOpen;
            debugPrint('[HomeScreen] 側欄切換: ${_sidebarOpen ? "展開" : "關閉"}');
          }),
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.primaryDark, width: 0.6),
        ),
        child: Icon(
          _sidebarOpen ? Icons.chevron_left : Icons.chevron_right,
          color: AppColors.textSecondary,
          size: 20,
        ),
      ),
    );
  }

  /// 側邊欄底部版本號
  Widget _buildSidebarFooter() {
    return Text(
      'v1.0.0',
      style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppColors.textHint),
    );
  }

  /// 選單項目
  Widget _buildSidebarItem(int index, {required bool compact}) {
    final item = items[index];
    final isSelected = index == _selectedIndex;

    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: GestureDetector(
        onTap: () {
          setState(() => _selectedIndex = index);
          debugPrint('[HomeScreen] 選單點擊: #$index "${item.title}"');

          if (MediaQuery.of(context).size.width < _kTabletBreakpoint) {
            _sidebarOpen = false;
            debugPrint('[HomeScreen] 手機模式 - 關閉 Drawer');
            Navigator.of(context).pop();
          }
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: EdgeInsets.zero,
          decoration: BoxDecoration(
            color: isSelected ? AppColors.surfaceLight : AppColors.surface,
            borderRadius: BorderRadius.circular(8),
            boxShadow: isSelected
                ? [BoxShadow(color: AppColors.glowStrong, blurRadius: 8, spreadRadius: 0)]
                : null,
          ),
          child: compact
              ? _buildCompactItemContent(item, isSelected)
              : _buildFullItemContent(item, isSelected),
        ),
      ),
    );
  }

  Widget _buildFullItemContent(_NavItem item, bool isSelected) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      child: Row(
        children: [
          _buildIconCircle(item.icon, isSelected),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.title,
                  style: TextStyle(
                    color: isSelected ? AppColors.accent : AppColors.textPrimary,
                    fontSize: 15,
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 1),
                Text(
                  item.subtitle,
                  style: TextStyle(
                    color: isSelected ? AppColors.textSecondary : AppColors.textHint,
                    fontSize: 12,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCompactItemContent(_NavItem item, bool isSelected) {
    return Tooltip(
      message: item.title,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildIconCircle(item.icon, isSelected),
          ],
        ),
      ),
    );
  }

  Widget _buildIconCircle(IconData icon, bool isSelected) {
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: isSelected ? AppColors.accent : AppColors.surfaceLight,
        boxShadow: const [
          BoxShadow(color: AppColors.primaryDark, offset: Offset(2, 2), blurRadius: 4),
        ],
      ),
      child: Icon(icon, color: isSelected ? AppColors.textPrimary : AppColors.textSecondary, size: 20),
    );
  }
}
