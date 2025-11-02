import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:provider/provider.dart';
import 'package:logger/logger.dart';

// ✅ Import your own project files
import 'firebase_options.dart';
import 'package:airport_auhtority_linkage_app/config/config.dart';
import 'package:airport_auhtority_linkage_app/models/analysis_data.dart' as model;
import 'pages/login_page.dart';
import 'pages/dashboard_page.dart';
import 'pages/search_page.dart';
import 'pages/stats_page.dart';
import 'pages/upload_page.dart';
import 'pages/analysis_page.dart';
import 'providers/auth_provider.dart' as my_auth;
import 'providers/stats_provider.dart';
import 'providers/search_provider.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final logger = Logger();

  // 🌍 Ensure web uses production backend (Railway)
  // and local builds use localhost in debug mode
  if (kIsWeb) {
    AppConfig.setEnvironment(isDev: false);
  } else {
    AppConfig.setEnvironment(isDev: kDebugMode);
  }

  AppConfig.logActiveConfig(); // 🧾 Print current environment + base URL

  try {
    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
    runApp(const MyApp());
  } catch (e, stackTrace) {
    logger.e('❌ Firebase initialization failed: $e\nStackTrace: $stackTrace');
    runApp(const ErrorApp());
  }
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    final logger = Logger();

    return MultiProvider(
      providers: [
        ChangeNotifierProvider<my_auth.AuthProvider>(
          create: (_) => my_auth.AuthProvider(),
          lazy: true,
        ),
        ChangeNotifierProvider<StatsProvider>(
          create: (_) => StatsProvider(),
          lazy: true,
        ),
        ChangeNotifierProvider<SearchProvider>(
          create: (_) => SearchProvider(),
          lazy: true,
        ),
      ],
      child: MaterialApp(
        title: 'Airport Authority Linkage App',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
          useMaterial3: true,
          scaffoldBackgroundColor: Colors.grey[50],
          fontFamily: 'Roboto',
          textTheme: Theme.of(context).textTheme.apply(
                fontFamily: 'Roboto',
                fontFamilyFallback: [
                  'NotoSans',
                  'NotoSansSymbols',
                  'NotoSansKR',
                ],
              ),
          appBarTheme: const AppBarTheme(
            backgroundColor: Color(0xFF1976D2),
            foregroundColor: Colors.white,
            elevation: 4,
            shadowColor: Colors.grey,
          ),
        ),
        initialRoute: '/',
        routes: {
          '/': (context) => const AuthWrapper(),
          '/login': (context) => const LoginPage(),
          '/dashboard': (context) => const DashboardPage(),
          '/upload': (context) => const UploadPage(),
          '/analysis': (context) {
            final args = ModalRoute.of(context)?.settings.arguments as Map<String, dynamic>?;
            final analysisResult =
                args?['analysisResult'] as Map<String, model.AnalysisData>?;
            logger.d('➡ Navigating to AnalysisPage with: $analysisResult');
            return AnalysisPage(initialAnalysisResult: analysisResult);
          },
          '/search': (context) {
            final args = ModalRoute.of(context)?.settings.arguments as Map<String, dynamic>?;
            final docId = args?['docId'] as String?;
            final filterBy = args?['filterBy'] as String? ?? '';
            if (docId == null || docId.isEmpty) {
              logger.w('⚠ Missing docId for SearchPage, using default');
              return const SearchPage(filterBy: '', docId: 'default_doc_id');
            }
            logger.d('➡ Navigating to SearchPage with docId: $docId');
            return SearchPage(filterBy: filterBy, docId: docId);
          },
          '/stats': (context) {
            final args = ModalRoute.of(context)?.settings.arguments as Map<String, dynamic>?;
            final docId = args?['docId'] as String?;
            if (docId == null || docId.isEmpty) {
              logger.w('⚠ Missing docId for StatsPage, using default');
              return const StatsPage(docId: 'default_doc_id');
            }
            logger.d('➡ Navigating to StatsPage with docId: $docId');
            return StatsPage(docId: docId);
          },
        },
        onGenerateRoute: (settings) {
          logger.w('⚠ Unknown route: ${settings.name}');
          return MaterialPageRoute(
            builder: (_) => const Scaffold(
              body: Center(child: Text('Route not found')),
            ),
          );
        },
        onUnknownRoute: (settings) {
          logger.w('⚠ Unknown route requested: ${settings.name}');
          return MaterialPageRoute(
            builder: (_) => const Scaffold(
              body: Center(child: Text('Route not found')),
            ),
          );
        },
      ),
    );
  }
}

class AuthWrapper extends StatelessWidget {
  const AuthWrapper({super.key});

  @override
  Widget build(BuildContext context) {
    final logger = Logger();

    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          logger.d('⌛ Waiting for Firebase Auth...');
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        } else if (snapshot.hasError) {
          logger.e('❌ Auth stream error: ${snapshot.error}');
          return const Scaffold(
            body: Center(child: Text('Authentication error. Please try again.')),
          );
        } else if (snapshot.hasData) {
          final user = snapshot.data;
          logger.i('✅ User authenticated: ${user?.uid}');
          return const DashboardPage();
        } else {
          logger.w('👤 No user authenticated');
          return const LoginPage();
        }
      },
    );
  }
}

class ErrorApp extends StatelessWidget {
  const ErrorApp({super.key});

  @override
  Widget build(BuildContext context) {
    final logger = Logger();
    logger.e('🚨 Firebase initialization failed. Showing ErrorApp.');

    return MaterialApp(
      home: Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text(
                'Failed to initialize app',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () => runApp(const MyApp()), // Retry initialization
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
