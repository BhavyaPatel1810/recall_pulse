import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'database_helper.dart';

class AuthService {
  static final AuthService instance = AuthService._init();
  AuthService._init();

  static const String _prefSupabaseUrl = 'pulse_supabase_url';
  static const String _prefSupabaseAnonKey = 'pulse_supabase_anon_key';

  static const String _envSupabaseUrl = String.fromEnvironment('SUPABASE_URL', defaultValue: '');
  static const String _envSupabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY', defaultValue: '');

  SupabaseClient? _client;
  bool _isInitialized = false;

  final StreamController<User?> _authStateController = StreamController<User?>.broadcast();
  Stream<User?> get authStateStream => _authStateController.stream;

  SupabaseClient? get client => _client;
  User? get currentUser => _client?.auth.currentUser;
  bool get isLoggedIn => currentUser != null;
  bool get isCloudConfigured => _isInitialized && _client != null;

  /// Initializes Supabase if project credentials are provided via environment or SharedPreferences.
  Future<void> initialize() async {
    final url = await getSupabaseUrl();
    final anonKey = await getSupabaseAnonKey();

    if (url.isEmpty || anonKey.isEmpty) {
      return;
    }

    await _initializeClient(url, anonKey);
  }

  Future<bool> configureSupabaseCredentials({
    required String url,
    required String anonKey,
  }) async {
    final cleanUrl = url.trim();
    final cleanKey = anonKey.trim();
    if (cleanUrl.isEmpty || cleanKey.isEmpty) return false;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefSupabaseUrl, cleanUrl);
    await prefs.setString(_prefSupabaseAnonKey, cleanKey);

    return await _initializeClient(cleanUrl, cleanKey);
  }

  Future<bool> _initializeClient(String url, String anonKey) async {
    try {
      if (!_isInitialized) {
        await Supabase.initialize(
          url: url,
          anonKey: anonKey,
        );
        _client = Supabase.instance.client;
        _isInitialized = true;
      } else {
        _client = SupabaseClient(url, anonKey);
      }

      _client!.auth.onAuthStateChange.listen((data) {
        _authStateController.add(data.session?.user);
      });

      _authStateController.add(_client!.auth.currentUser);
      return true;
    } catch (e) {
      debugPrint('Supabase initialization warning: $e');
      return false;
    }
  }

  Future<String> getSupabaseUrl() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_prefSupabaseUrl);
    if (saved != null && saved.isNotEmpty) return saved;
    return _envSupabaseUrl;
  }

  Future<String> getSupabaseAnonKey() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_prefSupabaseAnonKey);
    if (saved != null && saved.isNotEmpty) return saved;
    return _envSupabaseAnonKey;
  }

  /// Signs up a new user with Email & Password and prepares local guest data for cloud merge.
  Future<AuthResponse> signUpWithEmail({
    required String email,
    required String password,
  }) async {
    _ensureConfigured();
    final response = await _client!.auth.signUp(
      email: email.trim(),
      password: password,
    );

    if (response.user != null) {
      await DatabaseHelper.instance.prepareGuestRecordsForAccountMerge();
    }
    return response;
  }

  /// Signs in an existing user with Email & Password and merges offline guest flashcards.
  Future<AuthResponse> signInWithEmail({
    required String email,
    required String password,
  }) async {
    _ensureConfigured();
    final response = await _client!.auth.signInWithPassword(
      email: email.trim(),
      password: password,
    );

    if (response.user != null) {
      await DatabaseHelper.instance.prepareGuestRecordsForAccountMerge();
    }
    return response;
  }

  /// Initiates Google Account OAuth Sign-In across Android and Linux Desktop.
  Future<bool> signInWithGoogle() async {
    _ensureConfigured();
    await DatabaseHelper.instance.prepareGuestRecordsForAccountMerge();

    return await _client!.auth.signInWithOAuth(
      OAuthProvider.google,
      redirectTo: kIsWeb ? null : 'io.supabase.recallpulse://login-callback/',
      authScreenLaunchMode: LaunchMode.externalApplication,
    );
  }

  /// Signs out from cloud sync while preserving all local SQLite decks and flashcards for offline use.
  Future<void> signOut() async {
    if (_client == null) return;
    await _client!.auth.signOut();
    _authStateController.add(null);
  }

  void _ensureConfigured() {
    if (_client == null) {
      throw Exception(
        'Supabase Cloud is not configured yet. Please enter your Supabase Project URL and Anon Key in the Cloud Server Configuration panel.',
      );
    }
  }
}