import 'package:airport_auhtority_linkage_app/models/analysis_data.dart' as model;
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:logger/logger.dart';

import 'login_page.dart';
import 'stats_page.dart';
import 'search_page.dart';
import 'upload_page.dart';
import 'analysis_page.dart';

class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  final Logger _logger = Logger();
  int _index = 0;

  // Store doc_id and analysisResult to pass between pages
  String? _docId;
  Map<String, dynamic>? _analysisResult; // Store analysisResult for AnalysisPage

  // GlobalKey for Scaffold to access its state
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  // List of page builders to pass docId and analysisResult dynamically
  final List<Widget Function(String?, Map<String, dynamic>?)> _pageBuilders = [
    (docId, _) => StatsPage(docId: docId),
    (docId, _) => SearchPage(filterBy: '', docId: docId),
    (docId, _) => const UploadPage(),
    (docId, analysisResult) => AnalysisPage(initialAnalysisResult: analysisResult as Map<String, model.AnalysisData>?),
  ];

  final List<String> _titles = const [
    'Stats',
    'Search',
    'Upload',
    'Analysis',
  ];

  // Update doc_id and analysisResult, show feedback
  void _updateState({String? docId, Map<String, dynamic>? analysisResult}) {
    bool stateChanged = false;
    if (docId != null && docId != _docId) {
      setState(() {
        _docId = docId;
        stateChanged = true;
      });
      _logger.d('Updated doc_id: $docId');
    }
    if (analysisResult != null && analysisResult != _analysisResult) {
      setState(() {
        _analysisResult = analysisResult;
        stateChanged = true;
      });
      _logger.d('Updated analysisResult: $analysisResult');
    }
    if (stateChanged && mounted) {
      final scaffoldContext = _scaffoldKey.currentContext;
      if (scaffoldContext != null && scaffoldContext.mounted) {
        ScaffoldMessenger.of(scaffoldContext).showSnackBar(
          SnackBar(
            content: Text(
              'Doc ID: ${_docId ?? 'N/A'}, Analysis Data: ${_analysisResult != null ? 'Updated' : 'N/A'}',
            ),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    }
  }

  // Navigate to page with optional state update
  void _navigateToPage(int index, {String? docId, Map<String, dynamic>? analysisResult}) {
    if (docId != null || analysisResult != null) {
      _updateState(docId: docId, analysisResult: analysisResult);
    }
    if (mounted && _scaffoldKey.currentState != null) {
      _scaffoldKey.currentState!.openEndDrawer(); // Close drawer if open
      setState(() => _index = index);
    }
  }

  // Handle logout with error feedback
  Future<void> _logout() async {
    try {
      await FirebaseAuth.instance.signOut();
      if (mounted) {
        final context = this.context;
        if (context.mounted) {
          Navigator.pushAndRemoveUntil(
            context,
            MaterialPageRoute(builder: (_) => const LoginPage()),
            (route) => false,
          );
          _logger.i('User logged out successfully');
        }
      }
    } catch (e) {
      _logger.e('Logout error: $e');
      if (mounted) {
        final scaffoldContext = _scaffoldKey.currentContext;
        if (scaffoldContext != null && scaffoldContext.mounted) {
          ScaffoldMessenger.of(scaffoldContext).showSnackBar(
            const SnackBar(content: Text('Failed to logout. Please try again.')),
          );
        }
      }
    }
  }

  @override
  void initState() {
    super.initState();
    _logger.d('Dashboard initialized with index: $_index');
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Check for arguments passed during navigation
    final args = ModalRoute.of(context)?.settings.arguments as Map<String, dynamic>?;
    if (args != null) {
      _updateState(
        docId: args['docId'] as String?,
        analysisResult: args['analysisResult'] as Map<String, dynamic>?,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        if (_index != 0) {
          setState(() => _index = 0); // Return to Stats page
          return false;
        }
        return true; // Allow app exit from Stats page
      },
      child: Scaffold(
        key: _scaffoldKey, // Assign the GlobalKey
        drawer: Drawer(
          child: ListView(
            padding: EdgeInsets.zero,
            children: [
              const DrawerHeader(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0xFF1976D2), Color(0xFF2196F3)],
                  ),
                ),
                child: Text(
                  'Dashboard Menu',
                  style: TextStyle(color: Colors.white, fontSize: 20),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.bar_chart),
                title: const Text('Stats'),
                onTap: () => _navigateToPage(0, docId: _docId),
              ),
              ListTile(
                leading: const Icon(Icons.search),
                title: const Text('Search'),
                onTap: () => _navigateToPage(1, docId: _docId),
              ),
              ListTile(
                leading: const Icon(Icons.upload_file),
                title: const Text('Upload'),
                onTap: () => _navigateToPage(2),
              ),
              ListTile(
                leading: const Icon(Icons.analytics),
                title: const Text('Analysis'),
                onTap: () => _navigateToPage(3, analysisResult: _analysisResult),
              ),
              const Divider(),
              ListTile(
                leading: const Icon(Icons.logout),
                title: const Text('Logout'),
                onTap: _logout,
              ),
            ],
          ),
        ),
        appBar: AppBar(
          title: Text(_titles[_index]),
          backgroundColor: const Color(0xFF1976D2),
          actions: [
            if (_docId != null)
              Padding(
                padding: const EdgeInsets.only(right: 16.0),
                child: Text(
                  'Doc ID: $_docId',
                  style: const TextStyle(fontSize: 14, color: Colors.white),
                ),
              ),
          ],
        ),
        body: Builder(
          builder: (context) => _pageBuilders[_index](_docId, _analysisResult),
        ),
        bottomNavigationBar: BottomNavigationBar(
          currentIndex: _index,
          selectedItemColor: const Color(0xFF1976D2),
          unselectedItemColor: Colors.grey,
          onTap: (i) => _navigateToPage(i, docId: _docId, analysisResult: _analysisResult),
          items: const [
            BottomNavigationBarItem(icon: Icon(Icons.bar_chart), label: 'Stats'),
            BottomNavigationBarItem(icon: Icon(Icons.search), label: 'Search'),
            BottomNavigationBarItem(icon: Icon(Icons.upload_file), label: 'Upload'),
            BottomNavigationBarItem(icon: Icon(Icons.analytics), label: 'Analysis'),
          ],
        ),
      ),
    );
  }
}