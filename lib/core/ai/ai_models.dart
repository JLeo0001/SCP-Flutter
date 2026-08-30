import 'dart:convert';
import '../../core/services/preference_service.dart';

/// ═══════════════════════════════════════════════════════════
///  AI 功能数据模型
///
///  设计原则:
///  · 不带任何默认 AI —— 出厂无供应商、无密钥、无模型,总开关默认关闭
///  · 配置完全自定义 —— 地址/密钥/模型/温度/最大输出/自定义路径/自定义请求头
///  · 用户须自行配置供应商并启用功能后,AI 入口才出现
/// ═══════════════════════════════════════════════════════════

/// 供应商协议类型
enum AiProviderType { openai, claude, gemini }

extension AiProviderTypeX on AiProviderType {
  String get id => switch (this) {
        AiProviderType.openai => 'openai',
        AiProviderType.claude => 'claude',
        AiProviderType.gemini => 'gemini',
      };

  String get label => switch (this) {
        AiProviderType.openai => 'OpenAI 兼容',
        AiProviderType.claude => 'Anthropic Claude',
        AiProviderType.gemini => 'Google Gemini',
      };

  /// 仅作为输入框 hint 提示,不会预填进配置
  String get baseUrlHint => switch (this) {
        AiProviderType.openai => 'https://api.openai.com/v1',
        AiProviderType.claude => 'https://api.anthropic.com',
        AiProviderType.gemini => 'https://generativelanguage.googleapis.com',
      };

  String get modelHint => switch (this) {
        AiProviderType.openai => '例如 deepseek-v4-flash',
        AiProviderType.claude => '例如 claude-sonnet-4-5',
        AiProviderType.gemini => '例如 gemini-2.0-flash',
      };

  static AiProviderType fromId(String? id) => switch (id) {
        'claude' => AiProviderType.claude,
        'gemini' => AiProviderType.gemini,
        _ => AiProviderType.openai,
      };
}

/// 供应商配置(一个 = 一个 API 端点)
class AiProviderConfig {
  String id;
  String name;
  AiProviderType type;
  String baseUrl; // 不含尾斜杠,如 https://api.openai.com/v1
  String apiKey;
  String model; // 模型名,完全由用户填写
  double? temperature; // null = 不发送该参数
  int? maxTokens; // null = 不发送(claude 协议需要时回退 2048)
  bool stream; // 流式输出
  String customPath; // 自定义请求路径,空 = 用协议默认;支持 {model} 占位
  Map<String, String> customHeaders; // 附加请求头
  bool enabled;

  AiProviderConfig({
    required this.id,
    required this.name,
    required this.type,
    required this.baseUrl,
    required this.apiKey,
    required this.model,
    this.temperature,
    this.maxTokens,
    this.stream = true,
    this.customPath = '',
    Map<String, String>? customHeaders,
    this.enabled = true,
  }) : customHeaders = customHeaders ?? {};

  String get displayModel => model.trim();

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'type': type.id,
        'baseUrl': baseUrl,
        'apiKey': apiKey,
        'model': model,
        'temperature': temperature,
        'maxTokens': maxTokens,
        'stream': stream,
        'customPath': customPath,
        'customHeaders': customHeaders,
        'enabled': enabled,
      };

  factory AiProviderConfig.fromJson(Map<String, dynamic> j) {
    final headers = <String, String>{};
    final raw = j['customHeaders'];
    if (raw is Map) {
      raw.forEach((k, v) => headers['$k'] = '$v');
    }
    return AiProviderConfig(
      id: (j['id'] ?? '') as String,
      name: (j['name'] ?? '未命名') as String,
      type: AiProviderTypeX.fromId(j['type'] as String?),
      baseUrl: (j['baseUrl'] ?? '') as String,
      apiKey: (j['apiKey'] ?? '') as String,
      model: (j['model'] ?? '') as String,
      temperature: (j['temperature'] as num?)?.toDouble(),
      maxTokens: j['maxTokens'] as int?,
      stream: (j['stream'] ?? true) as bool,
      customPath: (j['customPath'] ?? '') as String,
      customHeaders: headers,
      enabled: (j['enabled'] ?? true) as bool,
    );
  }

  AiProviderConfig copy() {
    final j = jsonDecode(jsonEncode(toJson())) as Map<String, dynamic>;
    return AiProviderConfig.fromJson(j);
  }
}

/// AI 功能配置(内置 4 项 + 用户自定义)
/// userPromptTemplate 支持占位符: {title} 文档标题, {content} 正文(已按字数上限截断)
class AiFeatureConfig {
  String id;
  String name;
  bool builtin;
  bool enabled;
  String providerId; // 关联 AiProviderConfig.id,空 = 未配置
  String model; // 覆盖供应商默认模型,空 = 用供应商的
  bool useArticleContext; // 自动携带当前阅读的文档正文
  String contextMode; // inject=注入提示词 | tool=工具读取(省 token) | none=不携带
  String systemPrompt;
  String userPromptTemplate; // chat 功能为空(自由对话)

  AiFeatureConfig({
    required this.id,
    required this.name,
    this.builtin = false,
    this.enabled = false,
    this.providerId = '',
    this.model = '',
    this.useArticleContext = true,
    this.contextMode = 'inject',
    this.systemPrompt = '',
    this.userPromptTemplate = '',
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'builtin': builtin,
        'enabled': enabled,
        'providerId': providerId,
        'model': model,
        'useArticleContext': useArticleContext,
        'contextMode': contextMode,
        'systemPrompt': systemPrompt,
        'userPromptTemplate': userPromptTemplate,
      };

  factory AiFeatureConfig.fromJson(Map<String, dynamic> j) => AiFeatureConfig(
        id: (j['id'] ?? '') as String,
        name: (j['name'] ?? '') as String,
        builtin: (j['builtin'] ?? false) as bool,
        enabled: (j['enabled'] ?? false) as bool,
        providerId: (j['providerId'] ?? '') as String,
        model: (j['model'] ?? '') as String,
        useArticleContext: (j['useArticleContext'] ?? true) as bool,
        contextMode: (j['contextMode'] ?? 'inject') as String,
        systemPrompt: (j['systemPrompt'] ?? '') as String,
        userPromptTemplate: (j['userPromptTemplate'] ?? '') as String,
      );
}

/// AI 总设置
class AiSettings {
  bool masterEnabled; // 总开关:关闭时所有 AI 入口隐藏、功能不可用
  List<AiProviderConfig> providers;
  List<AiFeatureConfig> features;
  int contextMaxChars; // 单次请求携带正文的最大字符数
  bool includeTitle; // 上下文附带文档标题

  AiSettings({
    required this.masterEnabled,
    required this.providers,
    required this.features,
    required this.contextMaxChars,
    required this.includeTitle,
  });

  /// 出厂状态:总开关关、无供应商、内置功能全部停用
  factory AiSettings.fresh() => AiSettings(
        masterEnabled: false,
        providers: [],
        features: AiSettings.defaultFeatures(),
        contextMaxChars: 6000,
        includeTitle: true,
      );

  // ── 内置功能的默认提示词(可被用户改写;这些只是提示词,不是默认 AI 服务) ──
  static List<AiFeatureConfig> defaultFeatures() => [
        AiFeatureConfig(
          id: 'summary',
          name: '内容摘要',
          builtin: true,
          contextMode: 'inject',
          systemPrompt: '你是 SCP 基金会文档的阅读助手,默认使用中文回答。忠实于原文,不要编造文档中不存在的内容。',
          userPromptTemplate:
              '请阅读以下文档,输出结构化摘要:\n'
              '1. 项目编号与代号(如有)\n'
              '2. 异常性质与威胁等级(如有)\n'
              '3. 收容/保护措施要点\n'
              '4. 文档主要内容概述\n'
              '要求简洁,分点作答。\n\n'
              '文档标题:{title}\n\n文档正文:\n{content}',
        ),
        AiFeatureConfig(
          id: 'translate',
          name: '翻译',
          builtin: true,
          contextMode: 'inject',
          systemPrompt: '你是专业翻译,熟悉 SCP 基金会的术语与文风。',
          userPromptTemplate:
              '将以下内容翻译为中文(若原文已是中文,则翻译为英文)。'
              '保留段落结构与专有名词(如 SCP 编号、部门名、人名),只输出译文,不要解释。\n\n{content}',
        ),
        AiFeatureConfig(
          id: 'explain',
          name: '名词解释',
          builtin: true,
          contextMode: 'inject',
          systemPrompt: '你是 SCP 基金会设定百科,熟悉基金会宇宙的世界观、术语与著名条目。',
          userPromptTemplate:
              '阅读以下文档,解释其中出现的专有名词、缩写、内部梗与设定(如基金会部门、等级制度、著名异常项目等)。'
              '逐条输出:术语 —— 解释。若文档本身易懂,请给出理解它所需的 3-5 条背景知识。\n\n'
              '文档标题:{title}\n\n文档正文:\n{content}',
        ),
        AiFeatureConfig(
          id: 'chat',
          name: '自由对话',
          builtin: true,
          contextMode: 'tool', // 对话默认工具读取,省 token
          systemPrompt:
              '你是 SCP 基金会文档的阅读助手。用户正在阅读一篇文档,请结合文档内容回答问题;文档未提及的信息请明确说明"文档未提及",不要编造。\n\n'
              '文档标题:{title}\n\n文档正文:\n{content}',
          userPromptTemplate: '',
        ),
      ];

  // ── 查询 ──

  /// 已启用且供应商可解析的快捷功能(不含自由对话;阅读页快捷入口用)
  List<AiFeatureConfig> effectiveFeatures() {
    if (!masterEnabled) return [];
    return features.where((f) {
      if (!f.enabled || f.id == 'chat') return false;
      final p = providerById(f.providerId);
      return p != null && p.enabled && p.model.trim().isNotEmpty && p.baseUrl.trim().isNotEmpty;
    }).toList();
  }

  /// 至少一个可用的启用供应商(决定阅读页 AI 入口是否显示)
  bool get isAvailable =>
      masterEnabled &&
      providers.any((p) => p.enabled && p.baseUrl.trim().isNotEmpty && p.model.trim().isNotEmpty);

  /// 是否已在任何层面完成配置(设置页提示用)
  bool get hasAnyProvider => providers.any((p) => p.baseUrl.trim().isNotEmpty && p.model.trim().isNotEmpty);

  /// 自由对话能力:不作为功能开关,配置了供应商即可用。
  /// 优先使用对话自己绑定的供应商(若仍可解析),否则默认列表最上方的启用供应商。
  ({AiProviderConfig provider, AiFeatureConfig feature})? chatCapability() {
    if (!masterEnabled) return null;
    AiFeatureConfig f;
    try {
      f = features.firstWhere((e) => e.id == 'chat');
    } catch (_) {
      f = AiSettings.defaultFeatures().firstWhere((e) => e.id == 'chat');
    }
    AiProviderConfig? p = providerById(f.providerId);
    bool usable(AiProviderConfig c) =>
        c.enabled && c.baseUrl.trim().isNotEmpty && c.model.trim().isNotEmpty;
    if (p == null || !usable(p)) {
      for (final c in providers) {
        if (usable(c)) {
          p = c;
          break;
        }
      }
    }
    if (p == null || !usable(p)) return null;
    return (provider: p, feature: f);
  }

  AiProviderConfig? providerById(String id) {
    for (final p in providers) {
      if (p.id == id) return p;
    }
    return null;
  }

  // ── 序列化 ──

  String toJsonString() => jsonEncode({
        'masterEnabled': masterEnabled,
        'providers': providers.map((e) => e.toJson()).toList(),
        'features': features.map((e) => e.toJson()).toList(),
        'contextMaxChars': contextMaxChars,
        'includeTitle': includeTitle,
        'v': 1,
      });

  factory AiSettings.fromJsonString(String s) {
    try {
      if (s.isEmpty) return AiSettings.fresh();
      final j = jsonDecode(s) as Map<String, dynamic>;
      final defaults = AiSettings.defaultFeatures();
      final loaded = (j['features'] as List? ?? [])
          .map((e) => AiFeatureConfig.fromJson(e as Map<String, dynamic>))
          .toList();
      // 内置功能补齐(升级/旧数据缺项),已有配置优先;chat 无 contextMode 时默认工具读取
      for (final d in defaults) {
        if (!loaded.any((f) => f.id == d.id)) loaded.add(d);
      }
      for (final f in loaded) {
        if (f.id == 'chat' && !(j['features'] as List? ?? []).any((e) =>
            e is Map && e['id'] == 'chat' && e['contextMode'] != null)) {
          f.contextMode = 'tool';
        }
      }
      return AiSettings(
        masterEnabled: (j['masterEnabled'] ?? false) as bool,
        providers: (j['providers'] as List? ?? [])
            .map((e) => AiProviderConfig.fromJson(e as Map<String, dynamic>))
            .toList(),
        features: loaded,
        contextMaxChars: (j['contextMaxChars'] ?? 6000) as int,
        includeTitle: (j['includeTitle'] ?? true) as bool,
      );
    } catch (_) {
      return AiSettings.fresh();
    }
  }
}

/// 设置存取。main() 已 await PreferenceService.init(),此处的同步读取安全。
class AiSettingsStore {
  static AiSettings _cache = AiSettings.fresh();

  /// 同步读取(带进程内缓存;save 后缓存随之更新)
  static AiSettings loadSync() => _cache;

  /// 每次进入设置/阅读页时调用一次,从磁盘刷新
  static AiSettings reload() {
    _cache = AiSettings.fromJsonString(PreferenceService.getAiSettingsJson());
    return _cache;
  }

  static Future<void> save(AiSettings s) async {
    _cache = s;
    await PreferenceService.setAiSettingsJson(s.toJsonString());
  }

  /// 判断当前是否可用(阅读页是否显示 AI 入口):总开 + 至少一个可用供应商
  static bool available(AiSettings s) => s.isAvailable;
}
