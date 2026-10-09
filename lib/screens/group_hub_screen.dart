import 'package:flutter/material.dart';

import '../services/group_service.dart';
import '../ui/widgets.dart';
import 'group_admin_screen.dart';
import 'guardian_map_screen.dart';
import 'permissions_setup_screen.dart';
import 'places_screen.dart';
import 'recent_trips_screen.dart';
import 'traveler_home_screen.dart';

class GroupHubScreen extends StatelessWidget {
  const GroupHubScreen({
    super.key,
    required this.groupId,
    required this.groupName,
    required this.role,
  });
  final String groupId, groupName, role;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isAdmin = role == 'admin';
    void go(Widget w) =>
        Navigator.push(context, MaterialPageRoute(builder: (_) => w));

    final tiles = <Widget>[
      ActionTile(
        highlight: true,
        icon: Icons.navigation_rounded,
        title: 'Start a trip',
        subtitle: 'Share your commute',
        onTap: () => go(TravelerHomeScreen(groupId: groupId)),
      ),
      ActionTile(
        icon: Icons.map_rounded,
        title: 'Live map',
        subtitle: 'Who is travelling now',
        onTap: () =>
            go(GuardianMapScreen(groupId: groupId, groupName: groupName)),
      ),
      ActionTile(
        icon: Icons.history_rounded,
        title: 'Recent trips',
        subtitle: 'Last 7 days',
        onTap: () => go(RecentTripsScreen(groupId: groupId)),
      ),
      ActionTile(
        icon: Icons.place_rounded,
        title: 'Places',
        subtitle: 'Home, college…',
        onTap: () => go(PlacesScreen(groupId: groupId)),
      ),
      ActionTile(
        icon: Icons.verified_user_rounded,
        title: 'Permissions',
        subtitle: 'Check and test alerts',
        onTap: () => go(const PermissionsSetupScreen()),
      ),
      if (isAdmin)
        ActionTile(
          icon: Icons.admin_panel_settings_rounded,
          title: 'Members',
          subtitle: 'Invite code, approvals',
          onTap: () =>
              go(GroupAdminScreen(groupId: groupId, groupName: groupName)),
        ),
    ];

    return Scaffold(
      appBar: AppBar(title: Text(groupName)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        children: [
          Row(
            children: [
              StatusChip(
                isAdmin ? 'Admin' : 'Member',
                cs.primary,
                icon: isAdmin ? Icons.shield : Icons.person,
              ),
            ],
          ),
          const SizedBox(height: 14),
          GridView(
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              mainAxisExtent: 172,
            ),
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            children: tiles,
          ),
          const SizedBox(height: 20),
          Center(
            child: TextButton.icon(
              icon: Icon(Icons.logout_rounded, color: cs.error),
              label: Text('Leave group', style: TextStyle(color: cs.error)),
              onPressed: () async {
                final ok = await showDialog<bool>(
                  context: context,
                  builder: (c) => AlertDialog(
                    title: Text('Leave $groupName?'),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(c, false),
                        child: const Text('Cancel'),
                      ),
                      TextButton(
                        onPressed: () => Navigator.pop(c, true),
                        child: const Text('Leave'),
                      ),
                    ],
                  ),
                );
                if (ok == true) {
                  await GroupService().leave(groupId);
                  if (context.mounted) Navigator.pop(context);
                }
              },
            ),
          ),
        ],
      ),
    );
  }
}
