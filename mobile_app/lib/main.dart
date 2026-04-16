// lib/main.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'firebase_options.dart';
import 'features/auth/presentation/pages/login_page.dart';
import 'features/feed/presentation/pages/feed_page.dart';
import 'features/feed/presentation/pages/my_complaints_page.dart';
import 'features/posts/presentation/pages/report_issue_page.dart';
import 'features/profile/presentation/pages/user_profile_page.dart';
import 'features/committee/presentation/pages/committee_shell.dart';
import 'services/committee_auth_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
    ),
  );
  runApp(const CampusVoiceApp());
}

// ── App Colors ────────────────────────────────────────────────────────────────
// Inspired by clean social/civic app designs — light, modern, approachable
class AppColors {
  // Brand
  static const primary     = Color(0xFF1A237E); // Navy — logo + branding only
  static const accent      = Color(0xFF5C6BC0); // Softer indigo — interactive elements
  static const accentLight = Color(0xFFE8EAF6); // Light indigo tint

  // Backgrounds
  static const background  = Color(0xFFF5F6FA); // Soft grey page bg
  static const surface     = Color(0xFFFFFFFF); // Card white
  static const surfaceAlt  = Color(0xFFF8F9FE); // Slightly tinted white

  // Text
  static const textDark    = Color(0xFF1C1C2E); // Headings
  static const textMid     = Color(0xFF6B7280); // Body
  static const textLight   = Color(0xFFB0B7C3); // Captions / placeholders

  // Borders
  static const border      = Color(0xFFEEEFF4); // Dividers

  // Status
  static const pending     = Color(0xFFFF9500); // iOS orange — pending
  static const inProgress  = Color(0xFF007AFF); // iOS blue — in progress
  static const resolved    = Color(0xFF34C759); // iOS green — resolved
  static const rejected    = Color(0xFFFF3B30); // iOS red — rejected

  // Status tints
  static const orangeTint  = Color(0xFFFFF3E0);
  static const blueTint    = Color(0xFFE3F2FD);
  static const greenTint   = Color(0xFFE8F5E9);
  static const redTint     = Color(0xFFFFEBEE);
  static const primaryTint = Color(0xFFE8EAF6);
}

// ── Global Draft Refresh Notifier ─────────────────────────────────────────────
// Incremented whenever a draft is saved or submitted so MyComplaintsPage
// can reload its draft list immediately without waiting for app restart.
final draftRefreshNotifier = ValueNotifier<int>(0);

class CampusVoiceApp extends StatelessWidget {
  const CampusVoiceApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'CampusVoice AIKTC',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        fontFamily: 'Roboto',
        colorScheme: ColorScheme.fromSeed(
          seedColor: AppColors.accent,
          brightness: Brightness.light,
        ),
        scaffoldBackgroundColor: AppColors.background,
        appBarTheme: const AppBarTheme(
          backgroundColor: AppColors.surface,
          foregroundColor: AppColors.textDark,
          elevation: 0,
          centerTitle: false,
          surfaceTintColor: Colors.transparent,
          iconTheme: IconThemeData(color: AppColors.textDark),
        ),
        cardTheme: CardThemeData(
          color: AppColors.surface,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: AppColors.surfaceAlt,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: AppColors.border),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: AppColors.border),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: AppColors.accent, width: 1.5),
          ),
        ),
      ),
      home: const AuthGate(),
    );
  }
}

// ── Auth Gate ─────────────────────────────────────────────────────────────────
class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const _SplashScreen();
        }
        if (snapshot.hasData && snapshot.data != null) {
          return const _RoleRouter();
        }
        return const LoginPage();
      },
    );
  }
}

// ── Role Router — checks Firestore to decide which shell to show ──────────────
class _RoleRouter extends StatefulWidget {
  const _RoleRouter();

  @override
  State<_RoleRouter> createState() => _RoleRouterState();
}

class _RoleRouterState extends State<_RoleRouter> {
  late Future<UserRoleResult> _roleFuture;

  @override
  void initState() {
    super.initState();
    final email = FirebaseAuth.instance.currentUser?.email ?? '';
    _roleFuture = CommitteeAuthService.instance.resolveRole(email);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<UserRoleResult>(
      future: _roleFuture,
      builder: (context, snap) {
        // Still loading
        if (snap.connectionState == ConnectionState.waiting) {
          return const _SplashScreen();
        }

        // Error — fail safe to student shell if student email, else login
        if (snap.hasError || !snap.hasData) {
          final email =
              FirebaseAuth.instance.currentUser?.email ?? '';
          if (CommitteeAuthService.instance.isStudentEmail(email)) {
            return const MainShell();
          }
          return const LoginPage();
        }

        final result = snap.data!;

        if (result.role == UserRole.committee && result.member != null) {
          return CommitteeShell(member: result.member!);
        }

        if (result.role == UserRole.student) {
          return const MainShell();
        }

        // Blocked — sign out async then show login
        // Use addPostFrameCallback to avoid setState during build
        WidgetsBinding.instance.addPostFrameCallback((_) {
          FirebaseAuth.instance.signOut();
        });
        return const LoginPage();
      },
    );
  }
}

// ── Main Shell — Bottom Navigation ────────────────────────────────────────────
class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _currentIndex = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: [
          const RepaintBoundary(child: FeedPage()),
          const RepaintBoundary(child: MyComplaintsPage()),
          const RepaintBoundary(child: _NotificationsPage()),
          RepaintBoundary(
            child: UserProfilePage(
              onSwitchTab: (i) => setState(() => _currentIndex = i),
            ),
          ),
        ],
      ),
      floatingActionButton: _CenterFAB(
        onPressed: () async {
          await Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const ReportIssuePage()),
          );
        },
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
      bottomNavigationBar: _BottomNavBar(
        currentIndex: _currentIndex,
        onTap: (i) => setState(() => _currentIndex = i),
      ),
    );
  }
}

// ── Center FAB ────────────────────────────────────────────────────────────────
class _CenterFAB extends StatelessWidget {
  final VoidCallback onPressed;
  const _CenterFAB({required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onPressed,
      child: Container(
        width: 56,
        height: 56,
        decoration: BoxDecoration(
          color: AppColors.primary,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: AppColors.primary.withValues(alpha: 0.35),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: const Icon(Icons.add_rounded, color: Colors.white, size: 28),
      ),
    );
  }
}

// ── Bottom Nav Bar ────────────────────────────────────────────────────────────
class _BottomNavBar extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;
  const _BottomNavBar({required this.currentIndex, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 20,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 64,
          child: Row(
            children: [
              _NavItem(
                icon: Icons.home_outlined,
                activeIcon: Icons.home_rounded,
                label: 'Home',
                isActive: currentIndex == 0,
                onTap: () => onTap(0),
              ),
              _NavItem(
                icon: Icons.assignment_outlined,
                activeIcon: Icons.assignment_rounded,
                label: 'My Issues',
                isActive: currentIndex == 1,
                onTap: () => onTap(1),
              ),
              // Center space for FAB
              const Expanded(child: SizedBox()),
              _NavItem(
                icon: Icons.notifications_none_rounded,
                activeIcon: Icons.notifications_rounded,
                label: 'Alerts',
                isActive: currentIndex == 2,
                onTap: () => onTap(2),
              ),
              _NavItem(
                icon: Icons.person_outline_rounded,
                activeIcon: Icons.person_rounded,
                label: 'Profile',
                isActive: currentIndex == 3,
                onTap: () => onTap(3),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  final IconData icon;
  final IconData activeIcon;
  final String label;
  final bool isActive;
  final VoidCallback onTap;

  const _NavItem({
    required this.icon,
    required this.activeIcon,
    required this.label,
    required this.isActive,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: isActive
                    ? AppColors.accentLight
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                isActive ? activeIcon : icon,
                color: isActive ? AppColors.primary : AppColors.textLight,
                size: 22,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
                color: isActive ? AppColors.primary : AppColors.textLight,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Notifications Page ────────────────────────────────────────────────────────
class _NotificationsPage extends StatelessWidget {
  const _NotificationsPage();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        automaticallyImplyLeading: false,
        title: const Text('Notifications',
            style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 20,
                color: AppColors.textDark)),
        elevation: 0,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: AppColors.border),
        ),
      ),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 90,
              height: 90,
              decoration: BoxDecoration(
                color: AppColors.accentLight,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.notifications_none_rounded,
                  size: 44, color: AppColors.accent),
            ),
            const SizedBox(height: 20),
            const Text('No notifications yet',
                style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textDark)),
            const SizedBox(height: 8),
            const Text(
              'You\'ll be notified when your\ncomplaint status changes',
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 14,
                  color: AppColors.textMid,
                  height: 1.5),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.accentLight,
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Text('FCM notifications — coming soon',
                  style: TextStyle(
                      fontSize: 12,
                      color: AppColors.accent,
                      fontWeight: FontWeight.w600)),
            ),
          ],
        ),
      ),
    );
  }
}


// ── Splash Screen ─────────────────────────────────────────────────────────────
class _SplashScreen extends StatelessWidget {
  const _SplashScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.primary,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 96,
              height: 96,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(24),
              ),
              child: const Icon(Icons.campaign_rounded,
                  color: Colors.white, size: 52),
            ),
            const SizedBox(height: 24),
            const Text('CampusVoice',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 30,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.5)),
            const SizedBox(height: 6),
            const Text('AIKTC',
                style: TextStyle(
                    color: Colors.white60,
                    fontSize: 13,
                    letterSpacing: 4,
                    fontWeight: FontWeight.w500)),
            const SizedBox(height: 48),
            const SizedBox(
              width: 28,
              height: 28,
              child: CircularProgressIndicator(
                  color: Colors.white, strokeWidth: 2.5),
            ),
          ],
        ),
      ),
    );
  }
}
