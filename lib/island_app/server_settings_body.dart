import 'package:flutter/material.dart';
import 'package:dna/island_app/api/client.dart';
import 'package:dna/island_app/server_config.dart';

/// 服务器设置（后端地址）内容，无脚手架，由 [RootShell] 承载。
class ServerSettingsBody extends StatefulWidget {
  const ServerSettingsBody({super.key, this.validator});

  /// 注入用：地址校验器（测试时替换）。
  final ServerValidator? validator;

  @override
  State<ServerSettingsBody> createState() => _ServerSettingsBodyState();
}

class _ServerSettingsBodyState extends State<ServerSettingsBody> {
  final _controller = TextEditingController();
  bool _loading = true;
  bool _saving = false;
  String? _error;

  ServerValidator get _validator =>
      widget.validator ?? ApiClient.instance.validateServer;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final url = await ServerConfig.getBaseUrl();
    if (mounted) {
      _controller.text = url;
      setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    final base = ServerConfig.normalize(_controller.text);
    if (base.isEmpty) {
      setState(() => _error = '请输入服务器地址');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    // 保存前先校验：地址填错会让整个 App 都连不上，必须当场拦住而不是存进去。
    final err = await _validator(base);
    if (!mounted) return;
    if (err != null) {
      setState(() {
        _saving = false;
        _error = err;
      });
      return;
    }
    await ServerConfig.setBaseUrl(base);
    if (!mounted) return;
    setState(() {
      _saving = false;
      _controller.text = base;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已保存服务器地址')),
    );
  }

  void _useOfficial() {
    setState(() {
      _controller.text = ServerConfig.defaultBaseUrl;
      _error = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return _loading
        ? const Center(child: CircularProgressIndicator())
        : ListView(
            padding: const EdgeInsets.all(16),
            children: [
              const Text('DNAISLAND 后端地址',
                  style: TextStyle(fontWeight: FontWeight.w500, fontSize: 16)),
              const SizedBox(height: 8),
              const Text(
                  'DNAISLAND 是开源项目，默认使用官方服务器；你也可以填写自建服务器的地址。',
                  style: TextStyle(color: Colors.grey)),
              const SizedBox(height: 12),
              TextField(
                controller: _controller,
                enabled: !_saving,
                decoration: InputDecoration(
                  hintText: ServerConfig.defaultBaseUrl,
                  labelText: '服务器地址',
                  border: const OutlineInputBorder(),
                  prefixIcon: const Icon(Icons.link),
                  errorText: _error,
                  errorMaxLines: 3,
                ),
                keyboardType: TextInputType.url,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _saving ? null : _save(),
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: _saving ? null : _useOfficial,
                  icon: const Icon(Icons.public, size: 18),
                  label: const Text('使用官方服务器'),
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _saving ? null : _save,
                  icon: const Icon(Icons.save),
                  label: Text(_saving ? '正在验证…' : '保存'),
                ),
              ),
            ],
          );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
}
