import 'package:flutter_riverpod/flutter_riverpod.dart';

class AppDarkMode extends Notifier<bool> {
  @override
  bool build() => false;
  void toggle() => state = !state;
}

final appDarkModeProvider = NotifierProvider<AppDarkMode, bool>(
  AppDarkMode.new,
);
