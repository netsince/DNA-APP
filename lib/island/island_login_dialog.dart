import 'package:flutter/material.dart';

import 'package:dna/theme/tokens.dart';
import 'package:dna/widgets/fit_text.dart';

import 'island_api.dart';
import 'island_session.dart';

/// 岛账号登录（最小版）：服务器地址 + 账号 + 密码。
///
/// **本地为主**：不登录也能用主项目的一切功能，以及「试聊」「从岛导入」
/// （卡片详情是公开的）；只有「发布到岛」需要登录。所以这里不做启动引导，
/// 只在真正需要的时候弹出来。
Future<bool> showIslandLoginDialog(
  BuildContext context, {
  IslandApi? api,
}) async {
  final bool? ok = await showDialog<bool>(
    context: context,
    builder: (BuildContext dialogContext) =>
        IslandLoginDialog(api: api),
  );
  return ok ?? false;
}

class IslandLoginDialog extends StatefulWidget {
  const IslandLoginDialog({super.key, this.api});

  final IslandApi? api;

  @override
  State<IslandLoginDialog> createState() => _IslandLoginDialogState();
}

class _IslandLoginDialogState extends State<IslandLoginDialog> {
  late final TextEditingController _server = TextEditingController(
    text: IslandSession.baseUrl,
  );
  final TextEditingController _user = TextEditingController();
  final TextEditingController _pass = TextEditingController();

  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _server.dispose();
    _user.dispose();
    _pass.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) {
      return;
    }
    if (_user.text.trim().isEmpty || _pass.text.isEmpty) {
      setState(() => _error = '请填写账号与密码');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final IslandApi api = widget.api ?? IslandApi();
    try {
      await IslandSession.saveServer(_server.text);
      await api.login(
        identifier: _user.text.trim(),
        password: _pass.text,
      );
      if (mounted) {
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _error = '$e');
      }
    } finally {
      if (widget.api == null) {
        api.dispose();
      }
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme cs = Theme.of(context).colorScheme;
    return AlertDialog(
      title: const FitText('登录 DNAISLAND'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const FitText('发布角色卡需要登录；其余功能不受影响。'),
            const SizedBox(height: AppSpacing.lg),
            TextField(
              controller: _server,
              decoration: const InputDecoration(
                labelText: '服务器地址',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            TextField(
              controller: _user,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: '账号',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            TextField(
              controller: _pass,
              obscureText: true,
              onSubmitted: (_) => _submit(),
              decoration: const InputDecoration(
                labelText: '密码',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
            if (_error != null) ...<Widget>[
              const SizedBox(height: AppSpacing.md),
              FitText(
                _error!,
                style: TextStyle(color: cs.error),
              ),
            ],
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(false),
          child: const FitText('取消'),
        ),
        FilledButton(
          onPressed: _busy ? null : _submit,
          child: FitText(_busy ? '登录中…' : '登录'),
        ),
      ],
    );
  }
}
