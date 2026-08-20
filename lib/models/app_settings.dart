import '../utils/message_processor.dart';
import 'llm_model_config.dart';
import 'llm_provider_config.dart';
import 'prompt_strategy.dart';
import 'quick_reply.dart';
import 'voice_models.dart';

class AppSettings {
  const AppSettings({
    required this.provider,
    required this.themeMode,
    required this.baseUrl,
    required this.apiKey,
    required this.selectedModel,
    required this.completedOobe,
    required this.autoSummaryPrompt,
    required this.summaryTurnInterval,
    this.summaryWordThreshold = 6000,
    required this.retrySequential,
    required this.inspirationIncludeSummary,
    required this.promptStrategy,
    required this.requireAuthForArchive,
    required this.requireAuthForApp,
    required this.requireNameToDelete,
    required this.allowDeleteMessage,
    required this.autoBackup,
    required this.showSplashAnimation,
    required this.showBottomNav,
    this.showTokenDashboard = false,
    this.enableForking = false,
    this.enableCommandMacros = true,
    this.enableRegexReplacement = true,
    this.regexRules = const <RegexRule>[],
    required this.appIcon,
    required this.snackDurationMs,
    required this.sherpaModelSource,
    this.sherpaCustomBaseUrl,
    required this.sherpaModelReady,
    this.sherpaModelPath,
    required this.selectedVoiceModelId,
    required this.accentMode,
    this.customAccentColor,
    required this.voiceInputEnabled,
    required this.ttsEnabled,
    this.ttsGlobalSeed,
    this.ttsQuoteOnly = true,
    this.showParenButton = true,
    this.showMessageAvatar = true,
    this.showMessageRetry = true,
    this.showMessageCopy = true,
    this.showMessageContinue = true,
    this.enterToSend = true,
    required this.chatMaskStrength,
    this.chatBubbleOpacity = 100,
    this.halfScreenChat = false,
    this.maxContextMessages = 120,
    this.maxContextTokens = 8000,
    this.temperature = 0.7,
    this.frequencyPenalty = 0.0,
    this.presencePenalty = 0.0,
    this.topP = 1.0,
    this.topK = 0.0,
    this.minP = 0.0,
    this.repetitionPenalty = 1.0,
    this.repetitionPenaltySlope = 0.0,
    this.loreStickyRounds = 3,
    this.loreMaxEntries = 8,
    this.loreBudgetTokens = 0,
    this.quickReplies = const <QuickReply>[],
    this.deepseekThinkingEnabled = true,
    this.deepseekThinkingEffort = 'high',
    this.simpleModelMode = true,
    this.activeModelId = LlmModelConfig.defaultId,
    this.providers = const <LlmProviderConfig>[],
    this.models = const <LlmModelConfig>[],
  });

  factory AppSettings.empty() {
    return AppSettings(
      provider: 'openai',
      themeMode: 'system',
      baseUrl: '',
      apiKey: '',
      selectedModel: '',
      completedOobe: false,
      autoSummaryPrompt: true,
      summaryTurnInterval: 200,
      summaryWordThreshold: 6000,
      retrySequential: false,
      inspirationIncludeSummary: false,
      promptStrategy: PromptStrategy.defaults(),
      requireAuthForArchive: false,
      requireAuthForApp: false,
      requireNameToDelete: true,
      allowDeleteMessage: false,
      autoBackup: true,
      showSplashAnimation: true,
      showBottomNav: false,
      showTokenDashboard: false,
      enableForking: false,
      enableCommandMacros: true,
      enableRegexReplacement: true,
      regexRules: <RegexRule>[],
      appIcon: 'default',
      snackDurationMs: 1000,
      sherpaModelSource: 'auto',
      sherpaCustomBaseUrl: null,
      sherpaModelReady: false,
      sherpaModelPath: null,
      selectedVoiceModelId: kVoiceModelDefaultId,
      accentMode: 'auto',
      customAccentColor: null,
      voiceInputEnabled: false,
      ttsEnabled: false,
      ttsGlobalSeed: null,
      ttsQuoteOnly: true,
      showParenButton: true,
      showMessageAvatar: true,
      showMessageRetry: true,
      showMessageCopy: true,
      showMessageContinue: true,
      enterToSend: true,
      chatMaskStrength: 75,
      chatBubbleOpacity: 100,
      halfScreenChat: false,
      maxContextMessages: 120,
      maxContextTokens: 8000,
      temperature: 0.7,
      frequencyPenalty: 0.0,
      presencePenalty: 0.0,
      topP: 1.0,
      topK: 0.0,
      minP: 0.0,
      repetitionPenalty: 1.0,
      repetitionPenaltySlope: 0.0,
      loreStickyRounds: 3,
      loreMaxEntries: 8,
      loreBudgetTokens: 0,
      quickReplies: const <QuickReply>[],
      deepseekThinkingEnabled: true,
      deepseekThinkingEffort: 'high',
      simpleModelMode: true,
      activeModelId: LlmModelConfig.defaultId,
      providers: <LlmProviderConfig>[LlmProviderConfig.defaultConfig()],
      models: <LlmModelConfig>[LlmModelConfig.defaultConfig()],
    );
  }

  final String provider;
  final String themeMode;
  final String baseUrl;
  final String apiKey;
  final String selectedModel;
  final bool completedOobe;
  final bool autoSummaryPrompt;
  final int summaryTurnInterval;

  /// 距上次摘要后新增内容的字符数阈值（0 表示禁用），用于按词数触发摘要，
  /// 与 [summaryTurnInterval] 的消息数触发构成「双触发」。默认 6000。
  final int summaryWordThreshold;
  final bool retrySequential;
  final bool inspirationIncludeSummary;
  final PromptStrategy promptStrategy;
  final bool requireAuthForArchive;
  final bool requireAuthForApp;

  /// 删除前是否强制输入完整名称。
  /// 开启时：输入对应名称（角色名 / 世界名 / 对话角色名 / 群成员名）→ 5 秒滚动确认（可反悔）。
  /// 关闭时：改为长按右下角按钮 5 秒删除（滚动同步进行）。对四类可归档实体统一生效。
  final bool requireNameToDelete;

  /// 是否允许在聊天页删除单条对话消息（长按/右键菜单显示「删除本条」）。
  final bool allowDeleteMessage;

  /// 是否开启每日自动备份（默认开启）。开启后每天首次进入应用时在软件外部
  /// 静默生成一份全量备份，保留最近 5 天，全程无提示。
  final bool autoBackup;

  final bool showSplashAnimation;

  /// 是否在主页等页面底部显示「主页 / 群聊 / 我家 / 世界」导航栏。默认关闭。
  final bool showBottomNav;

  /// 是否在聊天界面显示上下文 Token 实时仪表盘（当前上下文占用 vs 预算）。
  /// 默认关闭，可在「外观与体验」中开启。
  final bool showTokenDashboard;

  /// 是否启用「从此处分叉」功能。开启后，在聊天页右键对方的气泡会显示
  /// 「从此处分叉」入口，可将该处之后的内容另起一个新会话继续。
  /// 默认关闭，可在「对话与策略」中开启。
  final bool enableForking;

  /// 是否启用命令宏（{{char}}/{{user}}/{{roll}}/{{random}} 等）。默认启用，可禁用。
  final bool enableCommandMacros;

  /// 是否启用正则替换。默认启用，可禁用。
  final bool enableRegexReplacement;

  /// 正则替换规则列表。
  final List<RegexRule> regexRules;

  final String appIcon;
  final int snackDurationMs;

  /// 语音识别模型来源偏好：'auto' | 'modelscope' | 'github' | 'custom'。
  /// 'auto' 才会探测并回退；其余为严格单选，失败直接报错。
  final String sherpaModelSource;

  /// 自定义模型服务器根地址（source 为 'custom' 时生效）。
  final String? sherpaCustomBaseUrl;

  /// 模型是否已下载就绪（本地存在可用模型）。
  final bool sherpaModelReady;

  /// 已下载模型的本地目录路径。
  final String? sherpaModelPath;

  /// 当前选中的语音识别模型 id。
  final String selectedVoiceModelId;

  /// 强调色（莫奈取色）模式：'auto' 跟随系统/角色卡；'custom' 使用自定义色。
  final String accentMode;

  /// 自定义强调色（ARGB 整数），仅当 [accentMode] 为 'custom' 时生效。
  final int? customAccentColor;

  /// 是否启用离线语音输入（STT）。关闭时聊天输入框不显示麦克风按钮。
  final bool voiceInputEnabled;

  /// 是否启用端侧语音合成（TTS）。
  final bool ttsEnabled;

  /// 全局 TTS seed：角色未单独设置 seed 时使用（保证音色稳定）。
  final int? ttsGlobalSeed;

  /// 合成时是否「引号内容优先」：开启时优先只读引号内的内容，
  /// 无引号内容则读全文；关闭时始终读全文。两者都永远排除括号内容。
  final bool ttsQuoteOnly;

  /// 聊天输入框旁是否显示「添加括号」按钮（点击在末尾追加（）并把光标置于中间）。
  final bool showParenButton;

  /// 对方气泡左上角是否显示角色头像（配合 TTS 朗读按钮，群聊中用于区分发言者）。
  final bool showMessageAvatar;

  /// 对方气泡上是否显示「重说」快捷按钮（仅最近一条 AI 消息显示）。
  final bool showMessageRetry;

  /// 对方气泡上是否显示「复制」快捷按钮。
  final bool showMessageCopy;

  /// 对方气泡上是否显示「继续说」快捷按钮（仅最近一条 AI 消息显示）。
  final bool showMessageContinue;

  /// 回车键行为：true = 回车发送、Shift+回车换行；false = 回车换行、Shift+回车发送。
  final bool enterToSend;

  /// 聊天界面背景遮罩强度，范围 0~100。
  /// 0 表示完全不遮罩（背景完全透出），100 表示遮罩最强（背景几乎被盖住）。
  final int chatMaskStrength;

  /// 聊天消息气泡（对话框）不透明度，范围 0~100。
  /// 100 完全不透明（默认）；数值越小气泡越透明、背景透出越多。
  final int chatBubbleOpacity;

  /// 半屏聊天：开启后聊天记录只显示在页面下半部分，
  /// 上半部分留空以便查看背景，两者之间以渐变过渡衔接。
  final bool halfScreenChat;

  /// 单次请求最多携带的历史消息条数（含用户与AI），0 表示不限制。
  /// 用于防止长对话超出模型上下文窗口导致模型退化（复读、答非所问）。
  final int maxContextMessages;

  /// 单次请求历史消息的 token 预算（精确逐条裁剪），0 表示不限制。
  /// 用当前模型的 tokenizer 估算，从最新往最老逐条累积，超出即裁掉更早消息。
  final int maxContextTokens;

  /// 采样温度。值越高越随机，越低越确定。默认 0.7。
  final double temperature;

  /// 频率惩罚（frequency_penalty）。越大越抑制重复出现过的词语，缓解复读。0~2。
  final double frequencyPenalty;

  /// 存在惩罚（presence_penalty）。越大越鼓励谈论新话题，缓解复读。0~2。
  final double presencePenalty;

  /// 核采样（top_p）：只从累积概率达到该阈值的词中采样。1.0 表示关闭。
  final double topP;

  /// Top-K 采样：只从概率最高的前 K 个词中采样。0 表示关闭。
  final double topK;

  /// 最小概率（min_p）：过滤掉概率低于「最高概率 × min_p」的词。0 表示关闭。
  final double minP;

  /// 重复惩罚（repetition_penalty）：对重复出现过的词施加惩罚。1.0 表示关闭。
  final double repetitionPenalty;

  /// 重复惩罚斜率（repetition_penalty_slope）：对最近重复词的额外加权。0 表示关闭。
  final double repetitionPenaltySlope;

  /// 世界词条 sticky 轮数：词条被激活后持续保留的轮数，0 表示禁用。
  final int loreStickyRounds;

  /// 世界词条注入条数上限：一次请求最多注入多少条命中词条，0 表示不限。
  final int loreMaxEntries;

  /// 世界词条注入 token 预算：命中词条描述累计 token 超过即裁剪，0 表示不限。
  final int loreBudgetTokens;

  /// 快速回复列表：聊天输入栏上方的一键发送按钮。支持宏与分组。
  final List<QuickReply> quickReplies;

  /// DeepSeek 思考模式开关（仅 DeepSeek 服务商生效）。
  /// 开启时请求携带 `{"thinking": {"type": "enabled"}}`，关闭时携带 `disabled`。
  /// 默认开启（与 DeepSeek 官方默认行为一致）。
  final bool deepseekThinkingEnabled;

  /// DeepSeek 思考强度：'low' / 'high' / 'max'（仅 DeepSeek 服务商生效）。
  /// 通过请求的 `reasoning_effort` 字段传递，默认 'high'。
  final String deepseekThinkingEffort;

  /// 简易模式开关（新手模式）：true 时仅展示原版单页面表单并操作默认实体；false 时展示多服务商与多模型列表。
  final bool simpleModelMode;

  /// 当前激活生效的模型 ID（默认指向 DNAAPP.MODELSETTING.MODEL.DEFAULT）。
  final String activeModelId;

  /// 服务商配置列表。
  final List<LlmProviderConfig> providers;

  /// 模型配置列表。
  final List<LlmModelConfig> models;

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'provider': provider,
      'themeMode': themeMode,
      'baseUrl': baseUrl,
      'apiKey': apiKey,
      'selectedModel': selectedModel,
      'completedOobe': completedOobe,
      'autoSummaryPrompt': autoSummaryPrompt,
      'summaryTurnInterval': summaryTurnInterval,
      'summaryWordThreshold': summaryWordThreshold,
      'retrySequential': retrySequential,
      'inspirationIncludeSummary': inspirationIncludeSummary,
      'promptStrategy': promptStrategy.toJson(),
      'requireAuthForArchive': requireAuthForArchive,
      'requireAuthForApp': requireAuthForApp,
      'requireNameToDelete': requireNameToDelete,
      'allowDeleteMessage': allowDeleteMessage,
      'autoBackup': autoBackup,
      'showSplashAnimation': showSplashAnimation,
      'showBottomNav': showBottomNav,
      'showTokenDashboard': showTokenDashboard,
      'enableForking': enableForking,
      'enableCommandMacros': enableCommandMacros,
      'enableRegexReplacement': enableRegexReplacement,
      'regexRules': regexRules.map((RegexRule r) => r.toJson()).toList(),
      'appIcon': appIcon,
      'snackDurationMs': snackDurationMs,
      'sherpaModelSource': sherpaModelSource,
      'sherpaCustomBaseUrl': sherpaCustomBaseUrl,
      'sherpaModelReady': sherpaModelReady,
      'sherpaModelPath': sherpaModelPath,
      'selectedVoiceModelId': selectedVoiceModelId,
      'accentMode': accentMode,
      'customAccentColor': customAccentColor,
      'voiceInputEnabled': voiceInputEnabled,
      'ttsEnabled': ttsEnabled,
      'ttsGlobalSeed': ttsGlobalSeed,
      'ttsQuoteOnly': ttsQuoteOnly,
      'showParenButton': showParenButton,
      'showMessageAvatar': showMessageAvatar,
      'showMessageRetry': showMessageRetry,
      'showMessageCopy': showMessageCopy,
      'showMessageContinue': showMessageContinue,
      'enterToSend': enterToSend,
      'chatMaskStrength': chatMaskStrength,
      'chatBubbleOpacity': chatBubbleOpacity,
      'halfScreenChat': halfScreenChat,
      'maxContextMessages': maxContextMessages,
      'maxContextTokens': maxContextTokens,
      'temperature': temperature,
      'frequencyPenalty': frequencyPenalty,
      'presencePenalty': presencePenalty,
      'topP': topP,
      'topK': topK,
      'minP': minP,
      'repetitionPenalty': repetitionPenalty,
      'repetitionPenaltySlope': repetitionPenaltySlope,
      'loreStickyRounds': loreStickyRounds,
      'loreMaxEntries': loreMaxEntries,
      'loreBudgetTokens': loreBudgetTokens,
      'quickReplies': quickReplies
          .map((QuickReply r) => r.toJson())
          .toList(),
      'deepseekThinkingEnabled': deepseekThinkingEnabled,
      'deepseekThinkingEffort': deepseekThinkingEffort,
      'simpleModelMode': simpleModelMode,
      'activeModelId': activeModelId,
      'providers': providers.map((LlmProviderConfig p) => p.toJson()).toList(),
      'models': models.map((LlmModelConfig m) => m.toJson()).toList(),
    };
  }

  factory AppSettings.fromJson(Map<String, dynamic> json) {
    final PromptStrategy promptStrategy = json['promptStrategy'] is Map
        ? PromptStrategy.fromJson(
            (json['promptStrategy'] as Map).cast<String, dynamic>(),
          )
        : PromptStrategy.defaults();
    return AppSettings(
      provider: (json['provider'] as String?) ?? 'openai',
      themeMode: (json['themeMode'] as String?) ?? 'system',
      baseUrl: (json['baseUrl'] as String?) ?? '',
      apiKey: (json['apiKey'] as String?) ?? '',
      selectedModel: (json['selectedModel'] as String?) ?? '',
      completedOobe: (json['completedOobe'] as bool?) ?? false,
      autoSummaryPrompt: (json['autoSummaryPrompt'] as bool?) ?? true,
      summaryTurnInterval: (json['summaryTurnInterval'] as int?) ?? 200,
      summaryWordThreshold: (json['summaryWordThreshold'] as int?) ?? 6000,
      retrySequential: (json['retrySequential'] as bool?) ?? false,
      inspirationIncludeSummary:
          (json['inspirationIncludeSummary'] as bool?) ?? false,
      promptStrategy: promptStrategy,
      requireAuthForArchive: (json['requireAuthForArchive'] as bool?) ?? false,
      requireAuthForApp: (json['requireAuthForApp'] as bool?) ?? false,
      requireNameToDelete: (json['requireNameToDelete'] as bool?) ?? true,
      allowDeleteMessage: (json['allowDeleteMessage'] as bool?) ?? false,
      autoBackup: (json['autoBackup'] as bool?) ?? true,
      showSplashAnimation: (json['showSplashAnimation'] as bool?) ?? true,
      showBottomNav: (json['showBottomNav'] as bool?) ?? false,
      showTokenDashboard: (json['showTokenDashboard'] as bool?) ?? false,
      enableForking: (json['enableForking'] as bool?) ?? false,
      enableCommandMacros: (json['enableCommandMacros'] as bool?) ?? true,
      enableRegexReplacement: (json['enableRegexReplacement'] as bool?) ?? true,
      regexRules: (json['regexRules'] as List<dynamic>?)
              ?.map((dynamic e) =>
                  RegexRule.fromJson(e as Map<String, dynamic>))
              .toList() ??
          <RegexRule>[],
      appIcon: (json['appIcon'] as String?) ?? 'default',
      snackDurationMs: (json['snackDurationMs'] as int?) ?? 1000,
      sherpaModelSource: (json['sherpaModelSource'] as String?) ?? 'auto',
      sherpaCustomBaseUrl: json['sherpaCustomBaseUrl'] as String?,
      sherpaModelReady: (json['sherpaModelReady'] as bool?) ?? false,
      sherpaModelPath: json['sherpaModelPath'] as String?,
      selectedVoiceModelId:
          (json['selectedVoiceModelId'] as String?) ?? kVoiceModelDefaultId,
      accentMode: (json['accentMode'] as String?) ?? 'auto',
      customAccentColor: json['customAccentColor'] as int?,
      voiceInputEnabled: (json['voiceInputEnabled'] as bool?) ?? false,
      ttsEnabled: (json['ttsEnabled'] as bool?) ?? false,
      ttsGlobalSeed: json['ttsGlobalSeed'] as int?,
      ttsQuoteOnly: (json['ttsQuoteOnly'] as bool?) ?? true,
      showParenButton: (json['showParenButton'] as bool?) ?? true,
      showMessageAvatar: (json['showMessageAvatar'] as bool?) ?? true,
      showMessageRetry: (json['showMessageRetry'] as bool?) ?? true,
      showMessageCopy: (json['showMessageCopy'] as bool?) ?? true,
      showMessageContinue: (json['showMessageContinue'] as bool?) ?? true,
      enterToSend: (json['enterToSend'] as bool?) ?? true,
      chatMaskStrength: (json['chatMaskStrength'] as int?) ?? 75,
      chatBubbleOpacity: (json['chatBubbleOpacity'] as int?) ?? 100,
      halfScreenChat: (json['halfScreenChat'] as bool?) ?? false,
      maxContextMessages: (json['maxContextMessages'] as int?) ?? 120,
      maxContextTokens: (json['maxContextTokens'] as int?) ?? 8000,
      temperature: (json['temperature'] as num?)?.toDouble() ?? 0.7,
      frequencyPenalty: (json['frequencyPenalty'] as num?)?.toDouble() ?? 0.0,
      presencePenalty: (json['presencePenalty'] as num?)?.toDouble() ?? 0.0,
      topP: (json['topP'] as num?)?.toDouble() ?? 1.0,
      topK: (json['topK'] as num?)?.toDouble() ?? 0.0,
      minP: (json['minP'] as num?)?.toDouble() ?? 0.0,
      repetitionPenalty: (json['repetitionPenalty'] as num?)?.toDouble() ?? 1.0,
      repetitionPenaltySlope:
          (json['repetitionPenaltySlope'] as num?)?.toDouble() ?? 0.0,
      loreMaxEntries: (json['loreMaxEntries'] as int?) ?? 8,
      loreBudgetTokens: (json['loreBudgetTokens'] as int?) ?? 0,
      quickReplies: (json['quickReplies'] as List?)
              ?.whereType<Map>()
              .map((Map r) =>
                  QuickReply.fromJson(r.cast<String, dynamic>()))
              .toList() ??
          const <QuickReply>[],
      deepseekThinkingEnabled:
          (json['deepseekThinkingEnabled'] as bool?) ?? true,
      deepseekThinkingEffort:
          (json['deepseekThinkingEffort'] as String?) ?? 'high',
      simpleModelMode: (json['simpleModelMode'] as bool?) ?? true,
      activeModelId:
          (json['activeModelId'] as String?) ?? LlmModelConfig.defaultId,
      providers: (json['providers'] as List<dynamic>?)
              ?.map((dynamic e) =>
                  LlmProviderConfig.fromJson(e as Map<String, dynamic>))
              .toList() ??
          <LlmProviderConfig>[
            LlmProviderConfig.defaultConfig(
              providerType: (json['provider'] as String?) ?? 'openai',
              baseUrl: (json['baseUrl'] as String?) ?? '',
              apiKey: (json['apiKey'] as String?) ?? '',
            ),
          ],
      models: (json['models'] as List<dynamic>?)
              ?.map((dynamic e) =>
                  LlmModelConfig.fromJson(e as Map<String, dynamic>))
              .toList() ??
          <LlmModelConfig>[
            LlmModelConfig.defaultConfig(
              modelName: (json['selectedModel'] as String?) ?? '',
            ),
          ],
    );
  }

  AppSettings copyWith({
    String? provider,
    String? themeMode,
    String? baseUrl,
    String? apiKey,
    String? selectedModel,
    bool? completedOobe,
    bool? autoSummaryPrompt,
    int? summaryTurnInterval,
    int? summaryWordThreshold,
    bool? retrySequential,
    bool? inspirationIncludeSummary,
    PromptStrategy? promptStrategy,
    bool? requireAuthForArchive,
    bool? requireAuthForApp,
    bool? requireNameToDelete,
    bool? allowDeleteMessage,
    bool? autoBackup,
    bool? showSplashAnimation,
    bool? showBottomNav,
    bool? showTokenDashboard,
    bool? enableForking,
    bool? enableCommandMacros,
    bool? enableRegexReplacement,
    List<RegexRule>? regexRules,
    String? appIcon,
    int? snackDurationMs,
    String? sherpaModelSource,
    String? sherpaCustomBaseUrl,
    bool? sherpaModelReady,
    String? sherpaModelPath,
    String? selectedVoiceModelId,
    String? accentMode,
    int? customAccentColor,
    bool? voiceInputEnabled,
    bool? ttsEnabled,
    int? ttsGlobalSeed,
    bool? ttsQuoteOnly,
    bool? showParenButton,
    bool? showMessageAvatar,
    bool? showMessageRetry,
    bool? showMessageCopy,
    bool? showMessageContinue,
    bool? enterToSend,
    int? chatMaskStrength,
    int? chatBubbleOpacity,
    bool? halfScreenChat,
    int? maxContextMessages,
    int? maxContextTokens,
    double? temperature,
    double? frequencyPenalty,
    double? presencePenalty,
    double? topP,
    double? topK,
    double? minP,
    double? repetitionPenalty,
    double? repetitionPenaltySlope,
    int? loreStickyRounds,
    int? loreMaxEntries,
    int? loreBudgetTokens,
    List<QuickReply>? quickReplies,
    bool? deepseekThinkingEnabled,
    String? deepseekThinkingEffort,
    bool? simpleModelMode,
    String? activeModelId,
    List<LlmProviderConfig>? providers,
    List<LlmModelConfig>? models,
  }) {
    return AppSettings(
      provider: provider ?? this.provider,
      themeMode: themeMode ?? this.themeMode,
      baseUrl: baseUrl ?? this.baseUrl,
      apiKey: apiKey ?? this.apiKey,
      selectedModel: selectedModel ?? this.selectedModel,
      completedOobe: completedOobe ?? this.completedOobe,
      autoSummaryPrompt: autoSummaryPrompt ?? this.autoSummaryPrompt,
      summaryTurnInterval: summaryTurnInterval ?? this.summaryTurnInterval,
      summaryWordThreshold: summaryWordThreshold ?? this.summaryWordThreshold,
      retrySequential: retrySequential ?? this.retrySequential,
      inspirationIncludeSummary: inspirationIncludeSummary ?? this.inspirationIncludeSummary,
      promptStrategy: promptStrategy ?? this.promptStrategy,
      requireAuthForArchive: requireAuthForArchive ?? this.requireAuthForArchive,
      requireAuthForApp: requireAuthForApp ?? this.requireAuthForApp,
      requireNameToDelete: requireNameToDelete ?? this.requireNameToDelete,
      allowDeleteMessage: allowDeleteMessage ?? this.allowDeleteMessage,
      autoBackup: autoBackup ?? this.autoBackup,
      showSplashAnimation: showSplashAnimation ?? this.showSplashAnimation,
      showBottomNav: showBottomNav ?? this.showBottomNav,
      showTokenDashboard: showTokenDashboard ?? this.showTokenDashboard,
      enableForking: enableForking ?? this.enableForking,
      enableCommandMacros: enableCommandMacros ?? this.enableCommandMacros,
      enableRegexReplacement:
          enableRegexReplacement ?? this.enableRegexReplacement,
      regexRules: regexRules ?? this.regexRules,
      appIcon: appIcon ?? this.appIcon,
      snackDurationMs: snackDurationMs ?? this.snackDurationMs,
      sherpaModelSource: sherpaModelSource ?? this.sherpaModelSource,
      sherpaCustomBaseUrl: sherpaCustomBaseUrl ?? this.sherpaCustomBaseUrl,
      sherpaModelReady: sherpaModelReady ?? this.sherpaModelReady,
      sherpaModelPath: sherpaModelPath ?? this.sherpaModelPath,
      selectedVoiceModelId: selectedVoiceModelId ?? this.selectedVoiceModelId,
      accentMode: accentMode ?? this.accentMode,
      customAccentColor: customAccentColor ?? this.customAccentColor,
      voiceInputEnabled: voiceInputEnabled ?? this.voiceInputEnabled,
      ttsEnabled: ttsEnabled ?? this.ttsEnabled,
      ttsGlobalSeed: ttsGlobalSeed ?? this.ttsGlobalSeed,
      ttsQuoteOnly: ttsQuoteOnly ?? this.ttsQuoteOnly,
      showParenButton: showParenButton ?? this.showParenButton,
      showMessageAvatar: showMessageAvatar ?? this.showMessageAvatar,
      showMessageRetry: showMessageRetry ?? this.showMessageRetry,
      showMessageCopy: showMessageCopy ?? this.showMessageCopy,
      showMessageContinue: showMessageContinue ?? this.showMessageContinue,
      enterToSend: enterToSend ?? this.enterToSend,
      chatMaskStrength: chatMaskStrength ?? this.chatMaskStrength,
      chatBubbleOpacity: chatBubbleOpacity ?? this.chatBubbleOpacity,
      halfScreenChat: halfScreenChat ?? this.halfScreenChat,
      maxContextMessages: maxContextMessages ?? this.maxContextMessages,
      maxContextTokens: maxContextTokens ?? this.maxContextTokens,
      temperature: temperature ?? this.temperature,
      frequencyPenalty: frequencyPenalty ?? this.frequencyPenalty,
      presencePenalty: presencePenalty ?? this.presencePenalty,
      topP: topP ?? this.topP,
      topK: topK ?? this.topK,
      minP: minP ?? this.minP,
      repetitionPenalty: repetitionPenalty ?? this.repetitionPenalty,
      repetitionPenaltySlope:
          repetitionPenaltySlope ?? this.repetitionPenaltySlope,
      loreStickyRounds: loreStickyRounds ?? this.loreStickyRounds,
      loreMaxEntries: loreMaxEntries ?? this.loreMaxEntries,
      loreBudgetTokens: loreBudgetTokens ?? this.loreBudgetTokens,
      quickReplies: quickReplies ?? this.quickReplies,
      deepseekThinkingEnabled:
          deepseekThinkingEnabled ?? this.deepseekThinkingEnabled,
      deepseekThinkingEffort:
          deepseekThinkingEffort ?? this.deepseekThinkingEffort,
      simpleModelMode: simpleModelMode ?? this.simpleModelMode,
      activeModelId: activeModelId ?? this.activeModelId,
      providers: providers ?? this.providers,
      models: models ?? this.models,
    );
  }
}
