# Release checklist

- Build the `just-gomoku` scheme with the Release configuration for iOS and macOS.
- Launch one signed development build on a physical device, complete a game, and confirm that the `ArchivedGame` record type appears in the Development environment of CloudKit Console.
- Deploy the CloudKit schema from Development to Production before the first App Store release.
- Verify completed-game history and preferences on two devices signed into the same iCloud account. Confirm that the active board remains device-local.
- Archive with App Store distribution signing and confirm the final signature contains CloudKit, iCloud container, key-value store, and production push entitlements.
- Re-run the unit, UI, accessibility, and analyzer checks after changing deployment or signing settings.
