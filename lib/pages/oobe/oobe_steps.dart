import 'package:flutter/material.dart';

import 'package:dna/theme/tokens.dart';

import '../../services/llm_provider.dart';
import 'package:dna/widgets/fit_text.dart';

/// OOBE 引导流程中的子步骤 Widget 与导航 Intent，从 oobe_page 拆分而来。

/// 引导总步数：欢迎 → API 配置 → 模型选择 → 社区。
///
/// 社区这一步原先只存在于社区自己的「服务器地址」兜底页里，用户装完 App 还得再进社区
/// 单独配一次；现在并入主引导，默认值与社区内完全一致（官方地址），连不上可以勾选忽略
/// 继续 —— 与 API Key 那一步同一套交互。
const int kOobeStepCount = 4;

class StepTracker extends StatelessWidget {
  const StepTracker({super.key, required this.stepIndex});

  final int stepIndex;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: List<Widget>.generate(kOobeStepCount, (int index) {
        final bool isActive = index <= stepIndex;
        return Expanded(
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            margin: EdgeInsets.only(right: index == kOobeStepCount - 1 ? 0 : 8),
            height: 6,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              color: isActive
                  ? Theme.of(context).colorScheme.primary
                  : Theme.of(context).colorScheme.primary.withValues(alpha: 0.2),
            ),
          ),
        );
      }),
    );
  }
}

class WelcomeStep extends StatelessWidget {
  const WelcomeStep({super.key});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            FitText('与汝共奏', style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 12),
            FitText('将通过 $kOobeStepCount 个步骤完成首次配置。',
                style: Theme.of(context).textTheme.bodyLarge),
            const SizedBox(height: 16),
            const StepBullet(text: '选择服务商、填写 API Key，并完成连接检测'),
            const StepBullet(text: '自动拉取模型或手动添加自定义模型'),
            const StepBullet(text: '完成后即可进入主界面'),
            const Spacer(),
            FitText(
              '提示：方向键或滑动手势可在步骤之间移动。',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
        ),
      ),
    );
  }
}

class StepBullet extends StatelessWidget {
  const StepBullet({super.key, required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Container(
            width: 8,
            height: 8,
            margin: const EdgeInsets.only(top: 8, right: 12),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primary,
              borderRadius: BorderRadius.circular(999),
            ),
          ),
          Expanded(child: FitText(text)),
        ],
      ),
    );
  }
}

class ApiStep extends StatelessWidget {
  const ApiStep({
    super.key,
    required this.providers,
    required this.selectedProviderId,
    required this.baseUrlController,
    required this.apiKeyController,
    required this.baseUrlHint,
    required this.checkingApi,
    required this.apiValidated,
    required this.apiError,
    required this.ignoreApiIssue,
    required this.onProviderChanged,
    required this.onIgnoreChanged,
    required this.onCheck,
    required this.onInputChanged,
    this.hideBaseUrl = false,
  });

  final List<LlmProvider> providers;
  final String selectedProviderId;
  final TextEditingController baseUrlController;
  final TextEditingController apiKeyController;
  final String baseUrlHint;
  final bool checkingApi;
  final bool apiValidated;
  final String? apiError;
  final bool ignoreApiIssue;
  final ValueChanged<String> onProviderChanged;
  final ValueChanged<bool> onIgnoreChanged;
  final VoidCallback onCheck;
  final VoidCallback onInputChanged;
  final bool hideBaseUrl;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: ListView(
          children: <Widget>[
            FitText('步骤 1/$kOobeStepCount · API 配置',
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            FitText('服务商', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: AppWeight.medium)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: providers.map((LlmProvider p) {
                final bool selected = p.id == selectedProviderId;
                return ChoiceChip(
                  label: FitText(p.label),
                  selected: selected,
                  onSelected: (_) => onProviderChanged(p.id),
                );
              }).toList(),
            ),
            const SizedBox(height: 16),
            const Divider(),
            const SizedBox(height: 12),
            if (!hideBaseUrl)
              TextField(
                controller: baseUrlController,
                decoration: InputDecoration(
                  labelText: 'Base URL',
                  hintText: baseUrlHint,
                ),
                onChanged: (_) => onInputChanged(),
              ),
            if (!hideBaseUrl) const SizedBox(height: 12),
            TextField(
              controller: apiKeyController,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'API Key'),
              onChanged: (_) => onInputChanged(),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: checkingApi ? null : onCheck,
              icon: checkingApi
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.verified_outlined),
              label: FitText(checkingApi ? '检测中...' : '保存并检测 API'),
            ),
            if (apiValidated) ...<Widget>[
              const SizedBox(height: 8),
              FitText(
                '连接验证成功。',
                style: TextStyle(color: Colors.green.shade700),
              ),
            ],
            if (apiError != null) ...<Widget>[
              const SizedBox(height: 8),
              FitText(
                apiError!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
              CheckboxListTile(
                value: ignoreApiIssue,
                title: const FitText('忽略此问题'),
                subtitle: const FitText('勾选后允许跳过本次检测并进入下一步。'),
                controlAffinity: ListTileControlAffinity.leading,
                onChanged: (bool? value) => onIgnoreChanged(value ?? false),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class ModelStep extends StatelessWidget {
  const ModelStep({
    super.key,
    required this.loadingModels,
    required this.models,
    required this.modelsError,
    required this.selectedModel,
    required this.onReload,
    required this.onSelect,
    required this.onCustom,
  });

  final bool loadingModels;
  final List<String> models;
  final String? modelsError;
  final String? selectedModel;
  final VoidCallback onReload;
  final ValueChanged<String?> onSelect;
  final VoidCallback onCustom;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            FitText('步骤 2/$kOobeStepCount · 模型选择',
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            Row(
              children: <Widget>[
                FilledButton.tonalIcon(
                  onPressed: loadingModels ? null : onReload,
                  icon: loadingModels
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.refresh),
                  label: FitText(loadingModels ? '加载中...' : '刷新模型列表'),
                ),
                const SizedBox(width: 12),
                OutlinedButton.icon(
                  onPressed: onCustom,
                  icon: const Icon(Icons.edit),
                  label: const FitText('自定义模型'),
                ),
              ],
            ),
            if (modelsError != null) ...<Widget>[
              const SizedBox(height: 8),
              FitText(
                modelsError!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            const SizedBox(height: 12),
            Expanded(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 300),
                child: loadingModels
                    ? const Center(child: CircularProgressIndicator())
                    : models.isEmpty
                        ? const Center(child: FitText('暂无可用模型，请先刷新或使用自定义模型。'))
                        : ListView.builder(
                            itemCount: models.length,
                            itemBuilder: (BuildContext context, int index) {
                              final String model = models[index];
                              final bool selected = model == selectedModel;
                              return ListTile(
                                leading: Icon(
                                  selected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                                ),
                                title: FitText(model),
                                onTap: () => onSelect(model),
                              );
                            },
                          ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 步骤 4：社区（DNAISLAND 服务器地址）。
///
/// 与社区内部的「服务器地址」设置共用同一套校验（`ApiClient.validateServer`）和同一个
/// 默认值（官方地址），所以这里填好的和进社区后看到的完全一致 —— 用户不用再单独配一次。
/// 连不上时可以勾选「忽略此问题」继续，与 API Key 那一步同一套交互，之后随时能在
/// 「社区 → 服务器地址」里改。
class CommunityStep extends StatelessWidget {
  const CommunityStep({
    super.key,
    required this.urlController,
    required this.defaultUrl,
    required this.checking,
    required this.validated,
    required this.error,
    required this.ignoreIssue,
    required this.onIgnoreChanged,
    required this.onCheck,
    required this.onInputChanged,
    required this.onUseDefault,
  });

  final TextEditingController urlController;
  final String defaultUrl;
  final bool checking;
  final bool validated;
  final String? error;
  final bool ignoreIssue;
  final ValueChanged<bool> onIgnoreChanged;
  final VoidCallback onCheck;
  final VoidCallback onInputChanged;
  final VoidCallback onUseDefault;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: ListView(
          children: <Widget>[
            FitText('步骤 $kOobeStepCount/$kOobeStepCount · 社区',
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            FitText(
              'DNAISLAND 社区：官方服务器地址已经填好，直接下一步即可。'
              '连不上可以先跳过，之后在「社区 → 服务器地址」里随时修改。',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: urlController,
              decoration: InputDecoration(
                labelText: '社区服务器地址',
                hintText: defaultUrl,
              ),
              keyboardType: TextInputType.url,
              onChanged: (_) => onInputChanged(),
            ),
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: checking ? null : onUseDefault,
              icon: const Icon(Icons.public, size: 18),
              label: const FitText('使用官方服务器'),
            ),
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: checking ? null : onCheck,
              icon: checking
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.verified_outlined),
              label: FitText(checking ? '检测中...' : '保存并检测社区'),
            ),
            if (validated) ...<Widget>[
              const SizedBox(height: 8),
              FitText('社区连接验证成功。',
                  style: TextStyle(color: Colors.green.shade700)),
            ],
            if (error != null) ...<Widget>[
              const SizedBox(height: 8),
              FitText(error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error)),
              CheckboxListTile(
                value: ignoreIssue,
                title: const FitText('忽略此问题'),
                subtitle: const FitText('勾选后允许跳过本次检测并完成引导。'),
                controlAffinity: ListTileControlAffinity.leading,
                onChanged: (bool? value) => onIgnoreChanged(value ?? false),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class OobeFooter extends StatelessWidget {
  const OobeFooter({
    super.key,
    required this.stepIndex,
    required this.canGoNext,
    required this.onBack,
    required this.onNext,
    required this.ignoreIssue,
  });

  final int stepIndex;
  final bool canGoNext;
  final VoidCallback onBack;
  final VoidCallback onNext;

  /// 当前步的检测失败但用户勾了「忽略此问题」。
  final bool ignoreIssue;

  @override
  Widget build(BuildContext context) {
    final String nextLabel;
    if (stepIndex == 0) {
      nextLabel = '开始';
    } else if (stepIndex >= kOobeStepCount - 1) {
      // 最后一步（社区）：连不上时同样允许忽略并完成引导。
      nextLabel = ignoreIssue ? '忽略并继续' : '完成';
    } else {
      nextLabel = ignoreIssue ? '忽略并继续' : '下一步';
    }

    return Row(
      children: <Widget>[
        OutlinedButton(
          onPressed: stepIndex == 0 ? null : onBack,
          child: const FitText('上一步'),
        ),
        const Spacer(),
        FilledButton(
          onPressed: canGoNext ? onNext : null,
          child: FitText(nextLabel),
        ),
      ],
    );
  }
}

class NextIntent extends Intent {
  const NextIntent();
}

class BackIntent extends Intent {
  const BackIntent();
}
