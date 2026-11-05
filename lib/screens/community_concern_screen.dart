import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../widgets/responsive_officer_shell.dart';
import 'complaints_screen.dart';
import 'violations_screen.dart';
import '../widgets/guided_tour.dart';
import '../core/safe_state.dart';

/// Community Concern screen with Complaints and Cases tabs in one officer shell.
/// Uses an [IndexedStack] so switching tabs keeps each tab's loaded data.
class CommunityConcernScreen extends StatefulWidget {
  const CommunityConcernScreen({super.key});

  @override
  State<CommunityConcernScreen> createState() => _CommunityConcernScreenState();
}

class _CommunityConcernScreenState extends State<CommunityConcernScreen> with SafeSetState<CommunityConcernScreen> {
  static const _tabs = ['Complaints', 'Cases'];
  static const _tabIcons = [
    Icons.forum_outlined,
    Icons.gavel_outlined,
  ];

  int _tab = 0;

  @override
  void initState() {
    super.initState();
    // Tells the guided tips which tab is showing.
    TourController.tabShown('/admin/community-concern', _tab, _tabs[_tab]);
  }

  @override
  Widget build(BuildContext context) {
    // Many roles reach this screen, so mobile uses the generic permission-filtered menu.
    return ResponsiveOfficerShell(
      title: 'Community Concern',
      activeItem: 'Community Concern',
      activeTab: 'Services',
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
              AdminComplaintsScreen(),
              AdminCasesScreen(),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildTabBar() {
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
              child: InkWell(
                borderRadius: BorderRadius.circular(9),
                onTap: () {
                  setState(() => _tab = i);
                  TourController.tabShown('/admin/community-concern', i, _tabs[i]);
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(
                    color: _tab == i ? const Color(0xFFEFF6F1) : Colors.transparent,
                    borderRadius: BorderRadius.circular(9),
                  ),
                  alignment: Alignment.center,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(_tabIcons[i],
                          size: 16, color: _tab == i ? AppColors.sidebarActiveText : AppColors.textMuted),
                      const SizedBox(width: 8),
                      Text(_tabs[i],
                          style: TextStyle(
                              fontSize: 13,
                              fontWeight: _tab == i ? FontWeight.w600 : FontWeight.w500,
                              color: _tab == i ? AppColors.sidebarActiveText : AppColors.textPrimary)),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
