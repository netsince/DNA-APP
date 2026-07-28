import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../models/conversation.dart';
import '../models/prompt_strategy.dart';
import '../services/auth_service.dart';
import '../services/data_backup_service.dart';
import '../services/conversation_export_import_service.dart';
import '../widgets/conversation_export_import_dialogs.dart';
import '../services/app_icon_service.dart';
import '../state/app_controller.dart';
import '../utils/dialogs.dart';
import '../utils/ui_feedback.dart';
import '../widgets/app_drawer.dart';

// =============================================================================
// Main settings list
// =============================================================================

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key, required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      drawer: AppDrawer(controller: controller, current: AppSection.settings),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final double w = constraints.maxWidth > 900 ? 900 : constraints.maxWidth;
          return Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: w),
              child: ListView(
                padding: const EdgeInsets.symmetric(vertical: 8),
                children: <Widget>[
                  _MenuItem(
                    icon: Icons.memory,
                    title: 'AI 服务',
                    subtitle: 'API 连接与模型选择',
                    onTap: () => _push(context, _AiServicePage(controller: controller)),
                  ),
                  _MenuItem(
                    icon: Icons.chat_bubble_outline,
                    title: '对话与策略',
                    subtitle: '提示词、灵感、摘要及发送策略',
                    onTap: () => _push(context, _ConversationPage(controller: controller)),
                  ),
                  _MenuItem(
                    icon: Icons.lock_outline,
                    title: '安全与隐私',
                    subtitle: '生物识别验证保护',
                    onTap: () => _push(context, _SecurityPage(controller: controller)),
                  ),
                  _MenuItem(
                    icon: Icons.palette_outlined,
                    title: '外观与体验',
                    subtitle: '应用图标、动画及引导流程',
                    onTap: () => _push(context, _AppearancePage(controller: controller)),
                  ),
                  _MenuItem(
                    icon: Icons.storage_outlined,
                    title: '数据管理',
                    subtitle: '备份、恢复与导出导入',
                    onTap: () => _push(context, _DataManagementPage(controller: controller)),
                  ),
                  _MenuItem(
                    icon: Icons.warning_amber_outlined,
                    title: '高级',
                    subtitle: '命令系统',
                    onTap: () => _push(context, _AdvancedPage(controller: controller)),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  void _push(BuildContext context, Widget page) {
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page));
  }
}

class _MenuItem extends StatelessWidget {
  const _MenuItem({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon),
      title: Text(title),
      subtitle: Text(subtitle),
      trailing: const Icon(Icons.chevron_right),
      onTap: onTap,
    );
  }
}

// =============================================================================
// Section page: AI 服务
// =============================================================================

class _AiServicePage extends StatefulWidget {
  const _AiServicePage({required this.controller});
  final AppController controller;

  @override
  State<_AiServicePage> createState() => _AiServicePageState();
}

class _AiServicePageState extends State<_AiServicePage> {
  late final TextEditingController _baseUrlCtrl;
  late final TextEditingController _apiKeyCtrl;

  bool _checkingApi = false;
  bool _loadingModels = false;
  String? _apiMessage;
  String? _modelsError;
  List<String> _models = <String>[];
  String? _selectedModel;

  @override
  void initState() {
    super.initState();
    final s = widget.controller.settings;
    _baseUrlCtrl = TextEditingController(text: s.baseUrl);
    _apiKeyCtrl = TextEditingController(text: s.apiKey);
    _selectedModel = s.selectedModel.isEmpty ? null : s.selectedModel;
  }

  @override
  void dispose() {
    _baseUrlCtrl.dispose();
    _apiKeyCtrl.dispose();
    super.dispose();
  }

  Future<void> _saveApi() => widget.controller.saveApiConfig(
        baseUrl: _baseUrlCtrl.text,
        apiKey: _apiKeyCtrl.text,
      );

  Future<void> _checkApi() async {
    setState(() { _checkingApi = true; _apiMessage = null; });
    await _saveApi();
    final r = await widget.controller.openAiService.validateApi(
      baseUrl: _baseUrlCtrl.text,
      apiKey: _apiKeyCtrl.text,
    );
    if (!mounted) return;
    setState(() { _checkingApi = false; _apiMessage = r.message; });
  }

  Future<void> _fetchModels() async {
    setState(() { _loadingModels = true; _modelsError = null; });
    final r = await widget.controller.openAiService.fetchModels(
      baseUrl: _baseUrlCtrl.text,
      apiKey: _apiKeyCtrl.text,
    );
    if (!mounted) return;
    setState(() {
      _loadingModels = false;
      _models = r.models;
      _modelsError = r.errorMessage;
      if ((_selectedModel ?? '').isEmpty && _models.isNotEmpty) {
        _selectedModel = _models.first;
      }
      if (_selectedModel != null && _selectedModel!.isNotEmpty && !_models.contains(_selectedModel)) {
        _models = <String>[_selectedModel!, ..._models];
      }
    });
  }

  Future<void> _saveModel() async {
    if ((_selectedModel ?? '').trim().isEmpty) return;
    await widget.controller.saveSelectedModel(_selectedModel!.trim());
  }

  Future<void> _addCustomModel() async {
    final v = await showTextInputDialog(
      context: context, title: '输入自定义模型', hintText: '例如 gpt-4.1-mini', confirmText: '确定',
    );
    if (!mounted || v == null || v.isEmpty) return;
    setState(() {
      _selectedModel = v;
      if (!_models.contains(v)) _models = <String>[v, ..._models];
    });
    await _saveModel();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('AI 服务')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          TextField(
            controller: _baseUrlCtrl,
            decoration: const InputDecoration(labelText: 'Base URL', hintText: 'https://api.openai.com/v1'),
            onChanged: (_) => _saveApi(),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _apiKeyCtrl,
            obscureText: true,
            decoration: const InputDecoration(labelText: 'API Key'),
            onChanged: (_) => _saveApi(),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _checkingApi ? null : _checkApi,
            icon: _checkingApi
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.network_check),
            label: Text(_checkingApi ? '检测中...' : '检测连接'),
          ),
          if (_apiMessage != null) ...[
            const SizedBox(height: 8),
            Row(
              children: <Widget>[
                Icon(
                  _apiMessage!.contains('成功') ? Icons.check_circle : Icons.error,
                  size: 16,
                  color: _apiMessage!.contains('成功') ? cs.primary : cs.error,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(_apiMessage!,
                      style: TextStyle(color: _apiMessage!.contains('成功') ? cs.primary : cs.error)),
                ),
              ],
            ),
          ],
          const SizedBox(height: 24),
          const Divider(),
          const SizedBox(height: 12),
          Text('模型选择', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 10, runSpacing: 10,
            children: <Widget>[
              FilledButton.tonalIcon(
                onPressed: _loadingModels ? null : _fetchModels,
                icon: _loadingModels
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.refresh),
                label: Text(_loadingModels ? '加载中...' : '刷新模型'),
              ),
              OutlinedButton.icon(
                onPressed: _addCustomModel,
                icon: const Icon(Icons.edit),
                label: const Text('自定义模型'),
              ),
            ],
          ),
          if (_modelsError != null) ...[
            const SizedBox(height: 8),
            Text(_modelsError!, style: TextStyle(color: cs.error)),
          ],
          const SizedBox(height: 8),
          if (_models.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                _selectedModel == null ? '尚未加载模型，可先点击"刷新模型"。' : '当前模型：$_selectedModel',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            )
          else
            Column(
              children: _models.map((String model) {
                final sel = model == _selectedModel;
                return ListTile(
                  dense: true, visualDensity: VisualDensity.compact,
                  leading: Icon(sel ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                      color: sel ? cs.primary : null),
                  title: Text(model),
                  onTap: () { setState(() => _selectedModel = model); _saveModel(); },
                );
              }).toList(),
            ),
        ],
      ),
    );
  }
}

// =============================================================================
// Section page: 对话与策略
// =============================================================================

class _ConversationPage extends StatefulWidget {
  const _ConversationPage({required this.controller});
  final AppController controller;

  @override
  State<_ConversationPage> createState() => _ConversationPageState();
}

class _ConversationPageState extends State<_ConversationPage> {
  late final TextEditingController _summaryCtrl;
  late PromptStrategy _strategy;
  bool _autoSummary = true;
  bool _retrySeq = false;
  bool _inspireSummary = false;

  @override
  void initState() {
    super.initState();
    final s = widget.controller.settings;
    _autoSummary = s.autoSummaryPrompt;
    _summaryCtrl = TextEditingController(text: s.summaryTurnInterval.toString());
    _retrySeq = s.retrySequential;
    _inspireSummary = s.inspirationIncludeSummary;
    _strategy = s.promptStrategy;
  }

  @override
  void dispose() { _summaryCtrl.dispose(); super.dispose(); }

  Future<void> _saveSummary() async {
    final turns = (int.tryParse(_summaryCtrl.text.trim()) ?? 200).clamp(10, 1000);
    _summaryCtrl.text = turns.toString();
    await widget.controller.saveSummarySettings(autoSummaryPrompt: _autoSummary, summaryTurnInterval: turns);
  }

  Future<void> _saveRetry() => widget.controller.saveRetryStrategy(retrySequential: _retrySeq);
  Future<void> _saveInspire() => widget.controller.saveInspirationSettings(includeSummary: _inspireSummary);
  Future<void> _saveStrategy() => widget.controller.savePromptStrategy(_strategy);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final ts = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('对话与策略')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          // --- Prompt strategy ---
          Text('提示词策略', style: ts.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(height: 16),
          Text('推进策略', style: ts.bodyMedium?.copyWith(color: cs.onSurfaceVariant)),
          const SizedBox(height: 8),
          Row(
            children: <Widget>[
              Expanded(child: ChoiceChip(
                label: const Text('强制推进'),
                selected: _strategy.advance == AdvanceStrategy.forced,
                onSelected: (s) { if (s) setState(() => _strategy = _strategy.copyWith(advance: AdvanceStrategy.forced)); _saveStrategy(); },
              )),
              const SizedBox(width: 8),
              Expanded(child: ChoiceChip(
                label: const Text('自由发展'),
                selected: _strategy.advance == AdvanceStrategy.free,
                onSelected: (s) { if (s) setState(() => _strategy = _strategy.copyWith(advance: AdvanceStrategy.free)); _saveStrategy(); },
              )),
            ],
          ),
          const SizedBox(height: 12),
          Text('沉浸策略', style: ts.bodyMedium?.copyWith(color: cs.onSurfaceVariant)),
          const SizedBox(height: 8),
          Row(
            children: <Widget>[
              Expanded(child: ChoiceChip(
                label: const Text('克制'),
                selected: _strategy.immersion == ImmersionStrategy.restrained,
                onSelected: (s) { if (s) setState(() => _strategy = _strategy.copyWith(immersion: ImmersionStrategy.restrained)); _saveStrategy(); },
              )),
              const SizedBox(width: 8),
              Expanded(child: ChoiceChip(
                label: const Text('更强'),
                selected: _strategy.immersion == ImmersionStrategy.strong,
                onSelected: (s) { if (s) setState(() => _strategy = _strategy.copyWith(immersion: ImmersionStrategy.strong)); _saveStrategy(); },
              )),
            ],
          ),
          const SizedBox(height: 12),
          Text('字数控制', style: ts.bodyMedium?.copyWith(color: cs.onSurfaceVariant)),
          const SizedBox(height: 8),
          Row(
            children: <Widget>[
              Expanded(child: ChoiceChip(
                label: const Text('严格 80-120 字'),
                selected: _strategy.length == LengthStrategy.strict,
                onSelected: (s) { if (s) setState(() => _strategy = _strategy.copyWith(length: LengthStrategy.strict)); _saveStrategy(); },
              )),
              const SizedBox(width: 8),
              Expanded(child: ChoiceChip(
                label: const Text('无限制'),
                selected: _strategy.length == LengthStrategy.unlimited,
                onSelected: (s) { if (s) setState(() => _strategy = _strategy.copyWith(length: LengthStrategy.unlimited)); _saveStrategy(); },
              )),
            ],
          ),
          const SizedBox(height: 24),
          const Divider(),
          // --- Inspiration ---
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('灵感附带最近摘要'),
            subtitle: const Text('开启后会在生成灵感时附带最近摘要。默认关闭以节省 token。'),
            value: _inspireSummary,
            onChanged: (v) { setState(() => _inspireSummary = v); _saveInspire(); },
          ),
          const Divider(),
          // --- Summary ---
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('允许自动提示摘要'),
            value: _autoSummary,
            onChanged: (v) { setState(() => _autoSummary = v); _saveSummary(); },
          ),
          const SizedBox(height: 4),
          TextField(
            controller: _summaryCtrl,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: '触发轮数（按用户消息计）',
              hintText: '默认 200，范围 10-1000',
              isDense: true,
            ),
            onChanged: (_) => _saveSummary(),
          ),
          const Divider(),
          // --- Retry ---
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('多个请求按顺序单次执行'),
            subtitle: const Text('开启后重说会顺序发送三次请求。关闭则并发请求三次。'),
            value: _retrySeq,
            onChanged: (v) { setState(() => _retrySeq = v); _saveRetry(); },
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// Section page: 安全与隐私
// =============================================================================

class _SecurityPage extends StatefulWidget {
  const _SecurityPage({required this.controller});
  final AppController controller;

  @override
  State<_SecurityPage> createState() => _SecurityPageState();
}

class _SecurityPageState extends State<_SecurityPage> {
  bool _authForApp = false;
  bool _authForArchive = false;
  bool _authAvailable = false;

  @override
  void initState() {
    super.initState();
    final s = widget.controller.settings;
    _authForApp = s.requireAuthForApp;
    _authForArchive = s.requireAuthForArchive;
    _checkAuth();
  }

  Future<void> _checkAuth() async {
    final a = await AuthService.canCheckBiometrics();
    if (mounted) setState(() => _authAvailable = a);
  }

  Future<void> _save() => widget.controller.saveAuthSettings(
    requireAuthForArchive: _authForArchive,
    requireAuthForApp: _authForApp,
  );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('安全与隐私')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          if (!_authAvailable)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Row(
                children: <Widget>[
                  Icon(Icons.info_outline, size: 16, color: Theme.of(context).colorScheme.error),
                  const SizedBox(width: 6),
                  Text('当前设备不支持生物识别验证',
                      style: TextStyle(color: Theme.of(context).colorScheme.error, fontSize: 12)),
                ],
              ),
            )
          else ...[
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('进入软件需验证'),
              subtitle: const Text('开启后每次进入应用或从后台切回都需要验证身份。'),
              value: _authForApp,
              onChanged: (v) { setState(() => _authForApp = v); _save(); },
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('查看归档需验证'),
              subtitle: const Text('开启后进入任意归档页面需要验证身份。'),
              value: _authForArchive,
              onChanged: (v) { setState(() => _authForArchive = v); _save(); },
            ),
          ],
        ],
      ),
    );
  }
}

// =============================================================================
// Section page: 外观与体验
// =============================================================================

class _AppearancePage extends StatefulWidget {
  const _AppearancePage({required this.controller});
  final AppController controller;

  @override
  State<_AppearancePage> createState() => _AppearancePageState();
}

class _AppearancePageState extends State<_AppearancePage> {
  bool _showSplash = true;
  String _iconKey = 'default';
  final bool _androidOk = AppIconService.isSupported;

  @override
  void initState() {
    super.initState();
    final s = widget.controller.settings;
    _showSplash = s.showSplashAnimation;
    _iconKey = s.appIcon;
  }

  Future<void> _selectIcon(AppIconOption opt) async {
    if (_iconKey == opt.key) return;
    setState(() => _iconKey = opt.key);
    await widget.controller.saveAppIcon(opt);
    if (!mounted) return;
    showSnack(context, '应用图标已切换，返回桌面即可看到效果。');
  }

  Future<void> _saveSplash() =>
      widget.controller.saveSplashAnimation(showSplashAnimation: _showSplash);

  Future<void> _restartOobe() async {
    await widget.controller.restartOobe();
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('外观与体验')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          Text('应用图标', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          if (!_androidOk)
            Text('应用图标切换仅支持 Android 平台。', style: TextStyle(color: cs.error, fontSize: 12))
          else
            Text('选择启动器上显示的图标。',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
          const SizedBox(height: 12),
          Wrap(
            spacing: 16, runSpacing: 12,
            children: AppIconService.availableOptions.map((AppIconOption opt) {
              return ChoiceChip(
                selected: _iconKey == opt.key,
                onSelected: _androidOk ? (_) => _selectIcon(opt) : null,
                label: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.asset(opt.assetPath, width: 36, height: 36,
                          errorBuilder: (_, __, ___) => const Icon(Icons.android)),
                    ),
                    const SizedBox(width: 10),
                    Text(opt.label),
                  ],
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 24),
          const Divider(),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('开场动画'),
            subtitle: const Text('关闭后将直接进入应用，不再播放启动动画。'),
            value: _showSplash,
            onChanged: (v) { setState(() => _showSplash = v); _saveSplash(); },
          ),
          const Padding(
            padding: EdgeInsets.only(bottom: 8),
            child: Text('可重新进入首次启动引导流程。'),
          ),
          OutlinedButton.icon(
            onPressed: _restartOobe,
            icon: const Icon(Icons.restart_alt),
            label: const Text('重新进入 OOBE'),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// Section page: 数据管理
// =============================================================================

class _DataManagementPage extends StatefulWidget {
  const _DataManagementPage({required this.controller});
  final AppController controller;

  @override
  State<_DataManagementPage> createState() => _DataManagementPageState();
}

class _DataManagementPageState extends State<_DataManagementPage> {
  bool _exporting = false;
  bool _importing = false;
  bool _exportingConv = false;
  bool _importingConv = false;

  String _ts() {
    final d = DateTime.now();
    String p(int n) => n.toString().padLeft(2, '0');
    return '${d.year}${p(d.month)}${p(d.day)}_${p(d.hour)}${p(d.minute)}${p(d.second)}';
  }

  // ---- All data export ----

  Future<void> _exportAll() async {
    setState(() => _exporting = true);
    try {
      final r = await widget.controller.exportAllData();
      if (!mounted) return;
      if (!r.success || r.data == null) { showSnack(context, r.message ?? '导出失败'); return; }
      final data = r.data!;
      if (!kIsWeb && Platform.isIOS) {
        final tmp = File(path.join((await getTemporaryDirectory()).path, 'DNA_${_ts()}.zip'));
        await tmp.writeAsBytes(data);
        if (!mounted) return;
        await Share.shareXFiles(<XFile>[XFile(tmp.path)], subject: 'DNA 全部数据导出');
        return;
      }
      final out = await FilePicker.platform.saveFile(
        dialogTitle: '导出全部数据为 ZIP', fileName: 'DNA_${_ts()}.zip',
        type: FileType.custom, allowedExtensions: <String>['zip'], bytes: data,
      );
      if (out == null) return;
      var saved = out;
      if (!kIsWeb && !Platform.isAndroid) {
        final f = File(out.endsWith('.zip') ? out : '$out.zip');
        await f.writeAsBytes(data);
        saved = f.path;
      }
      if (!mounted) return;
      showSnack(context, '已导出到：$saved');
    } catch (e) { if (mounted) showSnack(context, '导出出错：$e');
    } finally { if (mounted) setState(() => _exporting = false); }
  }

  // ---- All data import ----

  Future<bool?> _pickMode({required String desc}) => showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('导入方式'),
      content: Text(desc),
      actions: <Widget>[
        TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('仅追加')),
        FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('全部替换')),
      ],
    ),
  );

  Future<void> _showReport(DataImportReport r, {bool onlyConv = false}) async {
    final sb = StringBuffer();
    if (!onlyConv) { sb.writeln('角色：${r.tasCount}'); sb.writeln('世界：${r.worldsCount}'); }
    sb.writeln('对话：${r.conversationsCount}');
    if (r.replaced) {
      if (r.backupPath != null) sb.writeln('\n替换前的数据已自动备份至：\n${r.backupPath}');
      else if (r.backupError != null) sb.writeln('\n⚠️ 自动备份失败：${r.backupError}');
    }
    if (!mounted) return;
    await showInfoDialog(context: context, title: '导入完成', content: Text(sb.toString()));
  }

  Future<void> _importAll() async {
    final picked = await FilePicker.platform.pickFiles(
      dialogTitle: '选择备份 ZIP', type: FileType.custom,
      allowedExtensions: <String>['zip'], withData: true,
    );
    if (picked == null || picked.files.isEmpty) return;
    final f = picked.files.first;
    final bytes = f.bytes ?? (f.path != null ? await File(f.path!).readAsBytes() : null);
    if (bytes == null) { if (mounted) showSnack(context, '无法读取文件内容。'); return; }
    final replaceAll = await _pickMode(
      desc: '全部替换：清空现有数据后导入；替换前的数据会自动备份为一个 ZIP。\n\n仅追加：只添加新的角色 / 世界 / 对话，已有数据保留。',
    );
    if (replaceAll == null) return;
    setState(() => _importing = true);
    try {
      final r = await widget.controller.importData(bytes, replaceAll: replaceAll);
      if (!mounted) return;
      if (!r.success || r.data == null) { showSnack(context, r.message ?? '导入失败'); return; }
      await _showReport(r.data!);
    } catch (e) { if (mounted) showSnack(context, '导入出错：$e');
    } finally { if (mounted) setState(() => _importing = false); }
  }

  // ---- Conversation export ----

  String _convName(Conversation c) {
    if (c.isGroup) return c.groupName.trim().isNotEmpty ? c.groupName.trim() : '群聊';
    final n = widget.controller.getTaById(c.taId)?.name;
    return (n != null && n.isNotEmpty) ? n : '未命名对话';
  }

  Future<void> _exportConv() async {
    setState(() => _exportingConv = true);
    try {
      final convs = widget.controller.allConversations;
      final nameById = <String, String>{for (final c in convs) c.id: _convName(c)};
      final sel = await showConversationPickerDialog(
        context: context, conversations: convs, nameById: nameById,
      );
      if (!mounted || sel == null || sel.isEmpty) return;
      final opts = await showExportOptionsDialog(context: context);
      if (opts == null) return;
      final r = await widget.controller.exportConversationsById(
        sel, includeCharacterCards: opts.includeCharacterCards, format: opts.format,
      );
      if (!mounted) return;
      if (!r.success || r.data == null) { showSnack(context, r.message ?? '导出失败'); return; }
      await handleExportResult(context, r.data!);
    } catch (e) { if (mounted) showSnack(context, '导出出错：$e');
    } finally { if (mounted) setState(() => _exportingConv = false); }
  }

  // ---- Conversation import ----

  List<NeededCharacter> _buildNeeded(ConversationImportData data) {
    final list = <NeededCharacter>[];
    for (final taId in data.collectTaIds()) {
      final pkg = data.embeddedPackages[taId];
      String? cardName;
      if (pkg != null && pkg['character'] is Map) {
        final n = (pkg['character'] as Map)['name'];
        if (n is String && n.isNotEmpty) cardName = n;
      }
      list.add(NeededCharacter(originalTaId: taId, hasCard: pkg != null, cardName: cardName));
    }
    return list;
  }

  Future<void> _importConv() async {
    final picked = await FilePicker.platform.pickFiles(
      dialogTitle: '选择对话 JSON', type: FileType.custom,
      allowedExtensions: <String>['json'], withData: true,
    );
    if (picked == null || picked.files.isEmpty) return;
    final f = picked.files.first;
    final bytes = f.bytes ?? (f.path != null ? await File(f.path!).readAsBytes() : null);
    if (bytes == null) { if (mounted) showSnack(context, '无法读取文件内容。'); return; }
    final parsed = widget.controller.parseConversationImportJson(utf8.decode(bytes));
    if (!mounted) return;
    if (!parsed.success || parsed.data == null) { showSnack(context, parsed.message ?? '导入失败'); return; }
    final data = parsed.data!;
    final decisions = await showCharacterResolutionDialog(
      context: context, needed: _buildNeeded(data), existingTas: widget.controller.tas,
    );
    if (decisions == null) return;
    final replaceAll = await _pickMode(
      desc: '全部替换：清空现有对话后导入；替换前的对话会自动备份为一个 ZIP。\n\n仅追加：只添加新的对话，已有对话保留。',
    );
    if (replaceAll == null) return;
    setState(() => _importingConv = true);
    try {
      final r = await widget.controller.applyConversationImport(data, decisions, replaceAll: replaceAll);
      if (!mounted) return;
      if (!r.success || r.data == null) { showSnack(context, r.message ?? '导入失败'); return; }
      await _showReport(r.data!, onlyConv: true);
    } catch (e) { if (mounted) showSnack(context, '导入出错：$e');
    } finally { if (mounted) setState(() => _importingConv = false); }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('数据管理')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          Text('全部数据', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          Text('将全部数据（角色、世界、对话，不含设置）打包为 ZIP 文件，或从 ZIP 导入。',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10, runSpacing: 10,
            children: <Widget>[
              FilledButton.tonalIcon(
                onPressed: _exporting || _importing ? null : _exportAll,
                icon: _exporting
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.archive_outlined),
                label: Text(_exporting ? '导出中...' : '导出全部数据'),
              ),
              OutlinedButton.icon(
                onPressed: _exporting || _importing ? null : _importAll,
                icon: _importing
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.upload_file_outlined),
                label: Text(_importing ? '导入中...' : '从 ZIP 导入'),
              ),
            ],
          ),
          const SizedBox(height: 24),
          const Divider(),
          const SizedBox(height: 8),
          Text('仅对话', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          Text('导出为 JSON（可内嵌角色卡）或 Markdown，方便阅读与分享。',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10, runSpacing: 10,
            children: <Widget>[
              FilledButton.tonalIcon(
                onPressed: _exportingConv || _importingConv ? null : _exportConv,
                icon: _exportingConv
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.forum_outlined),
                label: Text(_exportingConv ? '导出中...' : '导出对话'),
              ),
              OutlinedButton.icon(
                onPressed: _exportingConv || _importingConv ? null : _importConv,
                icon: _importingConv
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.upload_file_outlined),
                label: Text(_importingConv ? '导入中...' : '从 JSON 导入'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// Section page: 高级
// =============================================================================

class _AdvancedPage extends StatefulWidget {
  const _AdvancedPage({required this.controller});
  final AppController controller;

  @override
  State<_AdvancedPage> createState() => _AdvancedPageState();
}

class _AdvancedPageState extends State<_AdvancedPage> {
  late final TextEditingController _cmdCtrl;
  static const _clearCmd = 'CLEAR ALL DATAS YES I DO THIS PLEASE DEL MY DATAS THANK YOU 114514';

  @override
  void initState() { super.initState(); _cmdCtrl = TextEditingController(); }

  @override
  void dispose() { _cmdCtrl.dispose(); super.dispose(); }

  Future<void> _run() async {
    final cmd = _cmdCtrl.text;
    if (cmd == _clearCmd) {
      await widget.controller.clearAllData();
      if (!mounted) return;
      _cmdCtrl.clear();
      showSnack(context, '数据已清除。');
      return;
    }
    showSnack(context, '未知指令或指令不匹配。');
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('高级')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: cs.errorContainer.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: cs.error.withValues(alpha: 0.3)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Icon(Icons.warning_amber_rounded, size: 18, color: cs.error),
                    const SizedBox(width: 8),
                    Text('危险操作', style: TextStyle(fontWeight: FontWeight.w600, color: cs.error, fontSize: 16)),
                  ],
                ),
                const SizedBox(height: 12),
                Text('输入命令并执行。命令大小写敏感。请确保您清楚自己在做什么。',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant)),
                const SizedBox(height: 16),
                TextField(
                  controller: _cmdCtrl,
                  decoration: const InputDecoration(labelText: '输入命令', isDense: true),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: _run,
                    style: FilledButton.styleFrom(
                      backgroundColor: cs.error,
                      foregroundColor: cs.onError,
                    ),
                    child: const Text('执行命令'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
