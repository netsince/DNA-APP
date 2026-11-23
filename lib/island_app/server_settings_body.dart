import 'package:flutter/material.dart';
import 'package:dna/island_app/api/client.dart';
import 'package:dna/utils/ui_feedback.dart';
import 'package:dna/island_app/server_config.dart';
import 'package:dna/widgets/form_draft.dart';
import 'package:dna/widgets/server_address_form.dart';
import 'package:dna/widgets/submit_form.dart';
import '../theme/tokens.dart';

/// 服务器设置（后端地址）内容，无脚手架，由 [RootShell] 承载。
///
/// 这页刻意很薄：输入框、主按钮、错误横幅都由共享的 [ServerAddressForm] 负责
/// （校验中禁用输入、回车提交、tonal 主按钮与「正在验证…」、红底错误横幅都在那边），
/// 本页只做「读一次 → 校验 → 提交」。提交态（忙态 + 异常原因）走 [SubmitFormState]。
class ServerSettingsBody extends StatefulWidget {
  const ServerSettingsBody({super.key, this.validator});

  /// 注入用：地址校验器（测试时替换）。
  final ServerValidator? validator;

  @override
  State<ServerSettingsBody> createState() => _ServerSettingsBodyState();
}

class _ServerSettingsBodyState extends State<ServerSettingsBody> {
  /// 地址草稿（控制器由草稿持有，页面不再自己 new 一个）。
  final FormDraft _draft = FormDraft(textFields: <String>['baseUrl']);

  /// 提交态：忙态 + 异常原因。
  final SubmitFormState _submit = SubmitFormState();

  /// 校验器给出的可读原因（空值 / 校验未通过）。**不是异常**，文案原样展示。
  String? _validationError;

  bool _loading = true;

  ServerValidator get _validator =>
      widget.validator ?? ApiClient.instance.validateServer;

  @override
  void initState() {
    super.initState();
    _submit.addListener(_onSubmitChanged);
    _load();
  }

  /// 提交态变了就重建（checking / 错误横幅都从这里来）。
  void _onSubmitChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _load() async {
    final url = await ServerConfig.getBaseUrl();
    if (mounted) {
      _draft.controller('baseUrl').text = url;
      setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    final base = ServerConfig.normalize(_draft.rawText('baseUrl'));
    if (base.isEmpty) {
      setState(() => _validationError = '请输入服务器地址');
      return;
    }
    // 一开始就清掉上一次的校验原因（与原来的 setState 同一步）。
    setState(() => _validationError = null);
    await _submit.run(
      errorPrefix: '保存失败',
      action: () async {
        // 保存前先校验：地址填错会让整个 App 都连不上，必须当场拦住而不是存进去。
        // 校验失败是「可读原因」而不是异常 → 走 _validationError 原样展示，
        // 不发请求、不落盘（与改造前一致）。
        final err = await _validator(base);
        if (!mounted) return;
        if (err != null) {
          setState(() => _validationError = err);
          return;
        }
        await ServerConfig.setBaseUrl(base);
        if (!mounted) return;
        setState(() => _draft.controller('baseUrl').text = base);
        showSnack(context, '已保存服务器地址');
      },
    );
  }

  void _useOfficial() {
    setState(() {
      _draft.controller('baseUrl').text = ServerConfig.defaultBaseUrl;
      _validationError = null;
    });
    // 换回官方地址也算「重新来」，顺手清掉上一次提交失败的原因。
    _submit.clearError();
  }

  @override
  Widget build(BuildContext context) {
    return _loading
        ? const Center(child: CircularProgressIndicator())
        : ListView(
            padding: AppInsets.card,
            children: [
              const Text(
                'DNAISLAND 后端地址',
                style: TextStyle(
                  fontWeight: FontWeight.w500,
                  fontSize: AppFontSize.subtitle,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'DNAISLAND 是开源项目，默认使用官方服务器；你也可以填写自建服务器的地址。',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 12),
              ServerAddressForm(
                controller: _draft.controller('baseUrl'),
                defaultUrl: ServerConfig.defaultBaseUrl,
                onUseDefault: _useOfficial,
                onSubmit: _save,
                checking: _submit.busy,
                // 异常原因（带 describeError）优先，其次是校验器的原样原因。
                error: _submit.errorText ?? _validationError,
                actionLabel: '保存',
                checkingLabel: '正在验证…',
                actionIcon: Icons.save,
                layout: ServerActionLayout.fullWidthFilled,
              ),
            ],
          );
  }

  @override
  void dispose() {
    // 只摘监听、不 dispose _submit：提交请求可能在页面 pop 之后才回来，
    // 那时 run() 会 notifyListeners()，对已 dispose 的 ChangeNotifier 通知会断言失败。
    _submit.removeListener(_onSubmitChanged);
    _draft.dispose();
    super.dispose();
  }
}
