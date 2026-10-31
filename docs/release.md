# Releasing to TestFlight

`.github/workflows/testflight.yml` builds a signed release on a GitHub macOS runner and uploads it to App Store Connect. Nothing needs a Mac or Xcode on Paul's side. Signing is automatic: Xcode, using an App Store Connect API key, creates the certificates and provisioning profiles it needs in the cloud.

## One-time setup (Paul)

1. **Join the Apple Developer Program** at <https://developer.apple.com/programs/enroll/> (99 USD a year). Approval can take a day or two. Note the **Team ID** (10 characters) under Membership details at <https://developer.apple.com/account>.
2. **Register the app's bundle ID** at <https://developer.apple.com/account/resources/identifiers/list>: click +, choose App IDs, then App. Description `Tiny Airways`, Bundle ID **Explicit** `com.paulkinderman.tinyAirways`. Under Capabilities tick **iCloud** (the game syncs its save through iCloud key-value storage; no container is needed). Continue, then Register.
3. **Create the app in App Store Connect** at <https://appstoreconnect.apple.com/apps>: click +, New App. Platform iOS, name `Tiny Airways` (if that name is taken on the App Store, try `Tiny Airways: Sky Tycoon`; only the store listing changes, the home-screen name stays Tiny Airways), primary language English, bundle ID `com.paulkinderman.tinyAirways`, SKU `tinyairways`, Full Access.
4. **Create an App Store Connect API key** at <https://appstoreconnect.apple.com/access/integrations/api>: under Team Keys click +, name it `GitHub TestFlight`, access **Admin** (needed so Xcode can create the distribution certificate). Download the `.p8` file (it can only be downloaded once) and note the **Key ID** and the **Issuer ID** shown above the list.
5. **Add four repository secrets** at <https://github.com/paulkinderman/tiny-airways/settings/secrets/actions> (New repository secret):

   | Name | Value |
   | --- | --- |
   | `APPLE_TEAM_ID` | The Team ID from step 1 |
   | `APP_STORE_CONNECT_KEY_ID` | The Key ID from step 4 |
   | `APP_STORE_CONNECT_ISSUER_ID` | The Issuer ID from step 4 |
   | `APP_STORE_CONNECT_PRIVATE_KEY` | The whole text of the `.p8` file, including the `-----BEGIN PRIVATE KEY-----` and `-----END PRIVATE KEY-----` lines |

## Each release

1. Open <https://github.com/paulkinderman/tiny-airways/actions/workflows/testflight.yml> and click **Run workflow** on `main` (or push a tag like `v1.0.1`). It takes about 20 minutes.
2. When it's green, the build appears in App Store Connect under the app's TestFlight tab after Apple processes it (10 to 30 minutes; Apple emails when it's done).
3. The first time only: in the TestFlight tab, open **Internal Testing**, click +, create a group (for example `Me`), and add yourself. Install the **TestFlight** app from the App Store on your iPhone, sign in with the same Apple ID, and accept the invite. Later builds show up there on their own.

The version shown in the app is `version` in `pubspec.yaml` (1.0.0); the build number is the workflow's run number, so every upload is new. The app declares it uses no non-exempt encryption (`ITSAppUsesNonExemptEncryption` in `Info.plist`), so TestFlight doesn't ask the export-compliance question.

## If the workflow fails

- **"Missing repository secrets"**: one of the four secrets in step 5 is missing or misspelled.
- **"No profiles for 'com.paulkinderman.tinyAirways' were found"** or a team error: the bundle ID from step 2 isn't registered under the same team as `APPLE_TEAM_ID`, or the API key isn't Admin.
- **"No suitable application records were found"**: the app from step 3 doesn't exist yet, or its bundle ID differs.
- **iCloud capability errors**: tick iCloud on the App ID (step 2), then run the workflow again.

## Before the build goes out

CI already runs on every pull request: format, analyze, all unit and widget tests (including the 30-day balance bot, see [balance.md](balance.md)), an unsigned release build for devices, and a launch of the app on an iPhone simulator.
