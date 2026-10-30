# Tiny Airways

An original, offline-friendly cartoon airline-management game for iPhone (Android later). The player hand-routes small planes between real cities, loads each flight with passengers and cargo, and reinvests profit to grow a fleet, a route network and the airports themselves. No ads, no paywalls, no premium currency.

Built with Flutter and the Flame engine so one codebase ships to iOS now and Android later.

## Running it

You need Flutter 3.47.9 (stable) and, for iOS, Xcode on a Mac.

```sh
flutter pub get
flutter run            # on a booted iOS simulator or connected device
```

## Checks

```sh
dart format lib test integration_test
flutter analyze
flutter test                                  # unit and widget tests
flutter test integration_test -d <simulator>  # launches the real app
```

CI runs all of these on every pull request, including a launch on an iOS simulator.

## Where things are

See [docs/architecture.md](docs/architecture.md) for the folder layout, the rules each layer follows, and how to add config files and save migrations.
