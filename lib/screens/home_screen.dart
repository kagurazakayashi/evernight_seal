import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../theme/app_colors.dart';
import '../widgets/side_menu.dart';
import 'cert_view_screen.dart';
import 'create_key_screen.dart';
import 'self_ca_screen.dart';
import 'create_csr_screen.dart';
import 'issue_cert_screen.dart';
import 'export_screen.dart';
import 'key_manager_screen.dart';

/// 主畫面 - 持有狀態並委託 [SideMenu] 渲染
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _selectedIndex = 0;
  bool _sidebarOpen = true;
  final GlobalKey<ScaffoldState> _mobileScaffoldKey = GlobalKey<ScaffoldState>();
  final GlobalKey<CertViewScreenState> _certViewKey = GlobalKey<CertViewScreenState>();

  /// 建立私鑰功能產生後儲存於此，供自簽名 CA 畫面讀取
  String? _lastGeneratedKeyPem;

  double? _lastWidth;
  double? _lastHeight;

  void _navigateToCertView(String pem) {
    debugPrint('[HomeScreen] 導覽到憑證檢視，PEM 長度=${pem.length}');
    final state = _certViewKey.currentState;
    if (state != null) {
      state.viewPem(pem);
    } else {
      debugPrint('[HomeScreen] 警告: CertViewScreen state 為 null，無法導覽');
    }
    setState(() => _selectedIndex = 0);
  }

  List<NavItem> _buildItems() {
    final l10n = AppLocalizations.of(context);
    return [
      NavItem(
        title: l10n.menuViewCert,
        subtitle: l10n.menuViewCertDesc,
        icon: Icons.visibility_outlined,
        page: CertViewScreen(key: _certViewKey),
      ),
      NavItem(
        title: l10n.menuCreateKey,
        subtitle: l10n.menuCreateKeyDesc,
        icon: Icons.vpn_key_outlined,
        page: CreateKeyScreen(
          onKeyGenerated: (pem) => setState(() => _lastGeneratedKeyPem = pem),
        ),
      ),
      NavItem(
        title: l10n.menuSelfCA,
        subtitle: l10n.menuSelfCADesc,
        icon: Icons.verified_user_outlined,
        page: SelfCAScreen(
          lastGeneratedKeyPem: _lastGeneratedKeyPem,
          onViewDetails: _navigateToCertView,
        ),
      ),
      NavItem(title: l10n.menuCreateCSR, subtitle: l10n.menuCreateCSRDesc, icon: Icons.description_outlined, page: const CreateCSRScreen()),
      NavItem(title: l10n.menuIssueCert, subtitle: l10n.menuIssueCertDesc, icon: Icons.assignment_turned_in_outlined, page: const IssueCertScreen()),
      NavItem(title: l10n.menuExport, subtitle: l10n.menuExportDesc, icon: Icons.file_download_outlined, page: const ExportScreen()),
      NavItem(title: l10n.menuKeyManager, subtitle: l10n.menuKeyManagerDesc, icon: Icons.folder_outlined, page: const KeyManagerScreen()),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final items = _buildItems();

    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        final h = constraints.maxHeight;

        if (w != _lastWidth || h != _lastHeight) {
          _lastWidth = w;
          _lastHeight = h;
          debugPrint(
            '[HomeScreen] 視窗尺寸: ${w.toInt()} x ${h.toInt()}  |  '
            '模式: ${_label(w)}  |  側欄: ${_sidebarOpen ? "展開" : "關閉"}',
          );
        }

        return Container(
          decoration: const BoxDecoration(gradient: AppColors.backgroundGradient),
          child: SideMenu(
            items: items,
            selectedIndex: _selectedIndex,
            onItemSelected: (i) {
              setState(() => _selectedIndex = i);
              debugPrint('[HomeScreen] 選單點擊: #$i "${items[i].title}"');
            },
            isOpen: _sidebarOpen,
            onToggle: () => setState(() => _sidebarOpen = !_sidebarOpen),
            mobileScaffoldKey: _mobileScaffoldKey,
            onDebugPrint: (msg) => debugPrint(msg),
          ),
        );
      },
    );
  }

  String _label(double width) {
    if (width >= kDesktopBreakpoint) return '桌面';
    if (width >= kTabletBreakpoint) return '平板';
    return '手機';
  }
}
