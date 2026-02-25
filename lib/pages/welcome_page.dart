import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:animate_do/animate_do.dart';
import 'package:lottie/lottie.dart';
import '../providers/settings_provider.dart';

class WelcomePage extends StatefulWidget {
  const WelcomePage({super.key});

  @override
  State<WelcomePage> createState() => _WelcomePageState();
}

class _WelcomePageState extends State<WelcomePage> {
  final PageController _pageController = PageController();
  final TextEditingController _apiKeyController = TextEditingController();
  final TextEditingController _baseUrlController = TextEditingController(text: 'https://api.openai.com/v1');
  final TextEditingController _customModelController = TextEditingController();
  
  int _currentStep = 0;
  bool _isTestingApi = false;
  bool _apiTestPassed = false;
  bool _hasAttemptedApiTest = false;
  bool _ignoreApiError = false;
  
  List<String> _availableModels = [];
  String? _selectedModel;
  bool _isLoadingModels = false;

  @override
  void dispose() {
    _pageController.dispose();
    _apiKeyController.dispose();
    _baseUrlController.dispose();
    _customModelController.dispose();
    super.dispose();
  }

  Future<void> _testApiAndNext() async {
    if (_apiKeyController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请输入 API Key')),
      );
      return;
    }

    setState(() {
      _isTestingApi = true;
      _hasAttemptedApiTest = false; // 重置尝试状态
    });
    
    final settings = context.read<SettingsProvider>();
    await settings.setApiKey(_apiKeyController.text.trim());
    await settings.setBaseUrl(_baseUrlController.text.trim());
    
    final success = await settings.testApiConnection();
    
    setState(() {
      _isTestingApi = false;
      _apiTestPassed = success;
      _hasAttemptedApiTest = true;
    });

    if (success || (_hasAttemptedApiTest && _ignoreApiError)) {
      _fetchModelsAndNext();
    } else if (!success) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('API 连接测试失败，请检查配置或勾选强制进入')),
      );
    }
  }

  Future<void> _fetchModelsAndNext() async {
    setState(() {
      _isLoadingModels = true;
      _availableModels = []; // 清空旧列表
    });
    
    if (_currentStep == 1) {
      _pageController.nextPage(duration: const Duration(milliseconds: 500), curve: Curves.easeInOut);
    }
    
    final settings = context.read<SettingsProvider>();
    final models = await settings.fetchAvailableModels();
    
    setState(() {
      _availableModels = models;
      _isLoadingModels = false;
      if (models.isNotEmpty) {
        // 优先选择之前选过的，或者默认模型
        if (_selectedModel == null || !models.contains(_selectedModel)) {
          _selectedModel = models.contains('gpt-3.5-turbo') ? 'gpt-3.5-turbo' : models.first;
        }
      }
    });
  }

  void _completeOOBE() async {
    final settings = context.read<SettingsProvider>();
    if (_selectedModel != null) {
      await settings.setSelectedModel(_selectedModel!);
    }
    await settings.completeFirstRun();
    if (mounted) {
      Navigator.of(context).pushReplacementNamed('/home');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // 背景装饰
          Positioned(
            top: -100,
            right: -100,
            child: FadeInDown(
              child: Container(
                width: 300,
                height: 300,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.blue.withOpacity(0.05),
                ),
              ),
            ),
          ),
          
          SafeArea(
            child: Column(
              children: [
                Expanded(
                  child: PageView(
                    controller: _pageController,
                    physics: const NeverScrollableScrollPhysics(),
                    onPageChanged: (index) => setState(() => _currentStep = index),
                    children: [
                      _buildWelcomeStep(),
                      _buildApiConfigStep(),
                      _buildModelSelectStep(),
                      _buildFinalStep(),
                    ],
                  ),
                ),
                _buildBottomNav(),
              ],
            ),
          ),
          const SizedBox(height: 60),
          const Text(
            '与汝共奏',
            style: TextStyle(
              fontSize: 32,
              fontWeight: FontWeight.w600,
              letterSpacing: 8,
              color: Colors.black87,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWelcomeStep() {
    return FadeInUp(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // 替换为 Logo
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(30),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 20,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Image.asset(
              'assets/icon.png',
              height: 120,
              width: 120,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildApiConfigStep() {
    return Padding(
      padding: const EdgeInsets.all(32.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FadeInLeft(
            child: const Text(
              '配置 API',
              style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(height: 8),
          FadeInLeft(
            delay: const Duration(milliseconds: 200),
            child: Text('为了连接到 AI，我们需要您的 API 凭据。', style: TextStyle(color: Colors.grey[600])),
          ),
          const SizedBox(height: 40),
          TextField(
            controller: _apiKeyController,
            decoration: InputDecoration(
              labelText: 'API Key',
              hintText: 'sk-...',
              prefixIcon: const Icon(Icons.key),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            ),
            obscureText: true,
          ),
          const SizedBox(height: 20),
          TextField(
            controller: _baseUrlController,
            decoration: InputDecoration(
              labelText: 'Base URL',
              prefixIcon: const Icon(Icons.link),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
          const SizedBox(height: 20),
          if (!_apiTestPassed && _hasAttemptedApiTest && _currentStep == 1)
            FadeIn(
              child: Row(
                children: [
                  Checkbox(
                    value: _ignoreApiError,
                    onChanged: (val) => setState(() => _ignoreApiError = val ?? false),
                  ),
                  const Expanded(child: Text('即使测试失败也继续（不建议）')),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildModelSelectStep() {
    return Padding(
      padding: const EdgeInsets.all(32.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '选择模型',
            style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text('选择您偏好的 AI 模型，或自定义一个。', style: TextStyle(color: Colors.grey[600])),
          const SizedBox(height: 32),
          Expanded(
            child: _isLoadingModels
                ? const Center(child: CircularProgressIndicator())
                : _availableModels.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Text('未能自动获取模型列表'),
                            TextButton(onPressed: _fetchModelsAndNext, child: const Text('重试')),
                            TextButton(onPressed: _showCustomModelDialog, child: const Text('手动添加模型')),
                          ],
                        ),
                      )
                    : ListView(
                        children: [
                          ..._availableModels.map((model) => RadioListTile<String>(
                                title: Text(model),
                                value: model,
                                groupValue: _selectedModel,
                                onChanged: (val) => setState(() => _selectedModel = val),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              )),
                          ListTile(
                            leading: const Icon(Icons.add),
                            title: const Text('自定义模型...'),
                            onTap: _showCustomModelDialog,
                          ),
                        ],
                      ),
          ),
        ],
      ),
    );
  }

  void _showCustomModelDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('自定义模型'),
        content: TextField(
          controller: _customModelController,
          decoration: const InputDecoration(hintText: '例如: gpt-4-32k'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
          ElevatedButton(
            onPressed: () {
              if (_customModelController.text.isNotEmpty) {
                setState(() {
                  _selectedModel = _customModelController.text.trim();
                  if (!_availableModels.contains(_selectedModel)) {
                    _availableModels.add(_selectedModel!);
                  }
                });
              }
              Navigator.pop(context);
            },
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  Widget _buildFinalStep() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        ZoomIn(
          child: const Icon(Icons.check_circle, size: 100, color: Colors.green),
        ),
        const SizedBox(height: 32),
        FadeInUp(
          child: const Text('一切就绪', style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
        ),
      ],
    );
  }

  Widget _buildBottomNav() {
    return Padding(
      padding: const EdgeInsets.all(32.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          if (_currentStep > 0)
            TextButton(
              onPressed: () => _pageController.previousPage(duration: const Duration(milliseconds: 500), curve: Curves.easeInOut),
              child: const Text('返回'),
            )
          else
            const SizedBox.shrink(),
          
          ElevatedButton(
            onPressed: _isTestingApi ? null : (_currentStep == 1 ? _testApiAndNext : (_currentStep == 3 ? _completeOOBE : () => _pageController.nextPage(duration: const Duration(milliseconds: 500), curve: Curves.easeInOut))),
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: _isTestingApi 
              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : Text(_currentStep == 3 ? '开始奏鸣' : '下一步'),
          ),
        ],
      ),
    );
  }
}
