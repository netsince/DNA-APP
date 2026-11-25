import 'package:material_ui/material_ui.dart';
import '../theme/tokens.dart';
import 'package:flutter/services.dart';
import 'package:dna/island_app/api/client.dart';
import 'package:dna/utils/ui_feedback.dart';
import '../widgets/form_draft.dart';
import '../widgets/form_fields.dart';
import '../widgets/submit_form.dart';

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
  /// 三个文本字段的草稿（控制器由草稿持有，页面不再各 new 一个）。
  final FormDraft _draft = FormDraft(
    textFields: <String>['baseUrl', 'apiKey', 'remark'],
  );

  /// 提交态（忙态 + 就地错误）。保存 / 重置 / 删除共用这一份。
  final SubmitFormState _submit = SubmitFormState();

  final FocusNode _baseUrlFocus = FocusNode();

  bool _loading = true;
  bool _configured = false;
  bool _enabled = true;
  bool _editing = false;
  bool _obscureKey = true;

  String _publicBaseUrl = '';
  String _token = '';

  @override
  void initState() {
    super.initState();
    _submit.addListener(_onSubmitChanged);
    _load();
  }

  /// 提交态变了就重建（忙态按钮 / 错误横幅都从这里来）。
  void _onSubmitChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    // 只摘监听、不 dispose _submit：提交请求可能在页面 pop 之后才回来，
    // 那时 run() 会 notifyListeners()，对已 dispose 的 ChangeNotifier 通知会断言失败；
    // 摘掉监听后既不会 setState-after-dispose，也没有监听者需要唤醒。
    _submit.removeListener(_onSubmitChanged);
    _draft.dispose();
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
        _draft.controller('baseUrl').text =
            (cfg['upstream_base_url'] ?? '').toString();
        _draft.controller('remark').text = (cfg['remark'] ?? '').toString();
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
    showSnack(context, msg, duration: const Duration(seconds: 3));
  }

  Future<void> _save() async {
    final baseUrl = _draft.text('baseUrl');
    // 校验时机与提示保持不变：仍先弹一句、再把焦点带回该字段。
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
    await _submit.run(
      errorPrefix: '保存失败',
      action: () async {
        await ApiClient.instance.saveProxyConfig(
          upstreamBaseUrl: baseUrl,
          upstreamApiKey: _draft.text('apiKey'),
          remark: _draft.text('remark'),
          enabled: _enabled,
        );
        if (!mounted) return;
        _snack(_configured ? '配置已更新' : '配置已保存');
        await _load();
      },
    );
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
    await _submit.run(
      errorPrefix: '重置失败',
      action: () async {
        final newToken = await ApiClient.instance.resetProxyToken();
        if (!mounted) return;
        setState(() => _token = newToken);
        _snack('令牌已重置');
      },
    );
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
    await _submit.run(
      errorPrefix: '删除失败',
      action: () async {
        await ApiClient.instance.deleteProxyConfig();
        if (!mounted) return;
        _snack('配置已删除');
        _draft.controller('apiKey').clear();
        await _load();
      },
    );
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
              padding: AppInsets.card,
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
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: scheme.secondaryContainer.withValues(alpha: AppAlpha.half),
        borderRadius: BorderRadius.circular(AppRadius.sm),
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
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              _labelRow(context, '状态', _enabled ? '已启用' : '已停用'),
              _labelRow(context, '上游 Base URL', _draft.rawText('baseUrl')),
              if (_draft.rawText('remark').isNotEmpty)
                _labelRow(context, '备注', _draft.rawText('remark')),
              const Divider(height: 24),
              _copyableRow(
                context,
                '对外 Base URL',
                _publicBaseUrl,
                () => _copy(_publicBaseUrl),
              ),
              _copyableRow(context, '访问令牌', _token, () => _copy(_token)),
            ],
          ),
        ),
      ),
      const SizedBox(height: 16),
      // 重置令牌 / 删除配置的失败原因就地显示在这里（它们都在已配置视图）。
      FormErrorBanner(message: _submit.errorText),
      Row(
        children: <Widget>[
          Expanded(
            child: FilledButton.tonal(
              onPressed: _submit.busy
                  ? null
                  : () => setState(() {
                    // 切视图时清掉上一次的失败原因，避免旧错误残留在横幅里。
                    _submit.clearError();
                    _editing = true;
                  }),
              child: const Text('编辑配置'),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: OutlinedButton(
              onPressed: _submit.busy ? null : _resetToken,
              child: const Text('重置令牌'),
            ),
          ),
        ],
      ),
      const SizedBox(height: 12),
      Center(
        child: TextButton.icon(
          onPressed: _submit.busy ? null : _deleteConfig,
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
      FormTextField(
        draft: _draft,
        id: 'baseUrl',
        label: '上游 Base URL',
        hint: 'https://api.openai.com/v1',
        keyboardType: TextInputType.url,
        focusNode: _baseUrlFocus,
        border: const OutlineInputBorder(),
      ),
      const SizedBox(height: 16),
      FormTextField(
        draft: _draft,
        id: 'apiKey',
        label: '上游 API Key',
        hint: _configured ? '留空保持不变' : 'sk-...',
        obscureText: _obscureKey,
        border: const OutlineInputBorder(),
        suffixIcon: IconButton(
          icon: Icon(_obscureKey ? Icons.visibility : Icons.visibility_off),
          onPressed: () => setState(() => _obscureKey = !_obscureKey),
        ),
      ),
      const SizedBox(height: 16),
      FormTextField(
        draft: _draft,
        id: 'remark',
        label: '备注（可选）',
        hint: '如：主力模型代理',
        maxLength: 120,
        border: const OutlineInputBorder(),
      ),
      // 保存失败的原因就地显示在字段下方（原来只弹一句 snackbar）。
      FormErrorBanner(message: _submit.errorText),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('启用转发'),
        subtitle: const Text('停用后令牌将无法转发请求'),
        value: _enabled,
        onChanged: _submit.busy ? null : (v) => setState(() => _enabled = v),
      ),
      const SizedBox(height: 16),
      Row(
        children: <Widget>[
          Expanded(
            child: OutlinedButton(
              onPressed: _submit.busy || !_configured
                  ? null
                  : () {
                      _draft.controller('apiKey').clear();
                      setState(() => _editing = false);
                    },
              child: const Text('取消'),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: FormSubmitButton(
              label: '保存',
              busy: _submit.busy,
              onPressed: _save,
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
        style: Theme.of(
          context,
        ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w500),
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
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.outline,
              ),
            ),
          ),
          Expanded(
            child: Text(value, style: Theme.of(context).textTheme.bodyMedium),
          ),
        ],
      ),
    );
  }

  Widget _copyableRow(
    BuildContext context,
    String label,
    String value,
    VoidCallback onCopy,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: 110,
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.outline,
              ),
            ),
          ),
          Expanded(
            child: SelectableText(
              value,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
          IconButton(
            tooltip: '复制',
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.copy, size: 18),
            onPressed: onCopy,
          ),
        ],
      ),
    );
  }
}
