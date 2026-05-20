import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/theme/app_theme.dart';
import '../core/theme/theme_mode_controller.dart';
import '../features/auth/data/auth_providers.dart';
import '../features/auth/presentation/auth_screen.dart';
import '../features/dashboard/presentation/dashboard_screen.dart';

const _enableInAppDevTools = bool.fromEnvironment('ENABLE_IN_APP_DEV_TOOLS');

class CraneTaskApp extends ConsumerStatefulWidget {
  const CraneTaskApp({super.key});

  @override
  ConsumerState<CraneTaskApp> createState() => _CraneTaskAppState();
}

class _CraneTaskAppState extends ConsumerState<CraneTaskApp> {
  bool _devToolsOpen = false;
  bool _showPerformanceOverlay = false;
  bool _showRepaintRainbow = false;

  @override
  void dispose() {
    debugRepaintRainbowEnabled = false;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final authUserId = ref.watch(
      authStateProvider.select(
        (authState) => authState.when<AsyncValue<String?>>(
          data: (state) => AsyncValue.data(state.session?.user.id),
          loading: () => const AsyncValue.loading(),
          error: AsyncValue.error,
        ),
      ),
    );
    final themeMode = ref.watch(themeModeControllerProvider);
    debugRepaintRainbowEnabled =
        _enableInAppDevTools && !kReleaseMode && _showRepaintRainbow;

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      showPerformanceOverlay:
          _enableInAppDevTools &&
          !kReleaseMode &&
          !kIsWeb &&
          _showPerformanceOverlay,
      title: 'Noggin',
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: themeMode,
      builder:
          (context, child) =>
              _enableInAppDevTools
                  ? _DebugDevToolsOverlay(
                    open: _devToolsOpen,
                    showPerformanceOverlay: _showPerformanceOverlay,
                    showRepaintRainbow: _showRepaintRainbow,
                    onToggleOpen:
                        () => setState(() => _devToolsOpen = !_devToolsOpen),
                    onTogglePerformanceOverlay:
                        (value) =>
                            setState(() => _showPerformanceOverlay = value),
                    onToggleRepaintRainbow:
                        (value) => setState(() => _showRepaintRainbow = value),
                    child: child ?? const SizedBox.shrink(),
                  )
                  : child ?? const SizedBox.shrink(),
      home: authUserId.when(
        data:
            (userId) =>
                userId == null ? const AuthScreen() : const DashboardScreen(),
        loading: () => const _SplashScreen(),
        error: (error, _) => _AuthErrorScreen(message: '$error'),
      ),
    );
  }
}

class _DebugDevToolsOverlay extends StatelessWidget {
  const _DebugDevToolsOverlay({
    required this.child,
    required this.open,
    required this.showPerformanceOverlay,
    required this.showRepaintRainbow,
    required this.onToggleOpen,
    required this.onTogglePerformanceOverlay,
    required this.onToggleRepaintRainbow,
  });

  final Widget child;
  final bool open;
  final bool showPerformanceOverlay;
  final bool showRepaintRainbow;
  final VoidCallback onToggleOpen;
  final ValueChanged<bool> onTogglePerformanceOverlay;
  final ValueChanged<bool> onToggleRepaintRainbow;

  @override
  Widget build(BuildContext context) {
    if (kReleaseMode) {
      return child;
    }

    final colorScheme = Theme.of(context).colorScheme;
    final overlaySize = open ? const Size(230, 174) : const Size(72, 40);
    return Stack(
      children: [
        child,
        Positioned(
          top: 12,
          right: 12,
          width: overlaySize.width,
          height: overlaySize.height,
          child: Align(
            alignment: Alignment.topRight,
            child: Material(
              color: Colors.transparent,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisSize: MainAxisSize.min,
                children: [
                  FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.redAccent,
                      foregroundColor: Colors.white,
                      minimumSize: const Size(72, 40),
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    onPressed: onToggleOpen,
                    child: Text(open ? 'CLOSE' : 'DEV'),
                  ),
                  if (open) ...[
                    const SizedBox(height: 8),
                    DecoratedBox(
                      decoration: BoxDecoration(
                        color: colorScheme.surface,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: colorScheme.outlineVariant),
                        boxShadow: const [
                          BoxShadow(
                            color: Color(0x26000000),
                            blurRadius: 18,
                            offset: Offset(0, 8),
                          ),
                        ],
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(10),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'Dev tools',
                              style: Theme.of(context).textTheme.labelLarge
                                  ?.copyWith(fontWeight: FontWeight.w800),
                            ),
                            const SizedBox(height: 8),
                            FilterChip(
                              label: Text(
                                kIsWeb
                                    ? 'Performance overlay: app only'
                                    : 'Performance overlay',
                              ),
                              selected: !kIsWeb && showPerformanceOverlay,
                              onSelected:
                                  kIsWeb ? null : onTogglePerformanceOverlay,
                            ),
                            const SizedBox(height: 6),
                            FilterChip(
                              label: const Text('Repaint rainbow'),
                              selected: showRepaintRainbow,
                              onSelected: onToggleRepaintRainbow,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _SplashScreen extends StatelessWidget {
  const _SplashScreen();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(body: Center(child: CircularProgressIndicator()));
  }
}

class _AuthErrorScreen extends StatelessWidget {
  const _AuthErrorScreen({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(message, textAlign: TextAlign.center),
        ),
      ),
    );
  }
}
