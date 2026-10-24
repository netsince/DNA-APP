import 'package:flutter/material.dart';

import '../models/ta.dart';
import '../state/app_controller.dart';
import '../widgets/app_editor_frame.dart';
import '../widgets/fit_text.dart';
import '../services/image_pick_capability.dart';
import 'ta_editor/ta_editor_form.dart';

/// 角色卡编辑器**外壳**：顶栏、菜单、保存按钮、导航都在这里。
///
/// 表单本体在 [TaEditorForm]（只有字段与图片槽），通过 [TaFormController] 取值。
/// 存本地还是发社区、按钮叫什么、要不要校验，全归宿主决定 —— 表单不再自带行为。
class TaEditorPage extends StatefulWidget {
  const TaEditorPage({
    super.key,
    this.controller,
    this.ta,
    this.onSave,
    this.title,
    this.saveLabel = '保存',
  });

  /// 本地角色卡库。社区发布/编辑角色卡时**不传**（那边零状态依赖）。
  final AppController? controller;

  final TA? ta;

  /// 保存回调。给了它就用它，不再写本地库。
  final Future<void> Function(TA ta)? onSave;

  /// 顶栏标题；为空时按「创建TA / 编辑TA」自动判断。
  final String? title;

  /// 保存按钮文案：本体「保存」/ 社区「发布到社区」。
  final String saveLabel;

  @override
  State<TaEditorPage> createState() => _TaEditorPageState();
}

class _TaEditorPageState extends State<TaEditorPage> {
  final TaFormController _form = TaFormController();

  /// 保存 / 发布进行中：防止连点重复提交，也用来在失败后复位。
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
    final TA ta = _form.current();
    final Future<void> Function(TA)? onSave = widget.onSave;
    setState(() => _saving = true);
    try {
      if (onSave != null) {
        await onSave(ta);
      } else {
        await widget.controller!.upsertTa(ta);
      }
    } catch (e) {
      // 失败必须让用户看见原因，并且**不关闭**页面。
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: FitText(_errorText(e))),
      );
      return;
    }
    await _form.afterSave();
    if (!mounted) return;
    Navigator.of(context).pop();
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
        title: FitText(
          widget.title ?? (widget.ta == null ? '创建TA' : '编辑TA'),
        ),
        actions: <Widget>[
          PopupMenuButton<String>(
            onSelected: (String value) {
              switch (value) {
                case 'export':
                  _form.exportViaDialog();
                  break;
                case 'import':
                  _form.importViaDialog();
                  break;
              }
            },
            itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
              const PopupMenuItem<String>(
                value: 'export',
                child: Row(
                  children: <Widget>[
                    Icon(Icons.upload_outlined),
                    SizedBox(width: 8),
                    FitText('导出角色'),
                  ],
                ),
              ),
              const PopupMenuItem<String>(
                value: 'import',
                child: Row(
                  children: <Widget>[
                    Icon(Icons.download_outlined),
                    SizedBox(width: 8),
                    FitText('导入角色'),
                  ],
                ),
              ),
            ],
          ),
          IconButton(
            onPressed: _save,
            icon: const Icon(Icons.save_outlined),
            tooltip: widget.saveLabel,
          ),
        ],
      ),
      body: TaEditorForm(
        ta: widget.ta,
        formController: _form,
        imagePicker: const DefaultImagePickCapability(),
        bgmSizeLimitUnlocked:
            widget.controller?.settings.bgmSizeLimitUnlocked ?? false,
      ),
      floatingActionButton: AppEditorFab(
        onPressed: _save,
        icon: const Icon(Icons.save_outlined),
        label: FitText(widget.saveLabel),
      ),
      ),
    );
  }
}
