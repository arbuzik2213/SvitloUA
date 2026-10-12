import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'screens/home_screen.dart';
import 'theme.dart';

void main() {
  runApp(const SvitloApp());
}

class SvitloApp extends StatelessWidget {
  const SvitloApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Світло',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(Brightness.light),
      darkTheme: buildTheme(Brightness.dark),
      builder: (context, child) {
        // Прозорий статус-бар з іконками під колір теми (на iPhone теж).
        final dark = Theme.of(context).brightness == Brightness.dark;
        return AnnotatedRegion<SystemUiOverlayStyle>(
          value: (dark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark)
              .copyWith(
            statusBarColor: Colors.transparent,
            systemNavigationBarColor: context.palette.paper,
          ),
          child: child!,
        );
      },
      home: const HomeScreen(),
    );
  }
}
