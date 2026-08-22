// Driver entrypoint — enables the Flutter driver extension so tooling can
// inspect and drive the running app (finders, taps, text entry, screenshots).
// NOT the shipped entrypoint; run with `flutter run -t lib/driver_main.dart`.
import 'package:flutter_driver/driver_extension.dart';
import 'package:lambda/main.dart' as app;

void main() {
  enableFlutterDriverExtension();
  app.main();
}
