import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:razorpay_flutter/razorpay_flutter.dart';

import 'core/api_config.dart';
import 'core/time_picker_helper.dart';
import 'screens/security_check_in_screen.dart';
import 'screens/security_check_out_screen.dart';
import 'screens/security_checked_out_history_screen.dart';
import 'screens/transaction_history_screen.dart';
import 'services/api_service.dart';
import 'services/notification_service.dart';
import 'state/auth_controller.dart';

final GlobalKey<NavigatorState> rootNavigatorKey = GlobalKey<NavigatorState>();

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  // Print centralized API diagnostics at startup
  ApiConfig.printStartupDiagnostics();

  runApp(ChangeNotifierProvider(
      create: (_) => AuthController(ApiService())..restore(),
      child: const SmartSocietyApp()));
  NotificationService.instance.initialize(navKey: rootNavigatorKey).catchError((e) {
    debugPrint('Notification initialization notice: $e');
  });
}


class SmartSocietyApp extends StatelessWidget {
  const SmartSocietyApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
      navigatorKey: rootNavigatorKey,
      title: 'Nivora',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(colorSchemeSeed: Colors.indigo, useMaterial3: true),
      home: const SessionGate());
}


class SessionGate extends StatelessWidget {
  const SessionGate({super.key});
  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthController>();
    if (auth.loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return auth.session == null
        ? const LoginScreen()
        : auth.session!.user.role == 'RESIDENT'
            ? const ResidentShell()
            : auth.session!.user.role == 'SECURITY'
                ? const SecurityShell()
                : auth.session!.user.role == 'ADMIN'
                    ? const AdminShell()
                    : RoleHome(role: auth.session!.user.role);
  }
}

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _form = GlobalKey<FormState>();
  final _loginInput = TextEditingController();
  final _password = TextEditingController();
  bool _submitting = false;
  bool _obscurePassword = true;
  bool _rememberMe = true;
  String _role = 'RESIDENT';

  static const _roles = {
    'RESIDENT': 'Resident',
    'ADMIN': 'Administrator',
    'STAFF': 'Society staff',
    'SECURITY': 'Security team',
  };

  @override
  void dispose() {
    _loginInput.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _submitting = true);
    await context.read<AuthController>().login(
          _loginInput.text.trim(),
          _password.text,
          requestedRole: _role,
          rememberMe: _rememberMe,
        );
    if (mounted) setState(() => _submitting = false);
  }

  Future<void> _forgotPassword() async {
    final email = TextEditingController(text: _loginInput.text.trim());
    final form = GlobalKey<FormState>();
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Reset your password'),
        content: Form(
          key: form,
          child: TextFormField(
            controller: email,
            keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(
              labelText: 'Account email',
              hintText: 'name@example.com',
            ),
            validator: (value) => value == null || !value.contains('@')
                ? 'Enter the email linked to your account'
                : null,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              if (!form.currentState!.validate()) return;
              final auth = context.read<AuthController>();
              final sent = await auth.requestPasswordReset(email.text.trim());
              if (!dialogContext.mounted || !mounted) return;
              if (sent) Navigator.pop(dialogContext);
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                content: Text(auth.message ??
                    auth.error ??
                    'Unable to request a password reset.'),
              ));
            },
            child: const Text('Send reset link'),
          ),
        ],
      ),
    );
    email.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthController>();
    final topPadding = MediaQuery.paddingOf(context).top;
    final bottomPadding = MediaQuery.paddingOf(context).bottom;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
        statusBarBrightness: Brightness.light,
        systemNavigationBarColor: Colors.white,
        systemNavigationBarIconBrightness: Brightness.dark,
      ),
      child: Scaffold(
        backgroundColor: const Color(0xFFF4F6F9),
        body: LayoutBuilder(
          builder: (context, constraints) {
            final isSmallScreen = constraints.maxHeight < 700;
            final heroHeight = topPadding + (isSmallScreen ? 140.0 : 165.0);
            final cardOverlap = isSmallScreen ? 20.0 : 28.0;

            return SingleChildScrollView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: Align(
                  alignment: Alignment.topCenter,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 440),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // ── Top Hero / Branding Section ─────────────────────
                        SizedBox(
                          height: heroHeight,
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              // 1. Background Visual
                              Image.asset(
                                'assets/images/hero_background.jpg',
                                fit: BoxFit.cover,
                                alignment: Alignment.topRight,
                                errorBuilder: (_, __, ___) => Container(
                                  decoration: const BoxDecoration(
                                    gradient: LinearGradient(
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight,
                                      colors: [
                                        Color(0xFFE9EDF5),
                                        Color(0xFFCBD6E6),
                                        Color(0xFF1E325C),
                                      ],
                                    ),
                                  ),
                                ),
                              ),

                              // 2. Gradient scrim to guarantee high contrast for left text
                              Container(
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    begin: Alignment.centerLeft,
                                    end: Alignment.centerRight,
                                    colors: [
                                      Colors.white.withValues(alpha: 0.96),
                                      Colors.white.withValues(alpha: 0.88),
                                      Colors.white.withValues(alpha: 0.22),
                                      Colors.transparent,
                                    ],
                                    stops: const [0.0, 0.44, 0.72, 1.0],
                                  ),
                                ),
                              ),

                              // 3. Subtle bottom fade into the card overlap area
                              Positioned(
                                bottom: 0,
                                left: 0,
                                right: 0,
                                height: 40,
                                child: Container(
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      begin: Alignment.topCenter,
                                      end: Alignment.bottomCenter,
                                      colors: [
                                        const Color(0xFFF4F6F9).withValues(alpha: 0.0),
                                        const Color(0xFFF4F6F9),
                                      ],
                                    ),
                                  ),
                                ),
                              ),

                              // 4. Branding Content
                              Positioned(
                                top: topPadding > 0 ? topPadding + 6 : 20,
                                left: 20,
                                right: 120,
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    // Logo mark
                                    Image.asset(
                                      'assets/images/nivora_logo_mark.png',
                                      height: isSmallScreen ? 34 : 40,
                                      fit: BoxFit.contain,
                                      errorBuilder: (_, __, ___) => const Icon(
                                        Icons.apartment_rounded,
                                        size: 34,
                                        color: Color(0xFF172A5A),
                                      ),
                                    ),
                                    const SizedBox(height: 3),

                                    // Wordmark
                                    Text(
                                      'Nivora',
                                      style: TextStyle(
                                        fontSize: isSmallScreen ? 25 : 28,
                                        fontWeight: FontWeight.w800,
                                        color: const Color(0xFF172A5A),
                                        letterSpacing: -0.5,
                                        height: 1.1,
                                      ),
                                    ),
                                    const SizedBox(height: 2),

                                    // Tagline
                                    Text(
                                      'Connected Community Living',
                                      style: TextStyle(
                                        fontSize: isSmallScreen ? 11.5 : 12.0,
                                        fontWeight: FontWeight.w600,
                                        color: const Color(0xFF2D478C),
                                        letterSpacing: 0.1,
                                      ),
                                    ),
                                    const SizedBox(height: 4),

                                    // Teal decorative accent
                                    Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Container(
                                          width: 24,
                                          height: 3,
                                          decoration: BoxDecoration(
                                            color: const Color(0xFF159A91),
                                            borderRadius: BorderRadius.circular(2),
                                          ),
                                        ),
                                        const SizedBox(width: 4),
                                        Container(
                                          width: 5,
                                          height: 3,
                                          decoration: BoxDecoration(
                                            color: const Color(0xFF159A91),
                                            borderRadius: BorderRadius.circular(2),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 5),

                                    // Pillars
                                    Text(
                                      'People  |  Safety  |  Services  |  Together',
                                      style: TextStyle(
                                        fontSize: isSmallScreen ? 9.5 : 10.0,
                                        fontWeight: FontWeight.w500,
                                        color: const Color(0xFF4A5A74),
                                        letterSpacing: 0.2,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),

                        // ── Main Login Card ──────────────────────────────────
                        Transform.translate(
                          offset: Offset(0, -cardOverlap),
                          child: Container(
                            margin: const EdgeInsets.symmetric(horizontal: 16),
                            padding: EdgeInsets.all(isSmallScreen ? 16 : 20),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(28),
                            border: Border.all(
                              color: const Color(0xFFEFF2F7),
                              width: 1.2,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: const Color(0xFF172A5A).withValues(alpha: 0.08),
                                blurRadius: 26,
                                offset: const Offset(0, 10),
                                spreadRadius: 0,
                              ),
                            ],
                          ),
                          child: Form(
                            key: _form,
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                // Card Header: Welcome back + Community Illustration
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            'Welcome back',
                                            style: TextStyle(
                                              fontSize: 23,
                                              fontWeight: FontWeight.w800,
                                              color: Color(0xFF172A5A),
                                              letterSpacing: -0.4,
                                            ),
                                          ),
                                          SizedBox(height: 3),
                                          Text(
                                            'Sign in to continue to Nivora',
                                            style: TextStyle(
                                              fontSize: 13,
                                              fontWeight: FontWeight.w500,
                                              color: Color(0xFF6B7C96),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Image.asset(
                                      'assets/images/community_illustration.png',
                                      width: 96,
                                      height: 60,
                                      fit: BoxFit.contain,
                                      errorBuilder: (_, __, ___) => const SizedBox(width: 96, height: 60),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 18),

                                // Field 1: Email or mobile number
                                TextFormField(
                                  controller: _loginInput,
                                  keyboardType: TextInputType.emailAddress,
                                  style: const TextStyle(
                                    fontSize: 14.5,
                                    color: Color(0xFF172A5A),
                                    fontWeight: FontWeight.w500,
                                  ),
                                  decoration: InputDecoration(
                                    hintText: 'Email or mobile number',
                                    hintStyle: const TextStyle(
                                      color: Color(0xFF94A3B8),
                                      fontSize: 14,
                                      fontWeight: FontWeight.w400,
                                    ),
                                    prefixIcon: const Icon(
                                      Icons.person_outline_rounded,
                                      color: Color(0xFF8A99AD),
                                      size: 22,
                                    ),
                                    filled: true,
                                    fillColor: const Color(0xFFFAFBFC),
                                    contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 16,
                                      vertical: 14,
                                    ),
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(14),
                                      borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                                    ),
                                    enabledBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(14),
                                      borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                                    ),
                                    focusedBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(14),
                                      borderSide: const BorderSide(color: Color(0xFF2D478C), width: 1.5),
                                    ),
                                  ),
                                  validator: (value) => value == null || value.trim().isEmpty
                                      ? 'Enter your email or mobile number'
                                      : null,
                                ),
                                const SizedBox(height: 14),

                                // Field 2: Sign in as (Role Selector)
                                DropdownButtonFormField<String>(
                                  initialValue: _role,
                                  isExpanded: true,
                                  icon: const Icon(
                                    Icons.keyboard_arrow_down_rounded,
                                    color: Color(0xFF172A5A),
                                  ),
                                  decoration: InputDecoration(
                                    labelText: 'Sign in as',
                                    labelStyle: const TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w500,
                                      color: Color(0xFF8A99AD),
                                    ),
                                    floatingLabelBehavior: FloatingLabelBehavior.always,
                                    prefixIcon: const Icon(
                                      Icons.groups_outlined,
                                      color: Color(0xFF8A99AD),
                                      size: 22,
                                    ),
                                    filled: true,
                                    fillColor: const Color(0xFFFAFBFC),
                                    contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 16,
                                      vertical: 12,
                                    ),
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(14),
                                      borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                                    ),
                                    enabledBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(14),
                                      borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                                    ),
                                    focusedBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(14),
                                      borderSide: const BorderSide(color: Color(0xFF2D478C), width: 1.5),
                                    ),
                                  ),
                                  items: _roles.entries.map((entry) {
                                    return DropdownMenuItem(
                                      value: entry.key,
                                      child: Text(
                                        entry.value,
                                        style: const TextStyle(
                                          fontSize: 14.5,
                                          fontWeight: FontWeight.w700,
                                          color: Color(0xFF172A5A),
                                        ),
                                      ),
                                    );
                                  }).toList(),
                                  onChanged: (value) => setState(() => _role = value ?? _role),
                                ),                                const SizedBox(height: 14),

                                // Field 3: Password
                                TextFormField(
                                  controller: _password,
                                  obscureText: _obscurePassword,
                                  style: const TextStyle(
                                    fontSize: 14.5,
                                    color: Color(0xFF172A5A),
                                    fontWeight: FontWeight.w500,
                                  ),
                                  decoration: InputDecoration(
                                    hintText: 'Password',
                                    hintStyle: const TextStyle(
                                      color: Color(0xFF94A3B8),
                                      fontSize: 14,
                                      fontWeight: FontWeight.w400,
                                    ),
                                    prefixIcon: const Icon(
                                      Icons.lock_outline_rounded,
                                      color: Color(0xFF8A99AD),
                                      size: 22,
                                    ),
                                    suffixIcon: IconButton(
                                      tooltip: _obscurePassword ? 'Show password' : 'Hide password',
                                      icon: Icon(
                                        _obscurePassword
                                            ? Icons.visibility_outlined
                                            : Icons.visibility_off_outlined,
                                        color: const Color(0xFF8A99AD),
                                        size: 20,
                                      ),
                                      onPressed: () => setState(
                                        () => _obscurePassword = !_obscurePassword,
                                      ),
                                    ),
                                    filled: true,
                                    fillColor: const Color(0xFFFAFBFC),
                                    contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 16,
                                      vertical: 14,
                                    ),
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(14),
                                      borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                                    ),
                                    enabledBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(14),
                                      borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                                    ),
                                    focusedBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(14),
                                      borderSide: const BorderSide(color: Color(0xFF2D478C), width: 1.5),
                                    ),
                                  ),
                                  validator: (value) => value == null || value.length < 8
                                      ? 'Password must be at least 8 characters'
                                      : null,
                                ),
                                const SizedBox(height: 12),

                                // Remember Me & Forgot Password Row
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Expanded(
                                      child: GestureDetector(
                                        onTap: () => setState(() => _rememberMe = !_rememberMe),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            SizedBox(
                                              width: 20,
                                              height: 20,
                                              child: Checkbox(
                                                value: _rememberMe,
                                                activeColor: const Color(0xFF172A5A),
                                                checkColor: Colors.white,
                                                shape: RoundedRectangleBorder(
                                                  borderRadius: BorderRadius.circular(4),
                                                ),
                                                side: const BorderSide(
                                                  color: Color(0xFFB0BDD0),
                                                  width: 1.5,
                                                ),
                                                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                                visualDensity: VisualDensity.compact,
                                                onChanged: (val) =>
                                                    setState(() => _rememberMe = val ?? true),
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            const Flexible(
                                              child: Text(
                                                'Remember me',
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: TextStyle(
                                                  fontSize: 13,
                                                  fontWeight: FontWeight.w600,
                                                  color: Color(0xFF172A5A),
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                    TextButton(
                                      onPressed: _forgotPassword,
                                      style: TextButton.styleFrom(
                                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                                        minimumSize: Size.zero,
                                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                        visualDensity: VisualDensity.compact,
                                      ),
                                      child: const Text(
                                        'Forgot password?',
                                        style: TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w600,
                                          color: Color(0xFF2D478C),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),

                                // Auth Error message display
                                if (auth.error != null)
                                  Container(
                                    margin: const EdgeInsets.only(top: 10),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 8,
                                    ),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFFEF2F2),
                                      borderRadius: BorderRadius.circular(10),
                                      border: Border.all(color: const Color(0xFFFCA5A5)),
                                    ),
                                    child: Row(
                                      children: [
                                        const Icon(
                                          Icons.error_outline_rounded,
                                          size: 16,
                                          color: Color(0xFFDC2626),
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Text(
                                            auth.error!,
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                              color: Color(0xFFDC2626),
                                              fontSize: 12,
                                              fontWeight: FontWeight.w500,
                                              height: 1.25,
                                            ),
                                          ),
                                        ),
                                        if (auth.error!.contains('START_ANDROID') ||
                                            auth.error!.contains('API_BASE_URL') ||
                                            auth.error!.contains('not configured'))
                                          IconButton(
                                            tooltip: 'Configuration Help',
                                            icon: const Icon(
                                              Icons.help_outline_rounded,
                                              size: 16,
                                              color: Color(0xFFDC2626),
                                            ),
                                            padding: EdgeInsets.zero,
                                            constraints: const BoxConstraints(
                                              minWidth: 24,
                                              minHeight: 24,
                                            ),
                                            visualDensity: VisualDensity.compact,
                                            onPressed: () {
                                              showDialog<void>(
                                                context: context,
                                                builder: (ctx) => AlertDialog(
                                                  title: const Text('API Configuration'),
                                                  content: Text(ApiConfig.configurationError),
                                                  actions: [
                                                    TextButton(
                                                      onPressed: () => Navigator.pop(ctx),
                                                      child: const Text('Close'),
                                                    ),
                                                  ],
                                                ),
                                              );
                                            },
                                          ),
                                        IconButton(
                                          tooltip: 'Dismiss',
                                          icon: const Icon(
                                            Icons.close_rounded,
                                            size: 16,
                                            color: Color(0xFFDC2626),
                                          ),
                                          padding: EdgeInsets.zero,
                                          constraints: const BoxConstraints(
                                            minWidth: 24,
                                            minHeight: 24,
                                          ),
                                          visualDensity: VisualDensity.compact,
                                          onPressed: () =>
                                              context.read<AuthController>().clearError(),
                                        ),
                                      ],
                                    ),
                                  ),
                                const SizedBox(height: 18),

                                // Primary Sign-in Button
                                SizedBox(
                                  width: double.infinity,
                                  height: 52,
                                  child: ElevatedButton(
                                    onPressed: _submitting ? null : _login,
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: const Color(0xFF172A5A),
                                      foregroundColor: Colors.white,
                                      elevation: 2,
                                      shadowColor: const Color(0xFF172A5A).withValues(alpha: 0.35),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(26),
                                      ),
                                    ),
                                    child: _submitting
                                        ? const SizedBox(
                                            width: 22,
                                            height: 22,
                                            child: CircularProgressIndicator(
                                              color: Colors.white,
                                              strokeWidth: 2.2,
                                            ),
                                          )
                                        : Stack(
                                            alignment: Alignment.center,
                                            children: [
                                              const Row(
                                                mainAxisAlignment: MainAxisAlignment.center,
                                                children: [
                                                  Text(
                                                    'Sign in',
                                                    style: TextStyle(
                                                      fontSize: 16,
                                                      fontWeight: FontWeight.w700,
                                                      color: Colors.white,
                                                      letterSpacing: 0.2,
                                                    ),
                                                  ),
                                                  SizedBox(width: 8),
                                                  Icon(
                                                    Icons.arrow_forward_rounded,
                                                    size: 18,
                                                    color: Colors.white,
                                                  ),
                                                ],
                                              ),
                                              Positioned(
                                                right: 0,
                                                child: Container(
                                                  width: 36,
                                                  height: 36,
                                                  decoration: BoxDecoration(
                                                    shape: BoxShape.circle,
                                                    color: Colors.white.withValues(alpha: 0.12),
                                                  ),
                                                  child: const Icon(
                                                    Icons.arrow_forward_rounded,
                                                    size: 16,
                                                    color: Colors.white,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                  ),
                                ),
                                const SizedBox(height: 18),

                                // Divider: "New to Nivora?"
                                const Row(
                                  children: [
                                    Expanded(
                                      child: Divider(
                                        color: Color(0xFFE2E8F0),
                                        thickness: 1,
                                      ),
                                    ),
                                    Padding(
                                      padding: EdgeInsets.symmetric(horizontal: 12),
                                      child: Text(
                                        'New to Nivora?',
                                        style: TextStyle(
                                          fontSize: 12.5,
                                          fontWeight: FontWeight.w500,
                                          color: Color(0xFF8A99AD),
                                        ),
                                      ),
                                    ),
                                    Expanded(
                                      child: Divider(
                                        color: Color(0xFFE2E8F0),
                                        thickness: 1,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 14),

                                // Create an account Outlined Button
                                SizedBox(
                                  width: double.infinity,
                                  height: 48,
                                  child: OutlinedButton(
                                    onPressed: _submitting
                                        ? null
                                        : () => Navigator.of(context).push(
                                              MaterialPageRoute(
                                                builder: (_) => const SignUpScreen(),
                                              ),
                                            ),
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: const Color(0xFF172A5A),
                                      side: const BorderSide(
                                        color: Color(0xFFC7D3E3),
                                        width: 1.2,
                                      ),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(14),
                                      ),
                                      backgroundColor: Colors.white,
                                    ),
                                    child: const Row(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        Icon(
                                          Icons.person_add_alt_1_outlined,
                                          color: Color(0xFF172A5A),
                                          size: 20,
                                        ),
                                        SizedBox(width: 8),
                                        Text(
                                          'Create an account',
                                          style: TextStyle(
                                            fontSize: 14.5,
                                            fontWeight: FontWeight.w700,
                                            color: Color(0xFF172A5A),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 10),

                                // Administrator account creation note
                                const Text(
                                  'Administrator accounts are created only by the society.',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: Color(0xFF94A3B8),
                                    fontSize: 11,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),

                      // ── Bottom Feature Highlights ────────────────────────
                      Transform.translate(
                        offset: Offset(0, -cardOverlap + 12),
                        child: Padding(
                          padding: EdgeInsets.fromLTRB(
                            14,
                            0,
                            14,
                            bottomPadding > 0 ? bottomPadding + 8 : 20,
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: _buildFeatureItem(
                                  icon: Icons.shield_outlined,
                                  iconColor: const Color(0xFF159A91),
                                  bgColor: const Color(0xFFE3F6F3),
                                  title: 'Secure',
                                  subtitle: 'Community Access',
                                ),
                              ),
                              _buildFeatureDivider(),
                              Expanded(
                                child: _buildFeatureItem(
                                  icon: Icons.groups_outlined,
                                  iconColor: const Color(0xFF2D478C),
                                  bgColor: const Color(0xFFEBF1FD),
                                  title: 'Simpler',
                                  subtitle: 'Visitor Management',
                                ),
                              ),
                              _buildFeatureDivider(),
                              Expanded(
                                child: _buildFeatureItem(
                                  icon: Icons.settings_suggest_outlined,
                                  iconColor: const Color(0xFF1A9E75),
                                  bgColor: const Color(0xFFE4F5EE),
                                  title: 'Easier',
                                  subtitle: 'Maintenance & Payments',
                                ),
                              ),
                              _buildFeatureDivider(),
                              Expanded(
                                child: _buildFeatureItem(
                                  icon: Icons.notifications_none_rounded,
                                  iconColor: const Color(0xFFD97706),
                                  bgColor: const Color(0xFFFEF3E6),
                                  title: 'Stay Connected',
                                  subtitle: 'Important Updates',
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    ),
  );
}

  Widget _buildFeatureItem({
    required IconData icon,
    required Color iconColor,
    required Color bgColor,
    required String title,
    required String subtitle,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: iconColor, size: 20),
        ),
        const SizedBox(height: 6),
        Text(
          title,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w700,
            color: Color(0xFF172A5A),
          ),
        ),
        const SizedBox(height: 2),
        Text(
          subtitle,
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontSize: 9.5,
            fontWeight: FontWeight.w400,
            color: Color(0xFF6B7C96),
            height: 1.15,
          ),
        ),
      ],
    );
  }

  Widget _buildFeatureDivider() {
    return Container(
      width: 1,
      height: 32,
      margin: const EdgeInsets.symmetric(horizontal: 4),
      color: const Color(0xFFE2E8F0).withValues(alpha: 0.8),
    );
  }
}

class SignUpScreen extends StatefulWidget {
  const SignUpScreen({super.key});

  @override
  State<SignUpScreen> createState() => _SignUpScreenState();
}

class _SignUpScreenState extends State<SignUpScreen> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _phone = TextEditingController();
  final _password = TextEditingController();
  final _confirmPassword = TextEditingController();
  final _flatNumber = TextEditingController();
  final _building = TextEditingController();
  final _emergencyContact = TextEditingController();
  final _designation = TextEditingController();
  final _employeeId = TextEditingController();
  String _role = 'RESIDENT';
  String _relation = 'TENANT';
  String _gender = 'PREFER_NOT_TO_SAY';
  String _shift = 'ROTATING';
  DateTime? _dateOfBirth;
  DateTime? _joiningDate;
  bool _submitting = false;

  static const _roles = {
    'RESIDENT': 'Resident',
    'STAFF': 'Society staff',
    'SECURITY': 'Security team'
  };

  @override
  void dispose() {
    for (final controller in [
      _name,
      _email,
      _phone,
      _password,
      _confirmPassword,
      _flatNumber,
      _building,
      _emergencyContact,
      _designation,
      _employeeId,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  String _isoDate(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';

  String _displayDate(DateTime? value) => value == null
      ? 'Choose date'
      : '${value.day.toString().padLeft(2, '0')}/${value.month.toString().padLeft(2, '0')}/${value.year}';

  Future<void> _pickDate({required bool joining}) async {
    final now = DateTime.now();
    final selected = await showDatePicker(
      context: context,
      initialDate: joining
          ? (_joiningDate ?? now)
          : (_dateOfBirth ?? DateTime(now.year - 25)),
      firstDate: joining ? DateTime(2000) : DateTime(1900),
      lastDate: now,
      helpText: joining ? 'Select joining date' : 'Select date of birth',
    );
    if (selected != null && mounted) {
      setState(() {
        if (joining) {
          _joiningDate = selected;
        } else {
          _dateOfBirth = selected;
        }
      });
    }
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    if ((_role == 'STAFF' || _role == 'SECURITY') && _joiningDate == null) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Choose your joining date.')));
      return;
    }
    setState(() => _submitting = true);
    final payload = <String, dynamic>{
      'role': _role,
      'name': _name.text.trim(),
      'email': _email.text.trim(),
      'phone': _phone.text.trim(),
      'password': _password.text,
      'password_confirmation': _confirmPassword.text,
      'emergency_contact': _emergencyContact.text.trim().isEmpty
          ? null
          : _emergencyContact.text.trim(),
      if (_dateOfBirth != null) 'date_of_birth': _isoDate(_dateOfBirth!),
      if (_role == 'RESIDENT') ...{
        'flat_number': _flatNumber.text.trim(),
        'building': _building.text.trim(),
        'relation_to_owner': _relation,
        'gender': _gender,
      },
      if (_role == 'STAFF') ...{
        'designation': _designation.text.trim(),
        'joining_date': _isoDate(_joiningDate!),
      },
      if (_role == 'SECURITY') ...{
        'employee_id': _employeeId.text.trim(),
        'joining_date': _isoDate(_joiningDate!),
        'shift': _shift,
      },
    };
    final success = await context.read<AuthController>().register(payload);
    if (!mounted) return;
    setState(() => _submitting = false);
    final auth = context.read<AuthController>();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(auth.message ?? auth.error ?? 'Unable to register.'),
    ));
    if (success) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final isResident = _role == 'RESIDENT';
    final isStaff = _role == 'STAFF';
    final isSecurity = _role == 'SECURITY';
    return Scaffold(
      appBar: AppBar(title: const Text('Create your account')),
      body: SafeArea(
        child: Form(
          key: _form,
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              const Text(
                'Choose your account type and provide the information needed by your society.',
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                initialValue: _role,
                decoration: const InputDecoration(
                    labelText: 'Account type', border: OutlineInputBorder()),
                items: _roles.entries
                    .map((entry) => DropdownMenuItem(
                        value: entry.key, child: Text(entry.value)))
                    .toList(),
                onChanged: (value) => setState(() => _role = value ?? _role),
              ),
              const SizedBox(height: 16),
              _requiredField(_name, 'Full name'),
              const SizedBox(height: 12),
              _requiredField(_email, 'Email address',
                  keyboardType: TextInputType.emailAddress,
                  validator: (value) => value == null || !value.contains('@')
                      ? 'Enter a valid email'
                      : null),
              const SizedBox(height: 12),
              _requiredField(_phone, 'Mobile number',
                  keyboardType: TextInputType.phone,
                  validator: (value) => value == null ||
                          !RegExp(r'^(?:\+91|91)?[6-9][0-9]{9}$')
                              .hasMatch(value.trim())
                      ? 'Enter a valid 10-digit Indian mobile number'
                      : null),

              const SizedBox(height: 12),
              _requiredField(_password, 'Password',
                  obscure: true,
                  validator: (value) => value == null || value.length < 8
                      ? 'Use at least 8 characters'
                      : null),
              const SizedBox(height: 12),
              _requiredField(_confirmPassword, 'Confirm password',
                  obscure: true,
                  validator: (value) => value != _password.text
                      ? 'Passwords do not match'
                      : null),
              const SizedBox(height: 12),
              _optionalField(_emergencyContact, 'Emergency contact',
                  keyboardType: TextInputType.phone),
              if (isResident) ...[
                const Divider(height: 32),
                Text('Residence details',
                    style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 12),
                _requiredField(_flatNumber, 'Flat number'),
                const SizedBox(height: 12),
                _requiredField(_building, 'Building / block'),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: _relation,
                  decoration: const InputDecoration(
                      labelText: 'Relationship to flat',
                      border: OutlineInputBorder()),
                  items: const [
                    DropdownMenuItem(value: 'OWNER', child: Text('Owner')),
                    DropdownMenuItem(value: 'TENANT', child: Text('Tenant')),
                    DropdownMenuItem(
                        value: 'FAMILY_MEMBER', child: Text('Family member')),
                  ],
                  onChanged: (value) =>
                      setState(() => _relation = value ?? _relation),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: _gender,
                  decoration: const InputDecoration(
                      labelText: 'Gender (optional)',
                      border: OutlineInputBorder()),
                  items: const [
                    DropdownMenuItem(value: 'MALE', child: Text('Male')),
                    DropdownMenuItem(value: 'FEMALE', child: Text('Female')),
                    DropdownMenuItem(
                        value: 'NON_BINARY', child: Text('Non-binary')),
                    DropdownMenuItem(
                        value: 'PREFER_NOT_TO_SAY',
                        child: Text('Prefer not to say')),
                  ],
                  onChanged: (value) =>
                      setState(() => _gender = value ?? _gender),
                ),
                const SizedBox(height: 12),
                _dateButton(
                    'Date of birth (optional)',
                    _displayDate(_dateOfBirth),
                    () => _pickDate(joining: false)),
              ],
              if (isStaff || isSecurity) ...[
                const Divider(height: 32),
                Text('Work details',
                    style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 12),
                if (isStaff) _requiredField(_designation, 'Designation'),
                if (isSecurity) ...[
                  _requiredField(_employeeId, 'Employee ID'),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: _shift,
                    decoration: const InputDecoration(
                        labelText: 'Shift', border: OutlineInputBorder()),
                    items: const [
                      DropdownMenuItem(
                          value: 'MORNING', child: Text('Morning')),
                      DropdownMenuItem(
                          value: 'EVENING', child: Text('Evening')),
                      DropdownMenuItem(value: 'NIGHT', child: Text('Night')),
                      DropdownMenuItem(
                          value: 'ROTATING', child: Text('Rotating')),
                    ],
                    onChanged: (value) =>
                        setState(() => _shift = value ?? _shift),
                  ),
                ],
                const SizedBox(height: 12),
                _dateButton('Joining date', _displayDate(_joiningDate),
                    () => _pickDate(joining: true)),
              ],
              const SizedBox(height: 24),
              FilledButton(
                onPressed: _submitting ? null : _submit,
                child: _submitting
                    ? const CircularProgressIndicator()
                    : const Text('Submit registration'),
              ),
              if (isStaff || isSecurity)
                const Padding(
                  padding: EdgeInsets.only(top: 12),
                  child: Text(
                    'Staff and security accounts require administrator activation before sign-in.',
                    textAlign: TextAlign.center,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _requiredField(
    TextEditingController controller,
    String label, {
    TextInputType? keyboardType,
    bool obscure = false,
    String? Function(String?)? validator,
  }) =>
      TextFormField(
        controller: controller,
        keyboardType: keyboardType,
        obscureText: obscure,
        decoration: InputDecoration(
            labelText: label, border: const OutlineInputBorder()),
        validator: validator ??
            (value) => value == null || value.trim().isEmpty
                ? '$label is required'
                : null,
      );

  Widget _optionalField(
    TextEditingController controller,
    String label, {
    TextInputType? keyboardType,
  }) =>
      TextFormField(
        controller: controller,
        keyboardType: keyboardType,
        decoration: InputDecoration(
            labelText: label, border: const OutlineInputBorder()),
      );

  Widget _dateButton(String label, String value, VoidCallback onTap) =>
      OutlinedButton.icon(
        onPressed: onTap,
        icon: const Icon(Icons.calendar_today_outlined),
        label: Align(
          alignment: Alignment.centerLeft,
          child: Text('$label: $value'),
        ),
      );
}

class RoleHome extends StatelessWidget {
  const RoleHome({super.key, required this.role});
  final String role;
  @override
  Widget build(BuildContext context) {
    final pages = role == 'SECURITY'
        ? const [
            'Dashboard',
            'Profile',
            'Visitors',
            'Parcels',
            'Notices',
            'Messages',
            'Notifications'
          ]
        : role == 'STAFF'
            ? const [
                'Dashboard',
                'Profile',
                'Complaints',
                'Parcels',
                'Notices',
                'Messages',
                'Notifications'
              ]
            : role == 'ADMIN'
                ? const [
                    'Dashboard',
                    'Profile',
                    'Residents',
                    'Flats',
                    'Visitors',
                    'Maintenance',
                    'Payments',
                    'Reports',
                    'Complaints',
                    'Notices',
                    'Staff',
                    'Parking',
                    'Parcels',
                    'Amenities',
                    'Bookings',
                    'Messages',
                    'Notifications'
                  ]
                : const [
                    'Profile',
                    'Visitors',
                    'Maintenance',
                    'Payments',
                    'Complaints',
                    'Notices',
                    'Parking',
                    'Amenities',
                    'Bookings',
                    'Messages',
                    'Notifications'
                  ];
    return Scaffold(
        appBar: AppBar(
            title: Text(role == 'ADMIN'
                ? 'Administration'
                : role == 'SECURITY'
                    ? 'Gate Management'
                    : role == 'STAFF'
                        ? 'Staff workspace'
                        : 'Resident Portal'),
            actions: [
              NotificationBell(role: role),
              IconButton(
                  icon: const Icon(Icons.logout),
                  onPressed: () => context.read<AuthController>().logout())
            ]),
        body: ListView(padding: const EdgeInsets.all(16), children: [
          Text('Welcome, ${context.read<AuthController>().session!.user.name}',
              style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 16),
          for (final page in pages)
            Card(
                child: ListTile(
                    leading: const Icon(Icons.chevron_right),
                    title: Text(page),
                    onTap: () => Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => page == 'Profile'
                            ? const AccountProfileScreen()
                            : role == 'ADMIN' && page == 'Reports'
                                ? const AdminReportsScreen()
                                : page == 'Dashboard' &&
                                        const {'ADMIN', 'STAFF', 'SECURITY'}
                                            .contains(role)
                                    ? RoleDashboardScreen(role: role)
                                    : role == 'ADMIN' && page == 'Payments'
                                        ? const AdminPaymentsScreen()
                                        : ModuleScreen(
                                            title: page, role: role)))))
        ]));
  }
}

class RoleDashboardScreen extends StatefulWidget {
  const RoleDashboardScreen({super.key, required this.role});
  final String role;

  @override
  State<RoleDashboardScreen> createState() => _RoleDashboardScreenState();
}

class AdminReportsScreen extends StatefulWidget {
  const AdminReportsScreen({super.key});

  @override
  State<AdminReportsScreen> createState() => _AdminReportsScreenState();
}

class _AdminReportsScreenState extends State<AdminReportsScreen> {
  static const _ranges = {
    'TODAY': 'Today',
    'THIS_WEEK': 'This week',
    'THIS_MONTH': 'This month',
    'LAST_MONTH': 'Last month',
    'THIS_YEAR': 'This year',
    'CUSTOM': 'Custom date range',
  };

  String _range = 'THIS_MONTH';
  DateTimeRange? _customRange;
  Map<String, dynamic>? _report;
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  String _date(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';

  Future<void> _load() async {
    if (_range == 'CUSTOM' && _customRange == null) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    final query = <String, String>{'range': _range};
    if (_customRange != null && _range == 'CUSTOM') {
      query['date_from'] = _date(_customRange!.start);
      query['date_to'] = _date(_customRange!.end);
    }
    try {
      final path =
          'admin/reports?${query.entries.map((entry) => '${Uri.encodeQueryComponent(entry.key)}=${Uri.encodeQueryComponent(entry.value)}').join('&')}';
      final result = await context.read<AuthController>().api.get(path);
      _report = Map<String, dynamic>.from(result['data'] as Map);
    } on ApiException catch (error) {
      _error = error.message;
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _selectCustomRange() async {
    final now = DateTime.now();
    final selected = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime(now.year + 1),
      initialDateRange: _customRange ??
          DateTimeRange(
              start: now.subtract(const Duration(days: 30)), end: now),
      helpText: 'Select report dates',
    );
    if (selected != null && mounted) {
      setState(() => _customRange = selected);
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading && _report == null) {
      return Scaffold(
          appBar: AppBar(title: const Text('Society reports')),
          body: const Center(child: CircularProgressIndicator()));
    }
    if (_error != null && _report == null) {
      return Scaffold(
          appBar: AppBar(title: const Text('Society reports')),
          body: _ErrorState(message: _error!, onRetry: _load));
    }
    final report = _report!;
    final maintenance = Map<String, dynamic>.from(report['maintenance'] as Map);
    final complaints = Map<String, dynamic>.from(report['complaints'] as Map);
    final visitors = Map<String, dynamic>.from(report['visitors'] as Map);
    final occupancy = Map<String, dynamic>.from(report['occupancy'] as Map);
    final parking = Map<String, dynamic>.from(report['parking'] as Map);
    final staff = Map<String, dynamic>.from(report['staff'] as Map);
    final collection = report['collection_by_day'] is List
        ? List<dynamic>.from(report['collection_by_day'] as List)
        : const <dynamic>[];
    final rangeData = Map<String, dynamic>.from(report['range'] as Map);
    return Scaffold(
      appBar: AppBar(title: const Text('Society reports')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
          children: [
            DropdownButtonFormField<String>(
              initialValue: _range,
              decoration: const InputDecoration(
                  labelText: 'Report period', border: OutlineInputBorder()),
              items: _ranges.entries
                  .map((entry) => DropdownMenuItem(
                      value: entry.key, child: Text(entry.value)))
                  .toList(),
              onChanged: (value) {
                setState(() => _range = value ?? _range);
                if (_range == 'CUSTOM') {
                  _selectCustomRange();
                } else {
                  _load();
                }
              },
            ),
            if (_range == 'CUSTOM')
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: OutlinedButton.icon(
                  onPressed: _selectCustomRange,
                  icon: const Icon(Icons.date_range_outlined),
                  label: Text(_customRange == null
                      ? 'Choose custom range'
                      : '${_date(_customRange!.start)} to ${_date(_customRange!.end)}'),
                ),
              ),
            const SizedBox(height: 12),
            Text(rangeData['label']?.toString() ?? '',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 16),
            _ReportSection(
              title: 'Maintenance collection',
              metrics: [
                ('Collected', _money(maintenance['collection']), Colors.green),
                (
                  'Payments',
                  maintenance['payments_received']?.toString() ?? '0',
                  Colors.blue
                ),
                (
                  'Pending due',
                  _money(maintenance['pending_amount']),
                  Colors.orange
                ),
                (
                  'Bills generated',
                  maintenance['bills_generated']?.toString() ?? '0',
                  Colors.indigo
                ),
              ],
            ),
            _ReportSection(
              title: 'Operations',
              metrics: [
                (
                  'Open complaints',
                  complaints['open']?.toString() ?? '0',
                  Colors.red
                ),
                (
                  'Resolved',
                  complaints['resolved']?.toString() ?? '0',
                  Colors.green
                ),
                (
                  'Visitors',
                  visitors['registered']?.toString() ?? '0',
                  Colors.purple
                ),
                (
                  'Checked in',
                  visitors['entered']?.toString() ?? '0',
                  Colors.teal
                ),
              ],
            ),
            _ReportSection(
              title: 'Society capacity',
              metrics: [
                (
                  'Occupied flats',
                  occupancy['occupied_flats']?.toString() ?? '0',
                  Colors.indigo
                ),
                (
                  'Vacant flats',
                  occupancy['vacant_flats']?.toString() ?? '0',
                  Colors.orange
                ),
                (
                  'Parking available',
                  parking['available_slots']?.toString() ?? '0',
                  Colors.green
                ),
                (
                  'Active staff',
                  staff['active']?.toString() ?? '0',
                  Colors.cyan
                ),
              ],
            ),
            const _SectionHeader(title: 'Collection by day'),
            if (collection.isEmpty)
              const _EmptyCard(
                  message: 'No verified payment collection in this period.')
            else
              ...collection.map((raw) {
                final item = Map<String, dynamic>.from(raw as Map);
                return _InfoCard(
                  icon: Icons.show_chart_outlined,
                  title: _money(item['amount']),
                  subtitle: item['date']?.toString() ?? '',
                );
              }),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(_error!,
                    style:
                        TextStyle(color: Theme.of(context).colorScheme.error)),
              ),
          ],
        ),
      ),
    );
  }
}

class _ReportSection extends StatelessWidget {
  const _ReportSection({required this.title, required this.metrics});
  final String title;
  final List<(String, String, Color)> metrics;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionHeader(title: title),
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            childAspectRatio: 1.8,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            children: metrics
                .map((metric) => _DashboardMetricTile(
                    metric: _DashboardMetric(metric.$1, metric.$2,
                        Icons.bar_chart_outlined, metric.$3)))
                .toList(),
          ),
          const SizedBox(height: 22),
        ],
      );
}

class _RoleDashboardScreenState extends State<RoleDashboardScreen> {
  Map<String, dynamic>? _data;
  String? _error;
  bool _loading = true;

  String get _endpoint => switch (widget.role) {
        'ADMIN' => 'admin/dashboard',
        'STAFF' => 'staff/dashboard',
        'SECURITY' => 'security/dashboard',
        _ => 'resident/dashboard',
      };

  String get _title => switch (widget.role) {
        'ADMIN' => 'Admin dashboard',
        'STAFF' => 'Staff dashboard',
        'SECURITY' => 'Security dashboard',
        _ => 'Dashboard',
      };

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await context.read<AuthController>().api.get(_endpoint);
      _data = Map<String, dynamic>.from(result['data'] as Map);
    } on ApiException catch (error) {
      _error = error.message;
    }
    if (mounted) setState(() => _loading = false);
  }

  void _open(String page) {
    Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => page == 'Payments' && widget.role == 'ADMIN'
            ? const AdminPaymentsScreen()
            : ModuleScreen(title: page, role: widget.role)));
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
          appBar: AppBar(title: Text(_title)),
          body: const Center(child: CircularProgressIndicator()));
    }
    if (_error != null) {
      return Scaffold(
          appBar: AppBar(title: Text(_title)),
          body: _ErrorState(message: _error!, onRetry: _load));
    }
    final data = _data!;
    final name = context.read<AuthController>().session!.user.name;
    final metrics = switch (widget.role) {
      'ADMIN' => [
          _DashboardMetric('Residents', data['total_residents'],
              Icons.people_outline, Colors.indigo),
          _DashboardMetric('Flats', data['total_flats'],
              Icons.apartment_outlined, Colors.blue),
          _DashboardMetric('Occupied', data['occupied_flats'],
              Icons.home_work_outlined, Colors.teal),
          _DashboardMetric('Vacant', data['vacant_flats'],
              Icons.meeting_room_outlined, Colors.orange),
          _DashboardMetric('Maintenance due', data['pending_maintenance_bills'],
              Icons.receipt_long_outlined, Colors.deepOrange),
          _DashboardMetric(
              'Collected',
              _money(data['total_collected_maintenance']),
              Icons.account_balance_wallet_outlined,
              Colors.green),
          _DashboardMetric('Open complaints', data['open_complaints'],
              Icons.support_agent_outlined, Colors.red),
          _DashboardMetric('Visitors today', data['today_visitors'],
              Icons.badge_outlined, Colors.purple),
          _DashboardMetric('Active staff', data['active_staff'],
              Icons.groups_outlined, Colors.cyan),
          _DashboardMetric('Parcels waiting', data['parcels_pending_pickup'],
              Icons.inventory_2_outlined, Colors.brown),
        ],
      'STAFF' => [
          _DashboardMetric('Assigned tasks', data['assigned_tasks'],
              Icons.assignment_outlined, Colors.indigo),
          _DashboardMetric('Pending', data['pending_tasks'],
              Icons.pending_actions_outlined, Colors.orange),
          _DashboardMetric('Completed', data['completed_tasks'],
              Icons.task_alt_outlined, Colors.green),
        ],
      _ => [
          _DashboardMetric('Expected visitors', data['expected_visitors'],
              Icons.event_available_outlined, Colors.indigo),
          _DashboardMetric('Waiting approval', data['waiting_for_approval'],
              Icons.hourglass_top_outlined, Colors.orange),
          _DashboardMetric('Checked in', data['checked_in_today'],
              Icons.login_outlined, Colors.green),
          _DashboardMetric('Checked out', data['checked_out_today'],
              Icons.logout_outlined, Colors.blue),
          _DashboardMetric(
              'Parcels to collect',
              data['parcels_awaiting_pickup'],
              Icons.inventory_2_outlined,
              Colors.brown),
        ],
    };
    final quickActions = switch (widget.role) {
      'ADMIN' => <(String, IconData, String)>[
          ('Add resident', Icons.person_add_alt_1, 'Residents'),
          ('Add flat', Icons.add_home_work_outlined, 'Flats'),
          ('Generate maintenance', Icons.receipt_long_outlined, 'Maintenance'),
          ('Record payment', Icons.payments_outlined, 'Payments'),
          ('Add notice', Icons.campaign_outlined, 'Notices'),
          ('View complaints', Icons.support_agent_outlined, 'Complaints'),
          ('Add staff', Icons.badge_outlined, 'Staff'),
          ('View visitors', Icons.groups_outlined, 'Visitors'),
        ],
      'STAFF' => <(String, IconData, String)>[
          ('My complaints', Icons.support_agent_outlined, 'Complaints'),
          ('Receive parcel', Icons.inventory_2_outlined, 'Parcels'),
          ('Messages', Icons.chat_bubble_outline, 'Messages'),
        ],
      _ => <(String, IconData, String)>[
          ('Check in visitor', Icons.login_outlined, 'Visitors'),
          ('Check out visitor', Icons.logout_outlined, 'Visitors'),
          ('Delivery entry', Icons.inventory_2_outlined, 'Parcels'),
          ('Vehicle entry', Icons.directions_car_outlined, 'Visitors'),
          ('Emergency contacts', Icons.emergency_outlined, 'Notifications'),
        ],
    };
    final activities = data['recent_activity'] is List
        ? List<dynamic>.from(data['recent_activity'] as List)
        : const <dynamic>[];
    final staffMember = data['staff_member'] is Map
        ? Map<String, dynamic>.from(data['staff_member'] as Map)
        : null;
    final complaints = data['recent_complaints'] is List
        ? List<dynamic>.from(data['recent_complaints'] as List)
        : const <dynamic>[];
    return Scaffold(
      appBar: AppBar(title: Text(_title)),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
          children: [
            Text('Welcome, $name',
                style: Theme.of(context)
                    .textTheme
                    .headlineSmall
                    ?.copyWith(fontWeight: FontWeight.w700)),
            if (staffMember != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                    '${staffMember['designation'] ?? 'Staff'}${staffMember['shift'] == null ? '' : ' · ${staffMember['shift']} shift'}'),
              ),
            const SizedBox(height: 18),
            GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              childAspectRatio: 1.42,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              children: metrics
                  .map((metric) => _DashboardMetricTile(metric: metric))
                  .toList(),
            ),
            const SizedBox(height: 24),
            const _SectionHeader(title: 'Quick actions'),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: quickActions
                  .map((action) => _QuickAction(
                        icon: action.$2,
                        label: action.$1,
                        onTap: () => _open(action.$3),
                      ))
                  .toList(),
            ),
            if (activities.isNotEmpty) ...[
              const SizedBox(height: 24),
              const _SectionHeader(title: 'Recent activity'),
              ...activities.map((raw) {
                final activity = Map<String, dynamic>.from(raw as Map);
                return _InfoCard(
                  icon: Icons.history_outlined,
                  title: activity['title']?.toString() ?? 'Society activity',
                  subtitle: activity['detail']?.toString() ?? '',
                );
              }),
            ],
            if (complaints.isNotEmpty) ...[
              const SizedBox(height: 24),
              const _SectionHeader(title: 'Assigned complaints'),
              ...complaints.map((raw) {
                final complaint = Map<String, dynamic>.from(raw as Map);
                return _InfoCard(
                  icon: Icons.assignment_outlined,
                  title: complaint['title']?.toString() ?? 'Complaint',
                  subtitle:
                      '${complaint['flat'] ?? 'Flat'} · ${complaint['status'] ?? ''}',
                  onTap: () => _open('Complaints'),
                );
              }),
            ],
          ],
        ),
      ),
    );
  }
}

class _DashboardMetric {
  const _DashboardMetric(this.label, this.value, this.icon, this.color);
  final String label;
  final dynamic value;
  final IconData icon;
  final Color color;
}

class _DashboardMetricTile extends StatelessWidget {
  const _DashboardMetricTile({required this.metric});
  final _DashboardMetric metric;

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Icon(metric.icon, color: metric.color),
              Text(metric.value?.toString() ?? '0',
                  style: Theme.of(context)
                      .textTheme
                      .titleLarge
                      ?.copyWith(fontWeight: FontWeight.w700)),
              Text(metric.label, maxLines: 1, overflow: TextOverflow.ellipsis),
            ],
          ),
        ),
      );
}

class NotificationBell extends StatefulWidget {
  const NotificationBell({super.key, required this.role});
  final String role;

  @override
  State<NotificationBell> createState() => _NotificationBellState();
}

class _NotificationBellState extends State<NotificationBell> with WidgetsBindingObserver {
  int _unread = 0;
  Timer? _pollingTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
    // Periodically refresh unread count every 10 seconds
    _pollingTimer = Timer.periodic(const Duration(seconds: 10), (_) => _load());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _load();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _load();
    }
  }

  @override
  void dispose() {
    _pollingTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _load() async {
    if (!mounted) return;
    try {
      final auth = context.read<AuthController>();
      if (auth.api.token == null || auth.session == null) {
        if (mounted && _unread != 0) setState(() => _unread = 0);
        return;
      }

      // Try dedicated unread-count endpoint first
      try {
        final response = await auth.api.get('notifications/unread-count');
        if (mounted) {
          final countVal = response['count'] ?? response['data']?['count'] ?? 0;
          final int count = countVal is int ? countVal : int.tryParse('$countVal') ?? 0;
          if (mounted && _unread != count) {
            setState(() => _unread = count);
          }
          return;
        }
      } on ApiException {
        // Fallback to notifications list
      }

      final response = await auth.api.get('notifications');
      final items = _pageItems(response);
      if (mounted) {
        final count = items
            .where((item) => item is Map && item['read_at'] == null)
            .length;
        if (mounted && _unread != count) {
          setState(() => _unread = count);
        }
      }
    } catch (_) {
      // Notification failure should not prevent the role dashboard from opening.
    }
  }

  Future<void> _open() async {
    await Navigator.of(context).push(MaterialPageRoute(
        builder: (_) =>
            ModuleScreen(title: 'Notifications', role: widget.role)));
    if (mounted) _load();
  }

  @override
  Widget build(BuildContext context) => Badge(
        isLabelVisible: _unread > 0,
        label: Text(
          _unread > 99 ? '99+' : '$_unread',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 10,
            fontWeight: FontWeight.bold,
          ),
        ),
        backgroundColor: const Color(0xFFEF4444),
        child: IconButton(
          tooltip: 'Notifications',
          icon: const Icon(Icons.notifications_none_rounded),
          onPressed: _open,
        ),
      );
}

class AccountProfileScreen extends StatefulWidget {
  const AccountProfileScreen({super.key});

  @override
  State<AccountProfileScreen> createState() => _AccountProfileScreenState();
}

class _AccountProfileScreenState extends State<AccountProfileScreen> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _phone = TextEditingController();
  final _emergencyContact = TextEditingController();
  final _password = TextEditingController();
  final _confirmPassword = TextEditingController();
  String _gender = 'PREFER_NOT_TO_SAY';
  DateTime? _dateOfBirth;
  bool _loading = true;
  bool _saving = false;
  String? _error;
  Map<String, dynamic>? _user;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final controller in [
      _name,
      _email,
      _phone,
      _emergencyContact,
      _password,
      _confirmPassword,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await context.read<AuthController>().api.get('auth/me');
      final user = Map<String, dynamic>.from(result['data'] as Map);
      final profile = user['profile'] is Map
          ? Map<String, dynamic>.from(user['profile'] as Map)
          : <String, dynamic>{};
      _user = user;
      _name.text = user['name']?.toString() ?? '';
      _email.text = user['email']?.toString() ?? '';
      _phone.text = user['phone']?.toString() ?? '';
      _emergencyContact.text = profile['emergency_contact']?.toString() ?? '';
      _dateOfBirth =
          DateTime.tryParse(profile['date_of_birth']?.toString() ?? '');
      if (const {'MALE', 'FEMALE', 'NON_BINARY', 'PREFER_NOT_TO_SAY'}
          .contains(profile['gender'])) {
        _gender = profile['gender'].toString();
      }
    } on ApiException catch (error) {
      _error = error.message;
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _pickDateOfBirth() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _dateOfBirth ?? DateTime(now.year - 25),
      firstDate: DateTime(1900),
      lastDate: now,
    );
    if (picked != null && mounted) setState(() => _dateOfBirth = picked);
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await context.read<AuthController>().api.patch('auth/profile', {
        'name': _name.text.trim(),
        'email': _email.text.trim(),
        'phone': _phone.text.trim().isEmpty ? null : _phone.text.trim(),
        'emergency_contact': _emergencyContact.text.trim().isEmpty
            ? null
            : _emergencyContact.text.trim(),
        'gender': _gender,
        if (_dateOfBirth != null)
          'date_of_birth':
              '${_dateOfBirth!.year.toString().padLeft(4, '0')}-${_dateOfBirth!.month.toString().padLeft(2, '0')}-${_dateOfBirth!.day.toString().padLeft(2, '0')}',
        if (_password.text.isNotEmpty) ...{
          'password': _password.text,
          'password_confirmation': _confirmPassword.text,
        },
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Profile updated successfully.')));
      await _load();
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
          appBar: AppBar(title: const Text('My profile')),
          body: const Center(child: CircularProgressIndicator()));
    }
    if (_error != null && _user == null) {
      return Scaffold(
          appBar: AppBar(title: const Text('My profile')),
          body: _ErrorState(message: _error!, onRetry: _load));
    }
    final resident = _user?['resident'] is Map
        ? Map<String, dynamic>.from(_user!['resident'] as Map)
        : null;
    final staff = _user?['staff_member'] is Map
        ? Map<String, dynamic>.from(_user!['staff_member'] as Map)
        : null;
    return Scaffold(
      appBar: AppBar(title: const Text('My profile')),
      body: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              child: ListTile(
                leading: CircleAvatar(child: Text(_initials(_name.text))),
                title: Text(_user?['role']?.toString() ?? 'Member'),
                subtitle: Text(resident == null
                    ? (staff?['designation']?.toString() ?? '')
                    : 'Flat ${resident['flat_number'] ?? '—'} · ${resident['building'] ?? '—'}'),
              ),
            ),
            const SizedBox(height: 16),
            _TextField(controller: _name, label: 'Full name'),
            _TextField(
                controller: _email,
                label: 'Email',
                keyboardType: TextInputType.emailAddress),
            _TextField(
                controller: _phone,
                label: 'Mobile number',
                required: false,
                keyboardType: TextInputType.phone),
            _TextField(
                controller: _emergencyContact,
                label: 'Emergency contact',
                required: false,
                keyboardType: TextInputType.phone),
            DropdownButtonFormField<String>(
              initialValue: _gender,
              decoration: const InputDecoration(
                  labelText: 'Gender', border: OutlineInputBorder()),
              items: const [
                DropdownMenuItem(value: 'MALE', child: Text('Male')),
                DropdownMenuItem(value: 'FEMALE', child: Text('Female')),
                DropdownMenuItem(
                    value: 'NON_BINARY', child: Text('Non-binary')),
                DropdownMenuItem(
                    value: 'PREFER_NOT_TO_SAY',
                    child: Text('Prefer not to say')),
              ],
              onChanged:
                  _saving ? null : (value) => setState(() => _gender = value!),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _saving ? null : _pickDateOfBirth,
              icon: const Icon(Icons.cake_outlined),
              label: Align(
                alignment: Alignment.centerLeft,
                child: Text(_dateOfBirth == null
                    ? 'Date of birth: not set'
                    : 'Date of birth: ${_dateOfBirth!.day.toString().padLeft(2, '0')}/${_dateOfBirth!.month.toString().padLeft(2, '0')}/${_dateOfBirth!.year}'),
              ),
            ),
            const Divider(height: 32),
            Text('Change password',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            _TextField(
                controller: _password,
                label: 'New password (optional)',
                required: false,
                obscure: true),
            _TextField(
                controller: _confirmPassword,
                label: 'Confirm new password',
                required: false,
                obscure: true,
                validator: (value) =>
                    _password.text.isEmpty || value == _password.text
                        ? null
                        : 'Passwords do not match'),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(_error!,
                    style:
                        TextStyle(color: Theme.of(context).colorScheme.error)),
              ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const CircularProgressIndicator()
                  : const Text('Save profile'),
            ),
          ],
        ),
      ),
    );
  }
}

class ResidentShell extends StatefulWidget {
  const ResidentShell({super.key});

  @override
  State<ResidentShell> createState() => _ResidentShellState();
}

class _ResidentShellState extends State<ResidentShell> {
  var _index = 0;

  static const _titles = ['Home', 'My Unit', 'Gate', 'More'];

  @override
  Widget build(BuildContext context) {
    final pages = [
      ResidentDashboardScreen(
          onOpenTab: (index) => setState(() => _index = index)),
      const MyUnitScreen(),
      const ResidentVisitorsScreen(),
      const ResidentMoreScreen(),
    ];
    return Scaffold(
      appBar: _index == 0
          ? null
          : AppBar(
              title: Text(_titles[_index]),
              actions: const [
                NotificationBell(role: 'RESIDENT'),
              ],
            ),
      extendBodyBehindAppBar: _index == 0,
      body: pages[_index],
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 10,
              offset: const Offset(0, -2),
            ),
          ],
        ),
        child: NavigationBar(
          selectedIndex: _index,
          onDestinationSelected: (index) => setState(() => _index = index),
          elevation: 0,
          backgroundColor: Theme.of(context).colorScheme.surface,
          indicatorColor: const Color(0xFF6366F1).withValues(alpha: 0.12),
          height: 65,
          destinations: const [
            NavigationDestination(
                icon: Icon(Icons.home_outlined),
                selectedIcon: Icon(Icons.home, color: Color(0xFF6366F1)),
                label: 'Home'),
            NavigationDestination(
                icon: Icon(Icons.apartment_outlined),
                selectedIcon: Icon(Icons.apartment, color: Color(0xFF6366F1)),
                label: 'My Unit'),
            NavigationDestination(
                icon: Icon(Icons.shield_outlined),
                selectedIcon: Icon(Icons.shield, color: Color(0xFF6366F1)),
                label: 'Gate'),
            NavigationDestination(
                icon: Icon(Icons.grid_view_outlined),
                selectedIcon: Icon(Icons.grid_view, color: Color(0xFF6366F1)),
                label: 'More'),
          ],
        ),
      ),
    );
  }
}

class SecurityShell extends StatefulWidget {
  const SecurityShell({super.key});

  @override
  State<SecurityShell> createState() => _SecurityShellState();
}

class _SecurityShellState extends State<SecurityShell> {
  var _index = 0;

  static const _titles = ['Dashboard', 'Visitors', 'Parcels', 'More'];

  @override
  Widget build(BuildContext context) {
    final pages = [
      SecurityDashboardScreen(
        onSelectTab: (index) => setState(() => _index = index),
      ),
      const ModuleScreen(title: 'Visitors', role: 'SECURITY', showAppBar: false),
      const ModuleScreen(title: 'Parcels', role: 'SECURITY', showAppBar: false),
      const SecurityMoreScreen(),
    ];
    return Scaffold(
      appBar: AppBar(
        title: Text(_titles[_index]),
        actions: const [
          NotificationBell(role: 'SECURITY'),
        ],
      ),
      body: pages[_index],
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 10,
              offset: const Offset(0, -2),
            ),
          ],
        ),
        child: NavigationBar(
          selectedIndex: _index,
          onDestinationSelected: (index) => setState(() => _index = index),
          elevation: 0,
          backgroundColor: Theme.of(context).colorScheme.surface,
          indicatorColor: const Color(0xFF6366F1).withValues(alpha: 0.12),
          height: 65,
          destinations: const [
            NavigationDestination(
                icon: Icon(Icons.dashboard_outlined),
                selectedIcon: Icon(Icons.dashboard, color: Color(0xFF6366F1)),
                label: 'Dashboard'),
            NavigationDestination(
                icon: Icon(Icons.badge_outlined),
                selectedIcon: Icon(Icons.badge, color: Color(0xFF6366F1)),
                label: 'Visitors'),
            NavigationDestination(
                icon: Icon(Icons.inventory_2_outlined),
                selectedIcon:
                    Icon(Icons.inventory_2, color: Color(0xFF6366F1)),
                label: 'Parcels'),
            NavigationDestination(
                icon: Icon(Icons.grid_view_outlined),
                selectedIcon: Icon(Icons.grid_view, color: Color(0xFF6366F1)),
                label: 'More'),
          ],
        ),
      ),
    );
  }
}

class SecurityDashboardScreen extends StatefulWidget {
  const SecurityDashboardScreen({super.key, required this.onSelectTab});
  final ValueChanged<int> onSelectTab;

  @override
  State<SecurityDashboardScreen> createState() =>
      _SecurityDashboardScreenState();
}

class _SecurityDashboardScreenState extends State<SecurityDashboardScreen> {
  Map<String, dynamic>? _data;
  String? _error;
  var _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final response =
          await context.read<AuthController>().api.get('security/dashboard');
      _data = Map<String, dynamic>.from(response['data'] as Map);
    } on ApiException catch (error) {
      _error = error.message;
    } catch (_) {
      _error = 'Unable to load security dashboard data. Please try again.';
    }
    if (mounted) setState(() => _loading = false);
  }

  void _openVisitors() {
    widget.onSelectTab(1);
  }

  void _openParcels() {
    widget.onSelectTab(2);
  }

  Future<void> _openCheckInWorkflow() async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => const SecurityCheckInScreen(),
      ),
    );
    if (changed == true && mounted) {
      _load();
    }
  }

  Future<void> _openCheckOutWorkflow() async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => const SecurityCheckOutScreen(),
      ),
    );
    if (changed == true && mounted) {
      _load();
    }
  }

  Future<void> _openCheckedOutHistory() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const SecurityCheckedOutHistoryScreen(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return _ErrorState(message: _error!, onRetry: _load);
    }

    final data = _data!;
    final name = context.read<AuthController>().session!.user.name;
    final expectedVisitors = data['expected_visitors'] as int? ?? 0;
    final waitingApproval = data['waiting_for_approval'] as int? ?? 0;
    final checkedInToday = data['checked_in_today'] as int? ?? 0;
    final checkedOutToday = data['checked_out_today'] as int? ?? 0;
    final parcelsAwaiting = data['parcels_awaiting_pickup'] as int? ?? 0;

    return RefreshIndicator(
      onRefresh: _load,
      child: CustomScrollView(
        slivers: [
          // Header
          SliverToBoxAdapter(
            child: Container(
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF6366F1).withValues(alpha: 0.3),
                    blurRadius: 20,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 28),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(Icons.shield,
                            color: Colors.white, size: 28),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Welcome back,',
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.9),
                                fontSize: 14,
                              ),
                            ),
                            Text(
                              name,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 20,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      Icon(Icons.check_circle,
                          color: Colors.white.withValues(alpha: 0.9), size: 16),
                      const SizedBox(width: 8),
                      Text(
                        'On duty · ${_formatDate(DateTime.now())}',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.9),
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),

          // Metrics Grid
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
            sliver: SliverGrid(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                mainAxisExtent: 130,
              ),
              delegate: SliverChildListDelegate([
                _SecurityMetricCard(
                  icon: Icons.event_available_outlined,
                  title: 'Expected Today',
                  value: expectedVisitors.toString(),
                  gradient: const LinearGradient(
                    colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)],
                  ),
                  onTap: _openVisitors,
                ),
                _SecurityMetricCard(
                  icon: Icons.hourglass_top_outlined,
                  title: 'Awaiting Approval',
                  value: waitingApproval.toString(),
                  gradient: const LinearGradient(
                    colors: [Color(0xFFF59E0B), Color(0xFFEF4444)],
                  ),
                  onTap: _openVisitors,
                  isUrgent: waitingApproval > 0,
                ),
                _SecurityMetricCard(
                  icon: Icons.login_outlined,
                  title: 'Checked In',
                  value: checkedInToday.toString(),
                  gradient: const LinearGradient(
                    colors: [Color(0xFF10B981), Color(0xFF059669)],
                  ),
                  onTap: _openCheckOutWorkflow,
                ),
                _SecurityMetricCard(
                  icon: Icons.logout_outlined,
                  title: 'Checked Out',
                  value: checkedOutToday.toString(),
                  gradient: const LinearGradient(
                    colors: [Color(0xFF3B82F6), Color(0xFF2563EB)],
                  ),
                  onTap: _openCheckedOutHistory,
                ),
                _SecurityMetricCard(
                  icon: Icons.inventory_2_outlined,
                  title: 'Parcels Waiting',
                  value: parcelsAwaiting.toString(),
                  gradient: const LinearGradient(
                    colors: [Color(0xFF8B5A3C), Color(0xFF6D4C41)],
                  ),
                  onTap: _openParcels,
                  isUrgent: parcelsAwaiting > 0,
                ),
                const _SecurityMetricCard(
                  icon: Icons.shield_outlined,
                  title: 'Gate Status',
                  value: 'Secure',
                  gradient: LinearGradient(
                    colors: [Color(0xFF059669), Color(0xFF047857)],
                  ),
                ),
              ]),
            ),
          ),

          // Quick Actions
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.fromLTRB(16, 24, 16, 12),
              child: Row(
                children: [
                  Icon(Icons.bolt, color: Color(0xFF6366F1), size: 20),
                  SizedBox(width: 8),
                  Text(
                    'Quick actions',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF1E293B),
                    ),
                  ),
                ],
              ),
            ),
          ),

          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
            sliver: SliverToBoxAdapter(
              child: Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  _SecurityQuickAction(
                    icon: Icons.login,
                    label: 'Check in visitor',
                    gradient: const LinearGradient(
                      colors: [Color(0xFFDCFCE7), Color(0xFFBBF7D0)],
                    ),
                    iconColor: const Color(0xFF059669),
                    onTap: _openCheckInWorkflow,
                  ),
                  _SecurityQuickAction(
                    icon: Icons.logout,
                    label: 'Check out visitor',
                    gradient: const LinearGradient(
                      colors: [Color(0xFFDBEAFE), Color(0xFFBFDBFE)],
                    ),
                    iconColor: const Color(0xFF2563EB),
                    onTap: _openCheckOutWorkflow,
                  ),
                  _SecurityQuickAction(
                    icon: Icons.inventory_2,
                    label: 'Record parcel',
                    gradient: const LinearGradient(
                      colors: [Color(0xFFFEF3C7), Color(0xFFFDE68A)],
                    ),
                    iconColor: const Color(0xFFD97706),
                    onTap: () async {
                      final parcelConfig = FormConfig.forRoute('security/parcels');
                      if (parcelConfig != null) {
                        final result = await Navigator.of(context).push<bool>(
                          MaterialPageRoute(
                            builder: (_) => ModuleFormScreen(config: parcelConfig),
                          ),
                        );
                        if (result == true) {
                          _load();
                        }
                      }
                    },
                  ),
                  _SecurityQuickAction(
                    icon: Icons.directions_car,
                    label: 'Vehicle entry',
                    gradient: const LinearGradient(
                      colors: [Color(0xFFE0E7FF), Color(0xFFC7D2FE)],
                    ),
                    iconColor: const Color(0xFF6366F1),
                    onTap: () async {
                      final visitorConfig = FormConfig.forRoute('security/visitors');
                      if (visitorConfig != null) {
                        final result = await Navigator.of(context).push<bool>(
                          MaterialPageRoute(
                            builder: (_) => ModuleFormScreen(config: visitorConfig),
                          ),
                        );
                        if (result == true) {
                          _load();
                        }
                      }
                    },
                  ),
                  _SecurityQuickAction(
                    icon: Icons.badge,
                    label: 'View all visitors',
                    gradient: const LinearGradient(
                      colors: [Color(0xFFF3E8FF), Color(0xFFE9D5FF)],
                    ),
                    iconColor: const Color(0xFF9333EA),
                    onTap: _openVisitors,
                  ),
                  _SecurityQuickAction(
                    icon: Icons.emergency,
                    label: 'Emergency alert',
                    gradient: const LinearGradient(
                      colors: [Color(0xFFFEE2E2), Color(0xFFFECACA)],
                    ),
                    iconColor: const Color(0xFFDC2626),
                    onTap: () {
                      showDialog(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          icon: const Icon(Icons.emergency, color: Color(0xFFDC2626), size: 48),
                          title: const Text('Emergency Alert'),
                          content: const Text(
                            'This will notify society management and available security personnel.\n\nAre you sure you want to proceed?',
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(ctx),
                              child: const Text('Cancel'),
                            ),
                            FilledButton(
                              style: FilledButton.styleFrom(
                                backgroundColor: const Color(0xFFDC2626),
                              ),
                              onPressed: () {
                                Navigator.pop(ctx);
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('Emergency alert broadcasted.'),
                                    backgroundColor: Color(0xFFDC2626),
                                  ),
                                );
                              },
                              child: const Text('Send Alert'),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime date) {
    final months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec'
    ];
    return '${months[date.month - 1]} ${date.day}, ${date.year}';
  }
}

class _SecurityMetricCard extends StatelessWidget {
  const _SecurityMetricCard({
    required this.icon,
    required this.title,
    required this.value,
    required this.gradient,
    this.onTap,
    this.isUrgent = false,
  });

  final IconData icon;
  final String title;
  final String value;
  final Gradient gradient;
  final VoidCallback? onTap;
  final bool isUrgent;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      elevation: 0,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: isUrgent
              ? Border.all(
                  color: const Color(0xFFF59E0B).withValues(alpha: 0.5),
                  width: 1.5,
                )
              : Border.all(
                  color: const Color(0xFFE2E8F0),
                  width: 1,
                ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.03),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
            if (isUrgent)
              BoxShadow(
                color: const Color(0xFFF59E0B).withValues(alpha: 0.12),
                blurRadius: 16,
                offset: const Offset(0, 4),
              ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Stack(
            children: [
              Positioned(
                right: -15,
                top: -15,
                child: IgnorePointer(
                  ignoring: true,
                  child: Opacity(
                    opacity: 0.08,
                    child: Container(
                      width: 70,
                      height: 70,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: gradient,
                      ),
                    ),
                  ),
                ),
              ),
              Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: onTap,
                  borderRadius: BorderRadius.circular(16),
                  splashColor: gradient.colors.first.withValues(alpha: 0.12),
                  highlightColor: gradient.colors.first.withValues(alpha: 0.06),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            gradient: gradient,
                            borderRadius: BorderRadius.circular(10),
                            boxShadow: [
                              BoxShadow(
                                color: gradient.colors.first
                                    .withValues(alpha: 0.25),
                                blurRadius: 6,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: Icon(icon, color: Colors.white, size: 20),
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              value,
                              style: const TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF1E293B),
                                letterSpacing: -0.5,
                                height: 1.1,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 3),
                            Text(
                              title,
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF64748B),
                                letterSpacing: 0.2,
                                height: 1.2,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SecurityQuickAction extends StatelessWidget {
  const _SecurityQuickAction({
    required this.icon,
    required this.label,
    required this.gradient,
    required this.iconColor,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Gradient gradient;
  final Color iconColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: (MediaQuery.of(context).size.width - 56) / 2,
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        child: Ink(
          decoration: BoxDecoration(
            gradient: gradient,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(8),
                      boxShadow: [
                        BoxShadow(
                          color: iconColor.withValues(alpha: 0.2),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Icon(icon, color: iconColor, size: 20),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      label,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: iconColor.withValues(alpha: 0.9),
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class SecurityMoreScreen extends StatelessWidget {
  const SecurityMoreScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const _SectionHeader(title: 'Features'),
        _MenuCard(
          icon: Icons.badge_outlined,
          title: 'Visitors',
          subtitle: 'Manage visitor entries and exits',
          onTap: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) =>
                  const ModuleScreen(title: 'Visitors', role: 'SECURITY'))),
        ),
        _MenuCard(
          icon: Icons.inventory_2_outlined,
          title: 'Parcels',
          subtitle: 'Record and track parcel deliveries',
          onTap: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) =>
                  const ModuleScreen(title: 'Parcels', role: 'SECURITY'))),
        ),
        _MenuCard(
          icon: Icons.campaign_outlined,
          title: 'Notices',
          subtitle: 'View society announcements',
          onTap: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) =>
                  const ModuleScreen(title: 'Notices', role: 'SECURITY'))),
        ),
        _MenuCard(
          icon: Icons.chat_bubble_outline,
          title: 'Messages',
          subtitle: 'Communicate with residents and staff',
          onTap: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) =>
                  const ModuleScreen(title: 'Messages', role: 'SECURITY'))),
        ),
        const SizedBox(height: 12),
        const _SectionHeader(title: 'Account'),
        _MenuCard(
          icon: Icons.person_outline,
          title: 'My profile',
          subtitle: 'View and update your account details',
          onTap: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => const AccountProfileScreen())),
        ),
        _MenuCard(
          icon: Icons.logout,
          title: 'Sign out',
          subtitle: 'Log out from your security account',
          onTap: () => context.read<AuthController>().logout(),
          isDestructive: true,
        ),
      ],
    );
  }
}

class _MenuCard extends StatelessWidget {
  const _MenuCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.isDestructive = false,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final bool isDestructive;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Icon(
          icon,
          color: isDestructive ? Colors.red : const Color(0xFF6366F1),
        ),
        title: Text(
          title,
          style: TextStyle(
            fontWeight: FontWeight.w600,
            color: isDestructive ? Colors.red : null,
          ),
        ),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}

class AdminShell extends StatefulWidget {
  const AdminShell({super.key});

  @override
  State<AdminShell> createState() => _AdminShellState();
}

class _AdminShellState extends State<AdminShell> {
  var _index = 0;

  static const _titles = ['Dashboard', 'Residents', 'Finance', 'More'];

  @override
  Widget build(BuildContext context) {
    final pages = [
      AdminDashboardScreen(
        onSelectTab: (index) => setState(() => _index = index),
      ),
      const ModuleScreen(title: 'Residents', role: 'ADMIN', showAppBar: false),
      const AdminPaymentsScreen(showAppBar: false),
      const AdminMoreScreen(),
    ];
    return Scaffold(
      appBar: AppBar(
        title: Text(_titles[_index]),
        actions: const [
          NotificationBell(role: 'ADMIN'),
        ],
      ),
      body: pages[_index],
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 10,
              offset: const Offset(0, -2),
            ),
          ],
        ),
        child: NavigationBar(
          selectedIndex: _index,
          onDestinationSelected: (index) => setState(() => _index = index),
          elevation: 0,
          backgroundColor: Theme.of(context).colorScheme.surface,
          indicatorColor: const Color(0xFF6366F1).withValues(alpha: 0.12),
          height: 65,
          destinations: const [
            NavigationDestination(
                icon: Icon(Icons.dashboard_outlined),
                selectedIcon: Icon(Icons.dashboard, color: Color(0xFF6366F1)),
                label: 'Dashboard'),
            NavigationDestination(
                icon: Icon(Icons.people_outlined),
                selectedIcon: Icon(Icons.people, color: Color(0xFF6366F1)),
                label: 'Residents'),
            NavigationDestination(
                icon: Icon(Icons.account_balance_wallet_outlined),
                selectedIcon: Icon(Icons.account_balance_wallet,
                    color: Color(0xFF6366F1)),
                label: 'Finance'),
            NavigationDestination(
                icon: Icon(Icons.grid_view_outlined),
                selectedIcon: Icon(Icons.grid_view, color: Color(0xFF6366F1)),
                label: 'More'),
          ],
        ),
      ),
    );
  }
}

class AdminDashboardScreen extends StatefulWidget {
  const AdminDashboardScreen({super.key, required this.onSelectTab});
  final ValueChanged<int> onSelectTab;

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen> {
  Map<String, dynamic>? _data;
  String? _error;
  var _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final response =
          await context.read<AuthController>().api.get('admin/dashboard');
      _data = Map<String, dynamic>.from(response['data'] as Map);
    } on ApiException catch (error) {
      _error = error.message;
    } catch (_) {
      _error = 'Unable to load administrator dashboard data. Please try again.';
    }
    if (mounted) setState(() => _loading = false);
  }

  void _openResidents() {
    widget.onSelectTab(1);
  }

  void _openFinance() {
    widget.onSelectTab(2);
  }

  void _openPage(String page) {
    Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => page == 'Reports'
            ? const AdminReportsScreen()
            : ModuleScreen(title: page, role: 'ADMIN')));
  }

  String _getGreeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good morning';
    if (hour < 17) return 'Good afternoon';
    return 'Good evening';
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return _ErrorState(message: _error!, onRetry: _load);
    }

    final data = _data!;
    final name = context.read<AuthController>().session!.user.name;
    final totalResidents = data['total_residents'] as int? ?? 0;
    final totalFlats = data['total_flats'] as int? ?? 0;
    final occupiedFlats = data['occupied_flats'] as int? ?? 0;
    final vacantFlats = data['vacant_flats'] as int? ?? 0;
    final pendingBills = data['pending_maintenance_bills'] as int? ?? 0;
    final collectedMaintenance =
        data['total_collected_maintenance'] as num? ?? 0;
    final openComplaints = data['open_complaints'] as int? ?? 0;
    final todayVisitors = data['today_visitors'] as int? ?? 0;
    final activeStaff = data['active_staff'] as int? ?? 0;
    final parcelsPending = data['parcels_pending_pickup'] as int? ?? 0;

    return RefreshIndicator(
      onRefresh: _load,
      child: CustomScrollView(
        slivers: [
          // Gradient Header
          SliverToBoxAdapter(
            child: Container(
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF4F46E5), Color(0xFF7C3AED)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF4F46E5).withValues(alpha: 0.3),
                    blurRadius: 20,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 28),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(Icons.admin_panel_settings,
                            color: Colors.white, size: 28),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${_getGreeting()} 👋',
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.9),
                                fontSize: 14,
                              ),
                            ),
                            Text(
                              name,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 20,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'Administrator Dashboard',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.95),
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Society Overview Section
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.fromLTRB(16, 24, 16, 12),
              child: Row(
                children: [
                  Icon(Icons.apartment, color: Color(0xFF4F46E5), size: 20),
                  SizedBox(width: 8),
                  Text(
                    'Society overview',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF1E293B),
                    ),
                  ),
                ],
              ),
            ),
          ),

          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
            sliver: SliverGrid(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                mainAxisExtent: 130,
              ),
              delegate: SliverChildListDelegate([
                _AdminMetricCard(
                  icon: Icons.people_outline,
                  title: 'Total Residents',
                  value: totalResidents.toString(),
                  gradient: const LinearGradient(
                    colors: [Color(0xFF4F46E5), Color(0xFF6366F1)],
                  ),
                  onTap: _openResidents,
                ),
                _AdminMetricCard(
                  icon: Icons.apartment_outlined,
                  title: 'Total Units',
                  value: totalFlats.toString(),
                  gradient: const LinearGradient(
                    colors: [Color(0xFF3B82F6), Color(0xFF2563EB)],
                  ),
                  onTap: () => _openPage('Flats'),
                ),
                _AdminMetricCard(
                  icon: Icons.home_work_outlined,
                  title: 'Occupied',
                  value: occupiedFlats.toString(),
                  gradient: const LinearGradient(
                    colors: [Color(0xFF14B8A6), Color(0xFF0D9488)],
                  ),
                  onTap: () => _openPage('Flats'),
                ),
                _AdminMetricCard(
                  icon: Icons.meeting_room_outlined,
                  title: 'Vacant',
                  value: vacantFlats.toString(),
                  gradient: const LinearGradient(
                    colors: [Color(0xFFF59E0B), Color(0xFFD97706)],
                  ),
                  onTap: () => _openPage('Flats'),
                ),
              ]),
            ),
          ),

          // Financial Overview Section
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.fromLTRB(16, 24, 16, 12),
              child: Row(
                children: [
                  Icon(Icons.account_balance_wallet,
                      color: Color(0xFF10B981), size: 20),
                  SizedBox(width: 8),
                  Text(
                    'Financial overview',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF1E293B),
                    ),
                  ),
                ],
              ),
            ),
          ),

          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
            sliver: SliverGrid(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                mainAxisExtent: 130,
              ),
              delegate: SliverChildListDelegate([
                _AdminMetricCard(
                  icon: Icons.receipt_long_outlined,
                  title: 'Pending Bills',
                  value: pendingBills.toString(),
                  gradient: const LinearGradient(
                    colors: [Color(0xFFEF4444), Color(0xFFDC2626)],
                  ),
                  onTap: () => _openPage('Maintenance'),
                  isUrgent: pendingBills > 0,
                ),
                _AdminMetricCard(
                  icon: Icons.account_balance_wallet_outlined,
                  title: 'Collected',
                  value: _formatMoney(collectedMaintenance),
                  gradient: const LinearGradient(
                    colors: [Color(0xFF10B981), Color(0xFF059669)],
                  ),
                  onTap: _openFinance,
                ),
              ]),
            ),
          ),

          // Operations Overview Section
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.fromLTRB(16, 24, 16, 12),
              child: Row(
                children: [
                  Icon(Icons.business_center, color: Color(0xFF7C3AED), size: 20),
                  SizedBox(width: 8),
                  Text(
                    'Operations overview',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF1E293B),
                    ),
                  ),
                ],
              ),
            ),
          ),

          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
            sliver: SliverGrid(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                mainAxisExtent: 130,
              ),
              delegate: SliverChildListDelegate([
                _AdminMetricCard(
                  icon: Icons.support_agent_outlined,
                  title: 'Open Complaints',
                  value: openComplaints.toString(),
                  gradient: const LinearGradient(
                    colors: [Color(0xFFF97316), Color(0xFFEA580C)],
                  ),
                  onTap: () => _openPage('Complaints'),
                  isUrgent: openComplaints > 0,
                ),
                _AdminMetricCard(
                  icon: Icons.badge_outlined,
                  title: 'Visitors Today',
                  value: todayVisitors.toString(),
                  gradient: const LinearGradient(
                    colors: [Color(0xFF8B5CF6), Color(0xFF7C3AED)],
                  ),
                  onTap: () => _openPage('Visitors'),
                ),
                _AdminMetricCard(
                  icon: Icons.groups_outlined,
                  title: 'Active Staff',
                  value: activeStaff.toString(),
                  gradient: const LinearGradient(
                    colors: [Color(0xFF06B6D4), Color(0xFF0891B2)],
                  ),
                  onTap: () => _openPage('Staff'),
                ),
                _AdminMetricCard(
                  icon: Icons.inventory_2_outlined,
                  title: 'Parcels Waiting',
                  value: parcelsPending.toString(),
                  gradient: const LinearGradient(
                    colors: [Color(0xFF8B5A3C), Color(0xFF6D4C41)],
                  ),
                  onTap: () => _openPage('Parcels'),
                ),
              ]),
            ),
          ),

          // Quick Actions
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.fromLTRB(16, 24, 16, 12),
              child: Row(
                children: [
                  Icon(Icons.bolt, color: Color(0xFF4F46E5), size: 20),
                  SizedBox(width: 8),
                  Text(
                    'Quick actions',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF1E293B),
                    ),
                  ),
                ],
              ),
            ),
          ),

          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
            sliver: SliverToBoxAdapter(
              child: Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  _AdminQuickAction(
                    icon: Icons.person_add,
                    label: 'Add resident',
                    gradient: const LinearGradient(
                      colors: [Color(0xFFDCFCE7), Color(0xFFBBF7D0)],
                    ),
                    iconColor: const Color(0xFF059669),
                    onTap: _openResidents,
                  ),
                  _AdminQuickAction(
                    icon: Icons.add_home_work,
                    label: 'Add unit',
                    gradient: const LinearGradient(
                      colors: [Color(0xFFDBEAFE), Color(0xFFBFDBFE)],
                    ),
                    iconColor: const Color(0xFF2563EB),
                    onTap: () => _openPage('Flats'),
                  ),
                  _AdminQuickAction(
                    icon: Icons.receipt_long,
                    label: 'Maintenance',
                    gradient: const LinearGradient(
                      colors: [Color(0xFFFEF3C7), Color(0xFFFDE68A)],
                    ),
                    iconColor: const Color(0xFFD97706),
                    onTap: () => _openPage('Maintenance'),
                  ),
                  _AdminQuickAction(
                    icon: Icons.payments,
                    label: 'Record payment',
                    gradient: const LinearGradient(
                      colors: [Color(0xFFD1FAE5), Color(0xFFA7F3D0)],
                    ),
                    iconColor: const Color(0xFF10B981),
                    onTap: _openFinance,
                  ),
                  _AdminQuickAction(
                    icon: Icons.campaign,
                    label: 'Add notice',
                    gradient: const LinearGradient(
                      colors: [Color(0xFFE0E7FF), Color(0xFFC7D2FE)],
                    ),
                    iconColor: const Color(0xFF6366F1),
                    onTap: () => _openPage('Notices'),
                  ),
                  _AdminQuickAction(
                    icon: Icons.assessment,
                    label: 'View reports',
                    gradient: const LinearGradient(
                      colors: [Color(0xFFF3E8FF), Color(0xFFE9D5FF)],
                    ),
                    iconColor: const Color(0xFF9333EA),
                    onTap: () => _openPage('Reports'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _formatMoney(num amount) {
    if (amount >= 100000) {
      return '₹${(amount / 100000).toStringAsFixed(1)}L';
    } else if (amount >= 1000) {
      return '₹${(amount / 1000).toStringAsFixed(1)}K';
    }
    return '₹${amount.toStringAsFixed(0)}';
  }
}

class _AdminMetricCard extends StatelessWidget {
  const _AdminMetricCard({
    required this.icon,
    required this.title,
    required this.value,
    required this.gradient,
    required this.onTap,
    this.isUrgent = false,
  });

  final IconData icon;
  final String title;
  final String value;
  final Gradient gradient;
  final VoidCallback onTap;
  final bool isUrgent;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      elevation: 0,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: isUrgent
              ? Border.all(
                  color: const Color(0xFFF59E0B).withValues(alpha: 0.5),
                  width: 1.5,
                )
              : Border.all(
                  color: const Color(0xFFE2E8F0),
                  width: 1,
                ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.03),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
            if (isUrgent)
              BoxShadow(
                color: const Color(0xFFF59E0B).withValues(alpha: 0.12),
                blurRadius: 16,
                offset: const Offset(0, 4),
              ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Stack(
            children: [
              Positioned(
                right: -15,
                top: -15,
                child: IgnorePointer(
                  ignoring: true,
                  child: Opacity(
                    opacity: 0.08,
                    child: Container(
                      width: 70,
                      height: 70,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: gradient,
                      ),
                    ),
                  ),
                ),
              ),
              Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: onTap,
                  borderRadius: BorderRadius.circular(16),
                  splashColor: gradient.colors.first.withValues(alpha: 0.12),
                  highlightColor: gradient.colors.first.withValues(alpha: 0.06),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            gradient: gradient,
                            borderRadius: BorderRadius.circular(10),
                            boxShadow: [
                              BoxShadow(
                                color: gradient.colors.first
                                    .withValues(alpha: 0.25),
                                blurRadius: 6,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: Icon(icon, color: Colors.white, size: 20),
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              value,
                              style: const TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF1E293B),
                                letterSpacing: -0.5,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 2),
                            Text(
                              title,
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF64748B),
                                letterSpacing: 0.2,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AdminQuickAction extends StatelessWidget {
  const _AdminQuickAction({
    required this.icon,
    required this.label,
    required this.gradient,
    required this.iconColor,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Gradient gradient;
  final Color iconColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: (MediaQuery.of(context).size.width - 56) / 2,
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        child: Ink(
          decoration: BoxDecoration(
            gradient: gradient,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(8),
                      boxShadow: [
                        BoxShadow(
                          color: iconColor.withValues(alpha: 0.2),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Icon(icon, color: iconColor, size: 20),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      label,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: iconColor.withValues(alpha: 0.9),
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class AdminMoreScreen extends StatelessWidget {
  const AdminMoreScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const _SectionHeader(title: 'Management'),
        _MenuCard(
          icon: Icons.people_outlined,
          title: 'Residents',
          subtitle: 'Manage residents and their units',
          onTap: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) =>
                  const ModuleScreen(title: 'Residents', role: 'ADMIN'))),
        ),
        _MenuCard(
          icon: Icons.apartment_outlined,
          title: 'Units',
          subtitle: 'Manage flats and occupancy',
          onTap: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) =>
                  const ModuleScreen(title: 'Flats', role: 'ADMIN'))),
        ),
        _MenuCard(
          icon: Icons.groups_outlined,
          title: 'Staff',
          subtitle: 'Manage society staff members',
          onTap: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) =>
                  const ModuleScreen(title: 'Staff', role: 'ADMIN'))),
        ),
        const SizedBox(height: 12),
        const _SectionHeader(title: 'Operations'),
        _MenuCard(
          icon: Icons.receipt_long_outlined,
          title: 'Maintenance',
          subtitle: 'Bills and maintenance tracking',
          onTap: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) =>
                  const ModuleScreen(title: 'Maintenance', role: 'ADMIN'))),
        ),
        _MenuCard(
          icon: Icons.support_agent_outlined,
          title: 'Complaints',
          subtitle: 'View and manage helpdesk tickets',
          onTap: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) =>
                  const ModuleScreen(title: 'Complaints', role: 'ADMIN'))),
        ),
        _MenuCard(
          icon: Icons.badge_outlined,
          title: 'Visitors',
          subtitle: 'Track visitor entries and exits',
          onTap: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) =>
                  const ModuleScreen(title: 'Visitors', role: 'ADMIN'))),
        ),
        _MenuCard(
          icon: Icons.inventory_2_outlined,
          title: 'Parcels',
          subtitle: 'Manage parcel deliveries',
          onTap: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) =>
                  const ModuleScreen(title: 'Parcels', role: 'ADMIN'))),
        ),
        _MenuCard(
          icon: Icons.campaign_outlined,
          title: 'Notices',
          subtitle: 'Society announcements and notices',
          onTap: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) =>
                  const ModuleScreen(title: 'Notices', role: 'ADMIN'))),
        ),
        _MenuCard(
          icon: Icons.local_parking_outlined,
          title: 'Parking',
          subtitle: 'Manage parking slots',
          onTap: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) =>
                  const ModuleScreen(title: 'Parking', role: 'ADMIN'))),
        ),
        _MenuCard(
          icon: Icons.pool_outlined,
          title: 'Amenities',
          subtitle: 'Manage amenity bookings',
          onTap: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) =>
                  const ModuleScreen(title: 'Amenities', role: 'ADMIN'))),
        ),
        _MenuCard(
          icon: Icons.assessment_outlined,
          title: 'Reports',
          subtitle: 'View financial and operational reports',
          onTap: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => const AdminReportsScreen())),
        ),
        const SizedBox(height: 12),
        const _SectionHeader(title: 'Communication'),
        _MenuCard(
          icon: Icons.chat_bubble_outline,
          title: 'Messages',
          subtitle: 'Communicate with residents',
          onTap: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) =>
                  const ModuleScreen(title: 'Messages', role: 'ADMIN'))),
        ),
        const SizedBox(height: 12),
        const _SectionHeader(title: 'Account'),
        _MenuCard(
          icon: Icons.person_outline,
          title: 'My profile',
          subtitle: 'View and update your account details',
          onTap: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => const AccountProfileScreen())),
        ),
        _MenuCard(
          icon: Icons.logout,
          title: 'Sign out',
          subtitle: 'Log out from your administrator account',
          onTap: () => context.read<AuthController>().logout(),
          isDestructive: true,
        ),
      ],
    );
  }
}

class ResidentDashboardScreen extends StatefulWidget {
  const ResidentDashboardScreen({super.key, required this.onOpenTab});
  final ValueChanged<int> onOpenTab;

  @override
  State<ResidentDashboardScreen> createState() =>
      _ResidentDashboardScreenState();
}

class _ResidentDashboardScreenState extends State<ResidentDashboardScreen> {
  Map<String, dynamic>? _data;
  String? _error;
  var _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final response =
          await context.read<AuthController>().api.get('resident/dashboard');
      _data = Map<String, dynamic>.from(response['data'] as Map);
    } on ApiException catch (error) {
      _error = error.message;
    }
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return _ErrorState(message: _error!, onRetry: _load);
    }
    final dashboard = _data!;
    final resident = Map<String, dynamic>.from(dashboard['resident'] as Map);
    final dues = Map<String, dynamic>.from(dashboard['dues'] as Map);
    final visitors = Map<String, dynamic>.from(dashboard['visitors'] as Map);
    final complaints =
        Map<String, dynamic>.from(dashboard['complaints'] as Map);
    final upcomingBooking = dashboard['upcoming_booking'] as Map?;
    final latestNotice = dashboard['latest_notice'] as Map?;
    final outstanding = _money(dues['outstanding_amount']);
    final overdue = _money(dues['overdue_amount']);
    final greeting = switch (DateTime.now().hour) {
      < 12 => 'Good morning',
      < 17 => 'Good afternoon',
      _ => 'Good evening',
    };
    
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFFF5F3FF),
            Color(0xFFFAF5FF),
            Color(0xFFFFFBFE),
          ],
        ),
      ),
      child: RefreshIndicator(
        onRefresh: _load,
        color: const Color(0xFF6366F1),
        child: CustomScrollView(
          slivers: [
            // Custom Header
            SliverToBoxAdapter(
              child: _ModernHeader(
                greeting: greeting,
                name: resident['name']?.toString() ?? 'Resident',
                flatInfo:
                    'Flat ${resident['flat_number'] ?? ''} · ${resident['building'] ?? ''} Wing',
              ),
            ),
            
            // Overdue Alert
            if (_asDouble(dues['overdue_amount']) > 0)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  child: _ModernUrgentCard(
                    icon: Icons.warning_amber_rounded,
                    title: 'Maintenance payment overdue',
                    message:
                        '$overdue is overdue. Review your dues and create a secure payment request.',
                    action: 'Pay now',
                    onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const DuesScreen())),
                  ),
                ),
              ),
            
            // At a Glance Section
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: _ModernSectionHeader(
                  title: 'At a glance',
                  icon: Icons.dashboard_outlined,
                ),
              ),
            ),
            
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              sliver: SliverGrid(
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                  mainAxisExtent: 170,
                ),
                delegate: SliverChildListDelegate([
                  _ModernInsightCard(
                    icon: Icons.account_balance_wallet_outlined,
                    title: 'MY DUES',
                    value: outstanding == '₹0.00' ? 'No dues' : outstanding,
                    subtitle: _asDouble(dues['outstanding_amount']) > 0
                        ? 'Outstanding'
                        : 'All clear',
                    gradient: const LinearGradient(
                      colors: [Color(0xFFFFA726), Color(0xFFFB8C00)],
                    ),
                    isPrimary: true,
                    onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const DuesScreen())),
                  ),
                  _ModernInsightCard(
                    icon: Icons.person_pin_circle_outlined,
                    title: 'AT THE GATE',
                    value: '${visitors['at_gate'] ?? 0}',
                    subtitle:
                        visitors['at_gate'] == 0 ? 'No visitors' : 'Waiting',
                    gradient: const LinearGradient(
                      colors: [Color(0xFF42A5F5), Color(0xFF1E88E5)],
                    ),
                    onTap: () => widget.onOpenTab(2),
                  ),
                  _ModernInsightCard(
                    icon: Icons.support_agent_outlined,
                    title: 'HELPDESK',
                    value: '${complaints['open'] ?? 0}',
                    subtitle:
                        complaints['open'] == 0 ? 'No requests' : 'Active',
                    gradient: const LinearGradient(
                      colors: [Color(0xFF7E57C2), Color(0xFF5E35B1)],
                    ),
                    onTap: () => Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => const ModuleScreen(
                            title: 'Complaints', role: 'RESIDENT'))),
                  ),
                  _ModernInsightCard(
                    icon: Icons.event_available_outlined,
                    title: 'VISITORS TODAY',
                    value: '${visitors['expected_today'] ?? 0}',
                    subtitle: visitors['expected_today'] == 0
                        ? 'None expected'
                        : 'Expected',
                    gradient: const LinearGradient(
                      colors: [Color(0xFF26A69A), Color(0xFF00897B)],
                    ),
                    onTap: () => widget.onOpenTab(2),
                  ),
                ]),
              ),
            ),
            
            // Quick Actions
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.fromLTRB(16, 24, 16, 0),
                child: _ModernSectionHeader(
                  title: 'Quick actions',
                  icon: Icons.bolt_outlined,
                ),
              ),
            ),
            
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              sliver: SliverToBoxAdapter(
                child: Row(
                  children: [
                    Expanded(
                      child: _ModernQuickAction(
                        icon: Icons.person_add_alt_1_rounded,
                        label: 'Add visitor',
                        gradient: const LinearGradient(
                          colors: [Color(0xFFE3F2FD), Color(0xFFBBDEFB)],
                        ),
                        iconColor: const Color(0xFF1976D2),
                        onTap: () => widget.onOpenTab(2),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _ModernQuickAction(
                        icon: Icons.payments_rounded,
                        label: 'Pay dues',
                        gradient: const LinearGradient(
                          colors: [Color(0xFFFFF3E0), Color(0xFFFFE0B2)],
                        ),
                        iconColor: const Color(0xFFE65100),
                        isPrimary: true,
                        onTap: () => Navigator.of(context).push(
                            MaterialPageRoute(
                                builder: (_) => const DuesScreen())),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
              sliver: SliverToBoxAdapter(
                child: Row(
                  children: [
                    Expanded(
                      child: _ModernQuickAction(
                        icon: Icons.calendar_month_rounded,
                        label: 'Book amenity',
                        gradient: const LinearGradient(
                          colors: [Color(0xFFF3E5F5), Color(0xFFE1BEE7)],
                        ),
                        iconColor: const Color(0xFF6A1B9A),
                        onTap: () => Navigator.of(context).push(
                            MaterialPageRoute(
                                builder: (_) => const ModuleScreen(
                                    title: 'Amenities', role: 'RESIDENT'))),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _ModernQuickAction(
                        icon: Icons.support_agent_rounded,
                        label: 'Helpdesk',
                        gradient: const LinearGradient(
                          colors: [Color(0xFFE8EAF6), Color(0xFFC5CAE9)],
                        ),
                        iconColor: const Color(0xFF3F51B5),
                        onTap: () => Navigator.of(context).push(
                            MaterialPageRoute(
                                builder: (_) => const ModuleScreen(
                                    title: 'Complaints', role: 'RESIDENT'))),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            
            // Society Snapshot
            if (upcomingBooking != null || latestNotice != null)
              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(16, 24, 16, 0),
                  child: _ModernSectionHeader(
                    title: 'Society snapshot',
                    icon: Icons.insights_outlined,
                  ),
                ),
              ),
            
            // Upcoming Booking
            if (upcomingBooking != null)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  child: _ModernInfoCard(
                    icon: Icons.event_rounded,
                    iconColor: const Color(0xFF7E57C2),
                    iconBackground: const Color(0xFFF3E5F5),
                    title: 'Upcoming booking',
                    subtitle: upcomingBooking['amenity_name']?.toString() ??
                        'Amenity booking',
                    detail:
                        '${upcomingBooking['booking_date'] ?? ''} at ${upcomingBooking['start_time'] ?? ''}',
                    onTap: () => Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => const ModuleScreen(
                            title: 'Bookings', role: 'RESIDENT'))),
                  ),
                ),
              ),
            
            // Announcements
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 24, 16, 0),
                child: _ModernSectionHeader(
                  title: 'Announcements',
                  icon: Icons.campaign_outlined,
                  action: 'View all',
                  onAction: () => Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => const ModuleScreen(
                          title: 'Notices', role: 'RESIDENT'))),
                ),
              ),
            ),
            
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
                child: latestNotice == null
                    ? const _ModernEmptyCard(
                        icon: Icons.campaign_outlined,
                        message: 'No announcements right now',
                      )
                    : _ModernInfoCard(
                        icon: Icons.campaign_rounded,
                        iconColor: const Color(0xFFE65100),
                        iconBackground: const Color(0xFFFFF3E0),
                        title: latestNotice['title']?.toString() ??
                            'Society update',
                        subtitle: latestNotice['content']?.toString() ?? '',
                        showArrow: true,
                        onTap: () => Navigator.of(context).push(
                            MaterialPageRoute(
                                builder: (_) => const ModuleScreen(
                                    title: 'Notices', role: 'RESIDENT'))),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class MyUnitScreen extends StatefulWidget {
  const MyUnitScreen({super.key});

  @override
  State<MyUnitScreen> createState() => _MyUnitScreenState();
}

class _MyUnitScreenState extends State<MyUnitScreen> {
  Map<String, dynamic>? _profile;
  List<dynamic> _parking = [];
  String? _error;
  var _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final api = context.read<AuthController>().api;
      final result = await Future.wait([
        api.get('resident/profile'),
        api.get('resident/parking-slots'),
      ]);
      _profile = Map<String, dynamic>.from(result[0]['data'] as Map);
      _parking = _pageItems(result[1]);
    } on ApiException catch (error) {
      _error = error.message;
    }
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) return _ErrorState(message: _error!, onRetry: _load);
    final profile = _profile!;
    final user = profile['user'] is Map
        ? Map<String, dynamic>.from(profile['user'] as Map)
        : <String, dynamic>{};
    final flat = profile['flat'] is Map
        ? Map<String, dynamic>.from(profile['flat'] as Map)
        : <String, dynamic>{};
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(padding: const EdgeInsets.all(16), children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Row(children: [
              CircleAvatar(
                  radius: 30, child: Text(_initials(user['name']?.toString()))),
              const SizedBox(width: 14),
              Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    Text(user['name']?.toString() ?? 'Resident',
                        style: Theme.of(context).textTheme.titleLarge),
                    Text(user['email']?.toString() ?? ''),
                    Text(
                        'Flat ${flat['flat_number'] ?? '—'} · ${flat['building'] ?? '—'}'),
                  ])),
              IconButton(
                tooltip: 'Edit profile',
                icon: const Icon(Icons.edit_outlined),
                onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => const ModuleScreen(
                        title: 'Profile', role: 'RESIDENT'))),
              ),
            ]),
          ),
        ),
        const SizedBox(height: 20),
        const _SectionHeader(title: 'Your parking'),
        if (_parking.isEmpty)
          const _EmptyCard(message: 'No parking slot is assigned to your unit.')
        else
          ..._parking.map((item) {
            final slot = Map<String, dynamic>.from(item as Map);
            return _InfoCard(
              icon: Icons.local_parking_outlined,
              title: slot['slot_number']?.toString() ?? 'Parking slot',
              subtitle: [slot['parking_type'], slot['vehicle_number']]
                  .whereType<String>()
                  .join(' · '),
            );
          }),
        const SizedBox(height: 20),
        const _SectionHeader(title: 'Unit services'),
        _InfoCard(
            icon: Icons.payment_outlined,
            title: 'Maintenance dues',
            subtitle: 'View bills, payment requests and history',
            onTap: () => Navigator.of(context)
                .push(MaterialPageRoute(builder: (_) => const DuesScreen()))),
        _InfoCard(
            icon: Icons.people_outline,
            title: 'Resident profile',
            subtitle: 'Keep your contact details updated',
            onTap: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) =>
                    const ModuleScreen(title: 'Profile', role: 'RESIDENT')))),
      ]),
    );
  }
}

class DuesScreen extends StatefulWidget {
  const DuesScreen({super.key});

  @override
  State<DuesScreen> createState() => _DuesScreenState();
}

class _DuesScreenState extends State<DuesScreen> {
  List<Map<String, dynamic>> _bills = [];
  final Set<int> _selectedBillIds = <int>{};
  var _selectedTab = 0;
  String? _error;
  var _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      _bills = _pageItems(await context
              .read<AuthController>()
              .api
              .get('resident/maintenance-bills'))
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList();
      _selectedBillIds
          .removeWhere((id) => !_bills.any((bill) => bill['id'] == id));
    } on ApiException catch (error) {
      _error = error.message;
    }
    if (mounted) setState(() => _loading = false);
  }

  List<Map<String, dynamic>> get _openInvoices => _bills
      .where(
          (bill) => _asDouble(bill['outstanding_amount'] ?? bill['amount']) > 0)
      .toList();

  List<Map<String, dynamic>> get _historyInvoices {
    final invoices = List<Map<String, dynamic>>.from(_bills);
    invoices.sort((first, second) => (second['created_at']?.toString() ?? '')
        .compareTo(first['created_at']?.toString() ?? ''));

    return invoices;
  }

  double get _selectedTotal => _bills
      .where((item) => _selectedBillIds.contains(item['id']))
      .fold<double>(
          0,
          (total, item) =>
              total + _asDouble(item['outstanding_amount'] ?? item['amount']));

  Future<void> _openInvoice(Map<String, dynamic> invoice) async {
    await Navigator.of(context).push<void>(MaterialPageRoute(
        builder: (_) => InvoiceViewerScreen(invoice: invoice)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
        appBar: AppBar(title: const Text('My Dues'), actions: [
          IconButton(
            tooltip: 'Transaction history',
            icon: const Icon(Icons.history),
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => const TransactionHistoryScreen())),
          ),
          IconButton(
            tooltip: 'Payment activity',
            icon: const Icon(Icons.receipt_long_outlined),
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => const PaymentActivityScreen())),
          ),
        ]),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? _ErrorState(message: _error!, onRetry: _load)
                : Column(children: [
                    _DuesTabs(
                      selectedIndex: _selectedTab,
                      onChanged: (index) =>
                          setState(() => _selectedTab = index),
                    ),
                    Expanded(
                      child: RefreshIndicator(
                        onRefresh: _load,
                        child: switch (_selectedTab) {
                          1 => _buildHistory(),
                          2 => _buildAdvance(),
                          _ => _buildOpenInvoices(),
                        },
                      ),
                    ),
                  ]),
        bottomNavigationBar: _selectedTab != 0 || _selectedBillIds.isEmpty
            ? null
            : SafeArea(
                child: Container(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    boxShadow: [
                      BoxShadow(color: Color(0x22000000), blurRadius: 12)
                    ],
                  ),
                  child: Row(children: [
                    Expanded(
                        child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('${_selectedBillIds.length} invoice(s) selected'),
                        Text(_money(_selectedTotal),
                            style: Theme.of(context)
                                .textTheme
                                .titleLarge
                                ?.copyWith(fontWeight: FontWeight.w800)),
                      ],
                    )),
                    FilledButton(
                      onPressed: _selectedTotal <= 0
                          ? null
                          : () async {
                              final changed = await Navigator.of(context)
                                  .push<bool>(MaterialPageRoute(
                                      builder: (_) => FullPaymentCheckoutScreen(
                                          billIds: _selectedBillIds.toList())));
                              if (changed == true) _load();
                            },
                      child: const Text('Pay Now'),
                    ),
                  ]),
                ),
              ));
  }

  Widget _buildOpenInvoices() {
    if (_openInvoices.isEmpty) {
      return ListView(children: const [
        SizedBox(height: 180),
        Center(child: Text('You have no open invoices.')),
      ]);
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      itemCount: _openInvoices.length,
      itemBuilder: (_, index) => _invoiceCard(_openInvoices[index]),
    );
  }

  Widget _invoiceCard(Map<String, dynamic> bill) {
    final outstanding = _asDouble(bill['outstanding_amount'] ?? bill['amount']);
    final status = bill['status']?.toString() ?? 'UNPAID';
    final billId = bill['id'] as int;
    final isSelected = _selectedBillIds.contains(billId);
    final suppliedDescription = bill['notes']?.toString().trim();
    final description = suppliedDescription == null ||
            suppliedDescription.isEmpty
        ? 'Monthly maintenance invoice for ${_monthAndYear(bill['billing_month'])}'
        : suppliedDescription;

    return Card(
      clipBehavior: Clip.antiAlias,
      margin: const EdgeInsets.only(bottom: 14),
      child: InkWell(
        onTap: () => _openInvoice(bill),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(
                child: Text(
                  'Maintenance · ${_monthAndYear(bill['billing_month'])}',
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              _StatusBadge(status: status),
              const SizedBox(width: 2),
              Checkbox(
                value: isSelected,
                visualDensity: VisualDensity.compact,
                onChanged: (selected) => setState(() {
                  if (selected == true) {
                    _selectedBillIds.add(billId);
                  } else {
                    _selectedBillIds.remove(billId);
                  }
                }),
              ),
            ]),
            const SizedBox(height: 12),
            Text('Due ${_friendlyDate(bill['due_date'])}'),
            const SizedBox(height: 5),
            Text(_money(outstanding),
                style: Theme.of(context)
                    .textTheme
                    .headlineSmall
                    ?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            Text(description, maxLines: 2, overflow: TextOverflow.ellipsis),
            const Divider(height: 28),
            Row(children: [
              TextButton.icon(
                onPressed: () => _openInvoice(bill),
                icon: const Icon(Icons.description_outlined),
                label: const Text('View Invoice'),
              ),
              const Spacer(),
              FilledButton(
                onPressed: () async {
                  final changed = await Navigator.of(context).push<bool>(
                      MaterialPageRoute(
                          builder: (_) => PaymentCheckoutScreen(bill: bill)));
                  if (changed == true) _load();
                },
                child: const Text('Pay full amount'),
              ),
            ]),
          ]),
        ),
      ),
    );
  }

  Widget _buildHistory() => _historyInvoices.isEmpty
      ? ListView(children: const [
          SizedBox(height: 180),
          Center(child: Text('No invoice history yet.')),
        ])
      : ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              color: Colors.blue.shade50,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.account_balance_wallet_outlined,
                            color: Colors.blue.shade700),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'View Complete Ledger',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: Colors.blue.shade900,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'See your complete transaction history with debit/credit entries and running balance',
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.blue.shade800,
                      ),
                    ),
                    const SizedBox(height: 12),
                    FilledButton.icon(
                      onPressed: () => Navigator.of(context).push(
                          MaterialPageRoute(
                              builder: (_) =>
                                  const TransactionHistoryScreen())),
                      icon: const Icon(Icons.history),
                      label: const Text('View Transaction History'),
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.blue.shade700,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'Invoice History',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(height: 12),
            for (final bill in _historyInvoices)
              Card(
                margin: const EdgeInsets.only(bottom: 12),
                child: ListTile(
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  leading: const CircleAvatar(
                      child: Icon(Icons.receipt_long_outlined)),
                  title: const Text('Invoice Posted on'),
                  subtitle: Text(
                      '${_friendlyDate(bill['created_at'])}\n${bill['status']?.toString().replaceAll('_', ' ') ?? 'INVOICE'}'),
                  isThreeLine: true,
                  trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                    Text(_money(bill['amount']),
                        style: const TextStyle(fontWeight: FontWeight.w700)),
                    const SizedBox(width: 6),
                    const Icon(Icons.chevron_right),
                  ]),
                  onTap: () => _openInvoice(bill),
                ),
              ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              icon: const Icon(Icons.payments_outlined),
              label: const Text('View payment history'),
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => const PaymentActivityScreen())),
            ),
          ],
        );

  Widget _buildAdvance() => ListView(
        children: const [
          SizedBox(height: 120),
          Padding(
            padding: EdgeInsets.all(32),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.savings_outlined, size: 54, color: Color(0xFF5C558A)),
              SizedBox(height: 12),
              Text('Advance balance',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
              SizedBox(height: 8),
              Text('No advance balance is recorded for your account.',
                  textAlign: TextAlign.center),
            ]),
          ),
        ],
      );
}

class _DuesTabs extends StatelessWidget {
  const _DuesTabs({required this.selectedIndex, required this.onChanged});
  final int selectedIndex;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    const labels = ['Open Invoices', 'History', 'Advance'];
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: const Color(0xFFF0EEF5),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: List.generate(labels.length, (index) {
          final selected = selectedIndex == index;
          return Expanded(
            child: Semantics(
              selected: selected,
              button: true,
              child: InkWell(
                borderRadius: BorderRadius.circular(9),
                onTap: () => onChanged(index),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(
                    color:
                        selected ? const Color(0xFF33256F) : Colors.transparent,
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: Text(labels[index],
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color:
                            selected ? Colors.white : const Color(0xFF24213B),
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      )),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}

class PaymentCheckoutScreen extends StatefulWidget {
  const PaymentCheckoutScreen({super.key, required this.bill});
  final Map<String, dynamic> bill;

  @override
  State<PaymentCheckoutScreen> createState() => _PaymentCheckoutScreenState();
}

class _PaymentCheckoutScreenState extends State<PaymentCheckoutScreen> {
  late Razorpay _razorpay;
  var _method = 'UPI';
  var _submitting = false;
  String? _error;
  Map<String, dynamic>? _pendingOrderData;

  @override
  void initState() {
    super.initState();
    _razorpay = Razorpay();
    _razorpay.on(Razorpay.EVENT_PAYMENT_SUCCESS, _handlePaymentSuccess);
    _razorpay.on(Razorpay.EVENT_PAYMENT_ERROR, _handlePaymentError);
    _razorpay.on(Razorpay.EVENT_EXTERNAL_WALLET, _handleExternalWallet);
  }

  @override
  void dispose() {
    _razorpay.clear();
    super.dispose();
  }

  Future<void> _handlePaymentSuccess(PaymentSuccessResponse response) async {
    if (!mounted) return;
    setState(() {
      _submitting = true;
      _error = null;
    });

    try {
      final api = context.read<AuthController>().api;
      await api.post('resident/payments/verify', {
        'razorpay_order_id':
            response.orderId ?? _pendingOrderData?['order_id'] ?? '',
        'razorpay_payment_id': response.paymentId ?? '',
        'razorpay_signature': response.signature ?? '',
      });

      if (!mounted) return;
      final billMonth = _monthAndYear(widget.bill['billing_month']);
      final amount = _asDouble(_pendingOrderData?['amount_formatted'] ??
          widget.bill['outstanding_amount'] ??
          widget.bill['amount']);

      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => AlertDialog(
          icon: const Icon(Icons.check_circle, color: Colors.green, size: 48),
          title: const Text('Payment Successful'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Invoice: Maintenance · $billMonth'),
              const SizedBox(height: 6),
              Text('Amount: ${_money(amount)}',
                  style: const TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 6),
              Text('Payment ID: ${response.paymentId}',
                  style: const TextStyle(fontSize: 12, color: Colors.grey)),
            ],
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Done'),
            ),
          ],
        ),
      );

      if (mounted) Navigator.pop(context, true);
    } on ApiException catch (error) {
      if (mounted) {
        setState(() => _error = error.message);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Payment verification failed: ${error.message}'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _error = 'Verification failed: $e');
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  void _handlePaymentError(PaymentFailureResponse response) {
    if (!mounted) return;
    setState(() => _submitting = false);

    if (response.code == Razorpay.PAYMENT_CANCELLED) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Payment cancelled.')),
      );
    } else {
      final msg = response.message ??
          'Payment failed. Your invoice has not been marked as paid.';
      setState(() => _error = msg);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(msg),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    }
  }

  void _handleExternalWallet(ExternalWalletResponse response) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
          content: Text('External wallet selected: ${response.walletName}')),
    );
  }

  Future<void> _submit() async {
    if (_submitting) return;
    setState(() {
      _submitting = true;
      _error = null;
    });

    try {
      final api = context.read<AuthController>().api;
      final createOrderRes = await api.post('resident/payments/create-order', {
        'invoiceId': widget.bill['id'],
        'payment_method': _method,
      });

      final data =
          Map<String, dynamic>.from(createOrderRes['data'] as Map);
      _pendingOrderData = data;

      final options = <String, dynamic>{
        'key': data['key_id'],
        'amount': data['amount'],
        'name': data['name'] ?? 'Nivora',
        'description': data['description'] ?? 'Maintenance Bill',
        'order_id': data['order_id'],
        'prefill': data['prefill'] is Map
            ? Map<String, dynamic>.from(data['prefill'] as Map)
            : <String, dynamic>{},
        'notes': data['notes'] is Map
            ? Map<String, dynamic>.from(data['notes'] as Map)
            : <String, dynamic>{},
        'timeout': 180,
      };

      _razorpay.open(options);
    } on ApiException catch (error) {
      if (mounted) {
        setState(() {
          _error = error.message;
          _submitting = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Failed to initiate payment: $e';
          _submitting = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final amount =
        _asDouble(widget.bill['outstanding_amount'] ?? widget.bill['amount']);
    final rawMaintenance = _asDouble(widget.bill['base_maintenance']);
    final water = _asDouble(widget.bill['water_charge']);
    final electricity =
        _asDouble(widget.bill['electricity_common_area_charge']);
    final parking = _asDouble(widget.bill['parking_charge']);
    final other = _asDouble(widget.bill['other_charges']);
    final lateFee = _asDouble(widget.bill['late_fee']);
    final discount = _asDouble(widget.bill['discount']);
    final maintenance = (rawMaintenance == 0 &&
            water == 0 &&
            electricity == 0 &&
            parking == 0 &&
            other == 0)
        ? amount
        : rawMaintenance;

    return Scaffold(
      appBar: AppBar(title: const Text('Review payment')),
      body: ListView(padding: const EdgeInsets.all(20), children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Amount due',
                    style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                Text(_money(amount),
                    style: Theme.of(context)
                        .textTheme
                        .headlineMedium
                        ?.copyWith(fontWeight: FontWeight.w700)),
                const Divider(height: 28),
                _PaymentLine(
                    label: 'Maintenance', value: _money(maintenance)),
                if (water > 0)
                  _PaymentLine(
                      label: 'Water charge', value: _money(water)),
                if (electricity > 0)
                  _PaymentLine(
                      label: 'Common electricity',
                      value: _money(electricity)),
                if (parking > 0)
                  _PaymentLine(
                      label: 'Parking charge', value: _money(parking)),
                if (other > 0)
                  _PaymentLine(
                      label: 'Other charges', value: _money(other)),
                if (lateFee > 0)
                  _PaymentLine(
                      label: 'Late fee', value: _money(lateFee)),
                if (discount > 0)
                  _PaymentLine(
                      label: 'Discount', value: '-${_money(discount)}'),
                const _PaymentLine(
                    label: 'Previous dues', value: '₹0.00'),
                const Divider(),
                _PaymentLine(
                    label: 'Total due', value: _money(amount), bold: true),
                const SizedBox(height: 12),
                Text('Due date: ${_friendlyDate(widget.bill['due_date'])}',
                    style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
        ),
        const SizedBox(height: 20),
        Text('Payment method', style: Theme.of(context).textTheme.titleMedium),
        RadioGroup<String>(
          groupValue: _method,
          onChanged: (value) {
            if (!_submitting) setState(() => _method = value!);
          },
          child: Column(children: [
            for (final method in const [
              'UPI',
              'CREDIT_CARD',
              'DEBIT_CARD',
              'NET_BANKING',
              'OTHER',
            ])
              RadioListTile<String>(
                  value: method, title: Text(_paymentMethodLabel(method))),
          ]),
        ),
        if (_error != null) ...[
          const SizedBox(height: 12),
          Text(_error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error)),
        ],
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: _submitting ? null : _submit,
          icon: _submitting
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.lock_outline),
          label: Text(_submitting ? 'Creating payment…' : 'Pay full amount'),
        ),
      ]),
    );
  }
}

class FullPaymentCheckoutScreen extends StatefulWidget {
  const FullPaymentCheckoutScreen({super.key, this.billIds});
  final List<int>? billIds;

  @override
  State<FullPaymentCheckoutScreen> createState() =>
      _FullPaymentCheckoutScreenState();
}

class _FullPaymentCheckoutScreenState extends State<FullPaymentCheckoutScreen> {
  late Razorpay _razorpay;
  var _method = 'UPI';
  var _submitting = false;
  var _loadingSummary = true;
  Map<String, dynamic>? _summary;
  String? _error;
  Map<String, dynamic>? _pendingOrderData;

  @override
  void initState() {
    super.initState();
    _razorpay = Razorpay();
    _razorpay.on(Razorpay.EVENT_PAYMENT_SUCCESS, _handlePaymentSuccess);
    _razorpay.on(Razorpay.EVENT_PAYMENT_ERROR, _handlePaymentError);
    _razorpay.on(Razorpay.EVENT_EXTERNAL_WALLET, _handleExternalWallet);
    _loadSummary();
  }

  @override
  void dispose() {
    _razorpay.clear();
    super.dispose();
  }

  Future<void> _loadSummary() async {
    setState(() {
      _loadingSummary = true;
      _error = null;
    });
    try {
      final endpoint = widget.billIds != null && widget.billIds!.isNotEmpty
          ? 'resident/payment-summary?maintenance_bill_ids=${widget.billIds!.join(',')}'
          : 'resident/payment-summary';
      final response =
          await context.read<AuthController>().api.get(endpoint);
      _summary = Map<String, dynamic>.from(response['data'] as Map);
    } on ApiException catch (error) {
      _error = error.message;
    }
    if (mounted) setState(() => _loadingSummary = false);
  }

  Future<void> _handlePaymentSuccess(PaymentSuccessResponse response) async {
    if (!mounted) return;
    setState(() {
      _submitting = true;
      _error = null;
    });

    try {
      final api = context.read<AuthController>().api;
      await api.post('resident/payments/verify', {
        'razorpay_order_id':
            response.orderId ?? _pendingOrderData?['order_id'] ?? '',
        'razorpay_payment_id': response.paymentId ?? '',
        'razorpay_signature': response.signature ?? '',
      });

      if (!mounted) return;
      final amount = _asDouble(_pendingOrderData?['amount_formatted'] ??
          _summary?['total_due'] ??
          0);

      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => AlertDialog(
          icon: const Icon(Icons.check_circle, color: Colors.green, size: 48),
          title: const Text('Payment Successful'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('All outstanding dues payment completed.'),
              const SizedBox(height: 6),
              Text('Amount: ${_money(amount)}',
                  style: const TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 6),
              Text('Payment ID: ${response.paymentId}',
                  style: const TextStyle(fontSize: 12, color: Colors.grey)),
            ],
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Done'),
            ),
          ],
        ),
      );

      if (mounted) Navigator.pop(context, true);
    } on ApiException catch (error) {
      if (mounted) {
        setState(() => _error = error.message);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Payment verification failed: ${error.message}'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _error = 'Verification failed: $e');
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  void _handlePaymentError(PaymentFailureResponse response) {
    if (!mounted) return;
    setState(() => _submitting = false);

    if (response.code == Razorpay.PAYMENT_CANCELLED) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Payment cancelled.')),
      );
    } else {
      final msg = response.message ??
          'Payment failed. Your invoices have not been marked as paid.';
      setState(() => _error = msg);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(msg),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    }
  }

  void _handleExternalWallet(ExternalWalletResponse response) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
          content: Text('External wallet selected: ${response.walletName}')),
    );
  }

  Future<void> _submit() async {
    if (_submitting) return;
    setState(() {
      _submitting = true;
      _error = null;
    });

    try {
      final api = context.read<AuthController>().api;
      final createOrderRes = await api.post('resident/payments/create-order', {
        'payment_method': _method,
        if (widget.billIds != null) 'maintenance_bill_ids': widget.billIds,
      });

      final data =
          Map<String, dynamic>.from(createOrderRes['data'] as Map);
      _pendingOrderData = data;

      final options = <String, dynamic>{
        'key': data['key_id'],
        'amount': data['amount'],
        'name': data['name'] ?? 'Nivora',
        'description': data['description'] ?? 'All Outstanding Dues',
        'order_id': data['order_id'],
        'prefill': data['prefill'] is Map
            ? Map<String, dynamic>.from(data['prefill'] as Map)
            : <String, dynamic>{},
        'notes': data['notes'] is Map
            ? Map<String, dynamic>.from(data['notes'] as Map)
            : <String, dynamic>{},
        'timeout': 180,
      };

      _razorpay.open(options);
    } on ApiException catch (error) {
      if (mounted) {
        setState(() {
          _error = error.message;
          _submitting = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Failed to initiate payment: $e';
          _submitting = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loadingSummary) {
      return Scaffold(
          appBar: AppBar(title: const Text('Pay all outstanding dues')),
          body: const Center(child: CircularProgressIndicator()));
    }
    if (_summary == null) {
      return Scaffold(
          appBar: AppBar(title: const Text('Pay all outstanding dues')),
          body: _ErrorState(message: _error!, onRetry: _loadSummary));
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Pay all outstanding dues')),
      body: ListView(padding: const EdgeInsets.all(20), children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Amount due',
                    style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                Text(_money(_summary!['total_due']),
                    style: Theme.of(context)
                        .textTheme
                        .headlineMedium
                        ?.copyWith(fontWeight: FontWeight.w700)),
                const Divider(height: 28),
                _PaymentLine(
                    label: 'Maintenance',
                    value: _money(_summary!['maintenance'])),
                _PaymentLine(
                    label: 'Water charge',
                    value: _money(_summary!['water_charge'])),
                _PaymentLine(
                    label: 'Common electricity',
                    value: _money(_summary!['electricity_common_area_charge'])),
                _PaymentLine(
                    label: 'Parking charge',
                    value: _money(_summary!['parking_charge'])),
                _PaymentLine(
                    label: 'Other charges',
                    value: _money(_summary!['other_charges'])),
                _PaymentLine(
                    label: 'Late fee', value: _money(_summary!['late_fee'])),
                if (_asDouble(_summary!['discount']) > 0)
                  _PaymentLine(
                      label: 'Discount',
                      value: '-${_money(_summary!['discount'])}'),
                _PaymentLine(
                    label: 'Previous dues',
                    value: _money(_summary!['previous_dues'])),
                const Divider(),
                _PaymentLine(
                    label: 'Total due',
                    value: _money(_summary!['total_due']),
                    bold: true),
                const SizedBox(height: 12),
                const Text(
                    'The backend calculates this amount from your outstanding bills. The app never sends the payable amount.'),
              ],
            ),
          ),
        ),
        const SizedBox(height: 20),
        Text('Payment method', style: Theme.of(context).textTheme.titleMedium),
        RadioGroup<String>(
          groupValue: _method,
          onChanged: (value) {
            if (!_submitting) setState(() => _method = value!);
          },
          child: Column(children: [
            for (final method in const [
              'UPI',
              'CREDIT_CARD',
              'DEBIT_CARD',
              'NET_BANKING',
              'OTHER',
            ])
              RadioListTile<String>(
                  value: method, title: Text(_paymentMethodLabel(method))),
          ]),
        ),
        if (_error != null) ...[
          const SizedBox(height: 12),
          Text(_error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error)),
        ],
        const SizedBox(height: 16),
        FilledButton.icon(
            onPressed: _submitting ? null : _submit,
            icon: _submitting
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.lock_outline),
            label: Text(
                _submitting ? 'Creating payment…' : 'Pay full amount')),
      ]),
    );
  }
}


class InvoiceViewerScreen extends StatefulWidget {
  const InvoiceViewerScreen({super.key, required this.invoice});
  final Map<String, dynamic> invoice;

  @override
  State<InvoiceViewerScreen> createState() => _InvoiceViewerScreenState();
}

class _InvoiceViewerScreenState extends State<InvoiceViewerScreen> {
  late Map<String, dynamic> _invoice;
  String? _error;
  var _loading = true;

  @override
  void initState() {
    super.initState();
    _invoice = Map<String, dynamic>.from(widget.invoice);
    _loadInvoice();
  }

  Future<void> _loadInvoice() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final response = await context
          .read<AuthController>()
          .api
          .get('resident/maintenance-bills/${_invoice['id']}');
      if (mounted) {
        setState(() =>
            _invoice = Map<String, dynamic>.from(response['data'] as Map));
      }
    } on ApiException catch (error) {
      if (mounted) {
        setState(() => _error = error.message);
      }
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Invoice')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    if (_error != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Invoice')),
        body: _ErrorState(message: _error!, onRetry: _loadInvoice),
      );
    }

    final invoice = _invoice;
    final document = invoice['invoice'] is Map
        ? Map<String, dynamic>.from(invoice['invoice'] as Map)
        : <String, dynamic>{};
    final society = document['society'] is Map
        ? Map<String, dynamic>.from(document['society'] as Map)
        : <String, dynamic>{};
    final unit = document['unit'] is Map
        ? Map<String, dynamic>.from(document['unit'] as Map)
        : invoice['flat'] is Map
            ? Map<String, dynamic>.from(invoice['flat'] as Map)
            : <String, dynamic>{};
    final resident = document['resident'] is Map
        ? Map<String, dynamic>.from(document['resident'] as Map)
        : <String, dynamic>{};
    final lines = document['line_items'] is List
        ? (document['line_items'] as List)
            .whereType<Map>()
            .map((line) => Map<String, dynamic>.from(line))
            .toList()
        : <Map<String, dynamic>>[];
    final currentTotal =
        _asDouble(document['current_total'] ?? invoice['amount']);
    final paid = _asDouble(document['paid_amount'] ?? invoice['paid_amount']);
    final previousDues = _asDouble(document['previous_dues']);
    final netPayable = _asDouble(document['net_payable'] ??
        invoice['outstanding_amount'] ??
        (currentTotal - paid));
    final unitLabel = [
      unit['building']?.toString(),
      unit['flat_number']?.toString(),
    ].whereType<String>().where((part) => part.isNotEmpty).join(' · ');
    final address =
        society['address']?.toString().replaceAll(r'\n', '\n').trim();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Invoice'),
        actions: const [
          Padding(
            padding: EdgeInsets.only(right: 16),
            child: Icon(Icons.description_outlined),
          ),
        ],
      ),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Center(
                child: Text('INVOICE',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w800, letterSpacing: 1.4)),
              ),
              const SizedBox(height: 20),
              Text(society['name']?.toString() ?? 'Nivora',
                  style: Theme.of(context)
                      .textTheme
                      .titleLarge
                      ?.copyWith(fontWeight: FontWeight.w800)),
              Text(
                address == null || address.isEmpty
                    ? 'Society address is not configured.'
                    : address,
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const Divider(height: 30),
              Text('Unit : ${unitLabel.isEmpty ? '-' : unitLabel}'),
              Text(
                  'Kind Attn. : ${resident['name']?.toString() ?? context.read<AuthController>().session?.user.name ?? '-'}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis),
              const SizedBox(height: 14),
              _PaymentLine(
                  label: 'Invoice No.',
                  value: document['invoice_number']?.toString() ??
                      'INV-${invoice['id']}'),
              _PaymentLine(
                  label: 'Invoice Date',
                  value: _friendlyDate(
                      document['invoice_date'] ?? invoice['created_at'])),
              _PaymentLine(
                  label: 'Due Date',
                  value: _friendlyDate(
                      document['due_date'] ?? invoice['due_date'])),
              _PaymentLine(
                  label: 'Invoice Period',
                  value: document['invoice_period']?.toString() ??
                      _monthAndYear(invoice['billing_month'])),
              const Divider(height: 30),
              const Row(children: [
                Expanded(
                    flex: 4,
                    child: Text('Accounts',
                        style: TextStyle(fontWeight: FontWeight.w800))),
                Expanded(
                    flex: 3,
                    child: Text('Rate / Comments',
                        style: TextStyle(fontWeight: FontWeight.w800))),
                Expanded(
                    flex: 2,
                    child: Text('Amount',
                        textAlign: TextAlign.right,
                        style: TextStyle(fontWeight: FontWeight.w800))),
              ]),
              const Divider(),
              if (lines.isEmpty)
                _InvoiceDocumentLine(
                    account: 'Maintenance Fee',
                    comment: 'Monthly maintenance fee',
                    amount: currentTotal)
              else
                for (final line in lines)
                  _InvoiceDocumentLine(
                    account: line['account']?.toString() ?? 'Charge',
                    rate: line['rate'],
                    comment: line['comment']?.toString() ?? '',
                    amount: _asDouble(line['amount']),
                  ),
              const Divider(height: 30),
              _PaymentLine(
                  label: 'Current Total',
                  value: _money(currentTotal),
                  bold: true),
              _PaymentLine(
                  label:
                      'Dues as of ${_friendlyDate(document['previous_dues_as_of'])}',
                  value: _money(previousDues)),
              if (paid > 0)
                _PaymentLine(label: 'Amount paid', value: _money(paid)),
              _PaymentLine(
                  label: 'Net Payable', value: _money(netPayable), bold: true),
              const SizedBox(height: 16),
              Text('Amount in words',
                  style: Theme.of(context)
                      .textTheme
                      .labelLarge
                      ?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              Text(document['amount_in_words']?.toString() ??
                  '${_money(netPayable)} payable'),
              if ((invoice['notes']?.toString().isNotEmpty ?? false)) ...[
                const SizedBox(height: 18),
                Text(invoice['notes'].toString(),
                    style: Theme.of(context).textTheme.bodySmall),
              ],
              const SizedBox(height: 22),
              const Text('This is a system-generated invoice.',
                  style: TextStyle(fontSize: 11, color: Colors.black54)),
            ]),
          ),
        ),
      ]),
    );
  }
}

class _InvoiceDocumentLine extends StatelessWidget {
  const _InvoiceDocumentLine({
    required this.account,
    required this.comment,
    required this.amount,
    this.rate,
  });
  final String account;
  final dynamic rate;
  final String comment;
  final double amount;

  @override
  Widget build(BuildContext context) {
    final rateText = rate == null ? '' : '${_money(rate)}/month';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(flex: 4, child: Text(account)),
        Expanded(
          flex: 3,
          child: Text(
            [rateText, comment].where((text) => text.isNotEmpty).join('\n'),
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
        Expanded(
          flex: 2,
          child: Text(_money(amount), textAlign: TextAlign.right),
        ),
      ]),
    );
  }
}

class PaymentActivityScreen extends StatefulWidget {
  const PaymentActivityScreen({super.key});

  @override
  State<PaymentActivityScreen> createState() => _PaymentActivityScreenState();
}

class _PaymentActivityScreenState extends State<PaymentActivityScreen> {
  List<dynamic> _payments = [];
  List<dynamic> _orders = [];
  String? _error;
  var _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final api = context.read<AuthController>().api;
      final results = await Future.wait([
        api.get('resident/maintenance-payments'),
        api.get('resident/payment-orders'),
      ]);
      _payments = _pageItems(results[0]);
      _orders = _pageItems(results[1]);
    } on ApiException catch (error) {
      _error = error.message;
    }
    if (mounted) setState(() => _loading = false);
  }

  List<Map<String, dynamic>> get _activity {
    final entries = <Map<String, dynamic>>[
      ..._orders.map((raw) => {
            ...Map<String, dynamic>.from(raw as Map),
            '_kind': 'order',
          }),
      // A successful full-payment order creates one payment row for each
      // invoice it settles. The aggregate order is the actual transaction;
      // hiding those child rows prevents duplicate activity entries.
      ..._payments
          .where((raw) =>
              Map<String, dynamic>.from(raw as Map)['payment_order_id'] == null)
          .map((raw) => {
                ...Map<String, dynamic>.from(raw as Map),
                '_kind': 'payment',
              }),
    ];
    entries.sort((a, b) => (b['created_at']?.toString() ?? '')
        .compareTo(a['created_at']?.toString() ?? ''));
    return entries;
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Payment activity')),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? _ErrorState(message: _error!, onRetry: _load)
                : RefreshIndicator(
                    onRefresh: _load,
                    child: _activity.isEmpty
                        ? ListView(children: const [
                            SizedBox(height: 180),
                            Center(child: Text('No payment activity yet.')),
                          ])
                        : ListView.builder(
                            padding: const EdgeInsets.all(16),
                            itemCount: _activity.length,
                            itemBuilder: (_, index) {
                              final item = _activity[index];
                              final isOrder = item['_kind'] == 'order';
                              return _PaymentActivityCard(
                                item: item,
                                isOrder: isOrder,
                                onTap: !isOrder
                                    ? null
                                    : () async {
                                        final changed = await Navigator.of(
                                                context)
                                            .push<bool>(MaterialPageRoute(
                                                builder: (_) =>
                                                    PaymentOrderDetailScreen(
                                                        order: item)));
                                        if (changed == true) _load();
                                      },
                              );
                            },
                          ),
                  ),
      );
}

class _PaymentActivityCard extends StatelessWidget {
  const _PaymentActivityCard(
      {required this.item, this.isOrder = false, this.onTap});
  final Map<String, dynamic> item;
  final bool isOrder;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final reference = isOrder
        ? item['provider_reference']?.toString() ?? 'Payment order'
        : item['reference_id']?.toString() ?? 'Payment transaction';
    final status = item['status']?.toString() ?? 'PENDING';
    final timestamp =
        item['paid_at'] ?? item['verified_at'] ?? item['created_at'];
    return Card(
      clipBehavior: Clip.antiAlias,
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: const Color(0xFF33256F).withValues(alpha: .10),
                borderRadius: BorderRadius.circular(12),
              ),
              child:
                  const Icon(Icons.payments_outlined, color: Color(0xFF33256F)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Payment',
                        style: Theme.of(context)
                            .textTheme
                            .titleMedium
                            ?.copyWith(fontWeight: FontWeight.w800)),
                    const SizedBox(height: 3),
                    Text(_money(item['amount']),
                        style: Theme.of(context)
                            .textTheme
                            .titleLarge
                            ?.copyWith(fontWeight: FontWeight.w800)),
                    const SizedBox(height: 8),
                    Text(reference,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall),
                    const SizedBox(height: 5),
                    Text(_paymentMethodLabel(
                        item['payment_method']?.toString() ?? '')),
                    if (timestamp != null) ...[
                      const SizedBox(height: 3),
                      Text(_friendlyDate(timestamp),
                          style: Theme.of(context).textTheme.bodySmall),
                    ],
                  ]),
            ),
            const SizedBox(width: 8),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              _StatusBadge(status: status),
              if (onTap != null) ...[
                const SizedBox(height: 10),
                const Icon(Icons.chevron_right),
              ],
            ]),
          ]),
        ),
      ),
    );
  }
}

class AdminPaymentsScreen extends StatefulWidget {
  const AdminPaymentsScreen({super.key, this.showAppBar = true});
  final bool showAppBar;

  @override
  State<AdminPaymentsScreen> createState() => _AdminPaymentsScreenState();
}

class _AdminPaymentsScreenState extends State<AdminPaymentsScreen> {
  List<dynamic> _payments = [];
  List<dynamic> _orders = [];
  String? _error;
  var _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final api = context.read<AuthController>().api;
      final results = await Future.wait([
        api.get('admin/payment-orders'),
        api.get('admin/maintenance-payments'),
      ]);
      _orders = _pageItems(results[0]);
      _payments = _pageItems(results[1]);
    } on ApiException catch (error) {
      _error = error.message;
    } catch (_) {
      _error = 'Unable to load payment activity. Please try again.';
    }
    if (mounted) setState(() => _loading = false);
  }

  List<Map<String, dynamic>> get _activity {
    final entries = <Map<String, dynamic>>[
      ..._orders.map((raw) => {
            ...Map<String, dynamic>.from(raw as Map),
            '_kind': 'order',
          }),
      ..._payments
          .where((raw) =>
              Map<String, dynamic>.from(raw as Map)['payment_order_id'] == null)
          .map((raw) => {
                ...Map<String, dynamic>.from(raw as Map),
                '_kind': 'payment',
              }),
    ];
    entries.sort((first, second) => (second['paid_at'] ??
            second['verified_at'] ??
            second['created_at'] ??
            '')
        .toString()
        .compareTo((first['paid_at'] ??
                first['verified_at'] ??
                first['created_at'] ??
                '')
            .toString()));
    return entries;
  }

  @override
  Widget build(BuildContext context) {
    final content = _loading
        ? const Center(child: CircularProgressIndicator())
        : _error != null
            ? _ErrorState(message: _error!, onRetry: _load)
            : RefreshIndicator(
                onRefresh: _load,
                child: _activity.isEmpty
                    ? ListView(children: const [
                        SizedBox(height: 180),
                        Center(child: Text('No payment activity yet.')),
                      ])
                    : ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: _activity.length,
                        itemBuilder: (_, index) {
                          final item = _activity[index];
                          final isOrder = item['_kind'] == 'order';
                          return _PaymentActivityCard(
                            item: item,
                            isOrder: isOrder,
                            onTap: () async {
                              final changed = await Navigator.of(context)
                                  .push<bool>(MaterialPageRoute(
                                builder: (_) => isOrder
                                    ? PaymentOrderDetailScreen(
                                        order: item, admin: true)
                                    : AdminMaintenancePaymentDetailScreen(
                                        payment: item),
                              ));
                              if (changed == true) _load();
                            },
                          );
                        },
                      ),
              );

    if (!widget.showAppBar) {
      return content;
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Payment activity')),
      body: content,
    );
  }
}

class AdminMaintenancePaymentDetailScreen extends StatefulWidget {
  const AdminMaintenancePaymentDetailScreen({super.key, required this.payment});
  final Map<String, dynamic> payment;

  @override
  State<AdminMaintenancePaymentDetailScreen> createState() =>
      _AdminMaintenancePaymentDetailScreenState();
}

class _AdminMaintenancePaymentDetailScreenState
    extends State<AdminMaintenancePaymentDetailScreen> {
  Map<String, dynamic>? _payment;
  String? _error;
  var _loading = true;
  var _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final response = await context
          .read<AuthController>()
          .api
          .get('admin/maintenance-payments/${widget.payment['id']}');
      _payment = Map<String, dynamic>.from(response['data'] as Map);
    } on ApiException catch (error) {
      _error = error.message;
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _review(String status) async {
    final receipt = TextEditingController(
        text: _payment?['receipt_reference']?.toString() ?? '');
    final saved = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
              title: Text(status == 'COMPLETED'
                  ? 'Confirm payment'
                  : 'Mark payment as failed'),
              content: status == 'COMPLETED'
                  ? TextField(
                      controller: receipt,
                      decoration: const InputDecoration(
                          labelText: 'Receipt / transaction reference',
                          helperText: 'Required for an approved payment'),
                    )
                  : const Text(
                      'This request will be marked failed and will not change the bill balance.'),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('Cancel')),
                FilledButton(
                    onPressed: () {
                      if (status == 'COMPLETED' &&
                          receipt.text.trim().isEmpty) {
                        return;
                      }
                      Navigator.pop(context, true);
                    },
                    child: const Text('Save')),
              ],
            ));
    if (saved != true) {
      receipt.dispose();
      return;
    }
    if (!mounted) {
      receipt.dispose();
      return;
    }
    setState(() => _saving = true);
    try {
      await context
          .read<AuthController>()
          .api
          .patch('admin/maintenance-payments/${widget.payment['id']}/status', {
        'status': status,
        if (receipt.text.trim().isNotEmpty)
          'receipt_reference': receipt.text.trim(),
      });
      if (mounted) Navigator.pop(context, true);
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _saving = false);
      receipt.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
          appBar: AppBar(title: const Text('Payment request')),
          body: const Center(child: CircularProgressIndicator()));
    }
    if (_error != null) {
      return Scaffold(
          appBar: AppBar(title: const Text('Payment request')),
          body: _ErrorState(message: _error!, onRetry: _load));
    }
    final payment = _payment!;
    final status = payment['status']?.toString() ?? 'PENDING';
    final bill = payment['bill'] as Map?;
    return Scaffold(
      appBar: AppBar(title: const Text('Payment request')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(
                    child: Text('Reference ${payment['reference_id'] ?? ''}',
                        style: Theme.of(context).textTheme.titleMedium)),
                _StatusBadge(status: status),
              ]),
              const SizedBox(height: 12),
              _PaymentLine(
                  label: 'Amount',
                  value: _money(payment['amount']),
                  bold: true),
              _PaymentLine(
                  label: 'Method',
                  value: _paymentMethodLabel(
                      payment['payment_method']?.toString() ?? '')),
              if (bill != null)
                _PaymentLine(
                    label: 'Maintenance bill',
                    value: bill['billing_month']?.toString() ?? '-'),
              if (payment['receipt_reference'] != null)
                _PaymentLine(
                    label: 'Receipt / transaction reference',
                    value: payment['receipt_reference'].toString()),
            ]),
          ),
        ),
        const SizedBox(height: 16),
        if (status == 'PENDING') ...[
          FilledButton.icon(
            onPressed: _saving ? null : () => _review('COMPLETED'),
            icon: const Icon(Icons.verified_outlined),
            label: const Text('Confirm payment'),
          ),
          TextButton(
            onPressed: _saving ? null : () => _review('FAILED'),
            child: const Text('Mark as failed'),
          ),
        ],
      ]),
    );
  }
}

class PaymentOrderDetailScreen extends StatefulWidget {
  const PaymentOrderDetailScreen(
      {super.key, required this.order, this.admin = false});
  final Map<String, dynamic> order;
  final bool admin;

  @override
  State<PaymentOrderDetailScreen> createState() =>
      _PaymentOrderDetailScreenState();
}

class _PaymentOrderDetailScreenState extends State<PaymentOrderDetailScreen> {
  Map<String, dynamic>? _order;
  String? _error;
  var _loading = true;
  var _saving = false;

  String get _endpoint =>
      widget.admin ? 'admin/payment-orders' : 'resident/payment-orders';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final response = await context
          .read<AuthController>()
          .api
          .get('$_endpoint/${widget.order['id']}');
      _order = Map<String, dynamic>.from(response['data'] as Map);
    } on ApiException catch (error) {
      _error = error.message;
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _cancel() async {
    setState(() => _saving = true);
    try {
      await context
          .read<AuthController>()
          .api
          .patch('$_endpoint/${widget.order['id']}/cancel', {});
      if (mounted) Navigator.pop(context, true);
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _updateStatus(String status) async {
    final reference = TextEditingController(
        text: _order?['gateway_payment_id']?.toString() ?? '');
    final note = TextEditingController();
    final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
              title: Text(status == 'SUCCESSFUL'
                  ? 'Confirm payment'
                  : 'Update payment order'),
              content: Column(mainAxisSize: MainAxisSize.min, children: [
                if (status == 'SUCCESSFUL')
                  TextField(
                    controller: reference,
                    decoration: const InputDecoration(
                        labelText: 'Receipt / transaction reference',
                        helperText: 'Required for an approved payment'),
                  ),
                TextField(
                  controller: note,
                  maxLines: 3,
                  decoration: const InputDecoration(
                      labelText: 'Verification note (optional)'),
                ),
              ]),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('Cancel')),
                FilledButton(
                    onPressed: () {
                      if (status == 'SUCCESSFUL' &&
                          reference.text.trim().isEmpty) {
                        return;
                      }
                      Navigator.pop(context, true);
                    },
                    child: const Text('Save')),
              ],
            ));
    if (confirmed != true) {
      reference.dispose();
      note.dispose();
      return;
    }
    if (!mounted) {
      reference.dispose();
      note.dispose();
      return;
    }
    setState(() => _saving = true);
    try {
      await context
          .read<AuthController>()
          .api
          .patch('$_endpoint/${widget.order['id']}/status', {
        'status': status,
        if (reference.text.trim().isNotEmpty)
          'gateway_payment_id': reference.text.trim(),
        if (note.text.trim().isNotEmpty) 'verification_note': note.text.trim(),
      });
      await _load();
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _saving = false);
      reference.dispose();
      note.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
          appBar: AppBar(title: const Text('Payment order')),
          body: const Center(child: CircularProgressIndicator()));
    }
    if (_error != null) {
      return Scaffold(
          appBar: AppBar(title: const Text('Payment order')),
          body: _ErrorState(message: _error!, onRetry: _load));
    }
    final order = _order!;
    final status = order['status']?.toString() ?? 'PENDING';
    final items = order['items'] is List ? order['items'] as List : const [];
    final canReview =
        widget.admin && const ['PENDING', 'PROCESSING'].contains(status);
    return Scaffold(
      appBar: AppBar(title: const Text('Payment order')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(
                    child: Text('Order ${order['provider_reference'] ?? ''}',
                        style: Theme.of(context).textTheme.titleMedium)),
                _StatusBadge(status: status),
              ]),
              const SizedBox(height: 12),
              _PaymentLine(
                  label: 'Total', value: _money(order['amount']), bold: true),
              _PaymentLine(
                  label: 'Method',
                  value: _paymentMethodLabel(
                      order['payment_method']?.toString() ?? '')),
              if (order['gateway_payment_id'] != null)
                _PaymentLine(
                    label: 'Receipt / transaction reference',
                    value: order['gateway_payment_id'].toString()),
              if (order['verification_note']?.toString().isNotEmpty ?? false)
                Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(order['verification_note'].toString())),
              if (order['receipt'] is Map)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.receipt_long_outlined),
                    label: const Text('View receipt'),
                    onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute(
                            builder: (_) => PaymentReceiptScreen(
                                orderId: order['id'], admin: widget.admin))),
                  ),
                ),
            ]),
          ),
        ),
        const SizedBox(height: 16),
        Text('Bills in this order',
            style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        for (final raw in items)
          Card(
              child: ListTile(
                  title: Text(
                      'Maintenance ${((raw as Map)['bill'] as Map?)?['billing_month'] ?? ''}'),
                  subtitle: Text(
                      'Due ${((raw['bill'] as Map?)?['due_date'] ?? '-')}'),
                  trailing: Text(_money(raw['amount']),
                      style: const TextStyle(fontWeight: FontWeight.w700)))),
        const SizedBox(height: 16),
        if (!widget.admin && status == 'PENDING')
          OutlinedButton.icon(
            onPressed: _saving ? null : _cancel,
            icon: const Icon(Icons.cancel_outlined),
            label: const Text('Cancel payment order'),
          ),
        if (canReview) ...[
          if (status == 'PENDING')
            OutlinedButton.icon(
              onPressed: _saving ? null : () => _updateStatus('PROCESSING'),
              icon: const Icon(Icons.manage_search_outlined),
              label: const Text('Mark as under review'),
            ),
          const SizedBox(height: 8),
          FilledButton.icon(
            onPressed: _saving ? null : () => _updateStatus('SUCCESSFUL'),
            icon: const Icon(Icons.verified_outlined),
            label: const Text('Confirm payment'),
          ),
          TextButton(
            onPressed: _saving ? null : () => _updateStatus('FAILED'),
            child: const Text('Mark as failed'),
          ),
        ],
        if (!widget.admin && status == 'PENDING')
          const Padding(
            padding: EdgeInsets.only(top: 12),
            child: Text(
                'This request is awaiting society verification. Your dues are updated only after the payment is confirmed.'),
          ),
      ]),
    );
  }
}

class PaymentReceiptScreen extends StatefulWidget {
  const PaymentReceiptScreen(
      {super.key, required this.orderId, this.admin = false});
  final dynamic orderId;
  final bool admin;

  @override
  State<PaymentReceiptScreen> createState() => _PaymentReceiptScreenState();
}

class _PaymentReceiptScreenState extends State<PaymentReceiptScreen> {
  Map<String, dynamic>? _receipt;
  String? _error;
  var _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final endpoint =
          widget.admin ? 'admin/payment-orders' : 'resident/payment-orders';
      final response = await context
          .read<AuthController>()
          .api
          .get('$endpoint/${widget.orderId}/receipt');
      _receipt = Map<String, dynamic>.from(response['data'] as Map);
    } on ApiException catch (error) {
      _error = error.message;
    }
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Payment receipt')),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? _ErrorState(message: _error!, onRetry: _load)
                : ListView(padding: const EdgeInsets.all(20), children: [
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(children: [
                                const Icon(Icons.verified_rounded,
                                    color: Colors.green),
                                const SizedBox(width: 8),
                                Text('Payment successful',
                                    style:
                                        Theme.of(context).textTheme.titleLarge),
                              ]),
                              const Divider(height: 28),
                              _PaymentLine(
                                  label: 'Receipt number',
                                  value:
                                      _receipt!['receipt_number']?.toString() ??
                                          '-'),
                              _PaymentLine(
                                  label: 'Amount',
                                  value: _money(_receipt!['amount']),
                                  bold: true),
                              _PaymentLine(
                                  label: 'Method',
                                  value: _paymentMethodLabel(
                                      _receipt!['payment_method']?.toString() ??
                                          '')),
                              _PaymentLine(
                                  label: 'Payment reference',
                                  value: _receipt!['payment_reference']
                                          ?.toString() ??
                                      '-'),
                              _PaymentLine(
                                  label: 'Issued at',
                                  value: _receipt!['issued_at']?.toString() ??
                                      '-'),
                            ]),
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                        'Keep this receipt number for your records. The confirmed amount has been applied to your maintenance dues.'),
                  ]),
      );
}

class ResidentVisitorsScreen extends StatefulWidget {
  const ResidentVisitorsScreen({super.key});

  @override
  State<ResidentVisitorsScreen> createState() => _ResidentVisitorsScreenState();
}

class _ResidentVisitorsScreenState extends State<ResidentVisitorsScreen> {
  List<dynamic> _visitors = [];
  String? _error;
  var _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      _visitors = _pageItems(
          await context.read<AuthController>().api.get('resident/visitors'));
    } on ApiException catch (error) {
      _error = error.message;
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _action(Map<String, dynamic> visitor, String action) async {
    try {
      await context
          .read<AuthController>()
          .api
          .patch('resident/visitors/${visitor['id']}/$action', {});
      await _load();
    } on ApiException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.message)));
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _ErrorState(message: _error!, onRetry: _load)
              : RefreshIndicator(
                  onRefresh: _load,
                  child: _visitors.isEmpty
                      ? ListView(children: const [
                          SizedBox(height: 180),
                          Center(
                              child: Text(
                                  'No upcoming visitors. Add one when you are expecting someone.'))
                        ])
                      : ListView.builder(
                          padding: const EdgeInsets.all(16),
                          itemCount: _visitors.length,
                          itemBuilder: (_, index) {
                            final visitor = Map<String, dynamic>.from(
                                _visitors[index] as Map);
                            final pending =
                                visitor['approval_status'] == 'PENDING' &&
                                    !visitor['is_pre_approved'];
                            return Card(
                                child: Padding(
                                    padding: const EdgeInsets.all(14),
                                    child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Row(children: [
                                            Expanded(
                                                child: Text(
                                                    visitor['visitor_name']
                                                            ?.toString() ??
                                                        'Visitor',
                                                    style: Theme.of(context)
                                                        .textTheme
                                                        .titleMedium)),
                                            _StatusBadge(
                                                status: visitor['entry_status']
                                                        ?.toString() ??
                                                    'EXPECTED')
                                          ]),
                                          const SizedBox(height: 6),
                                          Text(
                                              '${visitor['visitor_type'] ?? 'Guest'} · ${visitor['purpose'] ?? ''}'),
                                          if (visitor['expected_at'] != null)
                                            Text(
                                                'Expected: ${visitor['expected_at']}'),
                                          if (pending)
                                            Padding(
                                                padding: const EdgeInsets.only(
                                                    top: 10),
                                                child:
                                                    Wrap(spacing: 8, children: [
                                                  FilledButton(
                                                      onPressed: () => _action(
                                                          visitor, 'approve'),
                                                      child: const Text(
                                                          'Approve')),
                                                  OutlinedButton(
                                                      onPressed: () => _action(
                                                          visitor, 'reject'),
                                                      child:
                                                          const Text('Reject')),
                                                ])),
                                        ])));
                          },
                        ),
                ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          final changed = await Navigator.of(context).push<bool>(
              MaterialPageRoute(
                  builder: (_) => const VisitorPreApprovalScreen()));
          if (changed == true) _load();
        },
        icon: const Icon(Icons.person_add_alt_1),
        label: const Text('Add visitor'),
      ));
}

class VisitorPreApprovalScreen extends StatefulWidget {
  const VisitorPreApprovalScreen({super.key});

  @override
  State<VisitorPreApprovalScreen> createState() =>
      _VisitorPreApprovalScreenState();
}

class _VisitorPreApprovalScreenState extends State<VisitorPreApprovalScreen> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  DateTime _expectedAt = DateTime.now().add(const Duration(hours: 1));
  var _type = 'GUEST';
  var _saving = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _selectDateTime() async {
    final date = await showDatePicker(
        context: context,
        firstDate: DateTime.now(),
        lastDate: DateTime.now().add(const Duration(days: 365)),
        initialDate: _expectedAt);
    if (date == null || !mounted) return;
    final time = await showScrollWheelTimePicker(
      context,
      initialTime: TimeOfDay.fromDateTime(_expectedAt),
      title: 'Select Expected Time',
    );
    if (time != null) {
      setState(() => _expectedAt =
          DateTime(date.year, date.month, date.day, time.hour, time.minute));
    }
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await context
          .read<AuthController>()
          .api
          .post('resident/visitors/pre-approvals', {
        'visitor_name': _name.text.trim(),
        'visitor_type': _type,
        'expected_at': _expectedAt.toIso8601String(),
      });
      if (mounted) Navigator.pop(context, true);
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Pre-approve visitor')),
        body: Form(
            key: _form,
            child: ListView(padding: const EdgeInsets.all(16), children: [
              _TextField(controller: _name, label: 'Visitor name'),
              DropdownButtonFormField<String>(
                  initialValue: _type,
                  decoration: const InputDecoration(
                      labelText: 'Visitor type', border: OutlineInputBorder()),
                  items: const [
                    DropdownMenuItem(value: 'GUEST', child: Text('Guest')),
                    DropdownMenuItem(
                        value: 'DELIVERY', child: Text('Delivery')),
                    DropdownMenuItem(value: 'CAB', child: Text('Cab / taxi')),
                    DropdownMenuItem(
                        value: 'SERVICE_PROVIDER',
                        child: Text('Service provider')),
                    DropdownMenuItem(value: 'OTHER', child: Text('Other')),
                  ],
                  onChanged: _saving
                      ? null
                      : (value) => setState(() => _type = value!)),
              const SizedBox(height: 14),
              OutlinedButton.icon(
                  onPressed: _saving ? null : _selectDateTime,
                  icon: const Icon(Icons.schedule),
                  label: Text(
                      'Expected: ${_friendlyDate(_expectedAt.toIso8601String())} at ${formatTimeOfDay12(TimeOfDay.fromDateTime(_expectedAt))}')),
              if (_error != null)
                Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(_error!,
                        style: TextStyle(
                            color: Theme.of(context).colorScheme.error))),
              const SizedBox(height: 20),
              FilledButton(
                  onPressed: _saving ? null : _save,
                  child: Text(_saving ? 'Saving…' : 'Pre-approve visitor')),
            ])),
      );
}

class ResidentMoreScreen extends StatelessWidget {
  const ResidentMoreScreen({super.key});

  @override
  Widget build(BuildContext context) {
    const modules = [
      ('Amenities', Icons.pool_outlined),
      ('Bookings', Icons.event_note_outlined),
      ('Complaints', Icons.support_agent_outlined),
      ('Notices', Icons.campaign_outlined),
      ('Payments', Icons.receipt_long_outlined),
      ('Parking', Icons.local_parking_outlined),
      ('Parcels', Icons.inventory_2_outlined),
      ('Messages', Icons.forum_outlined),
      ('Notifications', Icons.notifications_outlined),
      ('Profile', Icons.person_outline),
    ];
    return ListView(padding: const EdgeInsets.all(12), children: [
      for (final module in modules)
        Card(
            child: ListTile(
          leading: Icon(module.$2),
          title: Text(module.$1),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => module.$1 == 'Payments'
                  ? const DuesScreen()
                  : module.$1 == 'Profile'
                      ? const AccountProfileScreen()
                      : ModuleScreen(title: module.$1, role: 'RESIDENT'))),
        )),
      const SizedBox(height: 8),
      Card(
          child: ListTile(
        leading: const Icon(Icons.logout),
        title: const Text('Log out'),
        onTap: () => context.read<AuthController>().logout(),
      )),
    ]);
  }
}

// ========================================
// MODERN UI COMPONENTS FOR RESIDENT DASHBOARD
// ========================================

class _ModernHeader extends StatelessWidget {
  const _ModernHeader({
    required this.greeting,
    required this.name,
    required this.flatInfo,
  });
  
  final String greeting;
  final String name;
  final String flatInfo;
  
  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // Decorative background (ignored for pointer events)
        Positioned(
          right: -50,
          top: -50,
          child: IgnorePointer(
            ignoring: true,
            child: Container(
              width: 200,
              height: 200,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    const Color(0xFF6366F1).withValues(alpha: 0.1),
                    const Color(0xFF6366F1).withValues(alpha: 0.0),
                  ],
                ),
              ),
            ),
          ),
        ),
        Positioned(
          left: -80,
          top: 60,
          child: IgnorePointer(
            ignoring: true,
            child: Container(
              width: 160,
              height: 160,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    const Color(0xFFA78BFA).withValues(alpha: 0.08),
                    const Color(0xFFA78BFA).withValues(alpha: 0.0),
                  ],
                ),
              ),
            ),
          ),
        ),
        // Content
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            greeting,
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(
                                  color: const Color(0xFF64748B),
                                  fontWeight: FontWeight.w500,
                                ),
                          ),
                          const SizedBox(width: 6),
                          const Text('👋', style: TextStyle(fontSize: 20)),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        name,
                        style: Theme.of(context)
                            .textTheme
                            .headlineMedium
                            ?.copyWith(
                              fontWeight: FontWeight.w700,
                              color: const Color(0xFF1E293B),
                              letterSpacing: -0.5,
                            ),
                      ),
                      const SizedBox(height: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFF6366F1).withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          flatInfo,
                          style: Theme.of(context)
                              .textTheme
                              .bodyMedium
                              ?.copyWith(
                                color: const Color(0xFF6366F1),
                                fontWeight: FontWeight.w600,
                              ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.06),
                        blurRadius: 10,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: const NotificationBell(role: 'RESIDENT'),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _ModernSectionHeader extends StatelessWidget {
  const _ModernSectionHeader({
    required this.title,
    required this.icon,
    this.action,
    this.onAction,
  });
  
  final String title;
  final IconData icon;
  final String? action;
  final VoidCallback? onAction;
  
  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)],
            ),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, size: 18, color: Colors.white),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            title,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFF1E293B),
                  letterSpacing: -0.3,
                ),
          ),
        ),
        if (action != null)
          TextButton(
            onPressed: onAction,
            style: TextButton.styleFrom(
              foregroundColor: const Color(0xFF6366F1),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  action!,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(width: 4),
                const Icon(Icons.arrow_forward, size: 16),
              ],
            ),
          ),
      ],
    );
  }
}

class _ModernInsightCard extends StatelessWidget {
  const _ModernInsightCard({
    required this.icon,
    required this.title,
    required this.value,
    required this.subtitle,
    required this.gradient,
    required this.onTap,
    this.isPrimary = false,
  });
  
  final IconData icon;
  final String title;
  final String value;
  final String subtitle;
  final Gradient gradient;
  final VoidCallback onTap;
  final bool isPrimary;
  
  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: isPrimary
                ? Border.all(
                    color: const Color(0xFFFB8C00).withValues(alpha: 0.3),
                    width: 2,
                  )
                : null,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 10,
                offset: const Offset(0, 2),
              ),
              if (isPrimary)
                BoxShadow(
                  color: const Color(0xFFFB8C00).withValues(alpha: 0.1),
                  blurRadius: 20,
                  offset: const Offset(0, 4),
                ),
            ],
          ),
          child: Stack(
            children: [
              // Decorative gradient circle (ignored for touch events)
              Positioned(
                right: -20,
                top: -20,
                child: IgnorePointer(
                  ignoring: true,
                  child: Opacity(
                    opacity: 0.1,
                    child: Container(
                      width: 80,
                      height: 80,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: gradient,
                      ),
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(9),
                          decoration: BoxDecoration(
                            gradient: gradient,
                            borderRadius: BorderRadius.circular(12),
                            boxShadow: [
                              BoxShadow(
                                color: gradient.colors.first
                                    .withValues(alpha: 0.3),
                                blurRadius: 8,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: Icon(icon, color: Colors.white, size: 20),
                        ),
                        if (isPrimary)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 7,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFB8C00)
                                  .withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Icon(
                              Icons.arrow_forward,
                              size: 13,
                              color: Color(0xFFFB8C00),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                          Text(
                            title,
                            style: Theme.of(context)
                                .textTheme
                                .labelSmall
                                ?.copyWith(
                                  color: const Color(0xFF64748B),
                                  fontWeight: FontWeight.w600,
                                  letterSpacing: 0.5,
                                ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            value,
                            style: Theme.of(context)
                                .textTheme
                                .headlineSmall
                                ?.copyWith(
                                  fontWeight: FontWeight.w700,
                                  color: const Color(0xFF1E293B),
                                  letterSpacing: -0.5,
                                ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 3),
                          Row(
                            children: [
                              Container(
                                width: 5,
                                height: 5,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  gradient: gradient,
                                ),
                              ),
                              const SizedBox(width: 5),
                              Expanded(
                                child: Text(
                                  subtitle,
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodySmall
                                      ?.copyWith(
                                        color: const Color(0xFF64748B),
                                        fontWeight: FontWeight.w500,
                                      ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ModernQuickAction extends StatelessWidget {
  const _ModernQuickAction({
    required this.icon,
    required this.label,
    required this.gradient,
    required this.iconColor,
    required this.onTap,
    this.isPrimary = false,
  });
  
  final IconData icon;
  final String label;
  final Gradient gradient;
  final Color iconColor;
  final VoidCallback onTap;
  final bool isPrimary;
  
  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: gradient,
            borderRadius: BorderRadius.circular(16),
            border: isPrimary
                ? Border.all(
                    color: const Color(0xFFE65100).withValues(alpha: 0.3),
                    width: 2,
                  )
                : null,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.03),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
              if (isPrimary)
                BoxShadow(
                  color: const Color(0xFFE65100).withValues(alpha: 0.15),
                  blurRadius: 15,
                  offset: const Offset(0, 4),
                ),
            ],
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: iconColor.withValues(alpha: 0.2),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Icon(icon, color: iconColor, size: 24),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  label,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: const Color(0xFF1E293B),
                      ),
                ),
              ),
              Icon(
                Icons.arrow_forward_ios,
                size: 14,
                color: iconColor.withValues(alpha: 0.6),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ModernInfoCard extends StatelessWidget {
  const _ModernInfoCard({
    required this.icon,
    required this.iconColor,
    required this.iconBackground,
    required this.title,
    required this.subtitle,
    this.detail,
    this.showArrow = false,
    required this.onTap,
  });
  
  final IconData icon;
  final Color iconColor;
  final Color iconBackground;
  final String title;
  final String subtitle;
  final String? detail;
  final bool showArrow;
  final VoidCallback onTap;
  
  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 10,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: iconBackground,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: iconColor, size: 24),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                            color: const Color(0xFF64748B),
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: const Color(0xFF1E293B),
                          ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (detail != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        detail!,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: const Color(0xFF94A3B8),
                            ),
                      ),
                    ],
                  ],
                ),
              ),
              if (showArrow)
                const Icon(
                  Icons.arrow_forward_ios,
                  size: 16,
                  color: Color(0xFF94A3B8),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ModernUrgentCard extends StatelessWidget {
  const _ModernUrgentCard({
    required this.icon,
    required this.title,
    required this.message,
    required this.action,
    required this.onTap,
  });
  
  final IconData icon;
  final String title;
  final String message;
  final String action;
  final VoidCallback onTap;
  
  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFFFF3E0), Color(0xFFFFE0B2)],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: const Color(0xFFFB8C00).withValues(alpha: 0.3),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFFB8C00).withValues(alpha: 0.1),
            blurRadius: 15,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFFFB8C00).withValues(alpha: 0.2),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Icon(icon, color: const Color(0xFFE65100), size: 24),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                              color: const Color(0xFFE65100),
                            ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        message,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: const Color(0xFF7C2D12),
                            ),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFFFB8C00), Color(0xFFE65100)],
                          ),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          action,
                          style: Theme.of(context)
                              .textTheme
                              .labelSmall
                              ?.copyWith(
                                color: Colors.white,
                                fontWeight: FontWeight.w600,
                              ),
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(
                  Icons.arrow_forward_ios,
                  size: 16,
                  color: Color(0xFFFB8C00),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ModernEmptyCard extends StatelessWidget {
  const _ModernEmptyCard({
    required this.icon,
    required this.message,
  });
  
  final IconData icon;
  final String message;
  
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: const Color(0xFFE2E8F0),
          width: 1,
        ),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: const BoxDecoration(
              color: Color(0xFFF1F5F9),
              shape: BoxShape.circle,
            ),
            child: Icon(
              icon,
              size: 32,
              color: const Color(0xFF94A3B8),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            message,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: const Color(0xFF64748B),
                ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

// ========================================
// ORIGINAL HELPER WIDGETS (KEPT FOR OTHER SCREENS)
// ========================================

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title});
  final String title;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Row(children: [
          Expanded(
              child: Text(title,
                  style: Theme.of(context)
                      .textTheme
                      .titleLarge
                      ?.copyWith(fontWeight: FontWeight.w700))),
        ]),
      );
}

class _QuickAction extends StatelessWidget {
  const _QuickAction(
      {required this.icon, required this.label, required this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
          width: 100,
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
          decoration: BoxDecoration(
              border: Border.all(
                  color: Theme.of(context).colorScheme.outlineVariant),
              borderRadius: BorderRadius.circular(14)),
          child: Column(children: [
            Icon(icon),
            const SizedBox(height: 6),
            Text(label,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis)
          ])));
}

class _InfoCard extends StatelessWidget {
  const _InfoCard(
      {required this.icon,
      required this.title,
      required this.subtitle,
      this.onTap});
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) => Card(
      child: ListTile(
          leading: Icon(icon),
          title: Text(title),
          subtitle: subtitle.isEmpty
              ? null
              : Text(subtitle, maxLines: 2, overflow: TextOverflow.ellipsis),
          trailing: onTap == null ? null : const Icon(Icons.chevron_right),
          onTap: onTap));
}

class _EmptyCard extends StatelessWidget {
  const _EmptyCard({required this.message});
  final String message;
  @override
  Widget build(BuildContext context) => Card(
      child: Padding(
          padding: const EdgeInsets.all(20),
          child: Center(child: Text(message, textAlign: TextAlign.center))));
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});
  final String message;
  final Future<void> Function() onRetry;
  @override
  Widget build(BuildContext context) => Center(
      child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.cloud_off_outlined, size: 40),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            FilledButton(onPressed: onRetry, child: const Text('Try again'))
          ])));
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.status});
  final String status;
  @override
  Widget build(BuildContext context) {
    final normalized = status.replaceAll('_', ' ');
    final color = status.contains('PAID') ||
            status.contains('SUCCESS') ||
            status.contains('COMPLETED') ||
            status.contains('APPROVED') ||
            status.contains('CONFIRMED') ||
            status.contains('ENTERED')
        ? Colors.green
        : status.contains('OVERDUE') || status.contains('REJECTED')
            ? Colors.red
            : Colors.orange;
    return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
            color: color.withValues(alpha: .12),
            borderRadius: BorderRadius.circular(99)),
        child: Text(normalized,
            style: TextStyle(
                fontSize: 11, color: color, fontWeight: FontWeight.w700)));
  }
}

class _PaymentLine extends StatelessWidget {
  const _PaymentLine(
      {required this.label, required this.value, this.bold = false});
  final String label;
  final String value;
  final bool bold;

  @override
  Widget build(BuildContext context) {
    final style = bold ? const TextStyle(fontWeight: FontWeight.w700) : null;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 5,
            child: Text(
              label,
              style: style,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 6,
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: style,
            ),
          ),
        ],
      ),
    );
  }
}

class _TextField extends StatelessWidget {
  const _TextField(
      {required this.controller,
      required this.label,
      this.keyboardType,
      this.required = true,
      this.obscure = false,
      this.validator});
  final TextEditingController controller;
  final String label;
  final TextInputType? keyboardType;
  final bool required;
  final bool obscure;
  final String? Function(String?)? validator;
  @override
  Widget build(BuildContext context) => Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: TextFormField(
          controller: controller,
          keyboardType: keyboardType,
          obscureText: obscure,
          decoration: InputDecoration(
              labelText: label, border: const OutlineInputBorder()),
          validator: validator ??
              (required
                  ? (value) => value == null || value.trim().isEmpty
                      ? '$label is required'
                      : null
                  : null)));
}

List<dynamic> _pageItems(Map<String, dynamic> response) {
  final data = response['data'];
  if (data is List) return data;
  if (data is Map && data['data'] is List) {
    return List<dynamic>.from(data['data'] as List);
  }
  return [];
}

double _asDouble(dynamic value) =>
    double.tryParse(value?.toString() ?? '') ?? 0;
String _money(dynamic value) => '₹${_asDouble(value).toStringAsFixed(2)}';
String _friendlyDate(dynamic value) {
  final parsed = DateTime.tryParse(value?.toString() ?? '');
  if (parsed == null) {
    return value?.toString().isNotEmpty == true ? value.toString() : '-';
  }
  return '${parsed.day.toString().padLeft(2, '0')}/${parsed.month.toString().padLeft(2, '0')}/${parsed.year}';
}

/// Returns a human-readable fallback message for visitor-related notification
/// types when the data payload does not include an explicit [message] field.
String _visitorMessageForType(String type, Map<String, dynamic> data) {
  final name = data['visitor_name']?.toString() ?? 'Visitor';
  final flat = data['flat_number']?.toString();
  final building = data['building']?.toString();
  final location = flat != null
      ? 'Flat $flat${building != null && building.isNotEmpty ? ', $building' : ''}'
      : 'your unit';
  switch (type) {
    case 'visitor_approved':
      return '$name has been approved for entry.';
    case 'visitor_rejected':
      return "$name's entry request was declined.";
    case 'visitor_checked_in':
      return '$name has entered the society.';
    case 'visitor_checked_out':
      return '$name has left the society.';
    default:
      return '$name is requesting entry to $location.';
  }
}

String _monthAndYear(dynamic value) {
  final parsed = DateTime.tryParse(value?.toString() ?? '');
  return parsed == null
      ? (value?.toString() ?? '-')
      : '${_monthName(parsed.month)} ${parsed.year}';
}

String _initials(String? name) => (name ?? 'R')
    .trim()
    .split(RegExp(r'\s+'))
    .where((word) => word.isNotEmpty)
    .take(2)
    .map((word) => word[0].toUpperCase())
    .join();
String _paymentMethodLabel(String method) => switch (method) {
      'UPI' => 'UPI',
      'CARD' => 'Credit / debit card',
      'CREDIT_CARD' => 'Credit card',
      'DEBIT_CARD' => 'Debit card',
      'NET_BANKING' => 'Net banking',
      'BANK_TRANSFER' => 'Net banking / transfer',
      'CASH' => 'Pay at society office',
      'OTHER' => 'Other supported method',
      _ => method
    };
String _emptyMessage(String title) => switch (title) {
      'Residents' => 'No residents found',
      'Complaints' =>
        'No complaints yet. Report an issue to society management.',
      'Bookings' => 'No bookings yet. Book an amenity when you need it.',
      'Parcels' => 'No parcels are currently available.',
      'Notifications' => 'No new notifications.',
      'Notices' => 'No notices are available.',
      'Visitors' => 'No visitors found.',
      _ => 'No records found.',
    };

class ModuleScreen extends StatefulWidget {
  const ModuleScreen({
    super.key,
    required this.title,
    required this.role,
    this.showAppBar = true,
  });
  final String title;
  final String role;
  final bool showAppBar;
  @override
  State<ModuleScreen> createState() => _ModuleScreenState();
}

class _ModuleScreenState extends State<ModuleScreen> {
  List<dynamic> _items = [];
  String? _error;
  bool _loading = true;
  String get _endpoint {
    const resident = {
      'Profile': 'resident/profile',
      'Visitors': 'resident/visitors',
      'Maintenance': 'resident/maintenance-bills',
      'Payments': 'resident/maintenance-payments',
      'Complaints': 'resident/complaints',
      'Notices': 'resident/notices',
      'Parking': 'resident/parking-slots',
      'Parcels': 'resident/parcels',
      'Amenities': 'amenities',
      'Bookings': 'resident/amenity-bookings',
      'Messages': 'conversations',
      'Notifications': 'notifications'
    };
    const security = {
      'Visitors': 'security/visitors',
      'Parcels': 'security/parcels',
      'Notices': 'security/notices',
      'Messages': 'conversations',
      'Notifications': 'notifications'
    };
    const staff = {
      'Complaints': 'staff/complaints',
      'Parcels': 'staff/parcels',
      'Notices': 'staff/notices',
      'Messages': 'conversations',
      'Notifications': 'notifications',
    };
    const admin = {
      'Dashboard': 'admin/dashboard',
      'Residents': 'admin/residents',
      'Flats': 'admin/flats',
      'Visitors': 'admin/visitors',
      'Maintenance': 'admin/maintenance-bills',
      'Payments': 'admin/payment-orders',
      'Reports': 'admin/reports',
      'Complaints': 'admin/complaints',
      'Notices': 'admin/notices',
      'Staff': 'admin/staff-members',
      'Parking': 'admin/parking-slots',
      'Parcels': 'admin/parcels',
      'Amenities': 'admin/amenities',
      'Bookings': 'admin/amenity-bookings',
      'Messages': 'conversations',
      'Notifications': 'notifications'
    };
    return (widget.role == 'ADMIN'
        ? admin
        : widget.role == 'SECURITY'
            ? security
            : widget.role == 'STAFF'
                ? staff
                : resident)[widget.title]!;
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final response = await context.read<AuthController>().api.get(_endpoint);
      final data = response['data'];
      _items = data is List
          ? data
          : data is Map && data['data'] is List
              ? data['data'] as List<dynamic>
              : data is Map
                  ? data.entries
                      .map((entry) =>
                          {'name': entry.key, 'status': '${entry.value}'})
                      .toList()
                  : [];

      if (widget.title == 'Residents') {
        debugPrint('[RESIDENT DEBUG] API URL: ${ApiConfig.baseUrl}/$_endpoint');
        debugPrint('[RESIDENT DEBUG] HTTP status code: 200');
        debugPrint('[RESIDENT DEBUG] Raw response body: $response');
        debugPrint('[RESIDENT DEBUG] Parsed JSON: $data');
        debugPrint('[RESIDENT DEBUG] Number of residents received: ${_items.length}');
        if (_items.isNotEmpty) {
          final first = Map<String, dynamic>.from(_items.first as Map);
          debugPrint('[RESIDENT DEBUG] First resident object: $first');
          final user = first['user'] is Map ? first['user'] as Map : null;
          final flat = first['flat'] is Map ? first['flat'] as Map : null;
          debugPrint('[RESIDENT DEBUG] Parsed Resident model: Resident(id: ${first['id']}, name: ${user?['name']}, flat: ${flat?['flat_number']})');
          debugPrint('[RESIDENT DEBUG] Resident name: ${user?['name']}');
          debugPrint('[RESIDENT DEBUG] Resident unit/flat: ${flat?['flat_number']} (${flat?['building']})');
          debugPrint('[RESIDENT DEBUG] Resident email: ${user?['email']}');
          debugPrint('[RESIDENT DEBUG] Resident phone: ${user?['phone']}');
        }
      }
    } on ApiException catch (exception) {
      _error = exception.message;
      if (widget.title == 'Residents') {
        debugPrint('[RESIDENT DEBUG] API Error: ${exception.message} (${exception.statusCode})');
      }
    } catch (exception) {
      _error = 'An unexpected error occurred. Please try again.';
      if (widget.title == 'Residents') {
        debugPrint('[RESIDENT DEBUG] Unexpected error: $exception');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  FormConfig? get _form => FormConfig.forRoute(_endpoint);
  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return widget.showAppBar
          ? Scaffold(
              appBar: AppBar(title: Text(widget.title)),
              body: const Center(child: CircularProgressIndicator()))
          : const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return widget.showAppBar
          ? Scaffold(
              appBar: AppBar(title: Text(widget.title)),
              body: Center(
                  child: FilledButton(
                      onPressed: _load, child: Text('Retry: $_error'))))
          : Center(
              child: FilledButton(
                  onPressed: _load, child: Text('Retry: $_error')));
    }

    final fab = (_form == null || !_form!.showCreate)
        ? null
        : FloatingActionButton(
            onPressed: () async {
              final result = await Navigator.of(context).push<bool>(
                MaterialPageRoute(
                    builder: (_) => ModuleFormScreen(config: _form!)),
              );
              if (result == true) _load();
            },
            child: const Icon(Icons.add),
          );

    final bodyContent = RefreshIndicator(
      onRefresh: _load,
      child: _items.isEmpty
          ? ListView(children: [
              const SizedBox(height: 180),
              Center(
                  child: Text(_emptyMessage(widget.title),
                      textAlign: TextAlign.center)),
              if (_form != null && _form!.showCreate)
                Padding(
                  padding: const EdgeInsets.all(20),
                  child: Center(
                      child: FilledButton.icon(
                    icon: const Icon(Icons.add),
                    label: Text(_form!.title),
                    onPressed: () async {
                      final result = await Navigator.of(context).push<bool>(
                          MaterialPageRoute(
                              builder: (_) =>
                                  ModuleFormScreen(config: _form!)));
                      if (result == true) _load();
                    },
                  )),
                ),
            ])
          : ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: _items.length,
              itemBuilder: (_, index) {
                final item = Map<String, dynamic>.from(_items[index] as Map);

                if (widget.title == 'Notifications') {
                  return _buildNotificationCard(context, item);
                }

                if (widget.title == 'Visitors') {
                  return _buildVisitorCard(context, item);
                }

                if (widget.title == 'Parcels') {
                  return _buildParcelCard(context, item);
                }

                if (widget.title == 'Residents') {
                  return _buildResidentCard(context, item);
                }

                final userMap = item['user'] is Map ? item['user'] as Map : null;
                final flatMap = item['flat'] is Map ? item['flat'] as Map : null;

                final headline = userMap?['name'] ??
                    item['name'] ??
                    item['title'] ??
                    (item['billing_month'] != null
                        ? 'Maintenance: ${item['billing_month']}'
                        : null) ??
                    item['provider_reference'] ??
                    item['reference_id'] ??
                    (flatMap != null ? 'Flat ${flatMap['flat_number']}' : null) ??
                    item['flat_number'] ??
                    item['slot_number'] ??
                    'Record #${item['id'] ?? index + 1}';
                final subtitle = [
                  item['status'],
                  item['relation_to_owner'],
                  userMap?['email'],
                  item['amount'] != null ? '₹${item['amount']}' : null,
                  item['email'],
                  item['due_date'],
                  item['payment_method'],
                  item['reference_id']
                ].whereType<String>().join(' • ');

                Widget? trailingWidget;
                if (_endpoint == 'amenities' ||
                    _endpoint == 'admin/amenities') {
                  trailingWidget = FilledButton.icon(
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                    ),
                    icon: const Icon(Icons.calendar_month, size: 16),
                    label: const Text('Book'),
                    onPressed: () async {
                      final bookingConfig =
                          FormConfig.forRoute('resident/amenity-bookings');
                      if (bookingConfig != null) {
                        final result = await Navigator.of(context).push<bool>(
                          MaterialPageRoute(
                            builder: (_) => ModuleFormScreen(
                              config: bookingConfig,
                              initial: {'amenity_id': item['id']},
                            ),
                          ),
                        );
                        if (result == true) _load();
                      }
                    },
                  );
                } else if (item['status'] != null) {
                  final statusStr = item['status'].toString().toUpperCase();
                  final isPositive = [
                    'ACTIVE',
                    'PAID',
                    'COMPLETED',
                    'APPROVED',
                    'CONFIRMED'
                  ].contains(statusStr);
                  final isWarning = [
                    'PENDING',
                    'IN_PROGRESS',
                    'OPEN',
                    'PARTIALLY_PAID',
                    'OVERDUE'
                  ].contains(statusStr);
                  trailingWidget = Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: isPositive
                          ? Colors.green.shade100
                          : (isWarning
                              ? Colors.orange.shade100
                              : Colors.red.shade100),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      statusStr,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: isPositive
                            ? Colors.green.shade800
                            : (isWarning
                                ? Colors.orange.shade900
                                : Colors.red.shade800),
                      ),
                    ),
                  );
                }

                return Card(
                  child: ListTile(
                    title: Text('$headline'),
                    subtitle: subtitle.isEmpty ? null : Text(subtitle),
                    trailing: trailingWidget,
                    onTap: () async {
                      final changed = await Navigator.of(context).push<bool>(
                        MaterialPageRoute(
                          builder: (_) => _endpoint == 'conversations'
                              ? ConversationDetailScreen(conversation: item)
                              : _endpoint == 'admin/payment-orders'
                                  ? PaymentOrderDetailScreen(
                                      order: item, admin: true)
                                  : RecordDetailScreen(
                                      title: widget.title,
                                      endpoint: _endpoint,
                                      item: item,
                                      config: _form,
                                    ),
                        ),
                      );
                      if (changed == true) _load();
                    },
                  ),
                );
              },
            ),
    );

    if (!widget.showAppBar) {
      return Scaffold(
        floatingActionButton: fab,
        body: bodyContent,
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          if (_endpoint == 'notifications')
            IconButton(
              tooltip: 'Mark all as read',
              icon: const Icon(Icons.done_all),
              onPressed: () async {
                final api = context.read<AuthController>().api;
                try {
                  await api.post('notifications/read-all', {});
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                          content: Text('All notifications marked as read.')),
                    );
                    _load();
                  }
                } catch (_) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                          content: Text('Failed to mark all as read.')),
                    );
                  }
                }
              },
            ),
          if (_endpoint == 'admin/maintenance-bills')
            IconButton(
              tooltip: 'Generate Monthly Invoices',
              icon: const Icon(Icons.autorenew),
              onPressed: () async {
                final api = context.read<AuthController>().api;
                try {
                  final response =
                      await api.post('admin/maintenance-generate', {});
                  final msg = response['message'] ??
                      'Maintenance generation completed.';
                  if (context.mounted) {
                    ScaffoldMessenger.of(context)
                        .showSnackBar(SnackBar(content: Text('$msg')));
                    _load();
                  }
                } on ApiException catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context)
                        .showSnackBar(SnackBar(content: Text(e.message)));
                  }
                }
              },
            ),
        ],
      ),
      floatingActionButton: fab,
      body: bodyContent,
    );
  }

  Widget _buildNotificationCard(
      BuildContext context, Map<String, dynamic> item) {
    final rawData = item['data'];
    final data = rawData is Map
        ? Map<String, dynamic>.from(rawData)
        : <String, dynamic>{};

    // Explicit notification type from the backend (set by FCM service)
    final notifType = data['type']?.toString() ?? '';

    // isVisitor = any notification that relates to a visitor
    final isVisitor = data['visitor_id'] != null ||
        data['visitor_request_id'] != null ||
        notifType == 'visitor_request' ||
        notifType == 'visitor_approval_request' ||
        notifType == 'visitor_waiting_for_approval' ||
        notifType == 'visitor_approved' ||
        notifType == 'visitor_rejected' ||
        notifType == 'visitor_checked_in' ||
        notifType == 'visitor_checked_out' ||
        (data['title']?.toString().toLowerCase().contains('visitor') ?? false) ||
        (item['title']?.toString().toLowerCase().contains('visitor') ?? false);

    // isVisitorRequest = only notifications where the resident can still approve/reject
    final isVisitorRequest = notifType == 'visitor_request' ||
        notifType == 'visitor_approval_request' ||
        notifType == 'visitor_waiting_for_approval' ||
        (notifType.isEmpty &&
            isVisitor &&
            (data['approval_status']?.toString().toUpperCase() == 'PENDING' ||
             data['approval_status'] == null));

    String title = data['title']?.toString() ??
        (notifType == 'visitor_approved'
            ? 'Visitor Approved'
            : notifType == 'visitor_rejected'
                ? 'Visitor Declined'
                : notifType == 'visitor_checked_in'
                    ? 'Visitor Checked In'
                    : notifType == 'visitor_checked_out'
                        ? 'Visitor Checked Out'
                        : (isVisitor
                            ? 'Visitor Request'
                            : (data['parcel_id'] != null
                                ? 'Parcel Received'
                                : (item['title']?.toString() ?? 'Society Notification'))));

    String message = data['message']?.toString() ??
        (data['visitor_name'] != null
            ? _visitorMessageForType(notifType, data)
            : (data['courier_name'] != null
                ? 'A parcel from ${data['courier_name']} has arrived for your unit.'
                : (item['message']?.toString() ??
                    'You have a new society notification.')));

    final isRead = item['read_at'] != null;
    final createdAt = item['created_at'];

    // ── Type-aware icon and colour ──────────────────────────────────────────
    IconData icon = Icons.notifications_outlined;
    Color iconColor = const Color(0xFF6366F1);
    Color iconBg = const Color(0xFFEEF2FF);

    switch (notifType) {
      case 'visitor_approved':
        icon = Icons.check_circle_outline_rounded;
        iconColor = const Color(0xFF10B981);
        iconBg = const Color(0xFFD1FAE5);
        break;
      case 'visitor_rejected':
        icon = Icons.cancel_outlined;
        iconColor = const Color(0xFFEF4444);
        iconBg = const Color(0xFFFEE2E2);
        break;
      case 'visitor_checked_in':
        icon = Icons.login_rounded;
        iconColor = const Color(0xFF3B82F6);
        iconBg = const Color(0xFFDBEAFE);
        break;
      case 'visitor_checked_out':
        icon = Icons.logout_rounded;
        iconColor = const Color(0xFF64748B);
        iconBg = const Color(0xFFF1F5F9);
        break;
      default:
        if (isVisitor) {
          icon = Icons.badge_outlined;
          iconColor = const Color(0xFFF59E0B);
          iconBg = const Color(0xFFFEF3C7);
        } else if (title.toLowerCase().contains('parcel') ||
            data['parcel_id'] != null) {
          icon = Icons.inventory_2_outlined;
          iconColor = const Color(0xFF10B981);
          iconBg = const Color(0xFFD1FAE5);
        } else if (title.toLowerCase().contains('payment') ||
            title.toLowerCase().contains('bill')) {
          icon = Icons.receipt_long_outlined;
          iconColor = const Color(0xFF3B82F6);
          iconBg = const Color(0xFFDBEAFE);
        } else if (title.toLowerCase().contains('alert') ||
            title.toLowerCase().contains('emergency')) {
          icon = Icons.emergency_outlined;
          iconColor = const Color(0xFFEF4444);
          iconBg = const Color(0xFFFEE2E2);
        }
        break;
    }

    Future<void> markRead() async {
      if (!isRead) {
        try {
          final api = context.read<AuthController>().api;
          await api.patch('notifications/${item['id']}/read', {});
          if (mounted) {
            setState(() {
              item['read_at'] = DateTime.now().toIso8601String();
            });
          }
        } catch (_) {}
      }
    }

    void openDetails() async {
      await markRead();
      if (!context.mounted) return;

      if (isVisitorRequest) {
        // Resident can approve or reject — show the interactive approval sheet
        _showVisitorNotificationSheet(context, item, data);
      } else if (isVisitor) {
        // Read-only info sheet for approved/rejected/checked-in/checked-out events
        showSocietyNotificationSheet(context, data);
      } else {
        _showGeneralNotificationSheet(context, title, message, createdAt, icon, iconColor, iconBg);
      }
    }

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
      elevation: isRead ? 0 : 1.5,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: isRead
              ? const Color(0xFFE2E8F0)
              : const Color(0xFF6366F1).withValues(alpha: 0.3),
          width: isRead ? 1 : 1.5,
        ),
      ),
      color: isRead ? Colors.white : const Color(0xFFF8FAFC),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: openDetails,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: iconBg,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(icon, color: iconColor, size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                title,
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: isRead
                                      ? FontWeight.w600
                                      : FontWeight.w700,
                                  color: const Color(0xFF1E293B),
                                ),
                              ),
                            ),
                            if (!isRead)
                              Container(
                                width: 8,
                                height: 8,
                                decoration: const BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: Color(0xFF6366F1),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          message,
                          style: TextStyle(
                            fontSize: 13,
                            color: isRead
                                ? const Color(0xFF64748B)
                                : const Color(0xFF334155),
                            height: 1.3,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (createdAt != null) ...[
                          const SizedBox(height: 6),
                          Text(
                            _friendlyDate(createdAt),
                            style: const TextStyle(
                              fontSize: 11,
                              color: Color(0xFF94A3B8),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
              if (isVisitor) ...[
                const SizedBox(height: 10),
                Align(
                  alignment: Alignment.centerRight,
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                      visualDensity: VisualDensity.compact,
                      side: const BorderSide(color: Color(0xFF6366F1)),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    icon: const Icon(Icons.touch_app_outlined, size: 16, color: Color(0xFF6366F1)),
                    label: const Text(
                      'View Request',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF6366F1)),
                    ),
                    onPressed: openDetails,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  void _showGeneralNotificationSheet(
    BuildContext context,
    String title,
    String message,
    dynamic createdAt,
    IconData icon,
    Color iconColor,
    Color iconBg,
  ) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: iconBg,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, color: iconColor, size: 24),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF1E293B),
                        ),
                      ),
                      if (createdAt != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          _friendlyDate(createdAt),
                          style: const TextStyle(
                            fontSize: 12,
                            color: Color(0xFF64748B),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
            const Divider(height: 32),
            Text(
              message,
              style: const TextStyle(
                fontSize: 15,
                height: 1.5,
                color: Color(0xFF334155),
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Close'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showVisitorNotificationSheet(
    BuildContext context,
    Map<String, dynamic> item,
    Map<String, dynamic> data,
  ) {
    showVisitorApprovalSheet(context, data, onActionDone: _load);
  }

  Widget _buildResidentCard(BuildContext context, Map<String, dynamic> item) {
    final user = item['user'] is Map ? item['user'] as Map : null;
    final flat = item['flat'] is Map ? item['flat'] as Map : null;

    final name = user?['name']?.toString() ??
        item['name']?.toString() ??
        'Resident #${item['id'] ?? ''}';
    final email = user?['email']?.toString() ?? item['email']?.toString() ?? '';
    final phone = user?['phone']?.toString() ?? item['phone']?.toString() ?? '';
    final flatNumber =
        flat?['flat_number']?.toString() ?? item['flat_number']?.toString();
    final building =
        flat?['building']?.toString() ?? item['building']?.toString();
    final relation =
        item['relation_to_owner']?.toString().toUpperCase() ?? 'RESIDENT';
    final isPrimary = item['is_primary_contact'] == true;

    final relationLabel = switch (relation) {
      'OWNER' => 'Owner',
      'TENANT' => 'Tenant',
      'FAMILY_MEMBER' => 'Family member',
      'SELF' => 'Resident',
      _ => relation,
    };

    final unitInfo = [
      if (flatNumber != null && flatNumber.isNotEmpty) 'Flat $flatNumber',
      if (building != null && building.isNotEmpty) building,
    ].join(' • ');

    final contactInfo = [
      if (email.isNotEmpty) email,
      if (phone.isNotEmpty) phone,
    ].join(' · ');

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: Color(0xFFE2E8F0)),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () async {
          final flattenedItem = {
            ...item,
            if (user != null) ...Map<String, dynamic>.from(user),
            if (flat != null) 'flat_number': flat['flat_number'],
            if (flat != null) 'building': flat['building'],
          };
          final changed = await Navigator.of(context).push<bool>(
            MaterialPageRoute(
              builder: (_) => RecordDetailScreen(
                title: widget.title,
                endpoint: _endpoint,
                item: flattenedItem,
                config: _form,
              ),
            ),
          );
          if (changed == true) _load();
        },
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    radius: 20,
                    backgroundColor:
                        const Color(0xFF6366F1).withValues(alpha: 0.12),
                    child: Text(
                      _initials(name),
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF6366F1),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                name,
                                style: const TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFF1E293B),
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (isPrimary) ...[
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Colors.blue.shade50,
                                  borderRadius: BorderRadius.circular(6),
                                  border:
                                      Border.all(color: Colors.blue.shade200),
                                ),
                                child: Text(
                                  'Primary',
                                  style: TextStyle(
                                    fontSize: 9,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.blue.shade800,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                        if (unitInfo.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Row(
                            children: [
                              const Icon(Icons.apartment,
                                  size: 13, color: Color(0xFF64748B)),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Text(
                                  unitInfo,
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w500,
                                    color: Color(0xFF64748B),
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: relation == 'OWNER'
                          ? Colors.green.shade50
                          : (relation == 'TENANT'
                              ? Colors.purple.shade50
                              : Colors.indigo.shade50),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: relation == 'OWNER'
                            ? Colors.green.shade200
                            : (relation == 'TENANT'
                                ? Colors.purple.shade200
                                : Colors.indigo.shade200),
                      ),
                    ),
                    child: Text(
                      relationLabel,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: relation == 'OWNER'
                            ? Colors.green.shade800
                            : (relation == 'TENANT'
                                ? Colors.purple.shade800
                                : Colors.indigo.shade800),
                      ),
                    ),
                  ),
                ],
              ),
              if (contactInfo.isNotEmpty) ...[
                const SizedBox(height: 10),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.contact_mail_outlined,
                          size: 13, color: Color(0xFF94A3B8)),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          contactInfo,
                          style: const TextStyle(
                            fontSize: 11,
                            color: Color(0xFF64748B),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildVisitorCard(BuildContext context, Map<String, dynamic> item) {
    final name = item['visitor_name'] ?? 'Visitor';
    final type = item['visitor_type']?.toString().toUpperCase() ?? 'GUEST';
    final purpose = item['purpose']?.toString();
    final vehicle = item['vehicle_number']?.toString();
    final entryStatus = item['entry_status']?.toString().toUpperCase() ?? '';
    final approvalStatus =
        item['approval_status']?.toString().toUpperCase() ?? '';
    final flat = item['flat'] is Map ? item['flat'] as Map : null;
    final flatNumber = flat?['flat_number']?.toString();
    final expectedAt = item['expected_at'];

    IconData typeIcon = Icons.person_outline;
    if (type.contains('DELIVERY')) typeIcon = Icons.local_shipping_outlined;
    if (type.contains('CAB')) typeIcon = Icons.local_taxi_outlined;
    if (type.contains('SERVICE')) typeIcon = Icons.handyman_outlined;

    final isApproved = approvalStatus == 'APPROVED' ||
        entryStatus == 'CHECKED_IN' ||
        entryStatus == 'ENTERED';
    final isPending = approvalStatus == 'PENDING' ||
        entryStatus == 'WAITING' ||
        entryStatus == 'EXPECTED';

    final badgeText = entryStatus.isNotEmpty ? entryStatus : approvalStatus;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: Color(0xFFE2E8F0)),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () async {
          final changed = await Navigator.of(context).push<bool>(
            MaterialPageRoute(
              builder: (_) => RecordDetailScreen(
                title: widget.title,
                endpoint: _endpoint,
                item: item,
                config: _form,
              ),
            ),
          );
          if (changed == true) _load();
        },
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEEF2FF),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(typeIcon,
                        color: const Color(0xFF6366F1), size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name.toString(),
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF1E293B),
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          [
                            type.toString(),
                            if (flatNumber != null) 'Flat $flatNumber',
                            if (purpose != null && purpose.isNotEmpty)
                              purpose,
                            if (vehicle != null && vehicle.isNotEmpty)
                              vehicle,
                          ].join(' • '),
                          style: const TextStyle(
                            fontSize: 12,
                            color: Color(0xFF64748B),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (badgeText.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: isApproved
                            ? Colors.green.shade50
                            : (isPending
                                ? Colors.amber.shade50
                                : Colors.red.shade50),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isApproved
                              ? Colors.green.shade200
                              : (isPending
                                  ? Colors.amber.shade200
                                  : Colors.red.shade200),
                        ),
                      ),
                      child: Text(
                        badgeText,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: isApproved
                              ? Colors.green.shade800
                              : (isPending
                                  ? Colors.amber.shade900
                                  : Colors.red.shade800),
                        ),
                      ),
                    ),
                ],
              ),
              if (expectedAt != null) ...[
                const SizedBox(height: 10),
                Row(
                  children: [
                    const Icon(Icons.access_time,
                        size: 14, color: Color(0xFF94A3B8)),
                    const SizedBox(width: 4),
                    Text(
                      'Expected: ${_friendlyDate(expectedAt)}',
                      style: const TextStyle(
                          fontSize: 11, color: Color(0xFF94A3B8)),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildParcelCard(BuildContext context, Map<String, dynamic> item) {
    final courier = item['courier_name'] ?? 'Courier Parcel';
    final type = item['parcel_type']?.toString().toUpperCase() ?? 'BOX';
    final tracking = item['tracking_number']?.toString();
    final status =
        item['status']?.toString().toUpperCase() ?? 'AWAITING_PICKUP';
    final flat = item['flat'] is Map ? item['flat'] as Map : null;
    final flatNumber = flat?['flat_number']?.toString();
    final resident =
        item['resident'] is Map ? item['resident'] as Map : null;
    final recipientName = resident?['user']?['name']?.toString();
    final receivedAt = item['received_at'] ?? item['created_at'];

    IconData typeIcon = Icons.inventory_2_outlined;
    if (type.contains('FOOD')) typeIcon = Icons.fastfood_outlined;
    if (type.contains('DOCUMENT')) typeIcon = Icons.description_outlined;

    final isCollected = status == 'COLLECTED';

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: Color(0xFFE2E8F0)),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () async {
          final changed = await Navigator.of(context).push<bool>(
            MaterialPageRoute(
              builder: (_) => RecordDetailScreen(
                title: widget.title,
                endpoint: _endpoint,
                item: item,
                config: _form,
              ),
            ),
          );
          if (changed == true) _load();
        },
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFEF3C7),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(typeIcon,
                        color: const Color(0xFFD97706), size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          courier.toString(),
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF1E293B),
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          [
                            type.toString(),
                            if (flatNumber != null) 'Unit $flatNumber',
                            if (recipientName != null) recipientName,
                            if (tracking != null && tracking.isNotEmpty)
                              'Track: $tracking',
                          ].join(' • '),
                          style: const TextStyle(
                            fontSize: 12,
                            color: Color(0xFF64748B),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: isCollected
                          ? Colors.green.shade50
                          : Colors.amber.shade50,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: isCollected
                            ? Colors.green.shade200
                            : Colors.amber.shade200,
                      ),
                    ),
                    child: Text(
                      isCollected ? 'COLLECTED' : 'READY FOR PICKUP',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: isCollected
                            ? Colors.green.shade800
                            : Colors.amber.shade900,
                      ),
                    ),
                  ),
                ],
              ),
              if (receivedAt != null) ...[
                const SizedBox(height: 10),
                Row(
                  children: [
                    const Icon(Icons.access_time,
                        size: 14, color: Color(0xFF94A3B8)),
                    const SizedBox(width: 4),
                    Text(
                      'Received: ${_friendlyDate(receivedAt)}',
                      style: const TextStyle(
                          fontSize: 11, color: Color(0xFF94A3B8)),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class ConversationDetailScreen extends StatefulWidget {
  const ConversationDetailScreen({super.key, required this.conversation});
  final Map<String, dynamic> conversation;

  @override
  State<ConversationDetailScreen> createState() =>
      _ConversationDetailScreenState();
}

class _ConversationDetailScreenState extends State<ConversationDetailScreen> {
  final _message = TextEditingController();
  Map<String, dynamic>? _conversation;
  String? _error;
  bool _loading = true;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _message.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final api = context.read<AuthController>().api;
      final result =
          await api.get('conversations/${widget.conversation['id']}');
      await api.patch('conversations/${widget.conversation['id']}/read', {});
      _conversation = Map<String, dynamic>.from(result['data'] as Map);
    } on ApiException catch (error) {
      _error = error.message;
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _send() async {
    final body = _message.text.trim();
    if (body.isEmpty) return;
    setState(() => _sending = true);
    try {
      await context.read<AuthController>().api.post(
          'conversations/${widget.conversation['id']}/messages',
          {'body': body});
      _message.clear();
      await _load();
    } on ApiException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.message)));
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final messages = _conversation?['messages'] as List<dynamic>? ?? [];
    return Scaffold(
      appBar: AppBar(
          title: Text(_conversation?['subject']?.toString() ?? 'Conversation')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: FilledButton(
                      onPressed: _load, child: Text('Retry: $_error')))
              : Column(children: [
                  Expanded(
                    child: RefreshIndicator(
                      onRefresh: _load,
                      child: messages.isEmpty
                          ? ListView(children: const [
                              SizedBox(height: 180),
                              Center(child: Text('No messages yet.')),
                            ])
                          : ListView.builder(
                              padding: const EdgeInsets.all(12),
                              itemCount: messages.length,
                              itemBuilder: (_, index) {
                                final message = Map<String, dynamic>.from(
                                    messages[index] as Map);
                                final sender = message['sender'] is Map
                                    ? (message['sender'] as Map)['name']
                                    : 'Member';
                                return Card(
                                    child: ListTile(
                                  title:
                                      Text(message['body']?.toString() ?? ''),
                                  subtitle:
                                      Text(sender?.toString() ?? 'Member'),
                                ));
                              },
                            ),
                    ),
                  ),
                  SafeArea(
                    top: false,
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Row(children: [
                        Expanded(
                          child: TextField(
                            controller: _message,
                            minLines: 1,
                            maxLines: 4,
                            decoration: const InputDecoration(
                                labelText: 'Message',
                                border: OutlineInputBorder()),
                          ),
                        ),
                        const SizedBox(width: 8),
                        IconButton(
                          onPressed: _sending ? null : _send,
                          icon: _sending
                              ? const CircularProgressIndicator()
                              : const Icon(Icons.send),
                        ),
                      ]),
                    ),
                  ),
                ]),
    );
  }
}

class RecordDetailScreen extends StatefulWidget {
  const RecordDetailScreen(
      {super.key,
      required this.title,
      required this.endpoint,
      required this.item,
      this.config});
  final String title;
  final String endpoint;
  final Map<String, dynamic> item;
  final FormConfig? config;
  @override
  State<RecordDetailScreen> createState() => _RecordDetailScreenState();
}

class _RecordDetailScreenState extends State<RecordDetailScreen> {
  late Map<String, dynamic> _item;
  bool _updatingStatus = false;
  bool _hasChanged = false;

  @override
  void initState() {
    super.initState();
    _item = Map<String, dynamic>.from(widget.item);
  }

  Future<void> _loadRecord() async {
    try {
      final response = await context
          .read<AuthController>()
          .api
          .get('${widget.endpoint}/${_item['id']}');
      if (mounted && response['data'] is Map) {
        setState(() {
          _item = Map<String, dynamic>.from(response['data'] as Map);
        });
      }
    } catch (_) {}
  }

  bool get _canDelete => const {
        'admin/residents',
        'admin/flats',
        'admin/maintenance-bills'
      }.contains(widget.endpoint);

  Future<void> _delete() async {
    final api = context.read<AuthController>().api;
    final accepted = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
                title: const Text('Delete record?'),
                content: const Text('This action cannot be undone.'),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('Cancel')),
                  FilledButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: const Text('Delete'))
                ]));
    if (accepted != true) return;
    try {
      await api.delete('${widget.endpoint}/${_item['id']}');
      if (mounted) {
        Navigator.pop(context, true);
      }
    } on ApiException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.message)));
      }
    }
  }

  Future<void> _patch(String suffix, [Map<String, dynamic>? data]) async {
    try {
      await context
          .read<AuthController>()
          .api
          .patch('${widget.endpoint}/${_item['id']}/$suffix', data ?? {});
      if (mounted) Navigator.pop(context, true);
    } on ApiException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.message)));
      }
    }
  }

  Future<void> _updateStaffStatus(String newStatus) async {
    final isActivating = newStatus == 'ACTIVE';
    final actionWord = isActivating ? 'Activate' : 'Deactivate';
    final confirmTitle = '$actionWord staff account?';
    final confirmBody = isActivating
        ? 'Activate this staff account?'
        : 'Deactivate this staff account?';

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(confirmTitle),
        content: Text(confirmBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(actionWord),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() => _updatingStatus = true);
    final api = context.read<AuthController>().api;

    try {
      final response = await api.patch(
        'admin/staff-members/${_item['id']}/status',
        {'status': newStatus},
      );

      if (!mounted) return;

      final updated = response['data'] is Map
          ? Map<String, dynamic>.from(response['data'] as Map)
          : null;

      setState(() {
        if (updated != null) {
          _item = updated;
        } else {
          _item['status'] = newStatus;
        }
        _hasChanged = true;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            isActivating
                ? 'Staff account activated successfully.'
                : 'Staff account deactivated successfully.',
          ),
        ),
      );
    } on ApiException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error.message)),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _updatingStatus = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, result) {
          if (!didPop) Navigator.pop(context, _hasChanged);
        },
        child: Scaffold(
            appBar: AppBar(
                title: Text(widget.title),
                leading: IconButton(
                  icon: const Icon(Icons.arrow_back),
                  onPressed: () => Navigator.pop(context, _hasChanged),
                ),
                actions: [
                  if (widget.config != null)
                    IconButton(
                        icon: const Icon(Icons.edit),
                        onPressed: () async {
                          final changed = await Navigator.push<bool>(
                              context,
                              MaterialPageRoute(
                                  builder: (_) => ModuleFormScreen(
                                      config: widget.config!,
                                      initial: widget.endpoint ==
                                                  'resident/profile' &&
                                              _item['user'] is Map
                                          ? {
                                              ..._item,
                                              ...Map<String, dynamic>.from(
                                                  _item['user'] as Map),
                                            }
                                          : _item,
                                      submitPath: widget.endpoint ==
                                              'resident/profile'
                                          ? widget.endpoint
                                          : '${widget.endpoint}/${_item['id']}',
                                      isEdit: true)));
                          if (changed == true && context.mounted) {
                            setState(() => _hasChanged = true);
                            _loadRecord();
                          }
                        }),
                  if (_canDelete)
                    IconButton(
                        icon: const Icon(Icons.delete), onPressed: _delete),
                  if (widget.endpoint == 'resident/visitors') ...[
                    IconButton(
                        tooltip: 'Approve',
                        icon: const Icon(Icons.check_circle),
                        onPressed: () => _patch('approve')),
                    IconButton(
                        tooltip: 'Reject',
                        icon: const Icon(Icons.cancel),
                        onPressed: () => _patch('reject')),
                  ],
                  if (widget.endpoint == 'security/visitors') ...[
                    IconButton(
                        tooltip: 'Record entry',
                        icon: const Icon(Icons.login),
                        onPressed: () => _patch('entry')),
                    IconButton(
                        tooltip: 'Record exit',
                        icon: const Icon(Icons.logout),
                        onPressed: () => _patch('exit')),
                  ],
                  if (widget.endpoint == 'resident/amenity-bookings' ||
                      widget.endpoint == 'admin/amenity-bookings')
                    IconButton(
                        tooltip: 'Cancel booking',
                        icon: const Icon(Icons.cancel_schedule_send),
                        onPressed: () => _patch('cancel')),
                  if (widget.endpoint == 'notifications')
                    IconButton(
                        tooltip: 'Mark read',
                        icon: const Icon(Icons.mark_email_read),
                        onPressed: () async {
                          final api = context.read<AuthController>().api;
                          try {
                            await api
                                .patch('notifications/${_item['id']}/read', {});
                            if (!context.mounted) return;
                            Navigator.pop(context, true);
                          } on ApiException catch (error) {
                            if (!context.mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text(error.message)));
                          }
                        }),
                  if (widget.endpoint == 'admin/parcels' ||
                      widget.endpoint == 'staff/parcels')
                    IconButton(
                        tooltip: 'Mark collected',
                        icon: const Icon(Icons.inventory_2),
                        onPressed: () => _patch('collect'))
                ]),
            body: ListView(padding: const EdgeInsets.all(16), children: [
              if (widget.endpoint == 'admin/staff-members') ...[
                Card(
                  elevation: 2,
                  color: _item['status'] == 'ACTIVE'
                      ? Colors.green.shade50
                      : Colors.orange.shade50,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              _item['status'] == 'ACTIVE'
                                  ? Icons.check_circle
                                  : Icons.pause_circle_filled,
                              color: _item['status'] == 'ACTIVE'
                                  ? Colors.green.shade700
                                  : Colors.orange.shade800,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'Status: ${_item['status'] ?? 'INACTIVE'}',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                                color: _item['status'] == 'ACTIVE'
                                    ? Colors.green.shade800
                                    : Colors.orange.shade900,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        if (_item['status'] == 'ACTIVE')
                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton.icon(
                              onPressed: _updatingStatus
                                  ? null
                                  : () => _updateStaffStatus('INACTIVE'),
                              icon: _updatingStatus
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2))
                                  : const Icon(Icons.block),
                              label: Text(_updatingStatus
                                  ? 'Updating...'
                                  : 'Deactivate Account'),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.red.shade700,
                                side: BorderSide(color: Colors.red.shade300),
                              ),
                            ),
                          )
                        else
                          SizedBox(
                            width: double.infinity,
                            child: FilledButton.icon(
                              onPressed: _updatingStatus
                                  ? null
                                  : () => _updateStaffStatus('ACTIVE'),
                              icon: _updatingStatus
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2, color: Colors.white))
                                  : const Icon(Icons.verified_user),
                              label: Text(_updatingStatus
                                  ? 'Updating...'
                                  : 'Activate Account'),
                              style: FilledButton.styleFrom(
                                backgroundColor: Colors.green.shade700,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
              ],
              if (widget.endpoint.contains('complaints')) ...[
                Card(
                  elevation: 2,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Complaint History & Timeline',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                        ),
                        const SizedBox(height: 12),
                        ListTile(
                          dense: true,
                          leading: const Icon(Icons.add_circle_outline,
                              color: Colors.blue),
                          title: const Text('Complaint Created'),
                          subtitle: Text(
                              'Created on ${_item['created_at'] ?? 'N/A'}'),
                        ),
                        if (_item['history'] is List &&
                            (_item['history'] as List).isNotEmpty)
                          for (final h in (_item['history'] as List))
                            ListTile(
                              dense: true,
                              leading: const Icon(Icons.history,
                                  color: Colors.orange),
                              title: Text(
                                '${h['from_status'] ?? 'OPEN'} → ${h['to_status']}',
                                style: const TextStyle(
                                    fontWeight: FontWeight.w600),
                              ),
                              subtitle: Text(
                                'Changed on ${h['created_at'] ?? 'N/A'}'
                                '${h['changed_by'] != null ? ' by ${h['changed_by']}' : ''}'
                                '${h['note'] != null && h['note'].toString().isNotEmpty ? '\nNote: ${h['note']}' : ''}',
                              ),
                            ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
              ],
              for (final entry in _item.entries.where((entry) =>
                  entry.value != null &&
                  entry.key != 'history' &&
                  !const [
                    'id',
                    'uuid',
                    'notifiable_type',
                    'notifiable_id',
                    'token',
                    'remember_token',
                    'password',
                    'updated_at',
                    'email_verified_at',
                  ].contains(entry.key.toLowerCase())))
                if (entry.value is Map)
                  for (final subEntry in (entry.value as Map)
                      .entries
                      .where((e) =>
                          e.value != null &&
                          !const ['id', 'uuid', 'password', 'updated_at']
                              .contains(e.key.toString().toLowerCase())))
                    Card(
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: const BorderSide(color: Color(0xFFE2E8F0)),
                      ),
                      child: ListTile(
                        title: Text(
                          _formatFieldLabel('${entry.key} ${subEntry.key}'),
                          style: const TextStyle(
                            fontSize: 13,
                            color: Color(0xFF64748B),
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        subtitle: Text(
                          _formatFieldValue(subEntry.key.toString(), subEntry.value),
                          style: const TextStyle(
                            fontSize: 15,
                            color: Color(0xFF1E293B),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    )
                else
                  Card(
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: const BorderSide(color: Color(0xFFE2E8F0)),
                    ),
                    child: ListTile(
                      title: Text(
                        _formatFieldLabel(entry.key),
                        style: const TextStyle(
                          fontSize: 13,
                          color: Color(0xFF64748B),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      subtitle: Text(
                        _formatFieldValue(entry.key, entry.value),
                        style: const TextStyle(
                          fontSize: 15,
                          color: Color(0xFF1E293B),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  )
            ])),
      );
}

String _formatFieldLabel(String key) {
  return key
      .replaceAll('_', ' ')
      .split(' ')
      .where((w) => w.isNotEmpty)
      .map((w) => w[0].toUpperCase() + w.substring(1).toLowerCase())
      .join(' ');
}

String _formatFieldValue(String key, dynamic value) {
  if (value == null) return '-';
  final keyLower = key.toLowerCase();
  if (keyLower.contains('_at') || keyLower == 'date' || keyLower == 'due_date' || keyLower == 'expected_at' || keyLower == 'received_at') {
    return _friendlyDate(value);
  }
  if (keyLower == 'amount' || keyLower == 'total_amount' || keyLower == 'collected_amount' || keyLower == 'penalty_amount') {
    return _money(value);
  }
  return value.toString();
}

class FormConfig {
  const FormConfig(this.title, this.path, this.fields,
      {this.patchOnEdit = false,
      this.optionalFields = const [],
      this.showCreate = true,
      this.optionsEndpoint,
      this.optionKeys = const {},
      this.staticOptions = const {}});
  final String title;
  final String path;
  final List<String> fields;
  final bool patchOnEdit;
  final List<String> optionalFields;
  final bool showCreate;
  final String? optionsEndpoint;
  final Map<String, String> optionKeys;
  final Map<String, List<FormOption>> staticOptions;
  static FormConfig? forRoute(String route) => {
        'resident/profile': const FormConfig('Edit profile', 'resident/profile',
            ['name', 'email', 'phone', 'password'],
            patchOnEdit: true, optionalFields: ['password']),
        'resident/complaints':
            const FormConfig('New complaint', 'resident/complaints', [
          'category',
          'title',
          'description',
          'priority'
        ], optionalFields: [
          'published_at',
          'expires_at'
        ], staticOptions: {
          'category': [
            FormOption('PLUMBING', 'Plumbing'),
            FormOption('ELECTRICITY', 'Electricity'),
            FormOption('SECURITY', 'Security'),
            FormOption('CLEANING', 'Cleaning'),
            FormOption('LIFT', 'Lift'),
            FormOption('PARKING', 'Parking'),
            FormOption('WATER', 'Water'),
            FormOption('NOISE', 'Noise'),
            FormOption('MAINTENANCE', 'Maintenance'),
            FormOption('OTHER', 'Other'),
          ],
          'priority': [
            FormOption('LOW', 'Low'),
            FormOption('MEDIUM', 'Medium'),
            FormOption('HIGH', 'High'),
            FormOption('EMERGENCY', 'Emergency'),
          ],
        }),
        'resident/maintenance-payments': const FormConfig(
            'Submit payment', 'resident/maintenance-payments', [
          'maintenance_bill_id',
          'amount',
          'payment_method',
          'reference_id',
          'receipt_reference',
        ],
            optionalFields: [
              'reference_id',
              'receipt_reference'
            ]),
        'resident/visitors': const FormConfig(
            'Pre-approve visitor', 'resident/visitors/pre-approvals', [
          'visitor_name',
          'visitor_type',
          'expected_at',
        ],
            staticOptions: {
              'visitor_type': [
                FormOption('GUEST', 'Guest'),
                FormOption('DELIVERY', 'Delivery'),
                FormOption('CAB', 'Cab / taxi'),
                FormOption('SERVICE_PROVIDER', 'Service provider'),
                FormOption('OTHER', 'Other'),
              ],
            }),
        'security/visitors': const FormConfig(
            'Gate visitor',
            'security/visitors',
            [
              'visitor_name',
              'flat_id',
              'resident_id',
              'visitor_type',
            ],
            optionsEndpoint: 'security/visitors/options',
            optionKeys: {'flat_id': 'flats', 'resident_id': 'residents'},
            staticOptions: {
              'visitor_type': [
                FormOption('GUEST', 'Guest'),
                FormOption('DELIVERY', 'Delivery'),
                FormOption('CAB', 'Cab / taxi'),
                FormOption('SERVICE_PROVIDER', 'Service provider'),
                FormOption('OTHER', 'Other'),
              ],
            }),
        'resident/amenity-bookings': const FormConfig(
            'Book amenity',
            'resident/amenity-bookings',
            ['amenity_id', 'booking_date', 'start_time', 'end_time', 'notes'],
            optionsEndpoint: 'amenities',
            optionKeys: {'amenity_id': 'data'}),
        'admin/staff-members':
            const FormConfig('Add staff member', 'admin/staff-members', [
          'name',
          'employee_id',
          'mobile',
          'email',
          'designation',
          'joining_date',
          'shift',
          'status',
          'emergency_contact'
        ], optionalFields: [
          'employee_id',
          'email',
          'shift',
          'emergency_contact'
        ], staticOptions: {
          'shift': [
            FormOption('MORNING', 'Morning'),
            FormOption('EVENING', 'Evening'),
            FormOption('NIGHT', 'Night'),
            FormOption('ROTATING', 'Rotating'),
          ],
          'status': [
            FormOption('ACTIVE', 'Active'),
            FormOption('INACTIVE', 'Inactive'),
            FormOption('ON_LEAVE', 'On leave'),
          ],
        }),
        'admin/parking-slots': const FormConfig(
            'Add parking slot',
            'admin/parking-slots',
            ['slot_number', 'parking_type', 'flat_id', 'vehicle_number'],
            optionalFields: ['flat_id', 'vehicle_number'],
            optionsEndpoint: 'admin/options',
            optionKeys: {'flat_id': 'flats'},
            staticOptions: {
              'parking_type': [
                FormOption('CAR', 'Car'),
                FormOption('BIKE', 'Bike'),
                FormOption('VISITOR', 'Visitor'),
                FormOption('OTHER', 'Other'),
              ],
            }),
        'admin/amenities': const FormConfig('Add amenity', 'admin/amenities', [
          'name',
          'description',
          'max_booking_hours',
          'opening_time',
          'closing_time',
          'is_active'
        ], optionalFields: [
          'description',
          'opening_time',
          'closing_time'
        ], staticOptions: {
          'is_active': [FormOption('1', 'Active'), FormOption('0', 'Inactive')],
        }),
        'admin/notices': const FormConfig('Create notice', 'admin/notices', [
          'title',
          'content',
          'category',
          'priority',
          'audience',
          'is_published',
          'published_at',
          'expires_at'
        ], optionalFields: [
          'published_at',
          'expires_at'
        ], staticOptions: {
          'category': [
            FormOption('GENERAL', 'General'),
            FormOption('MAINTENANCE', 'Maintenance'),
            FormOption('EMERGENCY', 'Emergency'),
            FormOption('EVENT', 'Event'),
            FormOption('SECURITY', 'Security'),
            FormOption('WATER', 'Water'),
            FormOption('ELECTRICITY', 'Electricity'),
          ],
          'priority': [
            FormOption('LOW', 'Low'),
            FormOption('NORMAL', 'Normal'),
            FormOption('HIGH', 'High'),
            FormOption('EMERGENCY', 'Emergency'),
          ],
          'audience': [
            FormOption('ALL', 'Society-wide'),
            FormOption('RESIDENTS', 'All residents'),
            FormOption('OWNERS', 'All owners'),
            FormOption('STAFF', 'All staff'),
          ],
          'is_published': [
            FormOption('1', 'Publish now'),
            FormOption('0', 'Save as draft'),
          ],
        }),
        'admin/flats': const FormConfig(
            'Flat',
            'admin/flats',
            [
              'flat_number',
              'building',
              'floor',
              'owner_user_id',
              'occupancy_status'
            ],
            optionsEndpoint: 'admin/options',
            optionKeys: {'owner_user_id': 'owners'},
            optionalFields: ['owner_user_id'],
            staticOptions: {
              'occupancy_status': [
                FormOption('VACANT', 'Vacant'),
                FormOption('OCCUPIED', 'Occupied'),
                FormOption('UNDER_MAINTENANCE', 'Under maintenance')
              ],
            }),
        'admin/maintenance-bills': const FormConfig(
            'Maintenance bill',
            'admin/maintenance-bills',
            [
              'flat_id',
              'billing_month',
              'billing_period_start',
              'billing_period_end',
              'due_date',
              'base_maintenance',
              'water_charge',
              'electricity_common_area_charge',
              'parking_charge',
              'other_charges',
              'late_fee',
              'discount',
              'notes'
            ],
            optionsEndpoint: 'admin/options',
            optionKeys: {'flat_id': 'flats'},
            optionalFields: [
              'billing_period_start',
              'billing_period_end',
              'water_charge',
              'electricity_common_area_charge',
              'parking_charge',
              'other_charges',
              'late_fee',
              'discount',
              'notes',
            ]),
        'admin/residents': const FormConfig(
            'Resident',
            'admin/residents',
            [
              'name',
              'email',
              'phone',
              'password',
              'flat_id',
              'relation_to_owner'
            ],
            optionalFields: ['password', 'phone'],
            optionsEndpoint: 'admin/options',
            optionKeys: {'flat_id': 'flats'},
            staticOptions: {
              'relation_to_owner': [
                FormOption('OWNER', 'Owner'),
                FormOption('TENANT', 'Tenant'),
                FormOption('FAMILY_MEMBER', 'Family member')
              ],
            }),
        'admin/complaints': const FormConfig('Update complaint',
            'admin/complaints', ['status', 'assigned_staff_id', 'note'],
            patchOnEdit: true,
            showCreate: false,
            optionalFields: ['assigned_staff_id', 'note'],
            optionsEndpoint: 'admin/options',
            optionKeys: {'assigned_staff_id': 'staff_members'},
            staticOptions: {
              'status': [
                FormOption('OPEN', 'Open'),
                FormOption('ASSIGNED', 'Assigned'),
                FormOption('IN_PROGRESS', 'In progress'),
                FormOption('RESOLVED', 'Resolved'),
                FormOption('CLOSED', 'Closed'),
                FormOption('REOPENED', 'Reopened'),
              ],
            }),
        'staff/complaints': const FormConfig(
            'Update complaint', 'staff/complaints', ['status', 'note'],
            patchOnEdit: true,
            showCreate: false,
            optionalFields: ['note'],
            staticOptions: {
              'status': [
                FormOption('OPEN', 'Open'),
                FormOption('ASSIGNED', 'Assigned'),
                FormOption('IN_PROGRESS', 'In progress'),
                FormOption('RESOLVED', 'Resolved'),
                FormOption('CLOSED', 'Closed'),
                FormOption('REOPENED', 'Reopened'),
              ],
            }),
        'admin/parcels': const FormConfig(
            'Receive parcel',
            'admin/parcels',
            [
              'flat_id',
              'resident_id',
              'courier_name',
              'tracking_number',
              'parcel_type',
              'notes'
            ],
            optionsEndpoint: 'admin/options',
            optionKeys: {'flat_id': 'flats', 'resident_id': 'residents'},
            optionalFields: ['tracking_number', 'notes'],
            staticOptions: {
              'parcel_type': [
                FormOption('DOCUMENT', 'Document'),
                FormOption('BOX', 'Box'),
                FormOption('FOOD', 'Food'),
                FormOption('OTHER', 'Other')
              ],
            }),
        'staff/parcels': const FormConfig(
            'Receive parcel',
            'staff/parcels',
            [
              'flat_id',
              'resident_id',
              'courier_name',
              'tracking_number',
              'parcel_type',
              'notes'
            ],
            optionsEndpoint: 'staff/options',
            optionKeys: {'flat_id': 'flats', 'resident_id': 'residents'},
            optionalFields: ['tracking_number', 'notes'],
            staticOptions: {
              'parcel_type': [
                FormOption('DOCUMENT', 'Document'),
                FormOption('BOX', 'Box'),
                FormOption('FOOD', 'Food'),
                FormOption('OTHER', 'Other')
              ],
            }),
        'security/parcels': const FormConfig(
            'Receive parcel',
            'security/parcels',
            [
              'flat_id',
              'resident_id',
              'courier_name',
              'tracking_number',
              'parcel_type',
              'notes'
            ],
            optionsEndpoint: 'security/visitors/options',
            optionKeys: {'flat_id': 'flats', 'resident_id': 'residents'},
            optionalFields: ['tracking_number', 'notes'],
            staticOptions: {
              'parcel_type': [
                FormOption('DOCUMENT', 'Document'),
                FormOption('BOX', 'Box'),
                FormOption('FOOD', 'Food'),
                FormOption('OTHER', 'Other')
              ],
            })
      }[route];
}

class FormOption {
  const FormOption(this.value, this.label);
  final String value;
  final String label;
}

class ModuleFormScreen extends StatefulWidget {
  const ModuleFormScreen(
      {super.key,
      required this.config,
      this.initial,
      this.submitPath,
      this.isEdit = false});
  final FormConfig config;
  final Map<String, dynamic>? initial;
  final String? submitPath;
  final bool isEdit;
  @override
  State<ModuleFormScreen> createState() => _ModuleFormScreenState();
}

class _ModuleFormScreenState extends State<ModuleFormScreen> {
  final _form = GlobalKey<FormState>();
  final Map<String, TextEditingController> _controllers = {};
  final Map<String, List<FormOption>> _options = {};
  String? _error;
  bool _saving = false;
  bool _loadingOptions = false;

  static const _dateFields = {
    'billing_month',
    'billing_period_start',
    'billing_period_end',
    'due_date',
    'joining_date',
    'booking_date',
    'date_of_birth',
  };

  static const _timeFields = {
    'start_time',
    'end_time',
    'opening_time',
    'closing_time',
  };

  bool _isDateField(String field) => _dateFields.contains(field);
  bool _isMonthField(String field) => field == 'billing_month';
  bool _isTimeField(String field) => _timeFields.contains(field);

  String _displayDate(String value, {bool monthOnly = false}) {
    final date = DateTime.tryParse(value);
    if (date == null) return monthOnly ? 'Select billing month' : 'Select date';
    return monthOnly
        ? '${_monthName(date.month)} ${date.year}'
        : '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
  }

  String _displayTime(String value, String field) {
    if (value.trim().isEmpty) return 'Select ${_fieldLabel(field).toLowerCase()}';
    final parsed = parseTimeOfDay(value);
    if (parsed == null) return value;
    return formatTimeOfDay12(parsed);
  }

  Future<void> _pickDate(String field) async {
    final current = DateTime.tryParse(_controllers[field]!.text);
    final now = DateTime.now();
    final selected = await showDatePicker(
      context: context,
      initialDate: current ?? now,
      firstDate: field == 'date_of_birth' ? DateTime(1900) : DateTime(2000),
      lastDate: field == 'date_of_birth' ? now : DateTime(now.year + 10),
      initialDatePickerMode:
          _isMonthField(field) ? DatePickerMode.year : DatePickerMode.day,
      helpText: _isMonthField(field)
          ? 'Select billing month and year'
          : 'Select ${_fieldLabel(field).toLowerCase()}',
    );
    if (selected == null || !mounted) return;
    final value = _isMonthField(field)
        ? DateTime(selected.year, selected.month, 1)
        : selected;
    setState(() => _controllers[field]!.text =
        '${value.year.toString().padLeft(4, '0')}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}');
  }

  Future<void> _pickTime(String field) async {
    final current = parseTimeOfDay(_controllers[field]!.text);
    TimeOfDay defaultTime;
    if (field == 'end_time' &&
        _controllers['start_time']?.text.isNotEmpty == true) {
      final start = parseTimeOfDay(_controllers['start_time']!.text);
      defaultTime = start != null
          ? TimeOfDay(hour: (start.hour + 1) % 24, minute: start.minute)
          : const TimeOfDay(hour: 10, minute: 0);
    } else if (field == 'closing_time' &&
        _controllers['opening_time']?.text.isNotEmpty == true) {
      final open = parseTimeOfDay(_controllers['opening_time']!.text);
      defaultTime = open != null
          ? TimeOfDay(hour: (open.hour + 8) % 24, minute: open.minute)
          : const TimeOfDay(hour: 18, minute: 0);
    } else {
      defaultTime = const TimeOfDay(hour: 9, minute: 0);
    }

    final selected = await showScrollWheelTimePicker(
      context,
      initialTime: current ?? defaultTime,
      title: 'Select ${_fieldLabel(field)}',
    );
    if (selected == null || !mounted) return;
    setState(() => _controllers[field]!.text = formatTimeOfDay24(selected));
  }

  String? _validateTimeField(String field, String? value) {
    final isOptional = widget.config.optionalFields.contains(field);
    if (!isOptional && (value == null || value.trim().isEmpty)) {
      return 'Please select ${_fieldLabel(field).toLowerCase()}.';
    }
    if (value != null && value.trim().isNotEmpty) {
      final time = parseTimeOfDay(value);
      if (time == null) {
        return 'Invalid time format.';
      }

      if (field == 'end_time') {
        final startStr = _controllers['start_time']?.text;
        if (startStr != null && startStr.trim().isNotEmpty) {
          final startTime = parseTimeOfDay(startStr);
          if (startTime != null) {
            final startMinutes = startTime.hour * 60 + startTime.minute;
            final endMinutes = time.hour * 60 + time.minute;
            if (endMinutes <= startMinutes) {
              return 'End time must be after start time.';
            }
          }
        }
      } else if (field == 'closing_time') {
        final openStr = _controllers['opening_time']?.text;
        if (openStr != null && openStr.trim().isNotEmpty) {
          final openTime = parseTimeOfDay(openStr);
          if (openTime != null) {
            final openMinutes = openTime.hour * 60 + openTime.minute;
            final closeMinutes = time.hour * 60 + time.minute;
            if (closeMinutes <= openMinutes) {
              return 'Closing time must be after opening time.';
            }
          }
        }
      }
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    for (final field in widget.config.fields) {
      final raw = widget.initial?[field];
      _controllers[field] = TextEditingController(
          text: field == 'is_active' && raw is bool
              ? (raw ? '1' : '0')
              : raw?.toString() ?? '');
    }
    _options.addAll(widget.config.staticOptions);
    _loadOptions();
  }

  Future<void> _loadOptions() async {
    final endpoint = widget.config.optionsEndpoint;
    if (endpoint == null) return;
    setState(() => _loadingOptions = true);
    try {
      final response = await context.read<AuthController>().api.get(endpoint);
      final data = response['data'];
      for (final entry in widget.config.optionKeys.entries) {
        dynamic raw;
        if (endpoint == 'amenities') {
          raw = data is Map ? data['data'] : data;
        } else if (data is Map) {
          raw = data[entry.value];
        }
        if (raw is List) {
          _options[entry.key] = raw
              .whereType<Map>()
              .map((item) => FormOption(
                  item['id'].toString(),
                  item['label']?.toString() ??
                      item['name']?.toString() ??
                      'Option'))
              .toList();
        }
      }
    } on ApiException catch (error) {
      _error = 'Could not load form selections: ${error.message}';
    } finally {
      if (mounted) setState(() => _loadingOptions = false);
    }
  }

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    final data = <String, dynamic>{};
    for (final entry in _controllers.entries) {
      final value = entry.value.text.trim();
      if (value.isNotEmpty) {
        data[entry.key] =
            entry.key.endsWith('_id') || entry.key == 'max_booking_hours'
                ? int.tryParse(value) ?? value
                : value;
      }
    }
    if (widget.config.path == 'resident/amenity-bookings') {
      final startTimeDisplay =
          formatTimeString12(data['start_time']?.toString());
      final endTimeDisplay = formatTimeString12(data['end_time']?.toString());
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Confirm Amenity Booking?'),
          content: Text(
            'Date: ${data['booking_date'] ?? 'Selected Date'}\n'
            'Time: $startTimeDisplay - $endTimeDisplay'
            '${data['notes'] != null && data['notes'].toString().trim().isNotEmpty ? '\nNotes: ${data['notes']}' : ''}',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Confirm Booking'),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
    }
    if (!mounted) return;
    try {
      final api = context.read<AuthController>().api;
      final path = widget.submitPath ?? widget.config.path;
      if (widget.isEdit) {
        if (widget.config.patchOnEdit) {
          await api.patch(path, data);
        } else {
          await api.put(path, data);
        }
      } else {
        await api.post(path, data);
      }
      if (mounted) {
        Navigator.pop(context, true);
      }
    } on ApiException catch (exception) {
      if (mounted) setState(() => _error = exception.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: AppBar(
          title: Text(widget.isEdit && widget.config.title.startsWith('New ')
              ? widget.config.title.replaceFirst('New ', 'Edit ')
              : (widget.isEdit && widget.config.title.startsWith('Add ')
                  ? widget.config.title.replaceFirst('Add ', 'Edit ')
                  : (widget.isEdit
                      ? 'Edit ${widget.config.title.toLowerCase()}'
                      : widget.config.title)))),
      body: Form(
          key: _form,
          child: ListView(padding: const EdgeInsets.all(16), children: [
            if (_loadingOptions)
              const Padding(
                  padding: EdgeInsets.only(bottom: 16),
                  child: LinearProgressIndicator()),
            for (final field in widget.config.fields)
              Padding(
                  padding: const EdgeInsets.only(bottom: 14),
                  child: _isDateField(field)
                      ? _DateSelectionField(
                          label: _fieldLabel(field),
                          value: _displayDate(_controllers[field]!.text,
                              monthOnly: _isMonthField(field)),
                          required:
                              !widget.config.optionalFields.contains(field),
                          onTap: _saving ? null : () => _pickDate(field),
                        )
                      : _isTimeField(field)
                          ? _TimeSelectionField(
                              label: _fieldLabel(field),
                              value: _displayTime(
                                  _controllers[field]!.text, field),
                              required: !widget.config.optionalFields
                                  .contains(field),
                              onTap: _saving ? null : () => _pickTime(field),
                              validator: (val) => _validateTimeField(
                                  field, _controllers[field]!.text),
                            )
                          : !_options.containsKey(field) &&
                                  !widget.config.optionKeys.containsKey(field)
                              ? TextFormField(
                                  controller: _controllers[field]!,
                                  keyboardType: field.endsWith('_id') ||
                                          field == 'max_booking_hours' ||
                                          const {
                                            'base_maintenance',
                                            'water_charge',
                                            'electricity_common_area_charge',
                                            'parking_charge',
                                            'other_charges',
                                            'late_fee',
                                            'discount',
                                          }.contains(field)
                                      ? TextInputType.number
                                      : TextInputType.text,
                                  maxLines:
                                      field == 'description' || field == 'content'
                                          ? 4
                                          : 1,
                                  decoration: InputDecoration(
                                      labelText: _fieldLabel(field),
                                      border: const OutlineInputBorder()),
                                  validator: (value) => value == null ||
                                          (value.trim().isEmpty &&
                                              !widget.config.optionalFields
                                                  .contains(field) &&
                                              field != 'notes' &&
                                              !(widget.isEdit &&
                                                  field == 'password'))
                                      ? '${_fieldLabel(field)} is required'
                                      : null)
                              : _SelectionField(
                                  label: _fieldLabel(field),
                                  options: _options[field] ?? const [],
                                  controller: _controllers[field]!,
                                  required: !widget.config.optionalFields
                                      .contains(field),
                                  enabled: !_saving && !_loadingOptions,
                                )),
            if (_error != null)
              Text(_error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error)),
            FilledButton(
                onPressed: _saving ? null : _save,
                child: _saving
                    ? const CircularProgressIndicator()
                    : const Text('Save'))
          ])));
}

class _DateSelectionField extends StatelessWidget {
  const _DateSelectionField({
    required this.label,
    required this.value,
    required this.required,
    required this.onTap,
  });

  final String label;
  final String value;
  final bool required;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => FormField<String>(
        key: ValueKey(value),
        initialValue: value.startsWith('Select') ? '' : value,
        validator: (fieldValue) =>
            required && (fieldValue == null || fieldValue.isEmpty)
                ? 'Please select ${label.toLowerCase()}.'
                : null,
        builder: (state) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            OutlinedButton.icon(
              onPressed: onTap,
              icon: const Icon(Icons.calendar_month_outlined),
              label: Align(
                alignment: Alignment.centerLeft,
                child: Text('$label: $value'),
              ),
            ),
            if (state.hasError)
              Padding(
                padding: const EdgeInsets.only(left: 12, top: 4),
                child: Text(
                  state.errorText!,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.error,
                    fontSize: 12,
                  ),
                ),
              ),
          ],
        ),
      );
}

class _TimeSelectionField extends StatelessWidget {
  const _TimeSelectionField({
    required this.label,
    required this.value,
    required this.required,
    required this.onTap,
    this.validator,
  });

  final String label;
  final String value;
  final bool required;
  final VoidCallback? onTap;
  final String? Function(String?)? validator;

  @override
  Widget build(BuildContext context) => FormField<String>(
        key: ValueKey(value),
        initialValue: value.startsWith('Select') ? '' : value,
        validator: validator ??
            (fieldValue) =>
                required && (fieldValue == null || fieldValue.isEmpty)
                    ? 'Please select ${label.toLowerCase()}.'
                    : null,
        builder: (state) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            OutlinedButton.icon(
              onPressed: onTap,
              icon: const Icon(Icons.access_time_outlined),
              label: Align(
                alignment: Alignment.centerLeft,
                child: Text('$label: $value'),
              ),
            ),
            if (state.hasError)
              Padding(
                padding: const EdgeInsets.only(left: 12, top: 4),
                child: Text(
                  state.errorText!,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.error,
                    fontSize: 12,
                  ),
                ),
              ),
          ],
        ),
      );
}

String _monthName(int month) => const [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ][month - 1];

class _SelectionField extends StatefulWidget {
  const _SelectionField(
      {required this.label,
      required this.options,
      required this.controller,
      required this.required,
      required this.enabled});
  final String label;
  final List<FormOption> options;
  final TextEditingController controller;
  final bool required;
  final bool enabled;

  @override
  State<_SelectionField> createState() => _SelectionFieldState();
}

class _SelectionFieldState extends State<_SelectionField> {
  @override
  Widget build(BuildContext context) {
    final current =
        widget.options.any((option) => option.value == widget.controller.text)
            ? widget.controller.text
            : null;
    return DropdownButtonFormField<String>(
      initialValue: current,
      isExpanded: true,
      decoration: InputDecoration(
          labelText: widget.label, border: const OutlineInputBorder()),
      items: widget.options
          .map((option) => DropdownMenuItem(
              value: option.value,
              child: Text(option.label, overflow: TextOverflow.ellipsis)))
          .toList(),
      onChanged: widget.enabled
          ? (value) => setState(() => widget.controller.text = value ?? '')
          : null,
      validator: (value) => widget.required && (value == null || value.isEmpty)
          ? 'Please select ${widget.label.toLowerCase()}.'
          : null,
    );
  }
}

String _fieldLabel(String field) {
  final custom = {
    'owner_user_id': 'Owner',
    'flat_id': 'Flat',
    'resident_id': 'Resident',
    'amenity_id': 'Amenity',
    'occupancy_status': 'Occupancy status',
    'parking_type': 'Parking type',
    'visitor_type': 'Visitor type',
    'start_time': 'Start time',
    'end_time': 'End time',
    'opening_time': 'Opening time',
    'closing_time': 'Closing time',
  }[field];
  if (custom != null) return custom;
  final replaced = field.replaceAll('_', ' ');
  if (replaced.isEmpty) return replaced;
  return replaced[0].toUpperCase() + replaced.substring(1);
}

void showVisitorApprovalSheet(
  BuildContext context,
  Map<String, dynamic> data, {
  VoidCallback? onActionDone,
}) {
  final visitorId = data['visitor_id'] ?? data['visitor_request_id'];
  final visitorName = data['visitor_name']?.toString() ?? 'Visitor';
  final visitorType = data['visitor_type']?.toString() ?? 'Guest';
  final flatNumber = data['flat_number']?.toString() ?? data['flat']?['flat_number']?.toString() ?? '';
  final building = data['building']?.toString() ?? data['flat']?['building']?.toString() ?? '';
  final location = 'Flat $flatNumber${building.isNotEmpty ? ' · $building' : ''}';
  final requestedAt = data['requested_at'] ?? data['created_at'];

  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) {
      String currentStatus = (data['approval_status']?.toString() ?? 'PENDING').toUpperCase();
      bool isProcessing = false;

      return StatefulBuilder(
        builder: (modalContext, setModalState) {
          final isPending = currentStatus == 'PENDING' || currentStatus == 'WAITING';
          final isApproved = currentStatus == 'APPROVED';
          final isRejected = currentStatus == 'REJECTED';

          Future<void> handleAction(String action) async {
            if (visitorId == null) return;
            setModalState(() => isProcessing = true);
            try {
              final api = context.read<AuthController>().api;
              final body = action == 'reject'
                  ? <String, dynamic>{'reason': 'Declined by resident'}
                  : <String, dynamic>{};
              await api.patch('resident/visitors/$visitorId/$action', body);
              
              final newStatus = action == 'approve' ? 'APPROVED' : 'REJECTED';
              setModalState(() {
                currentStatus = newStatus;
                isProcessing = false;
              });
              data['approval_status'] = newStatus;
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(action == 'approve'
                        ? 'Visitor approved successfully.'
                        : 'Visitor request declined.'),
                  ),
                );
              }
              onActionDone?.call();
            } on ApiException catch (e) {
              setModalState(() => isProcessing = false);
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(e.message)),
                );
              }
            } catch (_) {
              setModalState(() => isProcessing = false);
            }
          }

          return Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFEF3C7),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(Icons.badge_outlined, color: Color(0xFFF59E0B), size: 24),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Visitor Request',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF1E293B),
                            ),
                          ),
                          if (requestedAt != null)
                            Text(
                              _friendlyDate(requestedAt),
                              style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                            ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: isApproved
                            ? Colors.green.shade100
                            : (isRejected ? Colors.red.shade100 : Colors.amber.shade100),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        currentStatus,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: isApproved
                              ? Colors.green.shade800
                              : (isRejected ? Colors.red.shade800 : Colors.amber.shade900),
                        ),
                      ),
                    ),
                  ],
                ),
                const Divider(height: 28),
                
                // Visitor Info Card
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: Column(
                    children: [
                      _buildApprovalDetailRow('Visitor Name', visitorName, isBold: true),
                      const SizedBox(height: 8),
                      _buildApprovalDetailRow('Visitor Type', visitorType),
                      const SizedBox(height: 8),
                      _buildApprovalDetailRow('Flat / Wing', location),
                      if (data['purpose'] != null && data['purpose'].toString().isNotEmpty) ...[
                        const SizedBox(height: 8),
                        _buildApprovalDetailRow('Purpose', data['purpose'].toString()),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 24),

                if (isPending) ...[
                  if (isProcessing)
                    const Center(child: CircularProgressIndicator())
                  else
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.red.shade700,
                              side: BorderSide(color: Colors.red.shade400),
                              padding: const EdgeInsets.symmetric(vertical: 14),
                            ),
                            icon: const Icon(Icons.close),
                            label: const Text('REJECT', style: TextStyle(fontWeight: FontWeight.bold)),
                            onPressed: () => handleAction('reject'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: FilledButton.icon(
                            style: FilledButton.styleFrom(
                              backgroundColor: const Color(0xFF10B981),
                              padding: const EdgeInsets.symmetric(vertical: 14),
                            ),
                            icon: const Icon(Icons.check),
                            label: const Text('APPROVE', style: TextStyle(fontWeight: FontWeight.bold)),
                            onPressed: () => handleAction('approve'),
                          ),
                        ),
                      ],
                    ),
                ] else ...[
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: const Text('Close'),
                    ),
                  ),
                ],
              ],
            ),
          );
        },
      );
    },
  );
}

Widget _buildApprovalDetailRow(String label, String value, {bool isBold = false}) {
  return Row(
    mainAxisAlignment: MainAxisAlignment.spaceBetween,
    children: [
      Text(
        label,
        style: const TextStyle(fontSize: 13, color: Color(0xFF64748B)),
      ),
      Text(
        value,
        style: TextStyle(
          fontSize: 13,
          fontWeight: isBold ? FontWeight.bold : FontWeight.w600,
          color: const Color(0xFF1E293B),
        ),
      ),
    ],
  );
}
// ── Society Notification Info Sheet ─────────────────────────────────────────
// Shown when the user taps an FCM notification for visitor_approved,
// visitor_rejected, visitor_checked_in, or visitor_checked_out.
// READ-ONLY sheet — no approve/reject buttons.
void showSocietyNotificationSheet(
  BuildContext context,
  Map<String, dynamic> data,
) {
  final type = data['type']?.toString()
      ?? data['notification_type']?.toString()
      ?? '';
  final visitorName = data['visitor_name']?.toString() ?? 'Visitor';
  final visitorId = data['visitor_id']?.toString();

  IconData icon;
  Color iconColor;
  Color iconBg;
  String title;
  String defaultMessage;

  switch (type) {
    case 'visitor_approved':
      icon = Icons.check_circle_outline_rounded;
      iconColor = const Color(0xFF10B981);
      iconBg = const Color(0xFFD1FAE5);
      title = 'Visitor Approved';
      defaultMessage = '$visitorName has been approved for entry.';
      break;
    case 'visitor_rejected':
      icon = Icons.cancel_outlined;
      iconColor = const Color(0xFFEF4444);
      iconBg = const Color(0xFFFEE2E2);
      title = 'Visitor Declined';
      defaultMessage = "$visitorName's entry request was declined.";
      break;
    case 'visitor_checked_in':
      icon = Icons.login_rounded;
      iconColor = const Color(0xFF3B82F6);
      iconBg = const Color(0xFFDBEAFE);
      title = 'Visitor Checked In';
      defaultMessage = '$visitorName has entered the society.';
      break;
    case 'visitor_checked_out':
      icon = Icons.logout_rounded;
      iconColor = const Color(0xFF64748B);
      iconBg = const Color(0xFFF1F5F9);
      title = 'Visitor Checked Out';
      defaultMessage = '$visitorName has left the society.';
      break;
    default:
      icon = Icons.notifications_outlined;
      iconColor = const Color(0xFF6366F1);
      iconBg = const Color(0xFFEEF2FF);
      title = data['title']?.toString() ?? 'Society Notification';
      defaultMessage = data['body']?.toString()
          ?? data['message']?.toString()
          ?? 'You have a new society notification.';
      break;
  }

  final displayMessage = data['body']?.toString()
      ?? data['message']?.toString()
      ?? defaultMessage;

  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) => Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: iconBg,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: iconColor, size: 24),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF1E293B),
                  ),
                ),
              ),
            ],
          ),
          const Divider(height: 28),
          Text(
            displayMessage,
            style: const TextStyle(
              fontSize: 15,
              height: 1.5,
              color: Color(0xFF334155),
            ),
          ),
          if (visitorId != null) ...[
            const SizedBox(height: 12),
            Text(
              'Visitor #$visitorId',
              style: const TextStyle(fontSize: 12, color: Color(0xFF94A3B8)),
            ),
          ],
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Close'),
            ),
          ),
        ],
      ),
    ),
  );
}