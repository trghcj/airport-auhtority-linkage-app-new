
// firebase_options.dart

import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart' show defaultTargetPlatform, kIsWeb, TargetPlatform;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      return web;
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.windows:
      case TargetPlatform.linux:
        throw UnsupportedError(
            'DefaultFirebaseOptions have not been configured for desktop platforms.');
      default:
        throw UnsupportedError(
            'DefaultFirebaseOptions are not supported for this platform.');
    }
  }}

  const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyCTDxgLO3uwJoDHXxByF9HMVABiD4Wj49g',
    authDomain: 'airport-authority-linkage.firebaseapp.com',
    projectId: 'airport-authority-linkage',
    storageBucket: 'airport-authority-linkage.firebasestorage.app',
    messagingSenderId: '707290062868',
    appId: '1:707290062868:web:d6da3cd3df86849d5f0701',
    measurementId: 'G-LTGRKBP1NC',
  );

  const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyCTDxgLO3uwJoDHXxByF9HMVABiD4Wj49g',
    appId: '1:707290062868:android:a40d8677fcb623535f0701',
    messagingSenderId: '707290062868',
    projectId: 'airport-authority-linkage',
    storageBucket: 'airport-authority-linkage.firebasestorage.app',
  );

  