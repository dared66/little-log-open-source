# Little Log tip jar

Settings → Support Little Log uses Apple StoreKit 2 on iPhone and Google Play Billing on Android through Flutter's official in_app_purchase plugin. Tips are optional consumables, grant no features, and never touch baby records or Google Drive. Web does not show the entry.

## iPhone: activate after Developer Program enrollment

1. In App Store Connect, create/select Little Log with the bundle ID used by the signed app (`app.littlelog.littleLog` in this checkout).
2. Accept the Paid Apps Agreement and complete banking and tax information. Enroll in the Small Business Program separately if eligible.
3. Create these **Consumable** In-App Purchases with exact IDs:

| Product ID | Reference name | Intended US price |
| --- | --- | --- |
| `app.littlelog.tip.tiny` | Tiny tip | $0.29 |
| `app.littlelog.tip.small` | Small tip | $0.99 |
| `app.littlelog.tip.medium` | Medium tip | $2.99 |
| `app.littlelog.tip.large` | Large tip | $4.99 |

Choose the available App Store price points and countries, add localized names/descriptions, and provide review information/screenshots. The app displays Apple's localized price, never a hardcoded amount. Missing products are not offered; an empty catalog shows a friendly unavailable message.

4. Test using Sandbox/TestFlight, including success, cancellation, Ask to Buy/pending approval, repeated purchases, network interruptions, leaving Settings during checkout, and relaunching with an unfinished purchase.
5. Submit the first purchases alongside the app version for review. Explain that these are voluntary developer tips, no subscription, and no unlocked content.

## Local testing before enrollment

In Xcode, open `ios/Runner.xcworkspace`, create a local StoreKit Configuration file, and add four consumable products with the IDs above. Select the file in Edit Scheme → Run → Options → StoreKit Configuration. Run from Xcode to exercise Apple's simulated checkout without a live account. Keep this local test configuration out of release distribution.

Run `flutter test test/tip_jar_test.dart` for fake-store regression coverage. These tests do not prove a live payment works. Real App Store catalog loading and charges require the account/products above.

## Payment behavior

The listener starts at app launch and remains alive when Settings closes. StoreKit 2 verifies transactions natively; no paid entitlement or balance is issued. Successful transactions are finished so the same tip can be purchased again. If finishing fails, Retry finishes the existing transaction without initiating a second purchase. Pending approval disables additional tips. Consumable tips do not have a restore-purchases button because they unlock nothing to restore.

## Implementation validation — September 24, 2026

Build `1.0.0+25`, based on source revision `e39f561` plus the local tip-jar changes. Seven focused tests pass: unavailable/missing products, duplicate prevention and cancellation, repeat purchases, completion retries, app-lifetime events, transaction verification, and small-screen large-text layout with localized pricing. Flutter analysis passes. Build 25 compiled, launched, and was version-checked on the iPhone 17 Pro simulator (iOS 26.5). The large-text capture in the project output folder is a test-rendered sample using fake products, not an actual App Store checkout. Live catalog, sandbox checkout, and physical-device payment verification remain pending account/product setup.


## Android: activate after Play Console enrollment

1. Register a [Google Play developer account](https://play.google.com/console/signup), complete the required verification, and configure a merchant payments profile and payout details.
2. Create Little Log with package name `app.littlelog.little_log`. Configure release signing and Play App Signing. This repository deliberately has no production signing key.
3. Create four **one-time products**, using the same product IDs in the table above. Configure active buy purchase options, localized descriptions, country availability, and approved $0.29 / $0.99 / $2.99 / $4.99 US prices. The app consumes each verified purchase so supporters can tip again.
4. Copy this app's **Base64 RSA licensing public key** from Play Console's monetization/licensing settings. Supply it as `PLAY_BILLING_PUBLIC_KEY` when building (for example with Flutter's `--dart-define-from-file` configuration alongside existing Google settings). It is a public verification key, not a service-account key or signing private key. An empty key disables checkout. Do not use placeholder keys in a distributed build.
5. Upload a signed app bundle to an internal test track. Add license testers, have them opt in and install through Google Play, and test using Google's test payment methods. A sideloaded debug emulator build with no configured products cannot validate live billing.
6. Exercise successful and repeated tips, cancellation, declined payment, pending approval, app restart/resume, and interrupted consumption. Complete any testing requirements shown by Play Console before production release.

The app verifies the signed purchase JSON locally against the configured RSA public key, package, product, token, and purchased state. It then consumes the tip, which also acknowledges it. Consumption failures remain retryable without another charge; an already-consumed response is treated as idempotent completion. Unconsumed purchases are queried on startup, resume, and Retry, including tips approved while the app was closed.

This optional tip jar grants no digital benefits and uses no payment server. Local signature checks do not provide server-side refund/revocation accounting or prevent a modified client from bypassing its own UI. Before adding paid features, balances, or entitlements, implement Google's recommended backend purchase-token verification. See [billing integration](https://developer.android.com/google/play/billing/integrate), [security guidance](https://developer.android.com/google/play/billing/security), and [billing tests](https://developer.android.com/google/play/billing/test).

## Android validation — September 24, 2026

Build `1.0.0+26`, based on `e39f561` plus local tip-jar changes. All nine focused purchase/UI tests pass and Flutter analysis is clean. The Android debug APK compiled, installed, launched, and was version-checked on emulator-5554. Main Settings → Support Little Log was opened and visually checked; the unconfigured billing state is captured in `../output/tip-jar-android-build26.png`. The shared Settings entry now appears on the main Settings page on both mobile platforms. No live charge was made. Google-signed purchase verification and checkout against the real Play catalog remain to be exercised using a configured Play license-testing account. The existing iPhone simulator remains on build 25; this Android follow-up did not reinstall it.

## Purchase reliability — October 9, 2026

Build 51 now queries StoreKit-verified unfinished transactions on startup, resume, and Retry. Duplicate successful transaction updates are finished once per app session. Store recovery, verification, and completion have bounded waits; a stalled paid transaction remains retryable without starting another charge. Retry appears only for a catalog/recovery/verification/completion problem. Four product IDs are supported, with amounts approved by the owner.

Fourteen focused tip-jar tests pass, including Apple unfinished-transaction conversion, duplicate deliveries, partial catalog retry, completion timeout/retry, pending approvals, cancellation, repeat tips, verification failures, Google consumption, and localized large-text layout. Flutter analysis is clean. The complete app was rebuilt, installed, launched, and version-checked as `1.0.0+51` on both the iPhone 17 Pro simulator and Android emulator-5554, based on `db9f077` plus working-tree changes. These checks use a test store and do not prove App Store sandbox or Google Play checkout.

App Store Connect now contains all four consumables with the approved US prices and Apple's regional equivalents, English display names, and descriptions. Product Apple IDs: tiny `6821251831`, small `6817632992`, medium `6821252181`, large `6821252398`. The Paid Apps Agreement, banking, and US tax setup were observed active. Products remain Prepare for Submission; review screenshots and first-IAP submission with the app version remain pending.

A native StoreKit catalog probe on the iOS simulator returned the actual small tip at `$0.99`. The three newly created products had not propagated at the time of testing; missing amounts remain hidden, available tips remain usable, and Retry is offered. Apple documents that sandbox metadata changes can take up to one hour. No real or sandbox purchase was completed. Google Play reports that a merchant account must be configured before monetization; the Android billing public key is also not yet configured. Android checkout remains blocked on that setup and a Play-installed test build.

Follow-up at 11:56 PM Pacific on October 9: the native StoreKit catalog returned all four exact product IDs with `$0.29`, `$0.99`, `$2.99`, and `$4.99`; the recurring catalog check was stopped. On October 10, build `1.0.0+51` was uploaded as `INTERNAL_ONLY`, processed as `VALID` / `READY_FOR_BETA_TESTING`, and assigned to the existing Owner testing group containing one tester (the owner). No external beta group was assigned. Fourteen purchase regression tests and Flutter analysis passed before the archive. Local development advanced to `1.0.0+52`, installed and launched on both emulators. Checkout itself remains unverified.
