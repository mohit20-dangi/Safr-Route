import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../services/group_service.dart';
import '../ui/widgets.dart';
import 'create_group_screen.dart';
import 'group_hub_screen.dart';
import 'join_group_screen.dart';
import 'settings_screen.dart';

class GroupsHomeScreen extends StatelessWidget {
  GroupsHomeScreen({super.key});
  final _groups = GroupService();

  void _add(BuildContext context) {
    showModalBottomSheet(
      context: context,
      builder: (c) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            ListTile(
              leading: const Icon(Icons.group_add),
              title: const Text('Create a group'),
              subtitle: const Text('Start a circle for your family'),
              onTap: () {
                Navigator.pop(c);
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const CreateGroupScreen()),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.vpn_key),
              title: const Text('Join with a code'),
              subtitle: const Text(
                'Ask the group admin for the 6-character code',
              ),
              onTap: () {
                Navigator.pop(c);
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const JoinGroupScreen()),
                );
              },
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('My groups'),
        actions: [
          IconButton(
            tooltip: 'Appearance',
            icon: const Icon(Icons.brightness_6_rounded),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const SettingsScreen()),
            ),
          ),
          IconButton(
            tooltip: 'Sign out',
            icon: const Icon(Icons.logout_rounded),
            onPressed: () => AuthService().signOut(),
          ),
        ],
      ),
      body: StreamBuilder(
        stream: _groups.userStream(),
        builder: (context, snap) {
          final data = snap.data?.data() ?? {};
          final ids = List<String>.from(data['groupIds'] ?? []);
          final names = Map<String, dynamic>.from(data['groupNames'] ?? {});
          if (ids.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(40),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(28),
                      decoration: BoxDecoration(
                        color: cs.primary.withValues(alpha: 0.12),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.family_restroom_rounded,
                        size: 64,
                        color: cs.primary,
                      ),
                    ),
                    const SizedBox(height: 24),
                    Text(
                      'No groups yet',
                      style: Theme.of(context).textTheme.titleLarge
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Create a group for your family, or join one with an invite code.',
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            );
          }
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 100),
            children: [
              for (final g in ids)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: StreamBuilder(
                    stream: _groups.myMembership(g),
                    builder: (context, ms) {
                      final m = ms.data?.data();
                      final status = m?['status'] ?? '...';
                      final role = m?['role'] ?? '';
                      final isActive = status == 'active';
                      final name = (names[g] ?? g).toString();
                      return Card(
                        clipBehavior: Clip.antiAlias,
                        child: InkWell(
                          onTap: isActive
                              ? () => Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => GroupHubScreen(
                                      groupId: g,
                                      groupName: name,
                                      role: role,
                                    ),
                                  ),
                                )
                              : null,
                          onLongPress: () async {
                            final ok = await showDialog<bool>(
                              context: context,
                              builder: (c) => AlertDialog(
                                title: Text('Leave $name?'),
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
                            if (ok == true) await _groups.leave(g);
                          },
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Row(
                              children: [
                                CircleAvatar(
                                  radius: 26,
                                  backgroundColor: cs.primaryContainer,
                                  child: Text(
                                    initials(name),
                                    style: TextStyle(
                                      color: cs.onPrimaryContainer,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        name,
                                        style: const TextStyle(
                                          fontSize: 17,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                      const SizedBox(height: 6),
                                      isActive
                                          ? StatusChip(
                                              role == 'admin'
                                                  ? 'Admin'
                                                  : 'Member',
                                              cs.primary,
                                              icon: role == 'admin'
                                                  ? Icons.shield
                                                  : Icons.person,
                                            )
                                          : const StatusChip(
                                              'Waiting for approval',
                                              Colors.orange,
                                              icon: Icons.hourglass_top,
                                            ),
                                    ],
                                  ),
                                ),
                                if (isActive)
                                  Icon(
                                    Icons.chevron_right_rounded,
                                    color: cs.onSurfaceVariant,
                                  ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
            ],
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _add(context),
        icon: const Icon(Icons.add),
        label: const Text('Add group'),
      ),
    );
  }
}
