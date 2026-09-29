// ignore_for_file: deprecated_member_use
import 'package:flutter/material.dart';

import 'package:dna/state/app_controller.dart';
import 'package:dna/widgets/fit_text.dart';

import 'model_edit_page.dart';
import 'model_list_body.dart';

/// 模型预设列表独立管理页。
///
/// 列表本身已抽到 [ModelListBody],与 AI 服务 `⋮` 页面的「模型」tab 共用。
class ModelListPage extends StatelessWidget {
  const ModelListPage({super.key, required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const FitText('模型预设管理'),
        actions: <Widget>[
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: '添加模型预设',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => ModelEditPage(controller: controller),
                ),
              );
            },
          ),
        ],
      ),
      body: ModelListBody(controller: controller),
      floatingActionButton: AddModelFab(controller: controller),
    );
  }
}
