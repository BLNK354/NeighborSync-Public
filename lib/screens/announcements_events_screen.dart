import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../widgets/responsive_officer_shell.dart';
import 'announcements_board_screen.dart';
import 'events_calendar_screen.dart';
import '../widgets/guided_tour.dart';
import '../core/safe_state.dart';

/// Officer page with Announcements and Events as two tabs.
/// Uses an [IndexedStack] so switching tabs keeps the other tab's data.
class AnnouncementsEventsScreen extends StatefulWidget {
  const AnnouncementsEventsScreen({super.key});

  @override
  State<AnnouncementsEventsScreen> createState() => _AnnouncementsEventsScreenState();
}

class _AnnouncementsEventsScreenState extends State<AnnouncementsEventsScreen> with SafeSetState<AnnouncementsEventsScreen> {
  static const _tabs = ['Announcements', 'Events'];
  static const _tabIcons = [
    Icons.campaign_outlined,
    Icons.event_outlined,
  ];

  int _tab = 0;

  @override
  void initState() {
    super.initState();
    // Report the opened tab so the tips do not use an old visit's tab.
    TourController.tabShown('/admin/announcements', _tab, _tabs[_tab]);
  }

  @override
  Widget build(BuildContext context) {
    return ResponsiveOfficerShell(
      title: 'Announcements & Events',
      activeItem: 'Announcements & Events',
      activeTab: 'News',
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
              AnnouncementsBody(officer: true),
              EventsBody(officer: true),
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
                  TourController.tabShown('/admin/announcements', i, _tabs[i]);
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
