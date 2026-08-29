import 'package:flutter/material.dart';

import '../../core/ai/ai_models.dart';
import '../../core/ai/ai_service.dart';

/// AI 设置主页 —— 总开关 / 供应商 / 功能 / 阅读上下文
class AiSettingsPage extends StatefulWidget {
  const AiSettingsPage({super.key});

  @override
  State<AiSettingsPage> createState() => _AiSettingsPageState();
}

class _AiSettingsPageState extends State<AiSettingsPage> {
  final AiSettings _s = AiSettingsStore.reload();

  Future<void> _persist() async {
    await AiSettingsStore.save(_s);
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('AI 设置')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          SwitchListTile(
            title: const Text('启用 AI 功能'),
            subtitle: const Text('总开关:关闭后隐藏所有 AI 入口。应用不内置任何 AI 服务,密钥由你自行配置'),
            value: _s.masterEnabled,
            onChanged: (v) {
              _s.masterEnabled = v;
              _persist();
            },
          ),
          const Divider(),
          _sectionHeader(context, '供应商', onAdd: _addProvider),
          if (_s.providers.isEmpty)
            _hintCard(context, Icons.extension, '尚未配置 AI 供应商',
                '点击右上角「添加」新建一个供应商,填入 API 地址、密钥与模型。支持 OpenAI 兼容接口、Anthropic Claude 与 Google Gemini。')
          else
            for (final p in _s.providers)
              ListTile(
                leading: Icon(
                  p.type == AiProviderType.openai
                      ? Icons.hub
                      : p.type == AiProviderType.claude
                          ? Icons.auto_awesome
                          : Icons.diamond_outlined,
                  color: p.enabled ? cs.primary : cs.outlineVariant,
                ),
                title:
                    Text(p.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: Text(
                  '${p.type.label} · ${p.model.trim().isEmpty ? "未填模型" : p.model.trim()}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: Switch(
                    value: p.enabled,
                    onChanged: (v) {
                      p.enabled = v;
                      _persist();
                    }),
                onTap: () => _editProvider(p),
              ),
          const Divider(),
          _sectionHeader(context, '功能', onAdd: _addCustomFeature),
          if (_s.features.isEmpty)
            _hintCard(
                context, Icons.tune, '没有可用功能', '添加自定义功能后,会显示为阅读页 AI 助手里的快捷操作。')
          else
            for (final f in _s.features)
              ListTile(
                leading: Icon(_featureIcon(f.id),
                    color: f.enabled ? cs.primary : cs.outlineVariant),
                title: Text(f.name),
                subtitle: Text(_featureSubtitle(f),
                    maxLines: 1, overflow: TextOverflow.ellipsis),
                trailing: Switch(
                    value: f.enabled,
                    onChanged: (v) {
                      f.enabled = v;
                      _persist();
                    }),
                onTap: () => _editFeature(f),
                onLongPress: f.builtin ? null : () => _deleteFeature(f),
              ),
          const Divider(),
          _sectionHeader(context, '阅读上下文'),
          ListTile(
            title: Text('正文携带上限 · ${_s.contextMaxChars} 字'),
            subtitle: Slider(
              min: 1000,
              max: 30000,
              divisions: 58,
              label: '${_s.contextMaxChars}',
              value: _s.contextMaxChars.clamp(1000, 30000).toDouble(),
              onChanged: (v) =>
                  setState(() => _s.contextMaxChars = (v / 500).round() * 500),
              onChangeEnd: (_) => _persist(),
            ),
          ),
          SwitchListTile(
            title: const Text('附带文档标题'),
            subtitle: const Text('在提示词的 {title} 占位符及上下文中注入当前文档标题'),
            value: _s.includeTitle,
            onChanged: (v) {
              _s.includeTitle = v;
              _persist();
            },
          ),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              '· 所有配置仅保存在本机;API Key 只会发送到你填写的地址。\n'
              '· 内置功能的提示词都可以修改;长按自定义功能可删除。\n'
              '· 若接口较慢或超额,可调低正文携带上限以减少 token 消耗。',
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: cs.outline),
            ),
          ),
        ],
      ),
    );
  }

  String _featureSubtitle(AiFeatureConfig f) {
    if (!f.enabled) return '已停用';
    final p = _s.providerById(f.providerId);
    if (p == null) return '未绑定供应商';
    final model = f.model.trim().isNotEmpty ? f.model.trim() : p.model.trim();
    return '${p.name} · ${model.isEmpty ? "未填模型" : model}';
  }

  IconData _featureIcon(String id) => switch (id) {
        'summary' => Icons.summarize_outlined,
        'translate' => Icons.translate,
        'explain' => Icons.menu_book_outlined,
        'chat' => Icons.forum_outlined,
        _ => Icons.bolt_outlined,
      };

  // ═══ 导航 ═══

  Future<void> _addProvider() async {
    final result = await Navigator.push<_ProviderEditResult>(
        context, MaterialPageRoute(builder: (_) => const _ProviderEditPage()));
    if (result == null || result.deleted) return;
    _s.providers.add(result.provider);
    await _persist();
  }

  Future<void> _editProvider(AiProviderConfig p) async {
    final result = await Navigator.push<_ProviderEditResult>(context,
        MaterialPageRoute(builder: (_) => _ProviderEditPage(existing: p)));
    if (result == null) return;
    if (result.deleted) {
      _s.providers.removeWhere((e) => e.id == p.id);
      // 解除功能绑定
      for (final f in _s.features) {
        if (f.providerId == p.id) f.providerId = '';
      }
    } else {
      final i = _s.providers.indexWhere((e) => e.id == p.id);
      if (i >= 0) _s.providers[i] = result.provider;
    }
    await _persist();
  }

  Future<void> _addCustomFeature() async {
    final f = AiFeatureConfig(
      id: 'custom_${DateTime.now().millisecondsSinceEpoch}',
      name: '自定义功能',
      useArticleContext: true,
    );
    final changed = await _pushFeature(f);
    if (changed == true) {
      _s.features.add(f);
      await _persist();
    }
  }

  Future<void> _editFeature(AiFeatureConfig f) async {
    final changed = await _pushFeature(f);
    if (changed == true) await _persist();
  }

  Future<bool?> _pushFeature(AiFeatureConfig f) {
    return Navigator.push<bool>(
      context,
      MaterialPageRoute(
          builder: (_) => _FeatureEditPage(feature: f, settings: _s)),
    );
  }

  Future<void> _deleteFeature(AiFeatureConfig f) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除功能'),
        content: Text('确定删除「${f.name}」?该操作不可撤销。'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('删除')),
        ],
      ),
    );
    if (ok == true) {
      _s.features.removeWhere((e) => e.id == f.id);
      await _persist();
    }
  }
}

// ── 通用小组件 ──

Widget _sectionHeader(BuildContext context, String title,
    {VoidCallback? onAdd}) {
  return Padding(
    padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
    child: Row(
      children: [
        Expanded(
            child: Text(title, style: Theme.of(context).textTheme.titleSmall)),
        if (onAdd != null)
          TextButton.icon(
            onPressed: onAdd,
            icon: const Icon(Icons.add, size: 18),
            label: const Text('添加'),
          ),
      ],
    ),
  );
}

Widget _hintCard(
    BuildContext context, IconData icon, String title, String body) {
  final cs = Theme.of(context).colorScheme;
  return Card(
    margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
    child: Padding(
      padding: const EdgeInsets.all(14),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, size: 22, color: cs.primary),
        const SizedBox(width: 12),
        Expanded(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            Text(body,
                style: TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant)),
          ]),
        ),
      ]),
    ),
  );
}

// ═══════════════════════════════════════════
//  供应商编辑页
// ═══════════════════════════════════════════

class _ProviderEditResult {
  final AiProviderConfig provider;
  final bool deleted;
  const _ProviderEditResult(this.provider, {this.deleted = false});
}

class _ProviderEditPage extends StatefulWidget {
  final AiProviderConfig? existing;
  const _ProviderEditPage({this.existing});

  @override
  State<_ProviderEditPage> createState() => _ProviderEditPageState();
}

class _ProviderEditPageState extends State<_ProviderEditPage> {
  late AiProviderType _type;
  late final TextEditingController _name;
  late final TextEditingController _base;
  late final TextEditingController _key;
  late final TextEditingController _model;
  late final TextEditingController _temp;
  late final TextEditingController _maxTok;
  late final TextEditingController _path;
  late final TextEditingController _headers;
  late bool _stream;
  late bool _enabled;
  bool _obscureKey = true;
  bool _testing = false;
  String? _testResult; // null=未测,空串=失败

  bool get _isNew => widget.existing == null;

  @override
  void initState() {
    super.initState();
    final p = widget.existing;
    _type = p?.type ?? AiProviderType.openai;
    _name = TextEditingController(text: p?.name ?? '');
    _base = TextEditingController(text: p?.baseUrl ?? '');
    _key = TextEditingController(text: p?.apiKey ?? '');
    _model = TextEditingController(text: p?.model ?? '');
    _temp = TextEditingController(text: p?.temperature?.toString() ?? '');
    _maxTok = TextEditingController(text: p?.maxTokens?.toString() ?? '');
    _path = TextEditingController(text: p?.customPath ?? '');
    _headers = TextEditingController(
        text: (p?.customHeaders ?? {})
            .entries
            .map((e) => '${e.key}: ${e.value}')
            .join('\n'));
    _stream = p?.stream ?? true;
    _enabled = p?.enabled ?? true;
  }

  @override
  void dispose() {
    for (final c in [
      _name,
      _base,
      _key,
      _model,
      _temp,
      _maxTok,
      _path,
      _headers
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  void _applyType(AiProviderType t) {
    setState(() => _type = t);
    // 新建时按协议起个默认名,方便区分
    if (_isNew && _name.text.trim().isEmpty) _name.text = t.label;
  }

  AiProviderConfig? _build() {
    final base = _base.text.trim();
    final model = _model.text.trim();
    if (base.isEmpty) {
      _err('请填写 API 地址');
      return null;
    }
    if (model.isEmpty) {
      _err('请填写模型名');
      return null;
    }
    return AiProviderConfig(
      id: widget.existing?.id ?? 'p_${DateTime.now().millisecondsSinceEpoch}',
      name: _name.text.trim().isEmpty ? model : _name.text.trim(),
      type: _type,
      baseUrl: base,
      apiKey: _key.text.trim(),
      model: model,
      temperature: double.tryParse(_temp.text.trim()),
      maxTokens: int.tryParse(_maxTok.text.trim()),
      stream: _stream,
      customPath: _path.text.trim(),
      customHeaders: _parseHeaders(_headers.text),
      enabled: _enabled,
    );
  }

  Map<String, String> _parseHeaders(String s) {
    final m = <String, String>{};
    for (var line in s.split('\n')) {
      line = line.trim();
      if (line.isEmpty) continue;
      final i = line.indexOf(':');
      if (i <= 0) continue;
      final k = line.substring(0, i).trim();
      final v = line.substring(i + 1).trim();
      if (k.isNotEmpty) m[k] = v;
    }
    return m;
  }

  void _err(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _save() async {
    final p = _build();
    if (p == null) return;
    Navigator.pop(context, _ProviderEditResult(p));
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除供应商'),
        content: const Text('已绑定此供应商的功能将变为未绑定状态。'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('删除')),
        ],
      ),
    );
    if (ok == true && mounted) {
      Navigator.pop(
          context, _ProviderEditResult(widget.existing!, deleted: true));
    }
  }

  Future<void> _test() async {
    final p = _build();
    if (p == null) return;
    setState(() {
      _testing = true;
      _testResult = null;
    });
    try {
      final msg = await AiService.instance.testConnection(p);
      _testResult = msg;
    } on AiException catch (e) {
      _testResult = '';
      _err(e.message);
    } catch (e) {
      _testResult = '';
      _err('测试失败: $e');
    }
    if (mounted) setState(() => _testing = false);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Text(_isNew ? '添加供应商' : '编辑供应商'),
        actions: [
          if (!_isNew)
            IconButton(
                icon: const Icon(Icons.delete_outline),
                tooltip: '删除',
                onPressed: _delete),
          TextButton(onPressed: _save, child: const Text('保存')),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          DropdownButtonFormField<AiProviderType>(
            value: _type,
            decoration: const InputDecoration(
              labelText: '接口类型',
              border: OutlineInputBorder(),
            ),
            items: [
              for (final t in AiProviderType.values)
                DropdownMenuItem(value: t, child: Text(t.label)),
            ],
            onChanged: (t) {
              if (t != null) _applyType(t);
            },
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _name,
            decoration: const InputDecoration(
                labelText: '名称',
                hintText: '便于识别,如「我的中转站」',
                border: OutlineInputBorder()),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _base,
            keyboardType: TextInputType.url,
            decoration: InputDecoration(
                labelText: 'API 地址 (Base URL)',
                hintText: _type.baseUrlHint,
                helperText: _type == AiProviderType.gemini
                    ? '密钥通过 x-goog-api-key 头发送'
                    : null,
                border: const OutlineInputBorder()),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _key,
            obscureText: _obscureKey,
            decoration: InputDecoration(
                labelText: 'API 密钥',
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  icon: Icon(
                      _obscureKey ? Icons.visibility_off : Icons.visibility),
                  onPressed: () => setState(() => _obscureKey = !_obscureKey),
                )),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _model,
            decoration: InputDecoration(
                labelText: '模型',
                hintText: _type.modelHint,
                border: const OutlineInputBorder()),
          ),
          const SizedBox(height: 14),
          Row(children: [
            Expanded(
              child: TextField(
                controller: _temp,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                    labelText: '温度 (可选)',
                    hintText: '留空不发送',
                    border: OutlineInputBorder()),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextField(
                controller: _maxTok,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                    labelText: '最大输出 tokens (可选)',
                    hintText: '留空不发送',
                    border: OutlineInputBorder()),
              ),
            ),
          ]),
          const SizedBox(height: 4),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('流式输出'),
            subtitle: const Text('边生成边显示;个别兼容端点不支持时可关闭'),
            value: _stream,
            onChanged: (v) => setState(() => _stream = v),
          ),
          const Divider(height: 24),
          TextField(
            controller: _path,
            decoration: InputDecoration(
                labelText: '自定义请求路径 (可选)',
                hintText: _type == AiProviderType.gemini
                    ? '/v1beta/models/{model}:streamGenerateContent?alt=sse'
                    : _type == AiProviderType.claude
                        ? '/v1/messages'
                        : '/chat/completions',
                helperText: '留空使用协议默认路径;{model} 会被替换为模型名;可含 ?query',
                border: const OutlineInputBorder()),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _headers,
            maxLines: 3,
            decoration: const InputDecoration(
                labelText: '自定义请求头 (可选)',
                hintText:
                    '每行一条,格式 Key: Value\n例如 anthropic-beta: prompt-caching-2024-07-31',
                border: OutlineInputBorder()),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('启用此供应商'),
            value: _enabled,
            onChanged: (v) => setState(() => _enabled = v),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _testing ? null : _test,
            icon: _testing
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.network_check),
            label: Text(_testResult == null
                ? '测试连接'
                : (_testResult!.isEmpty ? '重试' : '再测一次')),
          ),
          if (_testResult != null && _testResult!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(_testResult!,
                  style: TextStyle(color: cs.primary, fontSize: 13)),
            ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════
//  功能编辑页
// ═══════════════════════════════════════════

class _FeatureEditPage extends StatefulWidget {
  final AiFeatureConfig feature;
  final AiSettings settings;
  const _FeatureEditPage({required this.feature, required this.settings});

  @override
  State<_FeatureEditPage> createState() => _FeatureEditPageState();
}

class _FeatureEditPageState extends State<_FeatureEditPage> {
  late final AiFeatureConfig _f;
  late final TextEditingController _name;
  late final TextEditingController _model;
  late final TextEditingController _system;
  late final TextEditingController _user;
  String _providerId = '';
  bool _context = true;

  bool get _isChat => _f.id == 'chat';
  bool get _builtin => _f.builtin;

  @override
  void initState() {
    super.initState();
    _f = widget.feature;
    _name = TextEditingController(text: _f.name);
    _model = TextEditingController(text: _f.model);
    _system = TextEditingController(text: _f.systemPrompt);
    _user = TextEditingController(text: _f.userPromptTemplate);
    _providerId = _f.providerId;
    _context = _f.useArticleContext;
  }

  @override
  void dispose() {
    _name.dispose();
    _model.dispose();
    _system.dispose();
    _user.dispose();
    super.dispose();
  }

  void _save() {
    final f = _f;
    if (_f.enabled && _providerId.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('启用功能前请先绑定供应商')));
      return;
    }
    f.name = _name.text.trim().isEmpty ? f.id : _name.text.trim();
    f.providerId = _providerId;
    f.model = _model.text.trim();
    f.useArticleContext = _context;
    f.systemPrompt = _system.text;
    f.userPromptTemplate = _isChat ? '' : _user.text;
    Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final providers =
        widget.settings.providers.where((p) => p.enabled).toList();
    return Scaffold(
      appBar: AppBar(
        title: Text(_builtin ? '编辑功能 · ${_f.name}' : '自定义功能'),
        actions: [TextButton(onPressed: _save, child: const Text('保存'))],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('启用此功能'),
            subtitle: const Text('启用后显示在阅读页 AI 助手的快捷操作中'),
            value: _f.enabled,
            onChanged: (v) => setState(() => _f.enabled = v),
          ),
          const SizedBox(height: 8),
          if (!_builtin)
            Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: TextField(
                controller: _name,
                decoration: const InputDecoration(
                    labelText: '功能名称', border: OutlineInputBorder()),
              ),
            ),
          DropdownButtonFormField<String>(
            value: _providerId.isEmpty ? '' : _providerId,
            decoration: const InputDecoration(
                labelText: '绑定供应商', border: OutlineInputBorder()),
            items: [
              const DropdownMenuItem(value: '', child: Text('未选择')),
              for (final p in providers)
                DropdownMenuItem(
                    value: p.id, child: Text('${p.name} (${p.model.trim()})')),
            ],
            onChanged: (v) => setState(() => _providerId = v ?? ''),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _model,
            decoration: InputDecoration(
              labelText: '模型覆盖 (可选)',
              hintText: '留空使用供应商默认模型',
              border: const OutlineInputBorder(),
            ),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('携带文档上下文'),
            subtitle: const Text('自动把当前阅读的文档标题与正文填入 {title} / {content}'),
            value: _context,
            onChanged: (v) => setState(() => _context = v),
          ),
          const Divider(height: 24),
          Text('系统提示词 (System)', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 6),
          TextField(
            controller: _system,
            maxLines: 4,
            decoration: const InputDecoration(
              hintText: '设定 AI 的角色与回答风格,可使用 {title} {content} 占位符',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 14),
          if (!_isChat) ...[
            Text('用户提示词模板', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 6),
            TextField(
              controller: _user,
              maxLines: 6,
              decoration: const InputDecoration(
                hintText: '点击快捷按钮时发送的内容,支持 {title} 与 {content} 占位符',
                border: OutlineInputBorder(),
              ),
            ),
          ] else
            _hintCard(
              context,
              Icons.forum_outlined,
              '自由对话模式',
              '对话页的输入框即此功能;系统提示词中的 {title} / {content} 会在对话开始时替换为当前文档。',
            ),
        ],
      ),
    );
  }
}
