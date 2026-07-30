import 'dart:async';
import 'package:flutter/material.dart';
import '../../core/services/database_helper.dart';
import '../../core/models/draft_model.dart';

/// 草稿编辑页 — 增强版（自动保存 + 字数统计 + 未保存提示）
class DraftEditPage extends StatefulWidget {
  final DraftModel? draft;
  final VoidCallback? onSaved;

  const DraftEditPage({super.key, this.draft, this.onSaved});

  @override
  State<DraftEditPage> createState() => _DraftEditPageState();
}

class _DraftEditPageState extends State<DraftEditPage> {
  late TextEditingController _titleController;
  late TextEditingController _contentController;
  Timer? _autoSaveTimer;
  bool _dirty = false;
  bool _saving = false;
  int _charCount = 0;
  int _lineCount = 0;
  int _draftId = 0; // 持久化草稿ID，新建后首次保存即固定
  final List<String> _undoStack = []; // 内容撤回栈
  bool _suppressUndo = false; // 撤回时阻止再次入栈

  @override
  void initState() {
    super.initState();
    _draftId = widget.draft?.draftId ?? 0;
    _titleController = TextEditingController(text: widget.draft?.title ?? '');
    _contentController = TextEditingController(text: widget.draft?.content ?? '');
    // 初始内容入栈和旧值记录
    _previousContent = _contentController.text;
    _undoStack.add(_previousContent);
    _updateStats();
    _titleController.addListener(_onTitleChanged);
    _contentController.addListener(_onContentChanged);
  }

  @override
  void dispose() {
    _autoSaveTimer?.cancel();
    _titleController.removeListener(_onTitleChanged);
    _contentController.removeListener(_onContentChanged);
    _titleController.dispose();
    _contentController.dispose();
    super.dispose();
  }

  void _onTitleChanged() {
    _dirty = true;
    setState(() {});
    _scheduleAutoSave();
  }

  void _onContentChanged() {
    _dirty = true;
    _updateStats();
    if (!_suppressUndo) {
      // 将本次编辑前的旧值入栈（当前 text 是已编辑后的新值，
      // 但 listener 回看 _previousContent 取的是变更前的值）
      if (!_undoStack.contains(_previousContent)) {
        _undoStack.add(_previousContent);
        if (_undoStack.length > 20) _undoStack.removeAt(0);
      }
    }
    _previousContent = _contentController.text;
    setState(() {});
    _scheduleAutoSave();
  }

  String _previousContent = ''; // 用于 undo 栈记录旧值

  void _scheduleAutoSave() {
    _autoSaveTimer?.cancel();
    _autoSaveTimer = Timer(const Duration(milliseconds: 1500), () {
      if (_dirty && mounted) _saveDraft(silent: true);
    });
  }

  void _undo() {
    if (_undoStack.length <= 1) {
      _snack('没有可撤回的内容');
      return;
    }
    _suppressUndo = true;
    // 弹出当前值
    _undoStack.removeLast();
    // 取上一个值恢复
    final previous = _undoStack.last;
    _contentController.text = previous;
    _contentController.selection = TextSelection.fromPosition(
      TextPosition(offset: previous.length),
    );
    _suppressUndo = false;
    _dirty = true;
    _updateStats();
  }

  void _updateStats() {
    _charCount = _contentController.text.length;
    final text = _contentController.text;
    int lines = 1;
    for (int i = 0; i < text.length; i++) {
      if (text[i] == '\n') lines++;
    }
    _lineCount = text.isEmpty ? 0 : lines;
  }

  Future<void> _saveDraft({bool silent = false}) async {
    if (_saving) return;
    _saving = true;
    try {
      // 新建草稿：首次保存时生成固定 ID
      if (_draftId == 0) {
        _draftId = DateTime.now().millisecondsSinceEpoch;
      }
      final draft = DraftModel(
        draftId: _draftId,
        lastModifyTime: DateTime.now().millisecondsSinceEpoch,
        title: _titleController.text,
        content: _contentController.text,
      );
      await DatabaseHelper.saveDraft(draft);
      _dirty = false;
      widget.onSaved?.call();
      if (!silent && mounted) {
        _snack('草稿已保存');
      }
    } finally {
      _saving = false;
    }
  }

  Future<bool> _onWillPop() async {
    if (!_dirty) return true;
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('未保存的更改'),
        content: const Text('当前草稿有未保存的更改，是否保存后再退出？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'discard'),
            child: const Text('不保存', style: TextStyle(color: Colors.red)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'cancel'),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, 'save'),
            child: const Text('保存并退出'),
          ),
        ],
      ),
    );
    if (result == 'save') {
      await _saveDraft();
      return true;
    }
    return result == 'discard';
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return PopScope(
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final canLeave = await _onWillPop();
        if (canLeave && mounted) {
          Navigator.of(context).pop();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('编辑草稿'),
          actions: [
            IconButton(
              icon: const Icon(Icons.undo),
              tooltip: '撤回 (${_undoStack.length - 1})',
              onPressed: _undoStack.length > 1 ? _undo : null,
            ),
            FilledButton.tonalIcon(
              onPressed: _dirty ? () => _saveDraft() : null,
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                visualDensity: VisualDensity.compact,
              ),
              icon: _saving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Icon(_dirty ? Icons.save : Icons.check_circle,
                      size: 18),
              label: Text(_dirty ? '保存' : '已保存'),
            ),
          ],
        ),
        body: Column(
          children: [
            // 标题输入
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: TextField(
                controller: _titleController,
                decoration: InputDecoration(
                  hintText: '标题（可选）',
                  hintStyle: TextStyle(color: cs.onSurface.withValues(alpha: 0.3)),
                  border: const OutlineInputBorder(),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  isDense: true,
                ),
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                maxLines: 1,
              ),
            ),
            const SizedBox(height: 8),
            // 内容输入
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: TextField(
                  controller: _contentController,
                  decoration: InputDecoration(
                    hintText: '开始写作…',
                    hintStyle: TextStyle(color: cs.onSurface.withValues(alpha: 0.2)),
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.zero,
                  ),
                  maxLines: null,
                  expands: true,
                  textAlignVertical: TextAlignVertical.top,
                  style: const TextStyle(fontSize: 15, height: 1.6),
                  keyboardType: TextInputType.multiline,
                ),
              ),
            ),
            // 底部统计栏
            Container(
              decoration: BoxDecoration(
                color: cs.surfaceContainerLow,
                border: Border(top: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.5))),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: SafeArea(
                top: false,
                child: Row(
                  children: [
                    Text(
                      '$_charCount 字',
                      style: TextStyle(fontSize: 12, color: cs.onSurface.withValues(alpha: 0.5)),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      '$_lineCount 行',
                      style: TextStyle(fontSize: 12, color: cs.onSurface.withValues(alpha: 0.4)),
                    ),
                    const Spacer(),
                    if (_dirty)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: cs.tertiaryContainer,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          '未保存',
                          style: TextStyle(fontSize: 11, color: cs.onTertiaryContainer),
                        ),
                      )
                    else
                      Icon(Icons.check_circle, size: 14, color: cs.primary.withValues(alpha: 0.5)),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
