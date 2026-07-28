import 'package:flutter/material.dart';

/// OOBE 引导流程中的子步骤 Widget 与导航 Intent，从 oobe_page 拆分而来。

class StepTracker extends StatelessWidget {
  const StepTracker({super.key, required this.stepIndex});

  final int stepIndex;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: List<Widget>.generate(3, (int index) {
        final bool isActive = index <= stepIndex;
        return Expanded(
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            margin: EdgeInsets.only(right: index == 2 ? 0 : 8),
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
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text('与汝共奏', style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 12),
            Text('将通过 3 个步骤完成首次配置。', style: Theme.of(context).textTheme.bodyLarge),
            const SizedBox(height: 16),
            const StepBullet(text: '配置 API Base URL 与 API Key，并完成连接检测'),
            const StepBullet(text: '自动拉取模型或手动添加自定义模型'),
            const StepBullet(text: '完成后即可进入主界面'),
            const Spacer(),
            Text(
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
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Container(
            width: 8,
            height: 8,
            margin: const EdgeInsets.only(top: 6, right: 10),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primary,
              borderRadius: BorderRadius.circular(999),
            ),
          ),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }
}

class ApiStep extends StatelessWidget {
  const ApiStep({
    super.key,
    required this.baseUrlController,
    required this.apiKeyController,
    required this.checkingApi,
    required this.apiValidated,
    required this.apiError,
    required this.ignoreApiIssue,
    required this.onIgnoreChanged,
    required this.onCheck,
    required this.onInputChanged,
  });

  final TextEditingController baseUrlController;
  final TextEditingController apiKeyController;
  final bool checkingApi;
  final bool apiValidated;
  final String? apiError;
  final bool ignoreApiIssue;
  final ValueChanged<bool> onIgnoreChanged;
  final VoidCallback onCheck;
  final VoidCallback onInputChanged;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: ListView(
          children: <Widget>[
            Text('步骤 1/3 · API 配置', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            TextField(
              controller: baseUrlController,
              decoration: const InputDecoration(
                labelText: 'Base URL',
                hintText: 'https://api.openai.com/v1',
              ),
              onChanged: (_) => onInputChanged(),
            ),
            const SizedBox(height: 12),
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
              label: Text(checkingApi ? '检测中...' : '保存并检测 API'),
            ),
            if (apiValidated) ...<Widget>[
              const SizedBox(height: 10),
              Text(
                '连接验证成功。',
                style: TextStyle(color: Colors.green.shade700),
              ),
            ],
            if (apiError != null) ...<Widget>[
              const SizedBox(height: 10),
              Text(
                apiError!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
              CheckboxListTile(
                value: ignoreApiIssue,
                title: const Text('忽略此问题'),
                subtitle: const Text('勾选后允许跳过本次检测并进入下一步。'),
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
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text('步骤 2/3 · 模型选择', style: Theme.of(context).textTheme.titleLarge),
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
                  label: Text(loadingModels ? '加载中...' : '刷新模型列表'),
                ),
                const SizedBox(width: 12),
                OutlinedButton.icon(
                  onPressed: onCustom,
                  icon: const Icon(Icons.edit),
                  label: const Text('自定义模型'),
                ),
              ],
            ),
            if (modelsError != null) ...<Widget>[
              const SizedBox(height: 10),
              Text(
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
                        ? const Center(child: Text('暂无可用模型，请先刷新或使用自定义模型。'))
                        : ListView.builder(
                            itemCount: models.length,
                            itemBuilder: (BuildContext context, int index) {
                              final String model = models[index];
                              final bool selected = model == selectedModel;
                              return ListTile(
                                leading: Icon(
                                  selected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                                ),
                                title: Text(model),
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

class OobeFooter extends StatelessWidget {
  const OobeFooter({
    super.key,
    required this.stepIndex,
    required this.canGoNext,
    required this.onBack,
    required this.onNext,
    required this.ignoreApiIssue,
  });

  final int stepIndex;
  final bool canGoNext;
  final VoidCallback onBack;
  final VoidCallback onNext;
  final bool ignoreApiIssue;

  @override
  Widget build(BuildContext context) {
    final String nextLabel;
    if (stepIndex == 0) {
      nextLabel = '开始';
    } else if (stepIndex == 1) {
      nextLabel = ignoreApiIssue ? '忽略并继续' : '下一步';
    } else {
      nextLabel = '完成';
    }

    return Row(
      children: <Widget>[
        OutlinedButton(
          onPressed: stepIndex == 0 ? null : onBack,
          child: const Text('上一步'),
        ),
        const Spacer(),
        FilledButton(
          onPressed: canGoNext ? onNext : null,
          child: Text(nextLabel),
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
