cat << 'INNER_EOF' > temp.diff
--- lib/src/app.dart
+++ lib/src/app.dart
@@ -176,6 +176,14 @@
       );
     }

+    // Create a global scroll behavior to enforce bouncing everywhere
+    final scrollBehavior = const MaterialScrollBehavior().copyWith(
+      physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
+      scrollbars: false,
+      overscroll: false,
+    );
+
     return MaterialApp(
       title: 'ArcPDF',
       navigatorKey: ref.read(intentServiceProvider).navigatorKey,
       debugShowCheckedModeBanner: false,
       themeMode: settings.themeMode,
       theme: buildTheme(lightColorScheme, Brightness.light),
       darkTheme: buildTheme(darkColorScheme, Brightness.dark),
+      scrollBehavior: scrollBehavior,
       home: const AppShell(),
       builder: (context, child) => LockScreenWrapper(child: child ?? const SizedBox.shrink()),
     );
   }
INNER_EOF
patch lib/src/app.dart < temp.diff
