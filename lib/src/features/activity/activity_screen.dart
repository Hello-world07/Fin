import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/formatters.dart';
import '../../core/providers.dart';
import '../../shared/async_view.dart';
import '../../shared/empty_state.dart';

class ActivityScreen extends ConsumerWidget {
  const ActivityScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(privacyModeProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Activity History')),
      body: AsyncView(
        value: ref.watch(activityProvider),
        builder: (events) {
          if (events.isEmpty) {
            return const EmptyState(
              icon: Icons.history,
              title: 'No activity yet',
              message:
                  'Important financial actions will appear here with date and time.',
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: events.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final event = events[index];
              return ListTile(
                contentPadding: const EdgeInsets.symmetric(vertical: 8),
                leading: const Icon(Icons.history),
                title: Text(
                  hideMoneyInText(event.title),
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                subtitle: Text(
                  hideMoneyInText(
                    '${formatDateTime(event.occurredAt)}${event.description == null ? '' : ' • ${displayName(event.description!)}'}',
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
