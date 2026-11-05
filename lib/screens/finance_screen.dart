import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../widgets/responsive_officer_shell.dart';
import 'billing_screen.dart';
import 'budget_screen.dart';
import 'payment_channels_screen.dart';
import 'payments_screen.dart';
import '../core/tour_anchors.dart';
import '../widgets/guided_tour.dart';
import '../core/safe_state.dart';

/// Finance screen with Billing, Payments, Budget and Channels tabs.
/// An [IndexedStack] keeps every tab alive, so switching does not reload.
class FinanceScreen extends StatefulWidget {
  /// Which tab to open on ('Billing' | 'Payments' | 'Budget'), matched
  /// case-insensitively. Null or unrecognised falls back to Billing.
  final String? initialTab;

  const FinanceScreen({super.key, this.initialTab});

  @override
  State<FinanceScreen> createState() => _FinanceScreenState();
}

class _FinanceScreenState extends State<FinanceScreen> with SafeSetState<FinanceScreen> {
  // 'Channels' lists accounts residents pay into. It lives here because the
  // treasurer has no system_settings permission to reach the CMS.
  static const _tabs = ['Billing', 'Payments', 'Budget', 'Channels'];
  static const _tabIcons = [
    Icons.receipt_long_outlined,
    Icons.payments_outlined,
    Icons.pie_chart_outline,
    Icons.qr_code_2_outlined,
  ];

  int _tab = 0;

  @override
  void initState() {
    super.initState();
    // /admin/finance?tab=payments opens on that tab.
    final want = widget.initialTab?.toLowerCase().trim();
    if (want != null && want.isNotEmpty) {
      final i = _tabs.indexWhere((t) => t.toLowerCase() == want);
      if (i >= 0) _tab = i;
    }
    // Report the open tab to the tips so an old report is not reused.
    TourController.tabShown('/admin/finance', _tab, _tabs[_tab]);
  }

  /// Switches tab when a new ?tab= arrives. The router keeps this State, so
  /// initState does not run again.
  @override
  void didUpdateWidget(covariant FinanceScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    final want = widget.initialTab?.toLowerCase().trim();
    if (want == null || want.isEmpty || want == oldWidget.initialTab?.toLowerCase().trim()) {
      return;
    }
    final i = _tabs.indexWhere((t) => t.toLowerCase() == want);
    if (i >= 0 && i != _tab) {
      setState(() => _tab = i);
      TourController.tabShown('/admin/finance', _tab, _tabs[_tab]);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Shared by several officer roles, so mobile uses the generic menu.
    return ResponsiveOfficerShell(
      title: 'Finance',
      activeItem: 'Finance',
      activeTab: 'Finance',
      desktopChild: _body(horizontalPadding: 24),
      mobileChild: _body(horizontalPadding: 16),
    );
  }

  Widget _body({required double horizontalPadding}) {
    return Column(
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(horizontalPadding, 16, horizontalPadding, 0),
          child: _buildTabBar(),
        ),
        Expanded(
          child: IndexedStack(
            index: _tab,
            children: const [
              AdminBillingScreen(),
              AdminPaymentsScreen(),
              AdminBudgetScreen(),
              PaymentChannelsScreen(),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildTabBar() {
    final narrow = MediaQuery.sizeOf(context).width < 520;
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: const [BoxShadow(color: Color(0x1A0D2617), blurRadius: 24, offset: Offset(0, 8))],
      ),
      child: Row(
        children: [
          for (var i = 0; i < _tabs.length; i++)
            Expanded(
              child: _tabAnchor(i, InkWell(
                borderRadius: BorderRadius.circular(9),
                onTap: () {
                  setState(() => _tab = i);
                  TourController.tabShown('/admin/finance', i, _tabs[i]);
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(
                    color: _tab == i ? const Color(0xFFEFF6F1) : Colors.transparent,
                    borderRadius: BorderRadius.circular(9),
                  ),
                  alignment: Alignment.center,
                  // Under 520px wide the icon is dropped so four labels fit.
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (!narrow) ...[
                        Icon(_tabIcons[i],
                            size: 16, color: _tab == i ? AppColors.sidebarActiveText : AppColors.textMuted),
                        const SizedBox(width: 8),
                      ],
                      Flexible(
                        child: Text(_tabs[i],
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                fontSize: narrow ? 12.5 : 13,
                                fontWeight: _tab == i ? FontWeight.w600 : FontWeight.w500,
                                color: _tab == i ? AppColors.sidebarActiveText : AppColors.textPrimary)),
                      ),
                    ],
                  ),
                ),
              )),
            ),
        ],
      ),
    );
  }

  /// Marks the Payments and Channels tabs as targets for the guided tips.
  Widget _tabAnchor(int i, Widget child) => switch (_tabs[i]) {
        'Payments' => TourAnchor(id: TourAnchorId.paymentsTab, child: child),
        'Channels' => TourAnchor(id: TourAnchorId.channelsTab, child: child),
        _ => child,
      };
}
