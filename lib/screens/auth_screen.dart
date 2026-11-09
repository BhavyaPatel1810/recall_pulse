import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/auth_service.dart';
import '../services/sync_service.dart';
import '../theme/pulse_theme.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _supabaseUrlController = TextEditingController();
  final TextEditingController _supabaseAnonKeyController = TextEditingController();

  bool _isLoginMode = true;
  bool _obscurePassword = true;
  bool _isSubmitting = false;
  bool _showServerConfig = false;
  bool _isSyncingNow = false;

  @override
  void initState() {
    super.initState();
    _loadExistingConfig();
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _supabaseUrlController.dispose();
    _supabaseAnonKeyController.dispose();
    super.dispose();
  }

  Future<void> _loadExistingConfig() async {
    final url = await AuthService.instance.getSupabaseUrl();
    final key = await AuthService.instance.getSupabaseAnonKey();

    if (!mounted) return;
    setState(() {
      _supabaseUrlController.text = url;
      _supabaseAnonKeyController.text = key;
      _showServerConfig = url.isEmpty || key.isEmpty;
    });
  }

  Future<bool> _ensureBackendReady() async {
    if (AuthService.instance.isCloudConfigured &&
        _supabaseUrlController.text.trim().isNotEmpty &&
        _supabaseAnonKeyController.text.trim().isNotEmpty) {
      await AuthService.instance.configureSupabaseCredentials(
        url: _supabaseUrlController.text,
        anonKey: _supabaseAnonKeyController.text,
      );
      return true;
    }

    final url = _supabaseUrlController.text.trim();
    final key = _supabaseAnonKeyController.text.trim();
    if (url.isEmpty || key.isEmpty) {
      setState(() {
        _showServerConfig = true;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: PulseTheme.neonCoral,
          content: Text('Please provide your Supabase Project URL and Anon Key first.'),
        ),
      );
      return false;
    }

    return await AuthService.instance.configureSupabaseCredentials(
      url: url,
      anonKey: key,
    );
  }

  Future<void> _submitEmailAuth() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text;

    if (email.isEmpty || password.length < 6) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: PulseTheme.neonCoral,
          content: Text('Enter a valid email and a password of at least 6 characters.'),
        ),
      );
      return;
    }

    setState(() {
      _isSubmitting = true;
    });

    try {
      final ready = await _ensureBackendReady();
      if (!ready) {
        if (!mounted) return;
        setState(() {
          _isSubmitting = false;
        });
        return;
      }

      if (_isLoginMode) {
        await AuthService.instance.signInWithEmail(
          email: email,
          password: password,
        );
      } else {
        await AuthService.instance.signUpWithEmail(
          email: email,
          password: password,
        );
      }

      if (!mounted) return;
      HapticFeedback.heavyImpact();

      // Immediately merge and sync local SQLite data with cloud account
      await SyncService.instance.syncAllData();

      if (!mounted) return;
      setState(() {
        _isSubmitting = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: PulseTheme.neonEmerald,
          content: Text(
            _isLoginMode
                ? 'Signed in & synchronized with RecallPulse Cloud!'
                : 'Account created! Local decks merged with cloud.',
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isSubmitting = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: PulseTheme.neonCoral,
          content: Text(e.toString().replaceAll('Exception: ', '')),
        ),
      );
    }
  }

  Future<void> _handleGoogleOAuth() async {
    setState(() {
      _isSubmitting = true;
    });

    try {
      final ready = await _ensureBackendReady();
      if (!ready) {
        if (!mounted) return;
        setState(() {
          _isSubmitting = false;
        });
        return;
      }

      await AuthService.instance.signInWithGoogle();
      if (!mounted) return;
      setState(() {
        _isSubmitting = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isSubmitting = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: PulseTheme.neonCoral,
          content: Text(e.toString().replaceAll('Exception: ', '')),
        ),
      );
    }
  }

  Future<void> _triggerManualSync() async {
    setState(() {
      _isSyncingNow = true;
    });
    HapticFeedback.mediumImpact();

    final report = await SyncService.instance.syncAllData();

    if (!mounted) return;
    setState(() {
      _isSyncingNow = false;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: report.success ? PulseTheme.neonEmerald : PulseTheme.neonCoral,
        content: Text(
          report.message,
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = AuthService.instance.currentUser;

    return Scaffold(
      backgroundColor: PulseTheme.bgPrimary,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Row(
          children: [
            Icon(Icons.cloud_sync_rounded, color: PulseTheme.neonIndigo, size: 22),
            SizedBox(width: 8),
            Text(
              'RecallPulse Cloud Sync',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
            ),
          ],
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        physics: const BouncingScrollPhysics(),
        children: [
          if (user != null)
            _buildAuthenticatedAccountCard(user.email ?? 'Authenticated User')
          else
            _buildAuthFormCard(),
          const SizedBox(height: 18),
          _buildServerConfigurationPanel(),
          const SizedBox(height: 18),
          _buildOfflineFirstArchitectureInfo(),
        ],
      ),
    );
  }

  Widget _buildAuthenticatedAccountCard(String email) {
    return PulseGlassPanel(
      padding: const EdgeInsets.all(22),
      borderColor: PulseTheme.neonEmerald.withOpacity(0.5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: PulseTheme.neonEmerald.withOpacity(0.15),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.verified_user_rounded, color: PulseTheme.neonEmerald, size: 28),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Cloud Account Active',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      email,
                      style: const TextStyle(fontSize: 13, color: PulseTheme.textSecondary),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: PulseTheme.neonIndigo,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              icon: _isSyncingNow
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.sync_rounded, size: 20),
              label: Text(
                _isSyncingNow ? 'Synchronizing with Cloud...' : 'Sync Now (Linux PC ↔ Android)',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              onPressed: _isSyncingNow ? null : _triggerManualSync,
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: PulseTheme.neonCoral,
                side: BorderSide(color: PulseTheme.neonCoral.withOpacity(0.5)),
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              icon: const Icon(Icons.logout_rounded, size: 18),
              label: const Text('Switch to Offline Guest Mode (Sign Out)'),
              onPressed: () async {
                await AuthService.instance.signOut();
                if (!mounted) return;
                setState(() {});
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAuthFormCard() {
    return PulseGlassPanel(
      padding: const EdgeInsets.all(22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                _isLoginMode ? 'Sign In to Cloud Sync' : 'Create Cloud Sync Account',
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: PulseTheme.neonAmber.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text(
                  'Offline-First Guest',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: PulseTheme.neonAmber),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          const Text(
            'Your existing local decks and SM-2 study progress will automatically merge with your cloud account upon sign-in.',
            style: TextStyle(fontSize: 12, color: PulseTheme.textSecondary, height: 1.4),
          ),
          const SizedBox(height: 20),
          TextField(
            controller: _emailController,
            keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(
              labelText: 'Email Address',
              prefixIcon: Icon(Icons.email_outlined, size: 18, color: PulseTheme.textTertiary),
            ),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _passwordController,
            obscureText: _obscurePassword,
            decoration: InputDecoration(
              labelText: 'Password',
              prefixIcon: const Icon(Icons.lock_outline, size: 18, color: PulseTheme.textTertiary),
              suffixIcon: IconButton(
                icon: Icon(
                  _obscurePassword ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                  size: 18,
                  color: PulseTheme.textTertiary,
                ),
                onPressed: () {
                  setState(() {
                    _obscurePassword = !_obscurePassword;
                  });
                },
              ),
            ),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: PulseTheme.neonIndigo,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: _isSubmitting ? null : _submitEmailAuth,
              child: _isSubmitting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : Text(
                      _isLoginMode ? 'Sign In & Merge Local Data' : 'Sign Up & Sync',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                    ),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white,
                side: const BorderSide(color: PulseTheme.borderSubtle),
                padding: const EdgeInsets.symmetric(vertical: 13),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              icon: const Icon(Icons.g_mobiledata_rounded, size: 24, color: PulseTheme.neonEmerald),
              label: const Text(
                'Continue with Google Account (OAuth)',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              onPressed: _isSubmitting ? null : _handleGoogleOAuth,
            ),
          ),
          const SizedBox(height: 12),
          Center(
            child: TextButton(
              onPressed: () {
                setState(() {
                  _isLoginMode = !_isLoginMode;
                });
              },
              child: Text(
                _isLoginMode
                    ? "Don't have a cloud account? Create one"
                    : 'Already have an account? Sign in',
                style: const TextStyle(color: PulseTheme.neonIndigo, fontWeight: FontWeight.w600),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildServerConfigurationPanel() {
    return PulseGlassPanel(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: () {
              setState(() {
                _showServerConfig = !_showServerConfig;
              });
            },
            child: Row(
              children: [
                const Icon(Icons.dns_outlined, color: PulseTheme.neonIndigo, size: 18),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Supabase Project Credentials',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                  ),
                ),
                Icon(
                  _showServerConfig ? Icons.expand_less : Icons.expand_more,
                  color: PulseTheme.textSecondary,
                ),
              ],
            ),
          ),
          if (_showServerConfig) ...[
            const SizedBox(height: 12),
            const Text(
              'Enter your Supabase Project URL and Anon Public Key to enable cross-platform PostgreSQL sync.',
              style: TextStyle(fontSize: 12, color: PulseTheme.textSecondary),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _supabaseUrlController,
              decoration: const InputDecoration(
                labelText: 'Supabase Project URL',
                hintText: 'https://xyzcompany.supabase.co',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _supabaseAnonKeyController,
              decoration: const InputDecoration(
                labelText: 'Supabase Anon Public Key',
                hintText: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...',
              ),
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: PulseTheme.surfaceElevated,
                  foregroundColor: Colors.white,
                ),
                icon: const Icon(Icons.save_outlined, size: 16, color: PulseTheme.neonEmerald),
                label: const Text('Save Endpoint'),
                onPressed: () async {
                  final ok = await AuthService.instance.configureSupabaseCredentials(
                    url: _supabaseUrlController.text,
                    anonKey: _supabaseAnonKeyController.text,
                  );
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      backgroundColor: ok ? PulseTheme.neonEmerald : PulseTheme.neonCoral,
                      content: Text(
                        ok ? 'Supabase endpoint saved and initialized.' : 'Invalid URL or Anon Key.',
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildOfflineFirstArchitectureInfo() {
    return PulseGlassPanel(
      padding: const EdgeInsets.all(18),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.shield_outlined, color: PulseTheme.neonEmerald, size: 18),
              SizedBox(width: 8),
              Text(
                'Deterministic Last-Write-Wins (LWW) Sync',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          SizedBox(height: 6),
          Text(
            '• Zero Latency: Every review rating and card edit writes immediately to local SQLite.\n'
            '• Conflict-Free: Modifications compare UTC timestamps so mobile reviews and desktop edits merge cleanly.\n'
            '• Soft-Delete Propagation: Deleted cards and decks propagate across all linked devices.',
            style: TextStyle(fontSize: 12, color: PulseTheme.textSecondary, height: 1.5),
          ),
        ],
      ),
    );
  }
}