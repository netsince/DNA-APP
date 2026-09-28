// ignore_for_file: deprecated_member_use
import 'package:flutter/material.dart';

import 'package:dna/theme/tokens.dart';
import 'package:dna/widgets/fit_text.dart';
import 'package:dna/widgets/setting_section.dart';

import '../../state/app_controller.dart';
import 'models/model_list_body.dart';
import 'models/provider_list_body.dart';
import 'sampler_settings_page.dart';

/// AI 服务「⋮」页 —— 标题下的分栏设置页。
///
/// ## 分栏按模式显隐
///
/// * **精简模式**:只显示「其他」(开关 + 采样参数);
/// * **完整模式**:显示「模型」「服务商」「其他」三栏。
///
/// 「其他」两栏**两种模式都显示** —— 否则完整模式进去后就再也切不回
/// 精简模式,且采样参数在完整模式下无法调整。
class AiServiceMorePage extends StatefulWidget {
  const AiServiceMorePage({super.key, required this.controller});

  final AppController controller;

  @override
  State<AiServiceMorePage> createState() => _AiServiceMorePageState();
}

class _AiServiceMorePageState extends State<AiServiceMorePage>
    with SingleTickerProviderStateMixin {
  /// 分栏控制器固定为 3 栏(完整模式的最大值)。
  ///
  /// **不能按模式动态改变长度**:`TabController.length` 是不可变的,
  /// 长度变化必须重建控制器,而重建会让正在显示的 `TabBarView` 抛索引越界。
  /// 因此这里始终建 3 栏,靠 `_visibleTabCount` 决定**显示**几栏。
  late final TabController _tabs;

  /// 当前模式下可见的分栏数:精简模式 1(只有「其他」),完整模式 3。
  int get _visibleTabCount =>
      widget.controller.settings.simpleModelMode ? 1 : 3;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  /// 精简模式只有「其他」一栏时,把 tab 索引钉在「其他」(index 2)。
  ///
  /// 否则从「模型」栏切到精简模式后,索引仍停在 0,
  /// 而界面此时只显示「其他」栏 → 内容与标题对不上。
  void _syncTabIndexToMode() {
    final int want = _visibleTabCount == 1 ? 2 : _tabs.index;
    if (_tabs.index != want) {
      _tabs.index = want;
    }
  }

  @override
  Widget build(BuildContext context) {
    // 监听 controller:在「其他」栏切换简易模式后,分栏栏与本页结构
    // 必须**立刻**跟着变,而不是等用户退出去再进来。
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (BuildContext context, Widget? _) {
        final int visible = _visibleTabCount;
        _syncTabIndexToMode();

        return Scaffold(
          appBar: AppBar(
            title: const FitText('AI 服务设置'),
            bottom: visible > 1
                ? TabBar(
                    controller: _tabs,
                    tabs: const <Widget>[
                      Tab(text: '模型'),
                      Tab(text: '服务商'),
                      Tab(text: '其他'),
                    ],
                  )
                : null,
          ),
          body: visible == 1
              ? _otherTab()
              : TabBarView(
                  controller: _tabs,
                  children: <Widget>[
                    ModelListBody(controller: widget.controller),
                    ProviderListBody(controller: widget.controller),
                    _otherTab(),
                  ],
                ),
          // 「添加」按钮跟随分栏:模型栏加模型,服务商栏加服务商,其他栏不加。
          floatingActionButton: visible == 1
              ? null
              : AnimatedBuilder(
                  animation: _tabs,
                  builder: (BuildContext context, Widget? _) {
                    if (_tabs.index == 0) {
                      return AddModelFab(controller: widget.controller);
                    }
                    if (_tabs.index == 1) {
                      return AddProviderFab(controller: widget.controller);
                    }
                    return const SizedBox.shrink();
                  },
                ),
        );
      },
    );
  }

  /// 「其他」栏:简易模式开关 + 全局采样参数。
  Widget _otherTab() {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (BuildContext context, Widget? _) {
        final bool isSimple = widget.controller.settings.simpleModelMode;
        return ListView(
          padding: AppInsets.page,
          children: <Widget>[
            SettingSection(
              icon: Icons.tune,
              title: '界面模式',
              children: <Widget>[
                SettingSwitch(
                  title: '新手简易模式',
                  subtitle: isSimple
                      ? '只显示连接与模型选择'
                      : '显示模型预设与服务商管理',
                  value: isSimple,
                  onChanged: (bool v) =>
                      widget.controller.toggleSimpleModelMode(v),
                ),
              ],
            ),
            AppSpacing.hLg,
            SettingSection(
              icon: Icons.speed,
              title: '生成参数',
              children: <Widget>[
                SettingTile(
                  icon: Icons.tune,
                  title: '全局默认采样参数',
                  subtitle: '场景预设与采样、防复读',
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) =>
                          SamplerSettingsPage(controller: widget.controller),
                    ),
                  ),
                ),
              ],
            ),
          ],
        );
      },
    );
  }
}
