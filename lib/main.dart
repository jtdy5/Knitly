import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';
import 'package:shared_preferences/shared_preferences.dart';

// --- MODELS ---

class Reminder {
  String id;
  String text;
  int type; // 0: Single Row, 1: Repeat, 2: Range
  int value1;
  int? value2;

  Reminder({required this.id, required this.text, required this.type, required this.value1, this.value2});

  bool appliesTo(int row) {
    if (type == 0) {
      return row == value1;
    }
    if (type == 1) {
      return row > 0 && row % value1 == 0;
    }
    if (type == 2) {
      return row >= value1 && row <= (value2 ?? value1);
    }
    return false;
  }

  Map<String, dynamic> toJson() => {'id': id, 'text': text, 'type': type, 'value1': value1, 'value2': value2};
  factory Reminder.fromJson(Map<String, dynamic> json) => Reminder(id: json['id'] ?? const Uuid().v4(), text: json['text'], type: json['type'], value1: json['value1'], value2: json['value2']);
}

class KnittingCounter {
  final String id;
  String name;
  int currentRow;
  List<Reminder> reminders;
  int linkType;
  int? autoResetTarget;
  int colorValue;

  KnittingCounter({required this.id, required this.name, this.currentRow = 0, this.reminders = const [], this.linkType = 0, this.autoResetTarget, this.colorValue = 0xFF2196F3});

  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'currentRow': currentRow, 'reminders': reminders.map((r) => r.toJson()).toList(), 'linkType': linkType, 'autoResetTarget': autoResetTarget, 'colorValue': colorValue};

  factory KnittingCounter.fromJson(Map<String, dynamic> json) {
    return KnittingCounter(
      id: json['id'], 
      name: json['name'], 
      currentRow: json['currentRow'] ?? 0, 
      reminders: json['reminders'] != null ? (json['reminders'] as List).map((r) => Reminder.fromJson(r)).toList() : [], 
      linkType: json['linkType'] ?? 0, 
      autoResetTarget: json['autoResetTarget'], 
      colorValue: json['colorValue'] ?? 0xFF2196F3
    );
  }
}

class ProjectPart {
  final String id;
  String name;
  List<KnittingCounter> counters;

  ProjectPart({required this.id, required this.name, required this.counters});
  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'counters': counters.map((c) => c.toJson()).toList()};
  factory ProjectPart.fromJson(Map<String, dynamic> json) => ProjectPart(id: json['id'], name: json['name'], counters: (json['counters'] as List).map((c) => KnittingCounter.fromJson(c)).toList());
}

class KnittingProject {
  final String id;
  String name;
  List<ProjectPart> parts;
  bool isArchived;

  KnittingProject({required this.id, required this.name, required this.parts, this.isArchived = false});
  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'parts': parts.map((p) => p.toJson()).toList(), 'isArchived': isArchived};
  factory KnittingProject.fromJson(Map<String, dynamic> json) => KnittingProject(id: json['id'], name: json['name'], parts: (json['parts'] as List).map((p) => ProjectPart.fromJson(p)).toList(), isArchived: json['isArchived'] ?? false);
}

// --- PROVIDER ---

class ProjectProvider extends ChangeNotifier {
  List<KnittingProject> _projects = [];
  bool isInitialized = false;
  String? activeProjectId;
  String? activePartId;
  String? floatingCounterId;
  double floatX = 20.0, floatY = 100.0;
  bool floatShowNext = false;

  ProjectProvider() { _loadFromLocal(); }

  List<KnittingProject> get projects => _projects.where((p) => !p.isArchived).toList();

  Future<void> _loadFromLocal() async {
    final prefs = await SharedPreferences.getInstance();
    // Fresh keys for Knitly!
    final String? jsonStr = prefs.getString('knitly_data_v1'); 
    if (jsonStr != null) {
      try {
        final List<dynamic> decoded = jsonDecode(jsonStr);
        _projects = decoded.map((p) => KnittingProject.fromJson(p)).toList();
      } catch (e) {
        _projects = [];
      }
    }
    
    activeProjectId = prefs.getString('knitly_active_proj');
    activePartId = prefs.getString('knitly_active_part');
    
    floatingCounterId = prefs.getString('knitly_float_id');
    floatX = prefs.getDouble('float_x') ?? 20.0;
    floatY = prefs.getDouble('float_y') ?? 100.0;
    floatShowNext = prefs.getBool('float_show_next') ?? false;
    
    isInitialized = true;
    notifyListeners();
  }

  Future<void> _autoSave() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('knitly_data_v1', jsonEncode(_projects.map((p) => p.toJson()).toList()));
  }

  Future<void> setActiveNavigation(String? projId, String? partId) async {
    activeProjectId = projId; 
    activePartId = partId;
    final prefs = await SharedPreferences.getInstance();
    if (projId != null) { 
      await prefs.setString('knitly_active_proj', projId); 
    } else { 
      await prefs.remove('knitly_active_proj'); 
    }
    if (partId != null) { 
      await prefs.setString('knitly_active_part', partId); 
    } else { 
      await prefs.remove('knitly_active_part'); 
    }
    notifyListeners();
  }

  Future<void> setFloatingReminderState(String? counterId, double x, double y, bool showNext) async {
    floatingCounterId = counterId; 
    floatX = x; 
    floatY = y; 
    floatShowNext = showNext;
    final prefs = await SharedPreferences.getInstance();
    if (counterId != null) {
      await prefs.setString('knitly_float_id', counterId); 
      await prefs.setDouble('float_x', x); 
      await prefs.setDouble('float_y', y); 
      await prefs.setBool('float_show_next', showNext);
    } else { 
      await prefs.remove('knitly_float_id'); 
    }
    notifyListeners();
  }

  void updateRow(String projectId, String partId, String counterId, int delta) {
    final part = getPart(projectId, partId);
    final globalCounter = part.counters.first;
    final clickedCounter = part.counters.firstWhere((c) => c.id == counterId);

    if (clickedCounter.id == globalCounter.id) {
      _applyDelta(globalCounter, delta);
      for (var sec in part.counters.skip(1)) { 
        if (sec.linkType == 2) {
          _applyDelta(sec, delta); 
        }
      }
    } else {
      _applyDelta(clickedCounter, delta);
      if (clickedCounter.linkType > 0) {
        _applyDelta(globalCounter, delta);
        for (var sec in part.counters.skip(1)) { 
          if (sec.id != clickedCounter.id && sec.linkType == 2) {
            _applyDelta(sec, delta); 
          }
        }
      }
    }
    _autoSave(); notifyListeners();
  }

  void _applyDelta(KnittingCounter counter, int delta) {
    int nextValue = counter.currentRow + delta;
    if (nextValue >= 0) {
      counter.currentRow = nextValue;
    }
  }

  KnittingProject? tryGetProj(String id) { 
    try { 
      return _projects.firstWhere((p) => p.id == id); 
    } catch (_) { 
      return null; 
    } 
  }
  
  KnittingProject getProj(String id) => _projects.firstWhere((p) => p.id == id);
  ProjectPart getPart(String pId, String ptId) => getProj(pId).parts.firstWhere((pt) => pt.id == ptId);
  KnittingCounter getCounter(String pId, String ptId, String cId) => getPart(pId, ptId).counters.firstWhere((c) => c.id == cId);

  void addReminder(String pId, String ptId, String cId, Reminder reminder) { getCounter(pId, ptId, cId).reminders.add(reminder); _autoSave(); notifyListeners(); }
  void removeReminder(String pId, String ptId, String cId, String reminderId) { getCounter(pId, ptId, cId).reminders.removeWhere((r) => r.id == reminderId); _autoSave(); notifyListeners(); }
  
  void setBulkPattern(String pId, String ptId, String cId, String text) {
    final counter = getCounter(pId, ptId, cId);
    List<String> lines = text.split('\n');
    for (int i = 0; i < lines.length; i++) {
      if (lines[i].trim().isNotEmpty) { 
        counter.reminders.add(Reminder(id: const Uuid().v4(), text: lines[i].trim(), type: 0, value1: i + 1)); 
      }
    }
    _autoSave(); notifyListeners();
  }

  void addProject(String name) { _projects.add(KnittingProject(id: const Uuid().v4(), name: name, parts: [ProjectPart(id: const Uuid().v4(), name: 'Main', counters: [KnittingCounter(id: const Uuid().v4(), name: 'Global Rows')])])); _autoSave(); notifyListeners(); }
  void addPart(String pId, String name) { getProj(pId).parts.add(ProjectPart(id: const Uuid().v4(), name: name, counters: [KnittingCounter(id: const Uuid().v4(), name: 'Global Rows')])); _autoSave(); notifyListeners(); }
  void addCounter(String pId, String ptId, String name) { getPart(pId, ptId).counters.add(KnittingCounter(id: const Uuid().v4(), name: name)); _autoSave(); notifyListeners(); }
  void renameCounter(String pId, String ptId, String cId, String name) { getCounter(pId, ptId, cId).name = name; _autoSave(); notifyListeners(); }
  void setLinkType(String pId, String ptId, String cId, int type) { getCounter(pId, ptId, cId).linkType = type; _autoSave(); notifyListeners(); }
}

// --- UI SCREENS ---

class RootScreen extends StatelessWidget {
  const RootScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ProjectProvider>();
    
    if (!provider.isInitialized) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    
    if (provider.activeProjectId != null) {
      final proj = provider.tryGetProj(provider.activeProjectId!);
      if (proj != null) {
        if (provider.activePartId != null) {
          return PartDetailScreen(projectId: proj.id, partId: provider.activePartId!);
        }
        return ProjectDetailScreen(projectId: proj.id);
      }
    }
    
    return const DashboardScreen();
  }
}

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ProjectProvider>();
    return Scaffold(
      appBar: AppBar(title: const Text("Knitly Dashboard")),
      body: ListView.builder(
        itemCount: provider.projects.length, 
        itemBuilder: (context, i) {
          final proj = provider.projects[i];
          return ListTile(
            title: Text(proj.name), 
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              provider.setActiveNavigation(proj.id, null);
              Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => ProjectDetailScreen(projectId: proj.id)));
            }
          );
        }
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _addProj(context), 
        child: const Icon(Icons.add)
      ),
    );
  }
  
  void _addProj(BuildContext context) {
    final c = TextEditingController();
    showDialog(
      context: context, 
      builder: (ctx) => AlertDialog(
        title: const Text("New Project"),
        content: TextField(controller: c, autofocus: true, decoration: const InputDecoration(hintText: "Project Name")), 
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Cancel")),
          ElevatedButton(
            onPressed: () { 
              if (c.text.isNotEmpty) {
                context.read<ProjectProvider>().addProject(c.text); 
              }
              Navigator.pop(ctx); 
            }, 
            child: const Text("Create")
          )
        ]
      )
    );
  }
}

class ProjectDetailScreen extends StatelessWidget {
  final String projectId;
  const ProjectDetailScreen({super.key, required this.projectId});
  
  @override
  Widget build(BuildContext context) {
    final prov = context.watch<ProjectProvider>();
    final proj = prov.tryGetProj(projectId);
    
    if (proj == null) {
      return const DashboardScreen();
    }
    
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back), 
          onPressed: () { 
            prov.setActiveNavigation(null, null); 
            Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const DashboardScreen())); 
          }
        ),
        title: Text(proj.name),
      ),
      body: ListView.builder(
        itemCount: proj.parts.length, 
        itemBuilder: (context, i) => ListTile(
          title: Text(proj.parts[i].name), 
          subtitle: Text("${proj.parts[i].counters.length} counter(s)"),
          trailing: const Icon(Icons.chevron_right),
          onTap: () {
            prov.setActiveNavigation(projectId, proj.parts[i].id);
            Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => PartDetailScreen(projectId: projectId, partId: proj.parts[i].id)));
          }
        )
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _addPart(context, prov),
        child: const Icon(Icons.add),
      ),
    );
  }

  void _addPart(BuildContext context, ProjectProvider prov) {
    final c = TextEditingController();
    showDialog(
      context: context, 
      builder: (ctx) => AlertDialog(
        title: const Text("Add Part"),
        content: TextField(controller: c, autofocus: true, decoration: const InputDecoration(hintText: "Part Name (e.g. Sleeves)")), 
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Cancel")),
          ElevatedButton(
            onPressed: () { 
              if (c.text.isNotEmpty) prov.addPart(projectId, c.text); 
              Navigator.pop(ctx); 
            }, 
            child: const Text("Create")
          )
        ]
      )
    );
  }
}

class PartDetailScreen extends StatelessWidget {
  final String projectId, partId;
  const PartDetailScreen({super.key, required this.projectId, required this.partId});
  
  @override
  Widget build(BuildContext context) {
    final prov = context.watch<ProjectProvider>();
    final proj = prov.tryGetProj(projectId);
    if (proj == null) {
      return const DashboardScreen();
    }
    final part = proj.parts.firstWhere((p) => p.id == partId);

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back), 
          onPressed: () { 
            prov.setActiveNavigation(projectId, null); 
            Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => ProjectDetailScreen(projectId: projectId))); 
          }
        ), 
        title: Text(part.name)
      ),
      body: Stack(
        children: [
          ListView.builder(
            padding: const EdgeInsets.only(bottom: 100), 
            itemCount: part.counters.length, 
            itemBuilder: (context, i) => CounterItemCard(projectId: projectId, partId: partId, counterId: part.counters[i].id, isMain: i == 0)
          ),
          if (prov.floatingCounterId != null) 
            _buildFloatingReminder(prov, prov.floatingCounterId!, part),
        ]
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _addCounter(context)