import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:dart_openai/dart_openai.dart';

class SettingsProvider extends ChangeNotifier {
  static const String _keyApiKey = 'openai_api_key';
  static const String _keyBaseUrl = 'openai_base_url';
  static const String _keyModel = 'openai_selected_model';
  static const String _keyIsFirstRun = 'is_first_run';

  String _apiKey = '';
  String _baseUrl = 'https://api.openai.com/v1';
  String _selectedModel = 'gpt-3.5-turbo';
  bool _isFirstRun = true;
  bool _isInitialized = false;

  String get apiKey => _apiKey;
  String get baseUrl => _baseUrl;
  String get selectedModel => _selectedModel;
  bool get isFirstRun => _isFirstRun;
  bool get isInitialized => _isInitialized;

  SettingsProvider() {
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    _apiKey = prefs.getString(_keyApiKey) ?? '';
    _baseUrl = prefs.getString(_keyBaseUrl) ?? 'https://api.openai.com/v1';
    _selectedModel = prefs.getString(_keyModel) ?? 'gpt-3.5-turbo';
    _isFirstRun = prefs.getBool(_keyIsFirstRun) ?? true;
    
    _applyOpenAISettings();
    _isInitialized = true;
    notifyListeners();
  }

  void _applyOpenAISettings() {
    OpenAI.apiKey = _apiKey;
    OpenAI.baseUrl = _baseUrl;
  }

  Future<void> setApiKey(String key) async {
    _apiKey = key;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyApiKey, key);
    _applyOpenAISettings();
    notifyListeners();
  }

  Future<void> setBaseUrl(String url) async {
    _baseUrl = url;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyBaseUrl, url);
    _applyOpenAISettings();
    notifyListeners();
  }

  Future<void> setSelectedModel(String model) async {
    _selectedModel = model;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyModel, model);
    notifyListeners();
  }

  Future<void> completeFirstRun() async {
    _isFirstRun = false;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyIsFirstRun, false);
    notifyListeners();
  }

  Future<void> resetFirstRun() async {
    _isFirstRun = true;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyIsFirstRun, true);
    notifyListeners();
  }

  // 检测 API 是否可用
  Future<bool> testApiConnection() async {
    if (_apiKey.isEmpty) return false;
    try {
      _applyOpenAISettings();
      await OpenAI.instance.model.list();
      return true;
    } catch (e) {
      debugPrint('API Test Failed: $e');
      return false;
    }
  }

  // 获取模型列表
  Future<List<String>> fetchAvailableModels() async {
    try {
      _applyOpenAISettings();
      final models = await OpenAI.instance.model.list();
      return models.map((m) => m.id).toList();
    } catch (e) {
      debugPrint('Fetch Models Failed: $e');
      return []; // 不再返回硬编码的列表
    }
  }
}
