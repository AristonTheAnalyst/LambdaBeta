import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'core/powersync/database.dart';
import 'core/powersync/secure_local_storage.dart';
import 'core/styles/app_fonts.dart';
import 'features/programs/view/review_container.dart';
import 'version_gate_app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  AppFonts.init();

  await Supabase.initialize(
    url: 'https://dybluaeowmpdwsweawcq.supabase.co',
    publishableKey:
        'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImR5Ymx1YWVvd21wZHdzd2Vhd2NxIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzI4MTA1MzcsImV4cCI6MjA4ODM4NjUzN30.rjzDqKQJT3giqZ4o7-8oRHaGw1IujnOQVzKINJDjWBg',
    // Persist the session (incl. refresh token) in the OS keychain/keystore
    // instead of supabase_flutter's plaintext SharedPreferences default.
    authOptions: FlutterAuthClientOptions(
      localStorage: SecureLocalStorage(),
    ),
  );

  await initializeDateFormatting('en_GB');
  await openDatabase();

  _initDeepLinks();

  // Above the app, not inside it: a review's bar has to survive every route the
  // user drills into, and the ambient session is the one piece of state that
  // outlives them all.
  runApp(ReviewScope(child: const VersionGateApp()));
}

void _initDeepLinks() {
  final appLinks = AppLinks();
  appLinks.uriLinkStream.listen((uri) {
    Supabase.instance.client.auth.getSessionFromUrl(uri);
  });
}
