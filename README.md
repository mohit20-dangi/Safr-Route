# SafeRoute

A Flutter app that keeps travellers safe on the road. A traveller plans a trip, a group of guardians watches their live location, and everyone is alerted if the trip goes off course.

## Features

- **Groups** – create or join a group; admins manage members.
- **Trip planning** – pick a destination and choose from alternative driving routes (OpenRouteService, with OSRM as fallback).
- **Live tracking** – the traveller's position is uploaded to Firestore in the background via a foreground service.
- **Route monitoring** – detects off-route, wrong direction, stopped off-route, stale location, low battery, location turned off, and arrival.
- **Alerts** – local alarm notifications for Android guardians, [ntfy](https://ntfy.sh) pushes for iPhone guardians, plus an alert history screen.
- **Guardian map** – live map of group members (flutter_map / OpenStreetMap).
- **Saved places and recent trips**, light/dark theme.

## Tech stack

Flutter (Dart SDK ^3.13.5), Firebase Auth + Cloud Firestore, Google Sign-In, geolocator, flutter_foreground_task, flutter_local_notifications, flutter_map.

## Project layout

```
lib/
  main.dart          app entry, Firebase init
  background/        foreground-service task: tracking + monitoring
  models/            data models
  screens/           UI screens
  services/          auth, groups, routing, route checking, alerts
  ui/                theme and shared widgets
test/                unit tests (route checker)
firestore.rules      Firestore security rules
```

## Getting started

1. Install [Flutter](https://docs.flutter.dev/get-started/install) and run `flutter pub get`.
2. Create a Firebase project, enable Google sign-in and Firestore, then run `flutterfire configure`. This generates `lib/firebase_options.dart`, `android/app/google-services.json` and `ios/Runner/GoogleService-Info.plist`. These files are git-ignored.
3. Copy `lib/config.example.dart` to `lib/config.dart` (git-ignored) and set your [OpenRouteService](https://openrouteservice.org) key in `orsKey`. Without a key the app falls back to the public OSRM server.
4. Deploy the rules: `firebase deploy --only firestore`.
5. Run the app: `flutter run`.

## Configuration

`lib/config.dart` controls upload interval (`uploadEvery`, `uploadEveryMeters`), trip retention (`keepTripsDays`) and the auto-arrival radius (`arriveRadiusM`).

## Tests

```
flutter test
```
