import 'package:material_ui/material_ui.dart';

import 'about.dart';
import 'edit_sheet.dart';
import 'engine.dart';
import 'state.dart';
import 'theme.dart';
import 'tools_panel.dart';
import 'widgets.dart';

/// Port of MainScreen in MainActivity.kt: directory browsing, file rows
/// grouped by SxxEyy, tools panel, bottom status/nav pills, edit sheet,
/// batch edit, rename confirm with live progress, directory rename.
class MainScreen extends StatefulWidget {
  final AppState state;
  const MainScreen(this.state, {super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  final _scrollCtrl = ScrollController();
  RowState? _singleRenameRow;
  final _dirRenameCtrl = TextEditingController();

  AppState get state => widget.state;

  @override
  void initState() {
    super.initState();
    _scrollCtrl.addListener(() {
      state.scrollMemory[state.currentPath] = _scrollCtrl.offset;
    });
    state.addListener(_onStateChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) => _reload());
  }

  @override
  void dispose() {
    _scrollCtrl.dispose();
    _dirRenameCtrl.dispose();
    state.removeListener(_onStateChanged);
    super.dispose();
  }

  void _onStateChanged() {
    // Tools panel collapses on directory change (native: LaunchedEffect
    // on currentPath).
    // (Handled in _goTo; kept here only for external path changes.)
  }

  void _showSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), duration: const Duration(seconds: 2)),
    );
  }

  Future<void> _reload({bool force = false}) async {
    try {
      await state.loadDir(force: force);
      _restoreScroll();
    } catch (e) {
      _showSnack('加载失败：${state.loadError}');
    }
  }

  void _restoreScroll() {
    final off = state.scrollMemory[state.currentPath];
    if (off == null || !_scrollCtrl.hasClients) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollCtrl.hasClients) return;
      final max = _scrollCtrl.position.maxScrollExtent;
      _scrollCtrl.jumpTo(off.clamp(0.0, max));
    });
  }

  void _goTo(String path) {
    state.currentPath = path;
    state.toolsOpen = false;
    state.touch();
    _reload();
  }

  int _itemCount() {
    var n = 3; // title, breadcrumb, tools toggle
    if (state.toolsOpen) n += 1;
    n += state.directories.length;
    if (state.loadError.isNotEmpty) n += 1;
    if (!state.loading && state.loadError.isEmpty && state.rows.isEmpty) {
      n += 1;
    }
    n += state.rows.length;
    return n;
  }

  Widget _buildItem(int index) {
    var i = index;
    if (i == 0) return _titleItem();
    i--;
    if (i == 0) return _breadcrumbItem();
    i--;
    if (i == 0) return _toolsToggleItem();
    i--;
    if (state.toolsOpen) {
      if (i == 0) {
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: ToolsPanel(state: state, showSnack: _showSnack),
        );
      }
      i--;
    }
    if (i < state.directories.length) {
      return _dirItem(state.directories[i]);
    }
    i -= state.directories.length;
    if (state.loadError.isNotEmpty) {
      if (i == 0) return _errorItem();
      i--;
    }
    if (!state.loading && state.loadError.isEmpty && state.rows.isEmpty) {
      if (i == 0) return _emptyItem();
      i--;
    }
    return _rowItem(state.rows[i]);
  }

  Widget _titleItem() {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
      child: Text(
        dirNameOf(state.currentPath).isEmpty
            ? '根目录'
            : dirNameOf(state.currentPath),
        style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              color: state.darkTheme ? Colors.white : scheme.onSurface,
            ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }

  Widget _breadcrumbItem() {
    final parts =
        state.currentPath.split('/').where((e) => e.isNotEmpty).toList();
    return SizedBox(
      height: 36,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        separatorBuilder: (_, _) => const SizedBox(width: 4),
        itemCount: parts.length + 1,
        itemBuilder: (context, i) {
          if (i == 0) {
            return ActionChip(
              onPressed: () => _goTo('/'),
              avatar: const Icon(Icons.home, size: 14),
              label: const Text('/'),
            );
          }
          final p = '/${parts.sublist(0, i).join('/')}';
          return ActionChip(
            onPressed: () => _goTo(p),
            label: Text(parts[i - 1]),
          );
        },
      ),
    );
  }

  Widget _toolsToggleItem() {
    final scheme = Theme.of(context).colorScheme;
    final open = state.toolsOpen;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: SizedBox(
        height: 50,
        width: double.infinity,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          decoration: BoxDecoration(
            color: open ? scheme.surface : scheme.primary,
            borderRadius: BorderRadius.circular(50),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.12),
                blurRadius: 8,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(50),
              onTap: () {
                state.toolsOpen = !state.toolsOpen;
                state.touch();
              },
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.build,
                      size: 19,
                      color: open ? scheme.primary : scheme.onPrimary),
                  const SizedBox(width: 8),
                  Text(
                    open
                        ? '收起批量工具'
                        : '批量工具 · TMDB · 集名刮削 · 编号 · 参数',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          color: open ? scheme.primary : scheme.onPrimary,
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                  const SizedBox(width: 6),
                  Icon(
                    open ? Icons.expand_less : Icons.expand_more,
                    size: 19,
                    color: open ? scheme.primary : scheme.onPrimary,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _dirItem(FsItem dir) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
      child: GlassCard(
        radius: 22,
        onTap: () => _goTo(state.currentPath == '/'
            ? '/${dir.name}'
            : '${state.currentPath}/${dir.name}'),
        child: Padding(
          padding:
              const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: scheme.primaryContainer,
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Icon(Icons.folder,
                    color: scheme.primary, size: 20),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  dir.name,
                  style: Theme.of(context).textTheme.bodyMedium,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              IconButton(
                onPressed: () => _showDirRenameDialog(dir),
                icon: Icon(Icons.edit,
                    size: 16, color: scheme.onSurfaceVariant),
                constraints: const BoxConstraints.tightFor(
                    width: 32, height: 32),
                padding: EdgeInsets.zero,
              ),
              Icon(Icons.chevron_right,
                  size: 18, color: scheme.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }

  Widget _errorItem() {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Icon(Icons.cloud_off, color: scheme.error, size: 32),
          const SizedBox(height: 6),
          const Text('目录加载失败',
              style: TextStyle(fontWeight: FontWeight.w600)),
          Text(state.loadError,
              style: TextStyle(color: scheme.error, fontSize: 13)),
          const SizedBox(height: 8),
          OutlinedButton(
              onPressed: () => _reload(), child: const Text('重试')),
        ],
      ),
    );
  }

  Widget _emptyItem() {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Text(
        '当前目录没有可重命名的媒体文件',
        style: Theme.of(context)
            .textTheme
            .bodySmall
            ?.copyWith(color: scheme.onSurfaceVariant),
      ),
    );
  }

  Widget _rowItem(RowState row) {
    final scheme = Theme.of(context).colorScheme;
    final preview = state.previewName(row);
    final changed = preview != row.name;
    final checked = state.selected.contains(row.name);
    final grp = row.names.length > 1 ? ' · 同名 ${row.names.length} 个' : '';
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
      child: GlassCard(
        radius: 22,
        color: checked
            ? scheme.primaryContainer.withValues(alpha: 0.45)
            : null,
        border: Border.all(
          color: checked ? scheme.primary : scheme.outlineVariant,
          width: checked ? 1.5 : 1,
        ),
        onTap: () => _openEditSheet(row),
        child: Row(
          children: [
            Checkbox(
              value: checked,
              onChanged: (v) {
                state.selected = v == true
                    ? {...state.selected, row.name}
                    : state.selected.where((e) => e != row.name).toSet();
                state.touch();
              },
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text('原名',
                            style: Theme.of(context)
                                .textTheme
                                .labelSmall
                                ?.copyWith(
                                    color: scheme.onSurfaceVariant)),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            row.name,
                            style:
                                Theme.of(context).textTheme.bodyMedium,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 7, vertical: 2),
                          decoration: BoxDecoration(
                            color: scheme.primaryContainer,
                            borderRadius: BorderRadius.circular(50),
                          ),
                          child: Text(
                            state.mediaType == 'movie'
                                ? (row.year.isEmpty ? '电影' : row.year)
                                : 'S${pad2(row.season)}E${pad2(row.episode)}',
                            style: Theme.of(context)
                                .textTheme
                                .labelSmall
                                ?.copyWith(
                                  color: scheme.onPrimaryContainer,
                                  fontWeight: FontWeight.bold,
                                ),
                          ),
                        ),
                      ],
                    ),
                    if (changed)
                      Row(
                        children: [
                          Text('新名',
                              style: Theme.of(context)
                                  .textTheme
                                  .labelSmall
                                  ?.copyWith(
                                    color: scheme.primary,
                                    fontWeight: FontWeight.bold,
                                  )),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text.rich(
                              TextSpan(children: [
                                diffSpans(row.name, preview,
                                    scheme.onSurfaceVariant, scheme.primary),
                                TextSpan(
                                  text: grp,
                                  style: TextStyle(
                                      color: scheme.onSurfaceVariant),
                                ),
                              ]),
                              style: Theme.of(context).textTheme.bodySmall,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      )
                    else
                      Text(
                        '未修改$grp',
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.copyWith(color: scheme.onSurfaceVariant),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _openEditSheet(RowState row) {
    state.editingRow = row;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (context) => EditSheet(
        state: state,
        row: row,
        showSnack: _showSnack,
        onSingleRename: () {
          Navigator.of(context).pop();
          _singleRenameRow = row;
          _showConfirmDialog();
        },
      ),
    ).whenComplete(() {
      state.editingRow = null;
    });
  }

  void _openBatchSheet() {
    state.batchOpen = true;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (context) =>
          BatchEditSheet(state: state, showSnack: _showSnack),
    ).whenComplete(() {
      state.batchOpen = false;
    });
  }

  Future<void> _showDirRenameDialog(FsItem dir) async {
    _dirRenameCtrl.text = dir.name;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('重命名目录'),
        content: TextField(
          controller: _dirRenameCtrl,
          decoration: const InputDecoration(labelText: '新名称'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('确定'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final newName = _dirRenameCtrl.text.trim();
    if (newName.isEmpty || newName == dir.name) return;
    final done = await state.renameDirectory(dir, newName);
    if (!mounted) return;
    _showSnack(done ? '目录已重命名' : '重命名失败');
  }

  List<RowState> _confirmChanges() {
    if (_singleRenameRow != null) return [_singleRenameRow!];
    if (state.selected.isNotEmpty) {
      return state.rows
          .where((r) =>
              state.selected.contains(r.name) &&
              state.previewName(r) != r.name)
          .toList();
    }
    return state.rows.where((r) => state.previewName(r) != r.name).toList();
  }

  void _showConfirmDialog() {
    final changes = _confirmChanges();
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => _ConfirmRenameDialog(
        state: state,
        changes: changes,
        onDone: () {
          _singleRenameRow = null;
        },
      ),
    ).whenComplete(() {
      _singleRenameRow = null;
      state.commitFinished = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final navTint =
        state.darkTheme ? Colors.white : scheme.onSurface;
    return PopScope(
      canPop: state.currentPath == '/',
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && state.currentPath != '/') {
          _goTo(parentOf(state.currentPath));
        }
      },
      child: Scaffold(
        backgroundColor: Colors.transparent,
        bottomNavigationBar: Padding(
          padding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Status / rename pill.
              Container(
                decoration: BoxDecoration(
                  color: scheme.surface.withValues(alpha: 0.96),
                  borderRadius: BorderRadius.circular(28),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.10),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                child: state.selected.isNotEmpty
                    ? Row(
                        children: [
                          Text(
                            '已选 ${state.selected.length}',
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(
                                  color: scheme.primary,
                                  fontWeight: FontWeight.w600,
                                ),
                          ),
                          TextButton(
                            onPressed: () {
                              state.selected =
                                  state.rows.map((r) => r.name).toSet();
                              state.touch();
                            },
                            child: const Text('全选'),
                          ),
                          TextButton(
                            onPressed: () {
                              state.selected = {};
                              state.touch();
                            },
                            child: const Text('取消'),
                          ),
                          const Spacer(),
                          FilledButton.icon(
                            onPressed: _openBatchSheet,
                            icon: const Icon(Icons.edit, size: 16),
                            label: const Text('批量编辑'),
                            style: FilledButton.styleFrom(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 6),
                            ),
                          ),
                          const SizedBox(width: 6),
                          FilledButton.icon(
                            onPressed: state.rows.any((r) =>
                                        state.selected.contains(r.name) &&
                                        state.previewName(r) != r.name) &&
                                    !state.committing
                                ? _showConfirmDialog
                                : null,
                            icon: const Icon(Icons.drive_file_rename_outline,
                                size: 16),
                            label: const Text('重命名'),
                            style: FilledButton.styleFrom(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 6),
                            ),
                          ),
                        ],
                      )
                    : Row(
                        children: [
                          Text(
                            '${state.rows.length} 文件 · ${state.renameableCount} 待改',
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(color: scheme.onSurfaceVariant),
                          ),
                          const Spacer(),
                          FilledButton.icon(
                            onPressed: state.renameableCount > 0 &&
                                    !state.committing
                                ? _showConfirmDialog
                                : null,
                            icon: state.committing
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : const Icon(
                                    Icons.drive_file_rename_outline,
                                    size: 16),
                            label: const Text('重命名'),
                          ),
                        ],
                      ),
              ),
              const SizedBox(height: 8),
              // Nav pill.
              Align(
                alignment: Alignment.center,
                child: Container(
                  decoration: BoxDecoration(
                    color: scheme.surface.withValues(alpha: 0.96),
                    borderRadius: BorderRadius.circular(50),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.12),
                        blurRadius: 14,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        onPressed: () => _goTo('/'),
                        icon: Icon(Icons.home, color: navTint),
                        tooltip: '根目录',
                      ),
                      IconButton(
                        onPressed: state.currentPath != '/'
                            ? () => _goTo(parentOf(state.currentPath))
                            : null,
                        icon: Icon(Icons.arrow_back, color: navTint),
                        tooltip: '上级目录',
                      ),
                      IconButton(
                        onPressed: () => _reload(force: true),
                        icon: Icon(Icons.refresh, color: navTint),
                        tooltip: '刷新',
                      ),
                      IconButton(
                        onPressed: () {
                          state.darkTheme = !state.darkTheme;
                          state.saveSetting();
                          state.touch();
                        },
                        icon: Icon(
                          state.darkTheme
                              ? Icons.light_mode
                              : Icons.dark_mode,
                          color: navTint,
                        ),
                        tooltip: '主题',
                      ),
                      IconButton(
                        onPressed: () => showModalBottomSheet(
                          context: context,
                          isScrollControlled: true,
                          shape: const RoundedRectangleBorder(
                            borderRadius: BorderRadius.vertical(
                                top: Radius.circular(28)),
                          ),
                          builder: (context) => const AboutSheet(),
                        ),
                        icon: Icon(Icons.info, color: navTint),
                        tooltip: '关于',
                      ),
                      IconButton(
                        onPressed: () => state.logout(),
                        icon: Icon(Icons.logout, color: navTint),
                        tooltip: '退出',
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        body: Stack(
          children: [
            ListView.builder(
              controller: _scrollCtrl,
              itemCount: _itemCount(),
              padding: const EdgeInsets.symmetric(vertical: 4),
              itemBuilder: (context, index) => _buildItem(index),
            ),
            if (state.loading)
              const Align(
                alignment: Alignment.topCenter,
                child: LinearProgressIndicator(),
              ),
          ],
        ),
      ),
    );
  }
}

/// Rename confirm dialog with live progress (port of the showConfirm
/// AlertDialog in MainScreen).
class _ConfirmRenameDialog extends StatefulWidget {
  final AppState state;
  final List<RowState> changes;
  final VoidCallback onDone;

  const _ConfirmRenameDialog({
    required this.state,
    required this.changes,
    required this.onDone,
  });

  @override
  State<_ConfirmRenameDialog> createState() => _ConfirmRenameDialogState();
}

class _ConfirmRenameDialogState extends State<_ConfirmRenameDialog> {
  bool _started = false;

  AppState get state => widget.state;

  void _run() {
    setState(() => _started = true);
    state.commitRename(widget.changes);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return PopScope(
      canPop: !state.committing,
      child: AnimatedBuilder(
        animation: state,
        builder: (context, _) {
          final running = state.committing;
          final done = state.commitFinished;
          return AlertDialog(
            title: Text(
              done
                  ? '重命名完成'
                  : running
                      ? '正在重命名'
                      : '确认重命名 ${widget.changes.length} 个文件？',
            ),
            content: SizedBox(
              width: double.maxFinite,
              child: (running || done)
                  ? Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        LinearProgressIndicator(
                          value: state.commitTotal > 0
                              ? state.commitDoneCount / state.commitTotal
                              : 0,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '正在改 ${state.commitDoneCount}/${state.commitTotal}',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        if (done) ...[
                          const SizedBox(height: 4),
                          Text(
                            '成功 ${state.commitDoneCount - state.commitFailedNames.length} 个，失败 ${state.commitFailedNames.length} 个',
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(fontWeight: FontWeight.w600),
                          ),
                          if (state.commitFailedNames.isNotEmpty)
                            SizedBox(
                              height: 160,
                              child: ListView.builder(
                                itemCount: state.commitFailedNames.length,
                                itemBuilder: (context, i) => Text(
                                  state.commitFailedNames[i],
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodySmall
                                      ?.copyWith(color: scheme.error),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ),
                        ],
                      ],
                    )
                  : SizedBox(
                      height: 320,
                      child: ListView.builder(
                        itemCount: widget.changes.length,
                        itemBuilder: (context, i) {
                          final r = widget.changes[i];
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 3),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  r.name,
                                  style:
                                      Theme.of(context).textTheme.bodySmall,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                Text.rich(
                                  TextSpan(children: [
                                    const TextSpan(text: '→ '),
                                    diffSpans(
                                        r.name,
                                        state.previewName(r),
                                        scheme.onSurfaceVariant,
                                        scheme.primary),
                                    if (r.names.length > 1)
                                      TextSpan(
                                        text:
                                            '（同名共 ${r.names.length} 个一起改）',
                                        style: TextStyle(
                                            color:
                                                scheme.onSurfaceVariant),
                                      ),
                                  ]),
                                  style:
                                      Theme.of(context).textTheme.bodySmall,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
            ),
            actions: [
              if (done)
                TextButton(
                  onPressed: () {
                    widget.onDone();
                    Navigator.of(context).pop();
                  },
                  child: const Text('完成'),
                )
              else if (!running)
                TextButton(
                  onPressed: _started ? null : _run,
                  child: const Text('执行'),
                ),
              if (!running && !done)
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('取消'),
                ),
            ],
          );
        },
      ),
    );
  }
}
