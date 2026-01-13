import 'package:flutter/material.dart';
import 'features/onboarding/onboarding_page.dart';
import 'features/home/home_page.dart';

class App extends StatelessWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'After',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      initialRoute: '/',
      routes: {
        '/': (context) => const _InitialRoute(),
      },
    );
  }
}

class _InitialRoute extends StatelessWidget {
  const _InitialRoute();

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
      future: OnboardingPage.shouldShowOnboarding(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        if (snapshot.data == true) {
          return const OnboardingPage();
        }
        // オンボーディング後は常にHomePage
        return const HomePage();
      },
    );
  }
}

