import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:dna/island_app/api/client.dart';

/// BYOK 代理（外链/API 转发）配置页。
///
/// 用户配置上游 OpenAI 兼容 Base URL 与 API Key，查看平台签发的访问令牌
/// 与对外 Base URL，可重置令牌、删除配置。与网页版 `/proxy/set` 共用后端。
class ProxyConfigPage extends StatefulWidget {
  const ProxyConfigPage({super.key});

  @override
  State<ProxyConfigPage> createState() => _ProxyConfigPageState();
}

class _ProxyConfigPageState extends State<ProxyConfigPage> {
  final TextEditingController _baseUrlController = TextEditingController();
  final TextEditingController _apiKeyController = TextEditingController();
  final TextEditingController _remarkController = TextEditingController();
  final FocusNode _baseUrlFocus = FocusNode();

  bool _loading = true;
  bool _saving = false;
  bool _configured = false;
  bool _enabled = true;
  bool _editing = false;
  bool _obscureKey = true;

  String _publicBaseUrl = '';
  String _token = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _baseUrlController.dispose();
    _apiKeyController.dispose();
    _remarkController.dispose();
    _baseUrlFocus.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final cfg = await ApiClient.instance.getProxyConfig();
      if (!mounted) return;
      setState(() {
        _configured = cfg['configured'] == true;
        _enabled = cfg['enabled'] == true;
        _publicBaseUrl = (cfg['public_base_url'] ?? '').toString();
        _token = (cfg['token'] ?? '').toString();
        _baseUrlController.text = (cfg['upstream_base_url'] ?? '').toString();
        _remarkController.text = (cfg['remark'] ?? '').toString();
        _editing = false;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      _snack('加载失败：$e');
    }
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg), duration: const Duration(seconds: 3)));
  }

  Future<void> _save() async {
    final baseUrl = _baseUrlController.text.trim();
    if (baseUrl.isEmpty) {
      _snack('请填写上游 Base URL');
      _baseUrlFocus.requestFocus();
      return;
    }
    if (!baseUrl.startsWith('http://') && !baseUrl.startsWith('https://')) {
      _snack('上游 Base URL 必须以 http:// 或 https:// 开头');
      _baseUrlFocus.requestFocus();
      return;
    }
    setState(() => _saving = true);
    try {
      await ApiClient.instance.saveProxyConfig(
        upstreamBaseUrl: baseUrl,
        upstreamApiKey: _apiKeyController.text.trim(),
        remark: _remarkController.text.trim(),
        enabled: _enabled,
      );
      if (!mounted) return;
      _snack(_configured ? '配置已更新' : '配置已保存');
      await _load();
    } catch (e) {
      if (!mounted) return;
      _snack('保存失败：$e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _resetToken() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('重置访问令牌'),
        content: const Text('重置后旧令牌立即失效，需要把新令牌更新到你的客户端。确定继续？'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('重置'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _saving = true);
    try {
      final newToken = await ApiClient.instance.resetProxyToken();
      if (!mounted) return;
      setState(() => _token = newToken);
      _snack('令牌已重置');
    } catch (e) {
      if (mounted) _snack('重置失败：$e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _deleteConfig() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除转发配置'),
        content: const Text('删除后该代理配置将失效（历史审计日志保留）。确定删除？'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _saving = true);
    try {
      await ApiClient.instance.deleteProxyConfig();
      if (!mounted) return;
      _snack('配置已删除');
      _apiKeyController.clear();
      await _load();
    } catch (e) {
      if (mounted) _snack('删除失败：$e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _copy(String text) {
    Clipboard.setData(ClipboardData(text: text));
    _snack('已复制');
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('代理中转')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: <Widget>[
                _infoBanner(context),
                const SizedBox(height: 16),
                if (_configured && !_editing)
                  ..._buildConfiguredView(context, scheme)
                else
                  ..._buildEditView(context, scheme),
              ],
            ),
    );
  }

  Widget _infoBanner(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.secondaryContainer.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(Icons.info_outline, color: scheme.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'BYOK（Bring Your Own Key）代理：配置你自己的上游 API 地址与密钥后，'
              '即可用平台签发的 Base URL + 令牌把请求转发到你的上游服务。',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildConfiguredView(BuildContext context, ColorScheme scheme) {
    return <Widget>[
      _sectionTitle(context, '当前配置'),
      Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              _labelRow(context, '状态', _enabled ? '已启用' : '已停用'),
              _labelRow(context, '上游 Base URL', _baseUrlController.text),
              if (_remarkController.text.isNotEmpty)
                _labelRow(context, '备注', _remarkController.text),
              const Divider(height: 24),
              _copyableRow(context, '对外 Base URL', _publicBaseUrl, () => _copy(_publicBaseUrl)),
              _copyableRow(context, '访问令牌', _token, () => _copy(_token)),
            ],
          ),
        ),
      ),
      const SizedBox(height: 16),
      Row(
        children: <Widget>[
          Expanded(
            child: FilledButton.tonal(
              onPressed: _saving ? null : () => setState(() => _editing = true),
              child: const Text('编辑配置'),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: OutlinedButton(
              onPressed: _saving ? null : _resetToken,
              child: const Text('重置令牌'),
            ),
          ),
        ],
      ),
      const SizedBox(height: 12),
      Center(
        child: TextButton.icon(
          onPressed: _saving ? null : _deleteConfig,
          style: TextButton.styleFrom(foregroundColor: scheme.error),
          icon: const Icon(Icons.delete_outline),
          label: const Text('删除转发配置'),
        ),
      ),
    ];
  }

  List<Widget> _buildEditView(BuildContext context, ColorScheme scheme) {
    return <Widget>[
      _sectionTitle(context, _configured ? '编辑配置' : '新建配置'),
      TextField(
        controller: _baseUrlController,
        focusNode: _baseUrlFocus,
        keyboardType: TextInputType.url,
        decoration: const InputDecoration(
          labelText: '上游 Base URL',
          hintText: 'https://api.openai.com/v1',
          border: OutlineInputBorder(),
        ),
      ),
      const SizedBox(height: 16),
      TextField(
        controller: _apiKeyController,
        obscureText: _obscureKey,
        decoration: InputDecoration(
          labelText: '上游 API Key',
          hintText: _configured ? '留空保持不变' : 'sk-...',
          border: const OutlineInputBorder(),
          suffixIcon: IconButton(
            icon: Icon(_obscureKey ? Icons.visibility : Icons.visibility_off),
            onPressed: () => setState(() => _obscureKey = !_obscureKey),
          ),
        ),
      ),
      const SizedBox(height: 16),
      TextField(
        controller: _remarkController,
        maxLength: 120,
        decoration: const InputDecoration(
          labelText: '备注（可选）',
          hintText: '如：主力模型代理',
          border: OutlineInputBorder(),
        ),
      ),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('启用转发'),
        subtitle: const Text('停用后令牌将无法转发请求'),
        value: _enabled,
        onChanged: _saving ? null : (v) => setState(() => _enabled = v),
      ),
      const SizedBox(height: 16),
      Row(
        children: <Widget>[
          Expanded(
            child: OutlinedButton(
              onPressed: _saving || !_configured
                  ? null
                  : () {
                      _apiKeyController.clear();
                      setState(() => _editing = false);
                    },
              child: const Text('取消'),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: FilledButton(
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('保存'),
            ),
          ),
        ],
      ),
    ];
  }

  Widget _sectionTitle(BuildContext context, String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Text(
        title,
        style: Theme.of(context)
            .textTheme
            .titleSmall
            ?.copyWith(fontWeight: FontWeight.w500),
      ),
    );
  }

  Widget _labelRow(BuildContext context, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: 110,
            child: Text(
              label,
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: Theme.of(context).colorScheme.outline),
            ),
          ),
          Expanded(
            child: Text(value, style: Theme.of(context).textTheme.bodyMedium),
          ),
        ],
      ),
    );
  }

  Widget _copyableRow(BuildContext context, String label, String value, VoidCallback onCopy) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: 110,
            child: Text(
              label,
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: Theme.of(context).colorScheme.outline),
            ),
          ),
          Expanded(
            child: SelectableText(
              value,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.copy, size: 18),
            onPressed: onCopy,
          ),
        ],
      ),
    );
  }
}
