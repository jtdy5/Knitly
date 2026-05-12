import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';
import 'package:shared_preferences/shared_preferences.dart';

// --- MODELS ---

class KnittingCounter {
  final String id;
  String name;
  int currentRow;
  Map<int, String> instructions;
  String? linkedToCounterId;
  int linkType; // 0: None, 1: One-Way (Sec->Glob), 2: Both-Ways (Sync)
  int? autoResetTarget;
  int colorValue;

  KnittingCounter({
    required this.id,
    required this.name,
    this.currentRow = 0,
    this.instructions = const {},
    this.linkedToCounterId,
    this.linkType = 0,
    this.autoResetTarget,
    this.colorValue = 0xFF2196F3,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'currentRow': currentRow,
        'instructions':
            instructions.map((key, value) => MapEntry(key.toString(), value)),
        'linkedToCounterId': linkedToCounterId,
        'linkType': linkType,
        'autoResetTarget': autoResetTarget,
        'colorValue': colorValue,
      };

  factory KnittingCounter.fromJson(Map<String, dynamic> json) =>
      KnittingCounter(
        id: json['id'],
        name: json['name'],
        currentRow: json['currentRow'] ?? 0,
        instructions: (json['instructions'] as Map<String, dynamic>?)?.map(
                (key, value) => MapEntry(int.parse(key), value.toString())) ??
            {},
        linkedToCounterId: json['linkedToCounterId'],
        linkType: json['linkType'] ?? 0,
        autoResetTarget: json['autoResetTarget'],
        colorValue: json['colorValue'] ?? 0xFF2196F3,
      );
}

class ProjectPart {
  final String id;
  String name;
  List<KnittingCounter> counters;

  ProjectPart({required this.id, required this.name, required this.counters});

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'counters': counters.map((c) => c.toJson()).toList(),
      };

  factory ProjectPart.fromJson(Map<String, dynamic> json) => ProjectPart(
        id: json['id'],
        name: json['name'],
        counters: (json['counters'] as List)
            .map((c) => KnittingCounter.fromJson(c))
            .toList(),
      );
}

class KnittingProject {
  final String id;
  String name;
  List<ProjectPart> parts;
  bool isArchived;

  KnittingProject(
      {required this.id,
      required this.name,
      required this.parts,
      this.isArchived = false});

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'parts': parts.map((p) => p.toJson()).toList(),
        'isArchived': isArchived,
      };

  factory KnittingProject.fromJson(Map<String, dynamic> json) =>
      KnittingProject(
        id: json['id'],
        name: json['name'],
        parts: (json['parts'] as List)
            .map((p) => ProjectPart.fromJson(p))
            .toList(),
        isArchived: json['isArchived'] ?? false,
      );
}

// --- PROVIDER ---

class ProjectProvider extends ChangeNotifier {
  List<KnittingProject> _projects = [];
  bool isInitialized = false;
  bool showArchived = false;

  String? _activeProjectId;
  String? _activePartId;
  String? _floatingCounterId;
  double _floatX = 20.0;
  double _floatY = 100.0;
  bool _floatShowNext = false;

  String? get activeProjectId => _activeProjectId;
  String? get activePartId => _activePartId;
  String? get floatingCounterId => _floatingCounterId;
  double get floatX => _floatX;
  double get floatY => _floatY;
  bool get floatShowNext => _floatShowNext;

  List<KnittingProject> get projects => showArchived
      ? _projects.where((p) => p.isArchived).toList()
      : _projects.where((p) => !p.isArchived).toList();

  ProjectProvider() {
    _loadFromLocal();
  }

  Future<void> _loadFromLocal() async {
    final prefs = await SharedPreferences.getInstance();
    final String? projectsJson = prefs.getString('saved_projects');
    if (projectsJson != null) {
      final List<dynamic> decoded = jsonDecode(projectsJson);
      _projects = decoded.map((p) => KnittingProject.fromJson(p)).toList();
    }
    _activeProjectId = prefs.getString('active_project_id');
    _activePartId = prefs.getString('active_part_id');
    _floatingCounterId = prefs.getString('floating_counter_id');
    _floatX = prefs.getDouble('float_x') ?? 20.0;
    _floatY = prefs.getDouble('float_y') ?? 100.0;
    _floatShowNext = prefs.getBool('float_show_next') ?? false;

    isInitialized = true;
    notifyListeners();
  }

  Future<void> _autoSave() async {
    final prefs = await SharedPreferences.getInstance();
    final String encoded =
        jsonEncode(_projects.map((p) => p.toJson()).toList());
    await prefs.setString('saved_projects', encoded);
  }

  Future<void> setActiveNavigation(String? projId, String? partId) async {
    _activeProjectId = projId;
    _activePartId = partId;
    final prefs = await SharedPreferences.getInstance();
    projId != null
        ? await prefs.setString('active_project_id', projId)
        : await prefs.remove('active_project_id');
    partId != null
        ? await prefs.setString('active_part_id', partId)
        : await prefs.remove('active_part_id');
    notifyListeners();
  }

  Future<void> setFloatingState(
      String? counterId, double x, double y, bool showNext) async {
    _floatingCounterId = counterId;
    _floatX = x;
    _floatY = y;
    _floatShowNext = showNext;
    final prefs = await SharedPreferences.getInstance();
    if (counterId != null) {
      await prefs.setString('floating_counter_id', counterId);
      await prefs.setDouble('float_x', x);
      await prefs.setDouble('float_y', y);
      await prefs.setBool('float_show_next', showNext);
    } else {
      await prefs.remove('floating_counter_id');
    }
    notifyListeners();
  }

  void updateRow(String projectId, String partId, String counterId, int delta) {
    final part = getPart(projectId, partId);
    final globalCounter = part.counters.first;
    final clickedCounter = part.counters.firstWhere((c) => c.id == counterId);

    if (clickedCounter.id == globalCounter.id) {
      _applyDeltaWithAutoReset(globalCounter, delta);
      for (var sec in part.counters.skip(1)) {
        if (sec.linkType == 2) _applyDeltaWithAutoReset(sec, delta);
      }
    } else {
      _applyDeltaWithAutoReset(clickedCounter, delta);
      if (clickedCounter.linkType > 0) {
        _applyDeltaWithAutoReset(globalCounter, delta);
        for (var sec in part.counters.skip(1)) {
          if (sec.id != clickedCounter.id && sec.linkType == 2) {
            _applyDeltaWithAutoReset(sec, delta);
          }
        }
      }
    }
    _autoSave();
    notifyListeners();
  }

  void _applyDeltaWithAutoReset(KnittingCounter counter, int delta) {
    int nextValue = counter.currentRow + delta;
    if (nextValue < 0) return;
    if (counter.autoResetTarget != null &&
        delta > 0 &&
        nextValue > counter.autoResetTarget!) {
      counter.currentRow = 0;
    } else {
      counter.currentRow = nextValue;
    }
  }

  void renameCounter(
      String projectId, String partId, String counterId, String newName) {
    getCounter(projectId, partId, counterId).name = newName;
    _autoSave();
    notifyListeners();
  }

  void setLinkType(
      String projectId, String partId, String counterId, int type) {
    final c = getCounter(projectId, partId, counterId);
    c.linkType = type;
    c.linkedToCounterId =
        (type == 0) ? null : getPart(projectId, partId).counters.first.id;
    _autoSave();
    notifyListeners();
  }

  void toggleArchiveStatus(String projectId) {
    final project = _projects.firstWhere((p) => p.id == projectId);
    project.isArchived = !project.isArchived;
    _autoSave();
    notifyListeners();
  }

  void toggleViewArchived() {
    showArchived = !showArchived;
    notifyListeners();
  }

  void addProject(String name) {
    final defaultCounter =
        KnittingCounter(id: const Uuid().v4(), name: 'Main Rows');
    final defaultPart = ProjectPart(
        id: const Uuid().v4(), name: 'Main Body', counters: [defaultCounter]);
    _projects.add(KnittingProject(
        id: const Uuid().v4(), name: name, parts: [defaultPart]));
    _autoSave();
    notifyListeners();
  }

  void deleteProject(String projectId) {
    _projects.removeWhere((p) => p.id == projectId);
    _autoSave();
    notifyListeners();
  }

  void addPart(String projectId, String partName) {
    final project = _projects.firstWhere((p) => p.id == projectId);
    project.parts.add(ProjectPart(
        id: const Uuid().v4(),
        name: partName,
        counters: [
          KnittingCounter(id: const Uuid().v4(), name: 'Main Counter')
        ]));
    _autoSave();
    notifyListeners();
  }

  void deletePart(String projectId, String partId) {
    final project = _projects.firstWhere((p) => p.id == projectId);
    project.parts.removeWhere((pt) => pt.id == partId);
    _autoSave();
    notifyListeners();
  }

  void addCounter(String projectId, String partId, String counterName) {
    final part = getPart(projectId, partId);
    part.counters
        .add(KnittingCounter(id: const Uuid().v4(), name: counterName));
    _autoSave();
    notifyListeners();
  }

  void deleteCounter(String projectId, String partId, String counterId) {
    final part = getPart(projectId, partId);
    part.counters.removeWhere((c) => c.id == counterId);
    _autoSave();
    notifyListeners();
  }

  void resetSpecificCounter(String projectId, String partId, String counterId) {
    getCounter(projectId, partId, counterId).currentRow = 0;
    _autoSave();
    notifyListeners();
  }

  void setCounterValue(
      String projectId, String partId, String counterId, int value) {
    if (value < 0) return;
    getCounter(projectId, partId, counterId).currentRow = value;
    _autoSave();
    notifyListeners();
  }

  void setCounterColor(
      String projectId, String partId, String counterId, int colorValue) {
    getCounter(projectId, partId, counterId).colorValue = colorValue;
    _autoSave();
    notifyListeners();
  }

  void setAutoResetTarget(
      String projectId, String partId, String counterId, int? target) {
    getCounter(projectId, partId, counterId).autoResetTarget = target;
    _autoSave();
    notifyListeners();
  }

  void setPattern(
      String projectId, String partId, String counterId, String rawText) {
    final counter = getCounter(projectId, partId, counterId);
    List<String> lines = rawText.split('\n');
    Map<int, String> newInstructions = Map.from(counter.instructions);
    for (int i = 0; i < lines.length; i++) {
      if (lines[i].trim().isNotEmpty) newInstructions[i + 1] = lines[i].trim();
    }
    counter.instructions = newInstructions;
    _autoSave();
    notifyListeners();
  }

  void addOrUpdateReminder(String projectId, String partId, String counterId,
      int rowNum, String text) {
    getCounter(projectId, partId, counterId).instructions[rowNum] = text;
    _autoSave();
    notifyListeners();
  }

  void addReminderRule(String projectId, String partId, String counterId,
      int startRow, int endRow, int interval, String text) {
    final counter = getCounter(projectId, partId, counterId);
    if (interval <= 0) interval = 1;
    for (int i = startRow; i <= endRow; i += interval)
      counter.instructions[i] = text;
    _autoSave();
    notifyListeners();
  }

  void removeReminder(
      String projectId, String partId, String counterId, int rowNum) {
    getCounter(projectId, partId, counterId).instructions.remove(rowNum);
    _autoSave();
    notifyListeners();
  }

  ProjectPart getPart(String projectId, String partId) => _projects
      .firstWhere((p) => p.id == projectId)
      .parts
      .firstWhere((pt) => pt.id == partId);

  KnittingCounter getCounter(
          String projectId, String partId, String counterId) =>
      getPart(projectId, partId).counters.firstWhere((c) => c.id == counterId);
}

// --- UI HELPERS ---

void _confirmDelete(BuildContext context, String item, VoidCallback onConfirm,
    {String? customTitle}) {
  showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
              title: Text(customTitle ?? "Delete $item?"),
              content: Text("This action cannot be undone."),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text("Cancel")),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                  onPressed: () {
                    onConfirm();
                    Navigator.pop(ctx);
                  },
                  child: const Text("Confirm",
                      style: TextStyle(color: Colors.white)),
                )
              ]));
}

// --- SCREENS ---

void main() {
  runApp(ChangeNotifierProvider(
      create: (_) => ProjectProvider(),
      child: MaterialApp(
        title: 'Knitly',
        theme: ThemeData(primarySwatch: Colors.brown, useMaterial3: true),
        home: const DashboardScreen(),
        debugShowCheckedModeBanner: false,
      )));
}

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});
  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  bool _navigationRestored = false;

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ProjectProvider>();
    if (provider.isInitialized && !_navigationRestored) {
      _navigationRestored = true;
      WidgetsBinding.instance
          .addPostFrameCallback((_) => _restoreNavigation(context, provider));
    }
    return Scaffold(
      appBar: AppBar(
          title: Text(
              provider.showArchived ? 'Archived Projects' : 'Active Projects'),
          actions: [
            IconButton(
                icon: Icon(provider.showArchived
                    ? Icons.unarchive
                    : Icons.archive_outlined),
                onPressed: () => provider.toggleViewArchived())
          ]),
      body: !provider.isInitialized
          ? const Center(child: CircularProgressIndicator())
          : provider.projects.isEmpty
              ? const Center(child: Text("Empty list."))
              : ListView.builder(
                  itemCount: provider.projects.length,
                  itemBuilder: (context, i) {
                    final proj = provider.projects[i];
                    return ListTile(
                        leading: Icon(Icons.book,
                            color:
                                proj.isArchived ? Colors.grey : Colors.brown),
                        title: Text(proj.name),
                        trailing:
                            Row(mainAxisSize: MainAxisSize.min, children: [
                          IconButton(
                              icon: Icon(proj.isArchived
                                  ? Icons.unarchive
                                  : Icons.archive),
                              onPressed: () =>
                                  provider.toggleArchiveStatus(proj.id)),
                          IconButton(
                              icon: const Icon(Icons.delete_outline,
                                  color: Colors.red),
                              onPressed: () => _confirmDelete(
                                  context,
                                  "Project",
                                  () => provider.deleteProject(proj.id)))
                        ]),
                        onTap: () {
                          provider.setActiveNavigation(proj.id, null);
                          Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (_) => ProjectDetailScreen(
                                      projectId: proj.id))).then(
                              (_) => provider.setActiveNavigation(null, null));
                        });
                  }),
      floatingActionButton: FloatingActionButton(
          onPressed: () => _showAddProject(context),
          child: const Icon(Icons.add)),
    );
  }

  void _restoreNavigation(BuildContext context, ProjectProvider provider) {
    final projId = provider.activeProjectId;
    final partId = provider.activePartId;
    if (projId != null && provider.projects.any((p) => p.id == projId)) {
      Navigator.push(
          context,
          MaterialPageRoute(
              builder: (_) => ProjectDetailScreen(projectId: projId)));
      if (partId != null) {
        final project = provider.projects.firstWhere((p) => p.id == projId);
        if (project.parts.any((p) => p.id == partId)) {
          Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) =>
                      PartDetailScreen(projectId: projId, partId: partId)));
        }
      }
    }
  }

  void _showAddProject(BuildContext context) {
    final c = TextEditingController();
    showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
                title: const Text("New Project"),
                content: TextField(controller: c, autofocus: true),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: const Text("Cancel")),
                  ElevatedButton(
                      onPressed: () {
                        if (c.text.isNotEmpty)
                          context.read<ProjectProvider>().addProject(c.text);
                        Navigator.pop(ctx);
                      },
                      child: const Text("Create"))
                ]));
  }
}

class ProjectDetailScreen extends StatelessWidget {
  final String projectId;
  const ProjectDetailScreen({super.key, required this.projectId});
  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ProjectProvider>();
    final project = provider.projects.firstWhere((p) => p.id == projectId);
    return Scaffold(
      appBar: AppBar(title: Text(project.name)),
      body: ListView.builder(
          itemCount: project.parts.length,
          itemBuilder: (context, i) => ListTile(
              leading: const Icon(Icons.layers),
              title: Text(project.parts[i].name),
              trailing: IconButton(
                  icon: const Icon(Icons.delete_outline, color: Colors.red),
                  onPressed: () => _confirmDelete(
                      context,
                      "Part",
                      () =>
                          provider.deletePart(projectId, project.parts[i].id))),
              onTap: () {
                provider.setActiveNavigation(projectId, project.parts[i].id);
                Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => PartDetailScreen(
                                projectId: projectId,
                                partId: project.parts[i].id)))
                    .then((_) => provider.setActiveNavigation(projectId, null));
              })),
      floatingActionButton: FloatingActionButton.extended(
          onPressed: () => _showAddPart(context),
          label: const Text("New Part"),
          icon: const Icon(Icons.add)),
    );
  }

  void _showAddPart(BuildContext context) {
    final c = TextEditingController();
    showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
                title: const Text("Add Part"),
                content: TextField(controller: c, autofocus: true),
                actions: [
                  ElevatedButton(
                      onPressed: () {
                        if (c.text.isNotEmpty)
                          context
                              .read<ProjectProvider>()
                              .addPart(projectId, c.text);
                        Navigator.pop(ctx);
                      },
                      child: const Text("Add"))
                ]));
  }
}

class PartDetailScreen extends StatefulWidget {
  final String projectId, partId;
  const PartDetailScreen(
      {super.key, required this.projectId, required this.partId});
  @override
  State<PartDetailScreen> createState() => _PartDetailScreenState();
}

class _PartDetailScreenState extends State<PartDetailScreen> {
  @override
  Widget build(BuildContext context) {
    final prov = context.watch<ProjectProvider>();
    final part = prov.getPart(widget.projectId, widget.partId);
    final size = MediaQuery.of(context).size;
    final topPadding = MediaQuery.of(context).padding.top + kToolbarHeight;
    final floatingId = prov.floatingCounterId;
    final hasFloatingCounter =
        floatingId != null && part.counters.any((c) => c.id == floatingId);

    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(title: Text(part.name), actions: [
        IconButton(
            icon: const Icon(Icons.add_box),
            onPressed: () => _addCounter(context))
      ]),
      body: Stack(children: [
        if (part.counters.isNotEmpty)
          CustomScrollView(slivers: [
            SliverToBoxAdapter(
                child: CounterItemCard(
                    projectId: widget.projectId,
                    partId: widget.partId,
                    counterId: part.counters.first.id,
                    isMain: true,
                    onPopOut: () => prov.setFloatingState(
                        part.counters.first.id,
                        prov.floatX,
                        prov.floatY,
                        prov.floatShowNext))),
            if (part.counters.length > 1)
              SliverPadding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8.0, vertical: 4.0),
                  sliver: SliverGrid(
                      gridDelegate:
                          const SliverGridDelegateWithMaxCrossAxisExtent(
                              maxCrossAxisExtent: 250,
                              mainAxisSpacing: 8,
                              crossAxisSpacing: 8,
                              childAspectRatio: 0.82),
                      delegate: SliverChildBuilderDelegate(
                          (context, index) => CounterItemCard(
                              projectId: widget.projectId,
                              partId: widget.partId,
                              counterId: part.counters[index + 1].id,
                              isMain: false,
                              onPopOut: () => prov.setFloatingState(
                                  part.counters[index + 1].id,
                                  prov.floatX,
                                  prov.floatY,
                                  prov.floatShowNext)),
                          childCount: part.counters.length - 1))),
            const SliverToBoxAdapter(child: SizedBox(height: 100))
          ])
        else
          const Center(child: Text("No counters.")),
        if (hasFloatingCounter)
          Positioned(
              left: prov.floatX,
              top: prov.floatY,
              child: GestureDetector(
                  onPanUpdate: (details) {
                    double nx = (prov.floatX + details.delta.dx)
                        .clamp(8.0, size.width - 248.0);
                    double ny = (prov.floatY + details.delta.dy)
                        .clamp(8.0, size.height - topPadding - 180.0);
                    prov.setFloatingState(
                        floatingId, nx, ny, prov.floatShowNext);
                  },
                  child: _buildFloat(floatingId))),
      ]),
    );
  }

  Widget _buildFloat(String id) {
    final prov = context.watch<ProjectProvider>();
    final c = prov.getCounter(widget.projectId, widget.partId, id);
    final cardColor = Color(c.colorValue);
    final targetRow = prov.floatShowNext ? c.currentRow + 1 : c.currentRow;
    return Material(
        elevation: 8,
        borderRadius: BorderRadius.circular(16),
        child: Container(
            width: 240,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
                border: Border.all(color: cardColor, width: 2),
                borderRadius: BorderRadius.circular(16),
                color: Colors.white),
            child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    const Icon(Icons.drag_indicator,
                        size: 18, color: Colors.grey),
                    Expanded(
                        child: Text(" ${c.name}",
                            style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                                color: cardColor),
                            overflow: TextOverflow.ellipsis)),
                    IconButton(
                        icon: const Icon(Icons.close, size: 18),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        onPressed: () => prov.setFloatingState(
                            null, prov.floatX, prov.floatY, prov.floatShowNext))
                  ]),
                  const Divider(),
                  Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text("Row $targetRow",
                            style: const TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 16)),
                        Switch.adaptive(
                            value: prov.floatShowNext,
                            activeColor: cardColor,
                            onChanged: (v) => prov.setFloatingState(
                                id, prov.floatX, prov.floatY, v))
                      ]),
                  Text(prov.floatShowNext ? "Next" : "Current",
                      style: const TextStyle(fontSize: 10, color: Colors.grey)),
                  const SizedBox(height: 6),
                  Text(c.instructions[targetRow] ?? "No instructions.",
                      style: const TextStyle(fontSize: 13))
                ])));
  }

  void _addCounter(BuildContext context) {
    final c = TextEditingController();
    showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
                title: const Text("Add Counter"),
                content: TextField(controller: c, autofocus: true),
                actions: [
                  ElevatedButton(
                      onPressed: () {
                        if (c.text.isNotEmpty)
                          context.read<ProjectProvider>().addCounter(
                              widget.projectId, widget.partId, c.text);
                        Navigator.pop(ctx);
                      },
                      child: const Text("Add"))
                ]));
  }
}

class CounterItemCard extends StatefulWidget {
  final String projectId, partId, counterId;
  final bool isMain;
  final VoidCallback onPopOut;
  const CounterItemCard(
      {super.key,
      required this.projectId,
      required this.partId,
      required this.counterId,
      required this.isMain,
      required this.onPopOut});
  @override
  State<CounterItemCard> createState() => _CounterItemCardState();
}

class _CounterItemCardState extends State<CounterItemCard> {
  bool _isPreview = false;

  @override
  Widget build(BuildContext context) {
    final prov = context.watch<ProjectProvider>();
    final counter =
        prov.getCounter(widget.projectId, widget.partId, widget.counterId);
    final cardColor = Color(counter.colorValue);

    return Card(
      margin: widget.isMain ? const EdgeInsets.all(12) : EdgeInsets.zero,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(
              color: cardColor.withValues(alpha: 0.3), // <-- Fixed here
              width: 2)),
      child: Padding(
          padding: const EdgeInsets.all(12.0),
          child: Column(children: [
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Expanded(
                  child: Text(
                      widget.isMain
                          ? "Global: ${counter.name}"
                          : "Secondary: ${counter.name}",
                      style: TextStyle(
                          fontSize: widget.isMain ? 16 : 12,
                          fontWeight: FontWeight.bold,
                          color: cardColor),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis)),
              Row(mainAxisSize: MainAxisSize.min, children: [
                IconButton(
                    icon: const Icon(Icons.refresh,
                        size: 20, color: Colors.orange),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    onPressed: () => _confirmDelete(
                        context,
                        "Row Progress",
                        () => prov.resetSpecificCounter(
                            widget.projectId, widget.partId, widget.counterId),
                        customTitle: "Reset row?")),
                if (!widget.isMain)
                  IconButton(
                      icon: Icon(
                          counter.linkType == 0 ? Icons.link_off : Icons.link,
                          size: 20,
                          color: cardColor),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      onPressed: () => _showLinkPicker(context, prov)),
                PopupMenuButton<String>(
                    icon: Icon(Icons.more_horiz, color: cardColor, size: 20),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    onSelected: (val) {
                      if (val == 'rename')
                        _showRename(context, prov, counter.name);
                      if (val == 'settings') _showSettings(context, prov);
                      if (val == 'color') _showColorPicker(context, prov);
                      if (val == 'delete')
                        _confirmDelete(
                            context,
                            "Counter",
                            () => prov.deleteCounter(widget.projectId,
                                widget.partId, widget.counterId));
                    },
                    itemBuilder: (ctx) => [
                          const PopupMenuItem(
                              value: 'rename', child: Text("Rename")),
                          const PopupMenuItem(
                              value: 'settings', child: Text("Notes & Logic")),
                          const PopupMenuItem(
                              value: 'color', child: Text("Color")),
                          const PopupMenuItem(
                              value: 'delete',
                              child: Text("Delete",
                                  style: TextStyle(color: Colors.red)))
                        ]),
              ])
            ]),
            if (!widget.isMain && counter.linkType > 0)
              Text(
                  counter.linkType == 1
                      ? "🔗 One-Way to Global"
                      : "🔗 Synced to Global",
                  style: const TextStyle(fontSize: 10, color: Colors.grey)),
            const SizedBox(height: 5),
            GestureDetector(
                onTap: () => _showManualEdit(context, prov, counter.currentRow),
                child: FittedBox(
                    child: Text('${counter.currentRow}',
                        style: TextStyle(
                            fontSize: widget.isMain ? 55 : 35,
                            fontWeight: FontWeight.bold,
                            color: cardColor)))),
            Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
              IconButton(
                  icon: Icon(Icons.remove_circle_outline,
                      size: widget.isMain ? 40 : 30,
                      color: cardColor.withValues(alpha: 0.6) // <-- Fixed here
                      ),
                  onPressed: () => prov.updateRow(
                      widget.projectId, widget.partId, widget.counterId, -1)),
              if (counter.instructions.isNotEmpty)
                IconButton(
                    icon: Icon(Icons.note_alt, size: 24, color: cardColor),
                    onPressed: widget.onPopOut)
              else
                const SizedBox(width: 24),
              IconButton(
                  icon: Icon(Icons.add_circle,
                      size: widget.isMain ? 50 : 35, color: cardColor),
                  onPressed: () => prov.updateRow(
                      widget.projectId, widget.partId, widget.counterId, 1)),
            ]),
            if (widget.isMain && counter.instructions.isNotEmpty) ...[
              const Divider(),
              Wrap(alignment: WrapAlignment.center, spacing: 8, children: [
                ChoiceChip(
                    label: const Text("Current"),
                    selected: !_isPreview,
                    onSelected: (v) => setState(() => _isPreview = false)),
                ChoiceChip(
                    label: const Text("Next"),
                    selected: _isPreview,
                    onSelected: (v) => setState(() => _isPreview = true))
              ]),
              Text(
                "Row ${_isPreview ? counter.currentRow + 1 : counter.currentRow}: ${counter.instructions[_isPreview ? counter.currentRow + 1 : counter.currentRow] ?? "None."}",
                style: const TextStyle(fontSize: 12),
                textAlign: TextAlign.center,
              )
            ]
          ])),
    );
  }

  void _showRename(BuildContext context, ProjectProvider prov, String current) {
    final c = TextEditingController(text: current);
    showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
                title: const Text("Rename"),
                content: TextField(controller: c, autofocus: true),
                actions: [
                  TextButton(
                      onPressed: () {
                        prov.renameCounter(widget.projectId, widget.partId,
                            widget.counterId, c.text);
                        Navigator.pop(ctx);
                      },
                      child: const Text("Save"))
                ]));
  }

  void _showLinkPicker(BuildContext context, ProjectProvider prov) {
    showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
            title: const Text("Link to Global Counter"),
            content: Column(mainAxisSize: MainAxisSize.min, children: [
              ListTile(
                  title: const Text("None (Independent)"),
                  leading: const Icon(Icons.link_off),
                  onTap: () {
                    prov.setLinkType(
                        widget.projectId, widget.partId, widget.counterId, 0);
                    Navigator.pop(ctx);
                  }),
              ListTile(
                  title: const Text("One-Way (This → Global)"),
                  subtitle: const Text("Only this counter changes global"),
                  leading: const Icon(Icons.trending_up),
                  onTap: () {
                    prov.setLinkType(
                        widget.projectId, widget.partId, widget.counterId, 1);
                    Navigator.pop(ctx);
                  }),
              ListTile(
                  title: const Text("Both-Ways (Synced)"),
                  subtitle: const Text("Changing either updates both"),
                  leading: const Icon(Icons.sync),
                  onTap: () {
                    prov.setLinkType(
                        widget.projectId, widget.partId, widget.counterId, 2);
                    Navigator.pop(ctx);
                  }),
            ])));
  }

  void _showColorPicker(BuildContext context, ProjectProvider prov) {
    final colors = [
      0xFF2196F3,
      0xFFF44336,
      0xFF4CAF50,
      0xFFFF9800,
      0xFF9C27B0,
      0xFFE91E63,
      0xFF00BCD4,
      0xFF795548,
      0xFF607D8B,
      0xFFFFC107
    ];
    showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
            title: const Text("Color"),
            content: Wrap(
                spacing: 12,
                runSpacing: 12,
                children: colors
                    .map((c) => GestureDetector(
                        onTap: () {
                          prov.setCounterColor(widget.projectId, widget.partId,
                              widget.counterId, c);
                          Navigator.pop(ctx);
                        },
                        child: CircleAvatar(backgroundColor: Color(c))))
                    .toList())));
  }

  void _showManualEdit(
      BuildContext context, ProjectProvider prov, int current) {
    final c = TextEditingController(text: current.toString());
    showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
                title: const Text("Set Row"),
                content: TextField(
                    controller: c, keyboardType: TextInputType.number),
                actions: [
                  TextButton(
                      onPressed: () {
                        if (int.tryParse(c.text) != null)
                          prov.setCounterValue(widget.projectId, widget.partId,
                              widget.counterId, int.parse(c.text));
                        Navigator.pop(ctx);
                      },
                      child: const Text("Set"))
                ]));
  }

  void _showSettings(BuildContext context, ProjectProvider prov) {
    showDialog(
        context: context,
        builder: (ctx) => Consumer<ProjectProvider>(builder: (context, p, _) {
              final c = p.getCounter(
                  widget.projectId, widget.partId, widget.counterId);
              final nc = TextEditingController(text: c.name);
              final targetC = TextEditingController(
                  text: c.autoResetTarget?.toString() ?? "");
              final sorted = c.instructions.entries.toList()
                ..sort((a, b) => a.key.compareTo(b.key));
              return AlertDialog(
                  title: Text(
                      widget.isMain ? "Global Settings" : "Secondary Settings"),
                  content: SingleChildScrollView(
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                    TextField(
                        controller: nc,
                        decoration:
                            const InputDecoration(labelText: "Rename Counter"),
                        onSubmitted: (v) => p.renameCounter(widget.projectId,
                            widget.partId, widget.counterId, v)),
                    TextField(
                        controller: targetC,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                            labelText: "Auto-Reset Target")),
                    const Divider(),
                    Wrap(spacing: 10, children: [
                      TextButton.icon(
                          onPressed: () => _showBulk(context, p),
                          icon: const Icon(Icons.paste),
                          label: const Text("Pattern")),
                      TextButton.icon(
                          onPressed: () => _showAddReminderMenu(context, p),
                          icon: const Icon(Icons.add_alert),
                          label: const Text("Reminder"))
                    ]),
                    if (sorted.isNotEmpty)
                      ...sorted.map((e) => ListTile(
                          title: Text("Row ${e.key}"),
                          subtitle: Text(e.value),
                          trailing: IconButton(
                              icon: const Icon(Icons.delete, size: 18),
                              onPressed: () => p.removeReminder(
                                  widget.projectId,
                                  widget.partId,
                                  widget.counterId,
                                  e.key))))
                  ])),
                  actions: [
                    TextButton(
                        onPressed: () {
                          if (int.tryParse(targetC.text) != null)
                            p.setAutoResetTarget(
                                widget.projectId,
                                widget.partId,
                                widget.counterId,
                                int.parse(targetC.text));
                          Navigator.pop(ctx);
                        },
                        child: const Text("Close"))
                  ]);
            }));
  }

  void _showBulk(BuildContext context, ProjectProvider prov) {
    final c = TextEditingController();
    showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
                title: const Text("Paste Pattern"),
                content: TextField(
                    controller: c,
                    maxLines: 5,
                    decoration: const InputDecoration(
                        hintText: "Paste row text here...")),
                actions: [
                  ElevatedButton(
                      onPressed: () {
                        prov.setPattern(widget.projectId, widget.partId,
                            widget.counterId, c.text);
                        Navigator.pop(ctx);
                      },
                      child: const Text("Import"))
                ]));
  }

  void _showAddReminderMenu(BuildContext context, ProjectProvider prov) {
    int mode = 0; // 0: Single, 1: Rule
    final sc = TextEditingController();
    final tc = TextEditingController();
    final rcStart = TextEditingController();
    final rcEnd = TextEditingController();
    final ic = TextEditingController();

    showDialog(
        context: context,
        builder: (ctx) => StatefulBuilder(builder: (context, setState) {
              return AlertDialog(
                title: const Text("Add Reminder"),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        ChoiceChip(
                          label: const Text("Single Row"),
                          selected: mode == 0,
                          onSelected: (val) => setState(() => mode = 0),
                        ),
                        const SizedBox(width: 10),
                        ChoiceChip(
                          label: const Text("Repeating Rule"),
                          selected: mode == 1,
                          onSelected: (val) => setState(() => mode = 1),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    if (mode == 0) ...[
                      TextField(
                        controller: sc,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                            labelText: "Row Number",
                            border: OutlineInputBorder()),
                      ),
                    ] else ...[
                      Row(
                        children: [
                          Expanded(
                              child: TextField(
                                  controller: rcStart,
                                  keyboardType: TextInputType.number,
                                  decoration: const InputDecoration(
                                      labelText: "Start Row",
                                      border: OutlineInputBorder()))),
                          const SizedBox(width: 8),
                          Expanded(
                              child: TextField(
                                  controller: rcEnd,
                                  keyboardType: TextInputType.number,
                                  decoration: const InputDecoration(
                                      labelText: "End Row",
                                      border: OutlineInputBorder()))),
                        ],
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: ic,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                            labelText: "Repeat Every X Rows",
                            border: OutlineInputBorder()),
                      ),
                    ],
                    const SizedBox(height: 12),
                    TextField(
                      controller: tc,
                      decoration: const InputDecoration(
                          labelText: "Instruction / Reminder Note",
                          border: OutlineInputBorder()),
                      maxLines: 2,
                    ),
                  ],
                ),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: const Text("Cancel")),
                  ElevatedButton(
                    onPressed: () {
                      if (mode == 0) {
                        int? rowNum = int.tryParse(sc.text);
                        if (rowNum != null && tc.text.isNotEmpty) {
                          prov.addOrUpdateReminder(widget.projectId,
                              widget.partId, widget.counterId, rowNum, tc.text);
                        }
                      } else {
                        int? start = int.tryParse(rcStart.text);
                        int? end = int.tryParse(rcEnd.text);
                        int? interval = int.tryParse(ic.text);
                        if (start != null &&
                            end != null &&
                            interval != null &&
                            tc.text.isNotEmpty) {
                          prov.addReminderRule(widget.projectId, widget.partId,
                              widget.counterId, start, end, interval, tc.text);
                        }
                      }
                      Navigator.pop(ctx);
                    },
                    child: const Text("Save"),
                  ),
                ],
              );
            }));
  }
} // End of _CounterItemCardState
