<div align="center">

# 🔒 SCP基金会

> 控制 · 收容 · 保护 — SCP中分网站移动端阅读工具

<p align="center">
  <img src="https://img.shields.io/github/actions/workflow/status/JLeo0001/SCP-Flutter/build.yml?branch=main&label=CI&logo=github&style=flat-square" alt="CI"/>
  <img src="https://img.shields.io/github/v/release/JLeo0001/SCP-Flutter?label=version&logo=flutter&style=flat-square" alt="Release"/>
  <img src="https://img.shields.io/badge/Flutter-3.27-02569B?logo=flutter&logoColor=white&style=flat-square" alt="Flutter"/>
  <img src="https://img.shields.io/badge/Android-5%2B-34A853?logo=android&logoColor=white&style=flat-square" alt="Android 5+"/>
  <br>
  <img src="https://img.shields.io/badge/包名-com.jleoz.scp-FF6F00?style=flat-square" alt="Package"/>
  <img src="https://img.shields.io/badge/license-CC_BY--SA_3.0-yellow?style=flat-square" alt="License"/>
</p>

<p align="center">
  <a href="#-下载">📥 下载</a> ·
  <a href="#-功能特性">✨ 功能</a> ·
  <a href="#-截图">📸 截图</a> ·
  <a href="#-技术栈">⚙️ 技术</a> ·
  <a href="#-项目结构">📁 结构</a> ·
  <a href="#-开发指南">🚀 开发</a> ·
  <a href="#-致谢">🙏 致谢</a>
</p>

</div>

---

## 📥 下载

| 文件 | 架构 | 适用设备 | 体积 |
|:---|:---|:---|---:|
| `*-universal.apk` | arm64-v8a + armeabi-v7a | 全兼容 | 最大 |
| `*-arm64-v8a.apk` | **64位** | 2017年后安卓手机 ⭐ | 推荐 |
| `*-armeabi-v7a.apk` | 32位 | 老旧设备 | 较小 |

<p align="center">
  <a href="https://github.com/JLeo0001/SCP-Flutter/releases/latest">
    <img src="https://img.shields.io/badge/⬇_下载最新_APK-34A853?style=for-the-badge&logo=android&logoColor=white" alt="Download APK"/>
  </a>
  <a href="https://github.com/JLeo0001/SCP-Flutter/actions/workflows/build.yml">
    <img src="https://img.shields.io/badge/⚙_CI_构建产物-4285F4?style=for-the-badge&logo=githubactions&logoColor=white" alt="CI Artifacts"/>
  </a>
</p>

> 所有 APK 均使用 **release 签名**构建，可直接安装使用。<br>
> 最新开发版可从 [GitHub Actions](https://github.com/JLeo0001/SCP-Flutter/actions/workflows/build.yml) 的 Artifacts 下载。

---

## ✨ 功能特性

### 📚 浏览

| 模块 | 内容 | 数据源 |
|:---|:---|---:|
| **SCP系列** | SCP / SCP-CN 主系列，支持 I~X 系列筛选 | 本地数据库 |
| **故事与设定** | 基金会故事、CN原创、故事系列、设定中心 | 本地数据库 |
| **图书馆** | 用户推荐、异常物品、GOI格式、征文竞赛等 | Wikidot 在线 |
| **放逐者图书馆** | 中/英放逐者图书馆作品 | 本地数据库 |
| **SCP国际版** | 各国分部作品，按国家浏览 | 本地数据库 |
| **背景资料** | 设定中心、相关组织、设施、特遣队等 | 本地数据库 |

> 💡 本地数据库含 **25,000+ 条**条目目录，无需网络即可浏览。

### 🔍 发现

| 功能 | 说明 |
|:---|:---|
| **最新原创/翻译** | 首页实时展示最新创作 |
| **最高评分** | 全部 / SCP / 故事排行 |
| **标签云** | 按标签浏览作品 |
| **随机SCP** | 随机一篇文档 |
| **编号直达** | 输入编号快速跳转 |
| **全文搜索** | 标题搜索，实时结果 |

### 📖 阅读

| 特性 | 说明 |
|:---|:---|
| **WebView 渲染** | 原生 Wikidot 页面效果，支持脚注弹窗、折叠块、代码复制 |
| **阅读主题** | 浅色 / 护眼 / 深色 / 纯黑 四种预设 |
| **字号/字重/字体** | 12-32px、4级字重、系统/自定义字体 |
| **阅读设置** | 行高、段距、边距、对齐、首行缩进、标题倍率、代码字号 |
| **阅读标尺** | 横向参考线辅助阅读 |
| **引用块样式** | 强调 / 柔和 / 现代 三种风格 |
| **图片控制** | 显示/隐藏、全宽/适中/紧凑 |
| **自动滚动** | 速度可调，阅读更轻松 |
| **全屏阅读** | 沉浸式阅读体验 |
| **简繁切换** | 自动检测，智能转换 |
| **阅读位置记忆** | 每3秒自动保存，返回时精确定位 |
| **阅读进度条** | 顶部彩色进度指示 |

### 📋 管理

| 功能 | 说明 |
|:---|:---|
| **收藏** | ❤️ 收藏文档，列表管理 |
| **已读标记** | 标记已读/未读 |
| **待读列表** | 稍后阅读，左滑、多选批量管理 |
| **阅读历史** | 自动记录访问过的文档 |
| **草稿箱** | 本地编写/保存草稿，自动保存+撤回 |
| **外部字体** | 扫描 `/sdcard/Fonts/` 加载自定义字体 |

### 👤 个人

| 功能 | 说明 |
|:---|:---|
| **自定义代号** | 设置你的基金会代号 |
| **职务称号** | 阅读获取积分，解锁6种岗位等级 |
| **头像** | 从相册选择个人头像 |
| **最近阅读** | 快速回到上次阅读位置 |

---

## ⚙️ 技术栈

| 领域 | 技术 |
|:---|:---|
| **框架** | Flutter 3.27 · Dart 3.6+ |
| **设计** | Material Design 3 · 动态取色 |
| **WebView** | webview_flutter · JS交互 · CSS注入 |
| **数据库** | sqflite · 预置25k+条目目录 · 离线全文库(gzip+FTS5) |
| **网络** | http · 直连Wikidot爬取 |
| **存储** | SharedPreferences · 文件存储 |
| **CI/CD** | GitHub Actions · 三架构APK构建 |
| **最低支持** | Android 5.0 (API 21) |
| **目标架构** | arm64-v8a · armeabi-v7a · universal |

### 数据架构

```
assets/scp.db (预置, ~1.7MB)
  └─ scps 表 → 25,000+ 条条目目录

scp_data.db (运行时创建)
  ├─ page_cache         → HTML 内容缓存
  ├─ likes              → 收藏/已读
  ├─ records            → 历史/待读
  ├─ drafts             → 草稿
  └─ reading_positions  → 阅读位置

offline_content.db (可选下载, ~200-300MB)
  ├─ pages              → 正文 HTML (gzip压缩)
  ├─ pages_fts          → FTS5 全文索引
  ├─ resources          → CSS/JS 阅读模板
  └─ build_meta         → 构建信息
```

> **离线内容库**：从 GitHub Releases 下载，含全部页面的压缩正文 + FTS5 全文搜索。
> 每周自动构建，App 内一键下载/导入，启动自动恢复。
> 不含图片，gzip 压缩比约 25%，支持离线阅读和全文搜索。

---

## 🚀 开发指南

### 前置条件

```bash
flutter doctor
```

### 快速开始

```bash
git clone https://github.com/JLeo0001/SCP-Flutter.git
cd SCP-Flutter
flutter pub get
flutter run
```

### 构建 APK

```bash
# 通用版（全部架构）
flutter build apk --release

# 按架构拆分
flutter build apk --release --split-per-abi
```

| 构建产物 | 命令 |
|:---|:---|
| `universal.apk` | `flutter build apk --release` |
| `arm64-v8a.apk` | 上者 + `--split-per-abi` |
| `armeabi-v7a.apk` | 上者 + `--split-per-abi` |

---

## 📁 项目结构

```
lib/
├── main.dart                      # 入口
├── app.dart                       # 底部导航壳
├── core/
│   ├── constants.dart             # 常量
│   ├── theme/                     # 主题
│   ├── models/                    # 数据模型
│   ├── services/                  # 数据库/偏好/爬虫
│   └── utils/                     # 工具
├── features/
│   ├── home/                      # 首页
│   ├── category/                  # 分类浏览
│   ├── detail/                    # 阅读页 (WebView)
│   ├── later/                     # 待读/历史/已读/收藏
│   ├── search/                    # 搜索
│   ├── feed/                      # 最新/评分排行
│   ├── tag/                       # 标签
│   ├── library/                   # 图书馆
│   ├── story/                     # 故事与设定
│   ├── user/                      # 我的/关于
│   └── draft/                     # 草稿箱
```

---

## 🙏 致谢

- [SCP基金会中国分部](http://scp-wiki-cn.wikidot.com) — 内容来源
- [zhufree/SCP-Android](https://github.com/zhufree/SCP-Android) — 原Android版启发
- 所有SCP基金会贡献者

## 📄 许可

应用内内容遵循 **CC-BY-SA 3.0** 协议。

---

<p align="center">
  <a href="https://github.com/JLeo0001/SCP-Flutter">
    <img src="https://img.shields.io/badge/GitHub-JLeo0001%2FSCP--Flutter-181717?logo=github&style=for-the-badge" alt="GitHub"/>
  </a>
  <a href="https://github.com/JLeo0001/SCP-Flutter/issues">
    <img src="https://img.shields.io/badge/🐛_反馈问题-FF6B6B?style=for-the-badge" alt="Issues"/>
  </a>
  <a href="https://github.com/JLeo0001/SCP-Flutter/releases">
    <img src="https://img.shields.io/badge/📦_下载_APK-34A853?style=for-the-badge" alt="Releases"/>
  </a>
</p>

<p align="center"><sub>控制 · 收容 · 保护 · Made with Flutter</sub></p>
