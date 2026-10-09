import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'settings_widgets.dart';

// Replace this URL when the policy is hosted.
const privacyPolicyUrl = 'https://example.com/finkeep/privacy-policy';

const privacyPolicySections = <(String, String)>[
  (
    'Your data',
    'FinKeep stores EMIs, installments, money records, repayments, subscriptions, activity and settings on this phone. The SQLite database is in private app documents storage. The PIN hash and backup password are in secure storage. Chat messages stay in memory for the session. No account is required.',
  ),
  (
    'What can leave the phone',
    'FinKeep does not send finance records to an app server and has no analytics, ads or crash-reporting SDK. Backups saved to your chosen folder can run automatically after you opt in; a cloud folder provider may sync them. PDF and CSV exports and shares leave the app only when you start them. Opening the policy link uses your browser.',
  ),
  (
    'Voice input',
    'Voice input asks Android for on-device recognition and uses the microphone only when you start listening. Availability depends on installed language packs. Android speech services may process or send audio to their provider, including Google; FinKeep cannot verify the provider behavior.',
  ),
  (
    'Permissions',
    'Android permissions: RECORD_AUDIO is for voice input; POST_NOTIFICATIONS is for reminders and is requested only when you turn them on; RECEIVE_BOOT_COMPLETED restores scheduled reminders; USE_BIOMETRIC and plugin-added USE_FINGERPRINT are for unlock; plugin-added VIBRATE supports notifications. AndroidX adds an app-scoped receiver permission. The debug build has INTERNET for Flutter tooling; the app manifest does not request it for release.',
  ),
  (
    'Backups and deletion',
    'The database is in private app storage. A pre-restore safety backup is stored privately on the phone. Your chosen backup folder can be Downloads, another document provider or cloud-backed storage. Settings > Clear all data removes finance records, activity and deleted items, but not saved backup files or every setting and PIN. Uninstalling removes private app data; delete external backup files separately.',
  ),
  (
    'Guidance',
    'FinKeep calculations and assistant answers use local data and are not financial advice.',
  ),
];

class PrivacyDataScreen extends StatelessWidget {
  const PrivacyDataScreen({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Privacy & data')),
    body: ListView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
      children: [
        for (final (title, body) in privacyPolicySections) ...[
          SettingsSectionHeader(title),
          SelectableText(body, style: Theme.of(context).textTheme.bodyMedium),
        ],
        const SizedBox(height: 20),
        TextButton.icon(
          onPressed: () => launchUrl(
            Uri.parse(privacyPolicyUrl),
            mode: LaunchMode.externalApplication,
          ),
          icon: const Icon(Icons.open_in_new),
          label: const Text('Privacy policy'),
        ),
      ],
    ),
  );
}
