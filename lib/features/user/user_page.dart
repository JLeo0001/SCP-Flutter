import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'about_page.dart';
import 'draft_list_page.dart';
import 'backup_page.dart';
import 'favorite_list_page.dart';
import 'download_page.dart';
import '../later/later_page.dart';
import '../../core/theme/app_theme.dart';
import '../../core/services/preference_service.dart';
import '../../core/services/database_helper.dart';
import '../../core/utils/route_observer.dart';
import '../../core/constants.dart';
import '../ai/ai_settings_page.dart';
import '../detail/detail_page.dart';

/// 用户页 — 对应 UserFragment.kt
class UserPage extends StatefulWidget {
  /// 主框架底部 tab 索引通知 — 用于切回本页时刷新统计数据
  final ValueNotifier<int>? tabIndex;

  const UserPage({super.key, this.tabIndex});

  @override
  State<UserPage> createState() => _UserPageState();
}

class _UserPageState extends State<UserPage>
    with WidgetsBindingObserver, RouteAware {
  File? _avatarFile;
  int _readCount = 0;
  int _laterCount = 0;
  final List<Map<String, String>> _recentHistory = [];

  static const _jobs = [
    '收容专家',
    '研究员',
    '安全人员',
    '战术反应人员',
    '外勤特工',
    '机动特遣队作业员',
  ];

  static const _jobRanks = [
    ['实习', '支援', '助理', '', '独立', '特级'],
    ['见习', '助理', '副', '', '高级', '主管'],
    ['实习', '一级', '二级', '组长', '参谋', '保安官'],
    ['实习', '支援', '一级', '二级', '三级', '小组组长'],
    ['实习', '支援', '辅助', '', '独立', '特级'],
    ['实习', '支援', '参谋', '队长', '指挥官', '主管'],
  ];

  static const _jobSuffix = [
    '收容技师',
    '研究员',
    '守卫',
    '战术反应人员',
    '外勤特工',
    '机动特遣队作业员',
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.tabIndex?.addListener(_onTabChanged);
    _userId = _initUserId();
    _loadAvatar();
    _loadStats();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route is PageRoute) {
      RouteObservers.observer.subscribe(this, route);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    RouteObservers.observer.unsubscribe(this);
    widget.tabIndex?.removeListener(_onTabChanged);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _loadStats();
    }
  }

  /// 从详情页等上层路由返回时刷新
  @override
  void didPopNext() {
    _loadStats();
  }

  /// 底部 tab 切换时刷新（切回本页即更新，覆盖 IndexedStack 不重建子页的情况）
  void _onTabChanged() {
    if (mounted) _loadStats();
  }

  void _loadAvatar() {
    // 头像文件存在 app 私有目录
    getApplicationDocumentsDirectory().then((dir) {
      final file = File('${dir.path}/user_head.jpg');
      if (file.existsSync()) {
        setState(() => _avatarFile = file);
      }
    });
  }

  Future<void> _loadStats() async {
    try {
      final rc = await DatabaseHelper.getReadCount();
      final lc = await DatabaseHelper.getRecordCount(SCPConstants.laterType);
      final records = await DatabaseHelper.getRecords(SCPConstants.historyType);
      if (mounted) {
        setState(() {
          _readCount = rc;
          _laterCount = lc;
          _recentHistory
            ..clear()
            ..addAll(records.take(3).map((r) => {
                  'title': r.title,
                  'link': r.link,
                  'time': r.showTime,
                }));
        });
      }
    } catch (_) {}
  }

  String _getRank(int point) {
    final job = PreferenceService.getJob();
    final jobIdx = _jobs.indexOf(job);
    if (jobIdx < 0) return 'D级人员';

    int level;
    if (point < 200) {
      level = 0;
    } else if (point < 700) {
      level = 1;
    } else if (point < 1500) {
      level = 2;
    } else if (point < 2500) {
      level = 3;
    } else if (point < 4000) {
      level = 4;
    } else if (point < 8000) {
      level = 5;
    } else {
      level = 5;
    }

    final rank = _jobRanks[jobIdx][level];
    final suffix = _jobSuffix[jobIdx];
    final levelLabel = level >= 3 ? '${['C', 'B', 'A'][level - 3]}级' : '';
    return '$levelLabel$rank$suffix';
  }

  String _userId = '000';

  String _initUserId() {
    var id = PreferenceService.getUserId();
    if (id.isEmpty) {
      id = DateTime.now().microsecondsSinceEpoch.remainder(600).abs().toString().padLeft(3, '0');
      PreferenceService.setUserId(id);
    }
    return id;
  }

  void _showNicknameDialog() {
    final controller =
        TextEditingController(text: PreferenceService.getNickname());
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('欢迎来到SCP基金会，调查员'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            hintText: '请输入你的名字',
            border: OutlineInputBorder(),
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('取消')),
          TextButton(
            onPressed: () {
              PreferenceService.saveNickname(controller.text.trim());
              Navigator.pop(ctx);
              setState(() {});
            },
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  void _showJobDialog() {
    final current = PreferenceService.getJob();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
            '欢迎来到SCP基金会，${PreferenceService.getNickname().isEmpty ? '调查员' : PreferenceService.getNickname()}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: _jobs.map((job) {
            return RadioListTile<String>(
              title: Text(job),
              value: job,
              groupValue: current,
              onChanged: (v) {
                PreferenceService.setJob(v!);
                Navigator.pop(ctx);
                setState(() {});
              },
            );
          }).toList(),
        ),
      ),
    );
  }

  Future<void> _pickAvatar() async {
    final picker = ImagePicker();
    final xFile = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 512,
      maxHeight: 512,
    );
    if (xFile != null) {
      final dir = await getApplicationDocumentsDirectory();
      final dest = File('${dir.path}/user_head.jpg');
      await dest.writeAsBytes(await xFile.readAsBytes());
      setState(() => _avatarFile = dest);
    }
  }

  void _showThemeDialog() {
    final current = AppTheme.currentTheme;
    final options = ['跟随系统', '日间模式', '夜间模式'];
    final icons = [Icons.brightness_auto, Icons.light_mode, Icons.dark_mode];

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('主题模式'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(3, (i) {
            return RadioListTile<int>(
              title: Row(children: [
                Icon(icons[i], size: 20),
                const SizedBox(width: 12),
                Text(options[i]),
              ]),
              value: i,
              groupValue: current,
              onChanged: (v) {
                AppTheme.setTheme(v!);
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('主题已切换'),
                    duration: Duration(milliseconds: 800),
                  ),
                );
              },
            );
          }),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final nickname = PreferenceService.getNickname();
    final job = PreferenceService.getJob();
    final hasName = nickname.isNotEmpty;

    return Scaffold(
      appBar: AppBar(title: const Text('我的')),
      body: ListView(
        children: [
          // 用户信息卡片
          _buildUserCard(cs, nickname, job, hasName),
          const Divider(),
          // 最近阅读
          if (_recentHistory.isNotEmpty) ...[
            _buildRecentHistory(cs),
            const Divider(),
          ],
          // 功能列表
          _buildMenuItem(Icons.edit_note, '草稿箱', () {
            Navigator.push(context,
                MaterialPageRoute(builder: (_) => const DraftListPage()));
          }),
          _buildMenuItem(Icons.bookmarks, '自由收藏', () {
            Navigator.push(context,
                MaterialPageRoute(builder: (_) => const FavoriteListPage()));
          }),
          _buildMenuItem(Icons.backup, '备份与恢复', () {
            Navigator.push(context,
                MaterialPageRoute(builder: (_) => const BackupPage()));
          }),
          _buildMenuItem(Icons.download, '文档缓存/本地数据', () {
            Navigator.push(context,
                MaterialPageRoute(builder: (_) => const DownloadPage()));
          }),
          const Divider(),
          _buildMenuItem(
            Icons.auto_awesome,
            'AI 设置',
            () {
              Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const AiSettingsPage()));
            },
            trailing: const Icon(Icons.chevron_right),
          ),
          _buildMenuItem(
            _themeIcon(),
            _themeLabel(),
            _showThemeDialog,
            trailing: const Icon(Icons.chevron_right),
          ),
          _buildMenuItem(Icons.info_outline, '关于', () {
            Navigator.push(context,
                MaterialPageRoute(builder: (_) => const AboutPage()));
          }),
          const SizedBox(height: 32),
          Center(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                '控制 · 收容 · 保护',
                style: TextStyle(
                  fontSize: 16,
                  color: theme.disabledColor,
                  letterSpacing: 4,
                ),
              ),
            ),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _buildUserCard(
      ColorScheme cs, String nickname, String job, bool hasName) {
    return Card(
      margin: const EdgeInsets.all(16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // 头像 + 代号
            Row(
              children: [
                GestureDetector(
                  onTap: _pickAvatar,
                  child: CircleAvatar(
                    radius: 36,
                    backgroundColor: cs.primaryContainer,
                    backgroundImage:
                        _avatarFile != null ? FileImage(_avatarFile!) : null,
                    child: _avatarFile == null
                        ? Icon(Icons.person, size: 36, color: cs.onPrimaryContainer)
                        : null,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      GestureDetector(
                        onTap: _showNicknameDialog,
                        child: Text(
                          hasName ? '代号：$nickname' : '代号：点击设置',
                          style: const TextStyle(
                              fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                      ),
                      const SizedBox(height: 4),
                      GestureDetector(
                        onTap: _showJobDialog,
                        child: Text(
                          '编号：$_userId\n'
                          '职务：${hasName ? _getRank(PreferenceService.getPoint()) : '点击设置'}',
                          style: TextStyle(
                            fontSize: 13,
                            color: cs.onSurfaceVariant,
                            height: 1.4,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

              ],
            ),
            const SizedBox(height: 16),
            // 数据统计
            Row(
              children: [
                _statChip(cs, Icons.menu_book, '已研究项目', _readCount, 2),
                const SizedBox(width: 12),
                _statChip(cs, Icons.bookmark, '已跟踪项目', _laterCount, 0),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// 统计卡片 — 点击跳转到对应的列表页（2=已读, 0=待读）
  Widget _statChip(
      ColorScheme cs, IconData icon, String label, int count, int initialTab) {
    return Expanded(
      child: GestureDetector(
        onTap: () => Navigator.push(context,
            MaterialPageRoute(builder: (_) => LaterPage(initialTab: initialTab))),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: cs.surfaceContainerHighest.withValues(alpha: 0.3),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 16, color: cs.primary),
              const SizedBox(width: 6),
              Text('$label：$count',
                  style: TextStyle(fontSize: 13, color: cs.onSurface)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRecentHistory(ColorScheme cs) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('最近阅读',
                  style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: cs.onSurface)),
              TextButton(
                onPressed: () => Navigator.push(context,
                    MaterialPageRoute(builder: (_) => const LaterPage(initialTab: 1))),
                child: const Text('更多 ›', style: TextStyle(fontSize: 13)),
              ),
            ],
          ),
        ),
        ..._recentHistory.map((item) => ListTile(
              dense: true,
              title: Text(item['title'] ?? '',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 14)),
              trailing: Text(item['time'] ?? '',
                  style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
              onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => DetailPage(
                          link: item['link'] ?? '',
                          title: item['title'] ?? ''))),
            )),
      ],
    );
  }

  String _themeLabel() {
    switch (AppTheme.currentTheme) {
      case ThemeModeOption.light:
        return '日间模式';
      case ThemeModeOption.dark:
        return '夜间模式';
      default:
        return '跟随系统';
    }
  }

  IconData _themeIcon() {
    switch (AppTheme.currentTheme) {
      case ThemeModeOption.light: return Icons.light_mode;
      case ThemeModeOption.dark:  return Icons.dark_mode;
      default:                    return Icons.brightness_auto;
    }
  }

  Widget _buildMenuItem(IconData icon, String title, VoidCallback onTap,
      {Widget? trailing}) {
    return ListTile(
      leading: Icon(icon),
      title: Text(title),
      trailing: trailing ?? const Icon(Icons.chevron_right),
      onTap: onTap,
    );
  }
}
