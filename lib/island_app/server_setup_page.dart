import 'package:flutter/material.dart';
import 'package:dna/island_app/api/client.dart';
import 'package:dna/island_app/server_config.dart';
import 'package:dna/island_app/widgets/async_action_button.dart';

/// 服务器地址兜底设置页。
///
/// 正常情况下不会出现：首次启动会先尝试官方默认地址（见 main.dart），只有校验失败
/// （官方服务器不可达 / 地址不是 DNAISLAND 服务器）时才展示本页，让用户检查网络后
/// 重试，或改填自建服务器地址。地址默认预填官方地址，避免用户「不知道填什么」。
///
/// 取代了旧的「首次启动向导」：那时它是必经闸门，现在它只是出错时的兜底。
class ServerSetupPage extends StatefulWidget {
  const ServerSetupPage({
    super.key,
    required this.onDone,
    this.initialUrl,
    this.initialError,
    this.validator,
  });

  /// 校验通过并保存地址后的回调。
  final VoidCallback onDone;

  /// 输入框初始值，默认 [ServerConfig.defaultBaseUrl]。
  final String? initialUrl;

  /// 首次启动校验失败的原因，展示给用户。
  final String? initialError;

  /// 注入用：地址校验器（测试时替换）。
  final ServerValidator? validator;

  @override
  State<ServerSetupPage> createState() => _ServerSetupPageState();
}

class _ServerSetupPageState extends State<ServerSetupPage> {
  late final TextEditingController _controller;
  bool _checking = false;
  String? _error;

  ServerValidator get _validator =>
      widget.validator ?? ApiClient.instance.validateServer;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(
      text: widget.initialUrl ?? ServerConfig.defaultBaseUrl,
    );
    _error = widget.initialError;
  }

  Future<void> _next() async {
    final base = ServerConfig.normalize(_controller.text);
    if (base.isEmpty) {
      setState(() => _error = '请输入服务器地址');
      return;
    }
    setState(() {
      _checking = true;
      _error = null;
    });
    final err = await _validator(base);
    if (!mounted) return;
    if (err != null) {
      setState(() {
        _checking = false;
        _error = err;
      });
      return;
    }
    await ServerConfig.setBaseUrl(base);
    if (mounted) widget.onDone();
  }

  void _useOfficial() {
    setState(() {
      _controller.text = ServerConfig.defaultBaseUrl;
      _error = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '设置服务器地址',
                    style: theme.textTheme.headlineSmall
                        ?.copyWith(fontWeight: FontWeight.w500),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    '无法连接官方服务器。请检查网络后重试，或改填你的自建服务器地址。'
                    'DNAISLAND 是开源项目，官方与自建服务器都受支持。',
                    style: TextStyle(color: Colors.grey),
                  ),
                  const SizedBox(height: 24),
                  TextField(
                    controller: _controller,
                    enabled: !_checking,
                    decoration: InputDecoration(
                      hintText: ServerConfig.defaultBaseUrl,
                      labelText: '服务器地址',
                      border: const OutlineInputBorder(),
                      prefixIcon: const Icon(Icons.link),
                      errorText: _error,
                      errorMaxLines: 3,
                    ),
                    keyboardType: TextInputType.url,
                    textInputAction: TextInputAction.go,
                    onSubmitted: (_) => _checking ? null : _next(),
                  ),
                  const SizedBox(height: 8),
                  TextButton.icon(
                    onPressed: _checking ? null : _useOfficial,
                    icon: const Icon(Icons.public, size: 18),
                    label: const Text('使用官方服务器'),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: AsyncActionButton(
                      variant: AsyncButtonVariant.filled,
                      enabled: !_checking,
                      onPressed: _next,
                      loadingSize: 18,
                      icon: const Icon(Icons.arrow_forward),
                      child: Text(_checking ? '正在验证…' : '下一步'),
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

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
}
