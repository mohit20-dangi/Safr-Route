// Git-ignored. Copy to the Mac manually. See config.example.dart.
class Config {
  static const orsKey = 'PASTE_ORS_KEY';
  static const uploadEvery = Duration(seconds: 30);
  static const uploadEveryMeters = 100.0;
  static const keepTripsDays = 7;
  static const arriveRadiusM =
      50.0; // trip ends automatically this close to the destination
}
