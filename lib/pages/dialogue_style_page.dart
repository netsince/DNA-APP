import 'package:flutter/material.dart';

import '../models/ta.dart';
import '../state/app_controller.dart';
import '../widgets/app_editor_frame.dart';
import '../widgets/fit_text.dart';
import 'dialogue_style/dialogue_style_form.dart';

/// 角色对话风格（Few-shot 示例）配置页 —— **外壳**。
///
/// 表单本体在 [DialogueStyleForm]（只有各轮输入输出），通过
/// [DialogueStyleFormController] 取值 / 追加一轮。
class DialogueStylePage extends StatefulWidget {
  const DialogueStylePage({
    super.key,
    this.controller,
    required this.ta,
    this.onSave,
  });

  /// 本地库。社区里编辑未发布/已发布的卡时**不传**（那边没有本地库）。
  final AppController? controller;

  final TA ta;

  /// 给了它就用它保存；否则写本地库。保存成功后一律把改好的 TA pop 回去。
  final Future<void> Function(TA ta)? onSave;

  @override
  State<DialogueStylePage> createState() => _DialogueStylePageState();
}

class _DialogueStylePageState extends State<DialogueStylePage> {
  final DialogueStyleFormController _form = DialogueStyleFormController();
  bool _saving = false;

  @override
  void dispose() {
    _form.dispose();
    super.dispose();
  }

  /// 异常 → 给用户看的一句话。
  static String _errorText(Object e) {
    final String text = e.toString();
    return text.startsWith('Exception: ') ? text.substring(11) : text;
  }

  Future<void> _save() async {
    if (_saving) {
      return;
    }
    final TA updated = widget.ta.copyWith(dialogueStyle: _form.current());
    final Future<void> Function(TA ta)? onSave = widget.onSave;
    setState(() => _saving = true);
    try {
      if (onSave != null) {
        await onSave(updated);
      } else {
        await widget.controller!.upsertTa(updated);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: FitText(_errorText(e))),
      );
      return;
    }
    if (!mounted) return;
    Navigator.of(context).pop(updated);
  }

  /// 返回时若还有未保存修改，先确认；没有修改就直接走。
  Future<void> _handlePop(bool didPop, Object? result) async {
    if (didPop) return;
    if (!mounted) return;
    if (!_form.isDirty) {
      Navigator.of(context).pop(result);
      return;
    }
    final bool? discard = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: const FitText('放弃修改？'),
        content: const FitText('还有未保存的修改，返回会丢失。'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const FitText('继续编辑'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const FitText('放弃'),
          ),
        ],
      ),
    );
    if (!mounted || discard != true) return;
    Navigator.of(context).pop(result);
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: _handlePop,
      child: Scaffold(
      appBar: AppBar(
        title: const FitText('对话风格（语气范例）'),
        actions: <Widget>[
          IconButton(
            onPressed: _save,
            icon: const Icon(Icons.check),
            tooltip: '保存',
          ),
        ],
      ),
      body: DialogueStyleForm(
        initial: widget.ta.dialogueStyle,
        formController: _form,
      ),
      floatingActionButton: AppEditorFab(
        onPressed: _form.addTurn,
        icon: const Icon(Icons.add),
        label: const FitText('添加对话范例'),
      ),
      ),
    );
  }
}
