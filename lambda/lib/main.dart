import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'app.dart';
import 'core/powersync/database.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Supabase.initialize(
    url: 'https://dybluaeowmpdwsweawcq.supabase.co',
    publishableKey:
        'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImR5Ymx1YWVvd21wZHdzd2Vhd2NxIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzI4MTA1MzcsImV4cCI6MjA4ODM4NjUzN30.rjzDqKQJT3giqZ4o7-8oRHaGw1IujnOQVzKINJDjWBg',
  );

  await initializeDateFormatting('en_GB');
  await openDatabase();

  _initDeepLinks();

  runApp(const LambdaApp());
}

void _initDeepLinks() {
  final appLinks = AppLinks();
  appLinks.uriLinkStream.listen((uri) {
    Supabase.instance.client.auth.getSessionFromUrl(uri);
  });
}
