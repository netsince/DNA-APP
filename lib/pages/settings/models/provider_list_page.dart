// ignore_for_file: deprecated_member_use
import 'package:flutter/material.dart';

import 'package:dna/state/app_controller.dart';
import 'package:dna/widgets/fit_text.dart';

import 'provider_edit_page.dart';
import 'provider_list_body.dart';

/// 服务商列表独立管理页。
///
/// 列表本身已抽到 [ProviderListBody],与 AI 服务 `⋮` 页面的「服务商」tab 共用。
class ProviderListPage extends StatelessWidget {
  const ProviderListPage({super.key, required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const FitText('服务商管理'),
        actions: <Widget>[
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: '添加服务商',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => ProviderEditPage(controller: controller),
                ),
              );
            },
          ),
        ],
      ),
      body: ProviderListBody(controller: controller),
      floatingActionButton: AddProviderFab(controller: controller),
    );
  }
}
