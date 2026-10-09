# FinKeep Privacy & Data

## Your data

FinKeep stores EMIs, installments, money records, repayments, subscriptions, activity and settings on this phone. The SQLite database is in private app documents storage. The PIN hash and backup password are in secure storage. Chat messages stay in memory for the session. No account is required.

## What can leave the phone

FinKeep does not send finance records to an app server and has no analytics, ads or crash-reporting SDK. Backups saved to your chosen folder can run automatically after you opt in; a cloud folder provider may sync them. PDF and CSV exports and shares leave the app only when you start them. Opening the policy link uses your browser.

## Voice input

Voice input asks Android for on-device recognition and uses the microphone only when you start listening. Availability depends on installed language packs. Android speech services may process or send audio to their provider, including Google; FinKeep cannot verify the provider behavior.

## Permissions

Android permissions: RECORD_AUDIO is for voice input; POST_NOTIFICATIONS is for reminders and is requested only when you turn them on; RECEIVE_BOOT_COMPLETED restores scheduled reminders; USE_BIOMETRIC and plugin-added USE_FINGERPRINT are for unlock; plugin-added VIBRATE supports notifications. AndroidX adds an app-scoped receiver permission. The debug build has INTERNET for Flutter tooling; the app manifest does not request it for release.

## Backups and deletion

The database is in private app storage. A pre-restore safety backup is stored privately on the phone. Your chosen backup folder can be Downloads, another document provider or cloud-backed storage. Settings > Clear all data removes finance records, activity and deleted items, but not saved backup files or every setting and PIN. Uninstalling removes private app data; delete external backup files separately.

## Guidance

FinKeep calculations and assistant answers use local data and are not financial advice.
