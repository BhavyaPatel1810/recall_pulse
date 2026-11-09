import 'package:shared_preferences/shared_preferences.dart';

class SettingsService {
  static final SettingsService instance = SettingsService._init();
  SettingsService._init();

  static const String _keyApiKey = 'pulse_gemini_api_key';
  static const String _keyModel = 'pulse_gemini_model';
  static const String _keyDailyLimit = 'pulse_daily_new_limit';
  static const String _keyLanguage = 'pulse_ai_language';
  static const String _keyActiveRecall = 'pulse_active_recall_enabled';

  static const List<String> availableModels = [
    'gemini-2.5-flash',
    'gemini-2.5-pro',
    'gemini-2.0-flash',
  ];

  static const List<String> availableLanguages = [
    'English',
    'Hindi',
    'Hinglish',
  ];

  Future<String> getApiKey() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyApiKey) ?? '';
  }

  Future<void> setApiKey(String apiKey) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyApiKey, apiKey.trim());
  }

  Future<String> getSelectedModel() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_keyModel);
    if (saved != null && availableModels.contains(saved)) {
      return saved;
    }
    return availableModels.first;
  }

  Future<void> setSelectedModel(String model) async {
    final prefs = await SharedPreferences.getInstance();
    if (availableModels.contains(model)) {
      await prefs.setString(_keyModel, model);
    }
  }

  Future<int> getDailyNewCardLimit() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_keyDailyLimit) ?? 20;
  }

  Future<void> setDailyNewCardLimit(int limit) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keyDailyLimit, limit.clamp(5, 200));
  }

  Future<String> getPreferredLanguage() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_keyLanguage);
    if (saved != null && availableLanguages.contains(saved)) {
      return saved;
    }
    return availableLanguages.first;
  }

  Future<void> setPreferredLanguage(String language) async {
    final prefs = await SharedPreferences.getInstance();
    if (availableLanguages.contains(language)) {
      await prefs.setString(_keyLanguage, language);
    }
  }

  Future<bool> getActiveRecallEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyActiveRecall) ?? true;
  }

  Future<void> setActiveRecallEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyActiveRecall, enabled);
  }
}