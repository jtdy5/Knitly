import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'package:uuid/uuid.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

// --- MODELS ---

class ReminderStep {
  final String label;       // E.g., "Row 11 WS"
  final String instruction; // E.g., "P all sts, turn work."

  ReminderStep({required this.label, required this.instruction});

  Map<String, dynamic> toJson() => {
        'label': label,
        'instruction': instruction,
      };

  factory ReminderStep.fromJson(Map<String, dynamic> json) => ReminderStep(
        label: json['label'] ?? '',
        instruction: json['instruction'] ?? '',
      );
}

class KnitCounter {
  final String id;
  String name;
  int currentRow;
  List<ReminderStep> reminders; // Changed from Map<int, String> to list of steps
  String? linkedCounterId;
  String linkMode;
  int? colorValue;
  List<String> history;
  int? autoResetThreshold;

  KnitCounter({
    required this.id,
    required this.name,
    this.currentRow = 0,
    this.reminders = const [],
    this.linkedCounterId,
    this.linkMode = 'none',
    this.colorValue,
    this.history = const [],
    this.autoResetThreshold,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'currentRow': currentRow,
        'reminders': reminders.map((r) => r.toJson()).toList(),
        'linkedCounterId': linkedCounterId,
        'linkMode': linkMode,
        'colorValue': colorValue,
        'history': history,
        'autoResetThreshold': autoResetThreshold,
      };

  factory KnitCounter.fromJson(Map<String, dynamic> json) => KnitCounter(
        id: json['id'],
        name: json['name'],
        currentRow: json['currentRow'] ?? 0,
        reminders: json['reminders'] != null
            ? (json['reminders'] as List)
                .map((r) => ReminderStep.fromJson(r))
                .toList()
            : [],
        linkedCounterId: json['linkedCounterId'],
        linkMode: json['linkMode'] ?? 'none',
        colorValue: json['colorValue'],
        history: json['history'] != null ? List<String>.from(json['history']) : [],
        autoResetThreshold: json['autoResetThreshold'],
      );
}

class ProjectPart {
  final String id;
  String name;
  List<KnitCounter> counters;

  ProjectPart({required this.id, required this.name, required this.counters});

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'counters': counters.map((c) => c.toJson()).toList()
      };

  factory ProjectPart.fromJson(Map<String, dynamic> json) => ProjectPart(
        id: json['id'],
        name: json['name'],
        counters: (json['counters'] as List)
            .map((c) => KnitCounter.fromJson(c))
            .toList(),
      );
}

class KnitProject {
  final String id;
  String title;
  bool isArchived;
  List<ProjectPart> parts;

  KnitProject({
    required this.id,
    required this.title,
    this.isArchived = false,
    required this.parts,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'isArchived': isArchived,
        'parts': parts.map((p) => p.toJson()).toList()
      };

  factory KnitProject.fromJson(Map<String, dynamic> json) => KnitProject(
        id: json['id'],
        title: json['title'],
        isArchived: json['isArchived'] ?? false,
        parts: json['parts'] != null
            ? (json['parts'] as List)
                .map((p) => ProjectPart.fromJson(p))
                .toList()
            : [],
      );
}

class AppPrefs {
  final String? lastProjectId;
  final String? lastPartId;
  final double reminderX;
  final double reminderY;
  final bool showNextReminder;
  final String? lastSelectedReminderCounterId;
  final bool keepAwake;

  AppPrefs({
    this.lastProjectId,
    this.lastPartId,
    this.reminderX = 16,
    this.reminderY = 450,
    this.showNextReminder = false,
    this.lastSelectedReminderCounterId,
    this.keepAwake = true,
  });

  Map<String, dynamic> toJson() => {
        'lastProjectId': lastProjectId,
        'lastPartId': lastPartId,
        'reminderX': reminderX,
        'reminderY': reminderY,
        'showNextReminder': showNextReminder,
        'lastSelectedReminderCounterId': lastSelectedReminderCounterId,
        'keepAwake': keepAwake,
      };

  factory AppPrefs.fromJson(Map<String, dynamic> json) => AppPrefs(
        lastProjectId: json['lastProjectId'],
        lastPartId: json['lastPartId'],
        reminderX: json['reminderX'] ?? 16.0,
        reminderY: json['reminderY'] ?? 450.0,
        showNextReminder: json['showNextReminder'] ?? false,
        lastSelectedReminderCounterId: json['lastSelectedReminderCounterId'],
        keepAwake: json['keepAwake'] ?? true,
      );
}

// --- STATE NOTIFIERS ---

class AppPrefsNotifier extends StateNotifier<AppPrefs> {
  AppPrefsNotifier() : super(AppPrefs()) {
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('app_prefs');
    if (raw != null) {
      state = AppPrefs.fromJson(jsonDecode(raw));
    }
  }

  void updatePrefs({
    String? lastProjectId,
    String? lastPartId,
    double? rx,
    double? ry,
    bool? showNext,
    String? lastSelectedReminderCounterId,
    bool? keepAwake,
    bool clearProject = false,
    bool clearPart = false,
  }) async {
    state = AppPrefs(
      lastProjectId: clearProject ? null : (lastProjectId ?? state.lastProjectId),
      lastPartId: (clearProject || clearPart) ? null : (lastPartId ?? state.lastPartId),
      reminderX: rx ?? state.reminderX,
      reminderY: ry ?? state.reminderY,
      showNextReminder: showNext ?? state.showNextReminder,
      lastSelectedReminderCounterId: clearPart
          ? null
          : (lastSelectedReminderCounterId ?? state.lastSelectedReminderCounterId),
      keepAwake: keepAwake ?? state.keepAwake,
    );
    final prefs = await SharedPreferences.getInstance();
    prefs.setString('app_prefs', jsonEncode(state.toJson()));
  }
}

final prefsProvider = StateNotifierProvider<AppPrefsNotifier, AppPrefs>((ref) => AppPrefsNotifier());

class ProjectNotifier extends StateNotifier<List<KnitProject>> {
  ProjectNotifier() : super([]) {
    loadData();
  }

  Future<void> loadData() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('knit_projects');
    if (raw != null) {
      state = (jsonDecode(raw) as List).map((p) => KnitProject.fromJson(p)).toList();
    }
  }

  void save() async {
    final prefs = await SharedPreferences.getInstance();
    prefs.setString('knit_projects', jsonEncode(state.map((p) => p.toJson()).toList()));
  }

  String exportProject(String projId) {
    final project = state.firstWhere((p) => p.id == projId);
    final jsonString = jsonEncode(project.toJson());
    return base64Encode(utf8.encode(jsonString));
  }

  void importProject(String base64Data) {
    try {
      final jsonString = utf8.decode(base64Decode(base64Data));
      final Map<String, dynamic> data = jsonDecode(jsonString);
      final importedProject = KnitProject.fromJson(data);
      final newProject = KnitProject(
        id: const Uuid().v4(),
        title: "${importedProject.title} (Imported)",
        isArchived: importedProject.isArchived,
        parts: importedProject.parts,
      );
      state = [...state, newProject];
      save();
    } catch (e) {
      throw const FormatException("Invalid project code");
    }
  }

  void addProject(String title) {
    state = [
      ...state,
      KnitProject(id: const Uuid().v4(), title: title, parts: [
        ProjectPart(id: const Uuid().v4(), name: "Main Section", counters: [
          KnitCounter(id: const Uuid().v4(), name: "Row Counter", colorValue: 0xFF64B5F6, history: [])
        ])
      ])
    ];
    save();
  }

  void addPart(String projId, String name) {
    state = state.map((p) {
      if (p.id == projId) {
        return KnitProject(
            id: p.id,
            title: p.title,
            isArchived: p.isArchived,
            parts: [
              ...p.parts,
              ProjectPart(id: const Uuid().v4(), name: name, counters: [
                KnitCounter(id: const Uuid().v4(), name: "Row Counter", colorValue: 0xFF64B5F6, history: [])
              ])
            ]);
      }
      return p;
    }).toList();
    save();
  }

  void addCounter(String projId, String partId, String name) {
    state = state.map((p) {
      if (p.id == projId) {
        return KnitProject(
            id: p.id,
            title: p.title,
            isArchived: p.isArchived,
            parts: p.parts.map((pt) {
              if (pt.id == partId) {
                return ProjectPart(id: pt.id, name: pt.name, counters: [
                  ...pt.counters,
                  KnitCounter(id: const Uuid().v4(), name: name, colorValue: 0xFFFFCA28, history: [])
                ]);
              }
              return pt;
            }).toList());
      }
      return p;
    }).toList();
    save();
  }

  void deleteProject(String projId) {
    if (state.any((p) => p.id == projId)) {
      state = state.where((p) => p.id != projId).toList();
      save();
    }
  }

  void toggleArchive(String projId) {
    state = state.map((p) => p.id == projId ? KnitProject(id: p.id, title: p.title, isArchived: !p.isArchived, parts: p.parts) : p).toList();
    save();
  }

  void deletePart(String projId, String partId) {
    state = state.map((p) => p.id == projId ? KnitProject(id: p.id, title: p.title, isArchived: p.isArchived, parts: p.parts.where((pt) => pt.id != partId).toList()) : p).toList();
    save();
  }

  void deleteCounter(String projId, String partId, String counterId) {
    state = state
        .map((p) => p.id == projId
            ? KnitProject(
                id: p.id,
                title: p.title,
                isArchived: p.isArchived,
                parts: p.parts
                    .map((pt) => pt.id == partId ? ProjectPart(id: pt.id, name: pt.name, counters: pt.counters.where((c) => c.id != counterId).toList()) : pt)
                    .toList())
            : p)
        .toList();
    save();
  }

  void renameProject(String projId, String newName) {
    state = state.map((p) => p.id == projId ? KnitProject(id: p.id, title: newName, isArchived: p.isArchived, parts: p.parts) : p).toList();
    save();
  }

  void renamePart(String projId, String partId, String newName) {
    state = state
        .map((p) => p.id == projId
            ? KnitProject(
                id: p.id,
                title: p.title,
                isArchived: p.isArchived,
                parts: p.parts.map((pt) => pt.id == partId ? ProjectPart(id: pt.id, name: newName, counters: pt.counters) : pt).toList())
            : p)
        .toList();
    save();
  }

  void renameCounter(String projId, String partId, String counterId, String newName) {
    state = state
        .map((p) => p.id == projId
            ? KnitProject(
                id: p.id,
                title: p.title,
                isArchived: p.isArchived,
                parts: p.parts
                    .map((pt) => pt.id == partId
                        ? ProjectPart(
                            id: pt.id,
                            name: pt.name,
                            counters: pt.counters
                                .map((c) => c.id == counterId
                                    ? KnitCounter(
                                        id: c.id,
                                        name: newName,
                                        currentRow: c.currentRow,
                                        reminders: c.reminders,
                                        linkedCounterId: c.linkedCounterId,
                                        linkMode: c.linkMode,
                                        colorValue: c.colorValue,
                                        history: c.history,
                                        autoResetThreshold: c.autoResetThreshold)
                                    : c)
                                .toList())
                        : pt)
                    .toList())
            : p)
        .toList();
    save();
  }

  void setAutoResetThreshold(String projId, String partId, String counterId, int? val) {
    state = state
        .map((p) => p.id == projId
            ? KnitProject(
                id: p.id,
                title: p.title,
                isArchived: p.isArchived,
                parts: p.parts
                    .map((pt) => pt.id == partId
                        ? ProjectPart(
                            id: pt.id,
                            name: pt.name,
                            counters: pt.counters
                                .map((c) => c.id == counterId
                                    ? KnitCounter(
                                        id: c.id,
                                        name: c.name,
                                        currentRow: c.currentRow,
                                        reminders: c.reminders,
                                        linkedCounterId: c.linkedCounterId,
                                        linkMode: c.linkMode,
                                        colorValue: c.colorValue,
                                        history: c.history,
                                        autoResetThreshold: val)
                                    : c)
                                .toList())
                        : pt)
                    .toList())
            : p)
        .toList();
    save();
  }

  void updateRow(String projId, String partId, String triggerCounterId, int delta) {
    _modifyRow(projId, partId, triggerCounterId, delta: delta);
  }

  void setExactRow(String projId, String partId, String triggerCounterId, int exactValue, {bool isReset = false}) {
    _modifyRow(projId, partId, triggerCounterId, exactValue: exactValue, isReset: isReset);
  }

  void _modifyRow(String projId, String partId, String triggerCounterId, {int? delta, int? exactValue, bool isReset = false}) {
    final now = DateTime.now();
    int h = now.hour;
    int m = now.minute;
    String ampm = h >= 12 ? "PM" : "AM";
    int displayH = h == 0 ? 12 : (h > 12 ? h - 12 : h);
    final nowStr = "${now.month}/${now.day} at $displayH:${m.toString().padLeft(2, '0')} $ampm";
    state = state.map((p) {
      if (p.id != projId) return p;

      return KnitProject(
        id: p.id,
        title: p.title,
        isArchived: p.isArchived,
        parts: p.parts.map((pt) {
          if (pt.id != partId) return pt;

          final triggerCounter = pt.counters.firstWhere((c) => c.id == triggerCounterId, orElse: () => pt.counters.first);

          return ProjectPart(
              id: pt.id,
              name: pt.name,
              counters: pt.counters.map((c) {
                bool shouldUpdate = false;

                if (c.id == triggerCounterId) {
                  shouldUpdate = true;
                } else {
                  if ((c.linkedCounterId == triggerCounterId && c.linkMode == 'sync') ||
                      (triggerCounter.linkedCounterId == c.id && triggerCounter.linkMode == 'sync') ||
                      (triggerCounter.linkedCounterId == c.id && triggerCounter.linkMode == 'follow')) {
                    shouldUpdate = true;
                  }
                }

                if (shouldUpdate) {
                  int newRow;
                  String actionStr;

                  if (exactValue != null) {
                    newRow = exactValue.clamp(0, 9999);
                    actionStr = isReset ? "Reset to $newRow ($nowStr)" : "Set exact to $newRow ($nowStr)";
                  } else {
                    newRow = (c.currentRow + (delta ?? 0)).clamp(0, 9999);
                    if (c.autoResetThreshold != null && newRow > c.autoResetThreshold!) {
                      newRow = 0;
                      actionStr = "Auto-reset to 0 after reaching ${c.autoResetThreshold} ($nowStr)";
                    } else {
                      final sign = (delta ?? 0) > 0 ? "+" : "";
                      actionStr = "$sign${delta ?? 0} -> Row $newRow ($nowStr)";
                    }
                  }

                  List<String> updatedHistory = c.history;
                  if (newRow != c.currentRow || isReset) {
                    updatedHistory = [actionStr, ...c.history].take(50).toList();
                  }

                  return KnitCounter(
                      id: c.id,
                      name: c.name,
                      currentRow: newRow,
                      reminders: c.reminders,
                      linkedCounterId: c.linkedCounterId,
                      linkMode: c.linkMode,
                      colorValue: c.colorValue,
                      history: updatedHistory,
                      autoResetThreshold: c.autoResetThreshold);
                }
                return c;
              }).toList());
        }).toList(),
      );
    }).toList();
    save();
  }

  void linkCounter(String projId, String partId, String counterId, String? linkToId, String mode) {
    state = state
        .map((p) => p.id == projId
            ? KnitProject(
                id: p.id,
                title: p.title,
                isArchived: p.isArchived,
                parts: p.parts
                    .map((pt) => pt.id == partId
                        ? ProjectPart(
                            id: pt.id,
                            name: pt.name,
                            counters: pt.counters
                                .map((c) => c.id == counterId
                                    ? KnitCounter(
                                        id: c.id,
                                        name: c.name,
                                        currentRow: c.currentRow,
                                        reminders: c.reminders,
                                        colorValue: c.colorValue,
                                        linkedCounterId: linkToId,
                                        linkMode: mode,
                                        history: c.history,
                                        autoResetThreshold: c.autoResetThreshold)
                                    : c)
                                .toList())
                        : pt)
                    .toList())
            : p)
        .toList();
    save();
  }

  void setCounterColor(String projId, String partId, String counterId, int color) {
    state = state
        .map((p) => p.id == projId
            ? KnitProject(
                id: p.id,
                title: p.title,
                isArchived: p.isArchived,
                parts: p.parts
                    .map((pt) => pt.id == partId
                        ? ProjectPart(
                            id: pt.id,
                            name: pt.name,
                            counters: pt.counters
                                .map((c) => c.id == counterId
                                    ? KnitCounter(
                                        id: c.id,
                                        name: c.name,
                                        currentRow: c.currentRow,
                                        reminders: c.reminders,
                                        colorValue: color,
                                        linkedCounterId: c.linkedCounterId,
                                        linkMode: c.linkMode,
                                        history: c.history,
                                        autoResetThreshold: c.autoResetThreshold)
                                    : c)
                                .toList())
                        : pt)
                    .toList())
            : p)
        .toList();
    save();
  }

  void updateSingleReminder(String projId, String partId, String counterId, int index, String? text) {
    state = state
        .map((p) => p.id == projId
            ? KnitProject(
                id: p.id,
                title: p.title,
                isArchived: p.isArchived,
                parts: p.parts
                    .map((pt) => pt.id == partId
                        ? ProjectPart(
                            id: pt.id,
                            name: pt.name,
                            counters: pt.counters.map((c) {
                              if (c.id == counterId) {
                                final up = List<ReminderStep>.from(c.reminders);
                                if (index >= 0 && index < up.length) {
                                  if (text == null || text.trim().isEmpty) {
                                    up.removeAt(index);
                                  } else {
                                    List<String> parts = text.split(':');
                                    String label = parts[0].trim();
                                    String instruction = parts.length > 1 ? parts.sublist(1).join(':').trim() : '';
                                    up[index] = ReminderStep(label: label, instruction: instruction);
                                  }
                                }
                                return KnitCounter(
                                    id: c.id,
                                    name: c.name,
                                    currentRow: c.currentRow,
                                    reminders: up,
                                    linkedCounterId: c.linkedCounterId,
                                    linkMode: c.linkMode,
                                    colorValue: c.colorValue,
                                    history: c.history,
                                    autoResetThreshold: c.autoResetThreshold);
                              }
                              return c;
                            }).toList())
                        : pt)
                    .toList())
            : p)
        .toList();
    save();
  }

  void addReminders(String projId, String partId, String counterId, int startRow, String pattern, {int? recurringInterval}) {
    final List<ReminderStep> rawSteps = [];

    if (recurringInterval != null && recurringInterval > 0) {
      // Basic fallback loop for dynamic configurations
      for (int r = startRow; r <= 1000; r += recurringInterval) {
        rawSteps.add(ReminderStep(label: "Row $r", instruction: pattern.trim()));
      }
    } else {
      // Split pattern content cleanly right before "Row " or "Round " to handle inline items 
      List<String> lines = pattern.split(RegExp(r'(?=(?:Row|Round)\s+\d+)', caseSensitive: false));
      
      for (var line in lines) {
        if (line.trim().isEmpty) continue;

        List<String> parts = line.split(':');
        String label = parts[0].trim();
        String instruction = parts.length > 1 ? parts.sublist(1).join(':').trim() : '';

        // Clean up formatting edge cases from regex grouping
        if (instruction.endsWith('.')) {
          instruction = instruction.substring(0, instruction.length);
        }

        rawSteps.add(ReminderStep(label: label, instruction: instruction));
      }
    }

    state = state
        .map((p) => p.id == projId
            ? KnitProject(
                id: p.id,
                title: p.title,
                isArchived: p.isArchived,
                parts: p.parts
                    .map((pt) => pt.id == partId
                        ? ProjectPart(
                            id: pt.id,
                            name: pt.name,
                            counters: pt.counters
                                .map((c) => c.id == counterId
                                    ? KnitCounter(
                                        id: c.id,
                                        name: c.name,
                                        currentRow: c.currentRow,
                                        colorValue: c.colorValue,
                                        linkedCounterId: c.linkedCounterId,
                                        linkMode: c.linkMode,
                                        reminders: [...c.reminders, ...rawSteps],
                                        history: c.history,
                                        autoResetThreshold: c.autoResetThreshold)
                                    : c)
                                .toList())
                        : pt)
                    .toList())
            : p)
        .toList();
    save();
  }
}

final projectProvider = StateNotifierProvider<ProjectNotifier, List<KnitProject>>((ref) => ProjectNotifier());

// --- ADAPTIVE UI CONFIRMATION ---

void _showDeleteConfirmation(BuildContext context, String title, String message, VoidCallback onConfirm) {
  showAdaptiveDialog(
    context: context,
    builder: (ctx) => AlertDialog.adaptive(
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.red)),
      content: Text(message),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Cancel")),
        TextButton(
            onPressed: () {
              onConfirm();
              Navigator.pop(ctx);
            },
            child: const Text("Delete", style: TextStyle(color: Colors.red))),
      ],
    ),
  );
}

// --- INITIAL ENTRY ---

void main() => runApp(const ProviderScope(child: KnitlyApp()));

class KnitlyApp extends ConsumerWidget {
  const KnitlyApp({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: Colors.white,
        colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFF64B5F6), primary: const Color(0xFF64B5F6), secondary: const Color(0xFFFFCA28)),
        appBarTheme: const AppBarTheme(
            backgroundColor: Colors.white,
            centerTitle: true,
            titleTextStyle: TextStyle(color: Color(0xFF263238), fontSize: 20, fontWeight: FontWeight.bold)),
      ),
      home: const RootScreen(),
    );
  }
}

class RootScreen extends ConsumerStatefulWidget {
  const RootScreen({super.key});
  @override
  ConsumerState<RootScreen> createState() => _RootScreenState();
}

class _RootScreenState extends ConsumerState<RootScreen> {
  bool _checked = false;
  @override
  Widget build(BuildContext context) {
    final appPrefs = ref.watch(prefsProvider);
    if (!_checked && appPrefs.lastProjectId != null) {
      _checked = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const ProjectListScreen()));
        Navigator.push(context, MaterialPageRoute(builder: (_) => ProjectDetailScreen(projectId: appPrefs.lastProjectId!)));

        if (appPrefs.lastPartId != null) {
          Navigator.push(
              context, MaterialPageRoute(builder: (_) => PartDetailScreen(projectId: appPrefs.lastProjectId!, partId: appPrefs.lastPartId!)));
        }
      });
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return const ProjectListScreen();
  }
}

class ProjectListScreen extends ConsumerWidget {
  const ProjectListScreen({super.key});
  void _showImportDialog(BuildContext context, WidgetRef ref) {
    final controller = TextEditingController();
    showAdaptiveDialog(
      context: context,
      builder: (ctx) => AlertDialog.adaptive(
        title: const Text("Import Project Blueprint"),
        content: Material(
          color: Colors.transparent,
          child: TextField(
            controller: controller,
            decoration: const InputDecoration(hintText: "Paste layout string code here...", border: OutlineInputBorder()),
            maxLines: 3,
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Cancel")),
          TextButton(
            onPressed: () {
              try {
                ref.read(projectProvider.notifier).importProject(controller.text.trim());
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                    content: Text("Blueprint data parsed and loaded!", style: TextStyle(color: Colors.white)), backgroundColor: Colors.green));
              } catch (e) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                    content: Text("Unable to parse config payload text.", style: TextStyle(color: Colors.white)), backgroundColor: Colors.red));
              }
            },
            child: const Text("Import"),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final allProjects = ref.watch(projectProvider);
    final active = allProjects.where((p) => !p.isArchived).toList();
    final archived = allProjects.where((p) => p.isArchived).toList();
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text("My Design Projects"),
          actions: [
            IconButton(
              icon: const Icon(Icons.file_download_outlined),
              tooltip: "Import Project Blueprint",
              onPressed: () => _showImportDialog(context, ref),
            )
          ],
          bottom: TabBar(indicatorColor: Theme.of(context).colorScheme.primary, tabs: const [
            Tab(text: "Active Workspace"),
            Tab(text: "Archived Collection")
          ]),
        ),
        body: TabBarView(children: [_buildList(context, ref, active), _buildList(context, ref, archived)]),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: () => _showRenameDialog(context, "New Pattern Blueprint", "e.g., Sweater",
              (name) => ref.read(projectProvider.notifier).addProject(name)),
          icon: const Icon(Icons.add, color: Colors.white),
          label: const Text("Create Blueprint", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          backgroundColor: Theme.of(context).colorScheme.primary,
        ),
      ),
    );
  }

  Widget _buildList(BuildContext context, WidgetRef ref, List<KnitProject> projects) {
    if (projects.isEmpty) {
      return Center(child: Text("No layout data here yet.", style: TextStyle(color: Colors.grey.shade400)));
    }
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: projects.length,
      itemBuilder: (context, i) {
        final p = projects[i];
        return Dismissible(
          key: Key(p.id),
          direction: DismissDirection.horizontal,
          background: Container(
            color: p.isArchived ? Colors.blue : Colors.orange,
            alignment: Alignment.centerLeft,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            margin: const EdgeInsets.only(bottom: 12),
            child: Icon(p.isArchived ? Icons.unarchive : Icons.archive, color: Colors.white),
          ),
          secondaryBackground: Container(
            color: Colors.red,
            alignment: Alignment.centerRight,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            margin: const EdgeInsets.only(bottom: 12),
            child: const Icon(Icons.delete, color: Colors.white),
          ),
          confirmDismiss: (direction) async {
            if (direction == DismissDirection.endToStart) {
              bool delete = false;
              await showAdaptiveDialog(
                context: context,
                builder: (ctx) => AlertDialog.adaptive(
                  title: const Text("Delete Project", style: TextStyle(color: Colors.red)),
                  content: const Text("Erase blueprint configuration completely?"),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Cancel")),
                    TextButton(
                        onPressed: () {
                          delete = true;
                          Navigator.pop(ctx);
                        },
                        child: const Text("Delete", style: TextStyle(color: Colors.red))),
                  ],
                ),
              );
              return delete;
            }
            return true;
          },
          onDismissed: (direction) {
            if (direction == DismissDirection.startToEnd) {
              ref.read(projectProvider.notifier).toggleArchive(p.id);
            } else {
              ref.read(projectProvider.notifier).deleteProject(p.id);
            }
          },
          child: Card(
            margin: const EdgeInsets.only(bottom: 12),
            color: const Color(0xFFF4F9FC),
            child: ListTile(
              title: Text(p.title, style: const TextStyle(fontWeight: FontWeight.bold)),
              subtitle: Text("${p.parts.length} specialized parts assembly"),
              onTap: () {
                ref.read(prefsProvider.notifier).updatePrefs(lastProjectId: p.id);
                Navigator.push(context, MaterialPageRoute(builder: (c) => ProjectDetailScreen(projectId: p.id)));
              },
              trailing: PopupMenuButton<String>(
                color: Colors.white,
                itemBuilder: (ctx) => [
                  const PopupMenuItem(value: 'export', child: Text("Export Data Bundle")),
                  const PopupMenuItem(value: 'rename', child: Text("Rename")),
                  PopupMenuItem(value: 'archive', child: Text(p.isArchived ? "Restore" : "Archive")),
                  const PopupMenuItem(value: 'delete', child: Text("Delete", style: TextStyle(color: Colors.red)))
                ],
                onSelected: (val) async {
                  if (val == 'export') {
                    final code = ref.read(projectProvider.notifier).exportProject(p.id);
                    await Clipboard.setData(ClipboardData(text: code));
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Export layout string payload copied to clipboard!")));
                  }
                  if (val == 'rename') {
                    _showRenameDialog(context, "Rename Title", "e.g., Sweater", (n) => ref.read(projectProvider.notifier).renameProject(p.id, n));
                  }
                  if (val == 'archive') {
                    ref.read(projectProvider.notifier).toggleArchive(p.id);
                  }
                  if (val == 'delete') {
                    _showDeleteConfirmation(context, "Remove Project", "Erase blueprint configuration completely?",
                        () => ref.read(projectProvider.notifier).deleteProject(p.id));
                  }
                },
              ),
            ),
          ),
        );
      },
    );
  }
}

class ProjectDetailScreen extends ConsumerWidget {
  final String projectId;
  const ProjectDetailScreen({super.key, required this.projectId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final project = ref.watch(projectProvider).where((p) => p.id == projectId).firstOrNull;
    if (project == null) {
      return const Scaffold(body: Center(child: Text("Data missing.")));
    }
    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) {
          ref.read(prefsProvider.notifier).updatePrefs(clearProject: true);
        }
      },
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
              icon: const Icon(Icons.arrow_back_ios_new),
              onPressed: () {
                ref.read(prefsProvider.notifier).updatePrefs(clearProject: true);
                Navigator.pop(context);
              }),
          title: Text(project.title),
          actions: [
            IconButton(
                icon: const Icon(Icons.add_circle),
                onPressed: () => _showRenameDialog(
                    context, "Create Section Part Line", "e.g., Sleeve", (name) => ref.read(projectProvider.notifier).addPart(project.id, name)))
          ],
        ),
        body: ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: project.parts.length,
          itemBuilder: (ctx, i) {
            final part = project.parts[i];
            return Dismissible(
              key: Key(part.id),
              direction: DismissDirection.endToStart,
              background: Container(
                color: Colors.red,
                alignment: Alignment.centerRight,
                padding: const EdgeInsets.symmetric(horizontal: 20),
                margin: const EdgeInsets.only(bottom: 12),
                child: const Icon(Icons.delete, color: Colors.white),
              ),
              confirmDismiss: (_) async {
                bool delete = false;
                await showAdaptiveDialog(
                  context: context,
                  builder: (ctx) => AlertDialog.adaptive(
                    title: const Text("Purge Part Block", style: TextStyle(color: Colors.red)),
                    content: const Text("Remove segment and tracking elements?"),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Cancel")),
                      TextButton(
                          onPressed: () {
                            delete = true;
                            Navigator.pop(ctx);
                          },
                          child: const Text("Delete", style: TextStyle(color: Colors.red))),
                    ],
                  ),
                );
                return delete;
              },
              onDismissed: (_) => ref.read(projectProvider.notifier).deletePart(project.id, part.id),
              child: Card(
                margin: const EdgeInsets.only(bottom: 12),
                color: const Color(0xFFE1F5FE),
                child: ListTile(
                  title: Text(part.name, style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF0288D1))),
                  subtitle: Text("Contains ${part.counters.length} modular row monitors"),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      PopupMenuButton<String>(
                        icon: const Icon(Icons.more_vert),
                        color: Colors.white,
                        itemBuilder: (c) => [
                          const PopupMenuItem(value: 'rename', child: Text("Rename")),
                          const PopupMenuItem(value: 'delete', child: Text("Delete", style: TextStyle(color: Colors.red))),
                        ],
                        onSelected: (val) {
                          if (val == 'rename') {
                            _showRenameDialog(context, "Rename Part", "e.g., Sleeve",
                                (name) => ref.read(projectProvider.notifier).renamePart(project.id, part.id, name));
                          }
                          if (val == 'delete') {
                            _showDeleteConfirmation(context, "Purge Part Block", "Remove segment and tracking elements?",
                                () => ref.read(projectProvider.notifier).deletePart(project.id, part.id));
                          }
                        },
                      ),
                      const Icon(Icons.chevron_right),
                    ],
                  ),
                  onTap: () {
                    ref.read(prefsProvider.notifier).updatePrefs(lastPartId: part.id);
                    Navigator.push(context, MaterialPageRoute(builder: (c) => PartDetailScreen(projectId: project.id, partId: part.id)));
                  },
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

// --- PART DETAIL CONFIG SCREEN ---

class PartDetailScreen extends ConsumerStatefulWidget {
  final String projectId;
  final String partId;
  const PartDetailScreen({super.key, required this.projectId, required this.partId});

  @override
  ConsumerState<PartDetailScreen> createState() => _PartDetailScreenState();
}

class _PartDetailScreenState extends ConsumerState<PartDetailScreen> {
  String? _selectedReminderCounterId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(prefsProvider.notifier).updatePrefs(lastProjectId: widget.projectId, lastPartId: widget.partId);
      if (ref.read(prefsProvider).keepAwake) {
        try {
          WakelockPlus.enable();
        } catch (_) {}
      }
    });
  }

  @override
  void dispose() {
    try {
      WakelockPlus.disable();
    } catch (_) {}
    super.dispose();
  }

  void _showSetRowDialog(BuildContext context, KnitCounter counter) {
    final controller = TextEditingController(text: counter.currentRow.toString());
    showAdaptiveDialog(
      context: context,
      builder: (ctx) => AlertDialog.adaptive(
        title: const Text("Set Exact Row"),
        content: Material(
          color: Colors.transparent,
          child: TextField(
            controller: controller,
            keyboardType: TextInputType.number,
            autofocus: true,
            decoration: const InputDecoration(border: OutlineInputBorder(), hintText: "Enter row number"),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Cancel")),
          TextButton(
            onPressed: () {
              final val = int.tryParse(controller.text);
              if (val != null) {
                ref.read(projectProvider.notifier).setExactRow(widget.projectId, widget.partId, counter.id, val);
              }
              Navigator.pop(ctx);
            },
            child: const Text("Set Row"),
          ),
        ],
      ),
    );
  }

  void _showResetToZeroConfirmation(BuildContext context, KnitCounter counter) {
    showAdaptiveDialog(
      context: context,
      builder: (ctx) => AlertDialog.adaptive(
        title: const Text("Reset to 0?", style: TextStyle(fontWeight: FontWeight.bold)),
        content: const Text("Are you sure you want to reset this counter back to zero?"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Cancel")),
          TextButton(
            onPressed: () {
              ref.read(projectProvider.notifier).setExactRow(widget.projectId, widget.partId, counter.id, 0, isReset: true);
              Navigator.pop(ctx);
            },
            child: const Text("Reset", style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  void _showAutoResetDialog(BuildContext context, KnitCounter counter) {
    final controller = TextEditingController(text: counter.autoResetThreshold?.toString() ?? "");
    showAdaptiveDialog(
      context: context,
      builder: (ctx) => AlertDialog.adaptive(
        title: const Text("Auto-Reset Target"),
        content: Material(
          color: Colors.transparent,
          child: TextField(
            controller: controller,
            keyboardType: TextInputType.number,
            autofocus: true,
            decoration: const InputDecoration(border: OutlineInputBorder(), hintText: "Enter max row value", helperText: "Leave blank to disable"),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Cancel")),
          TextButton(
            onPressed: () {
              final val = int.tryParse(controller.text);
              ref.read(projectProvider.notifier).setAutoResetThreshold(widget.projectId, widget.partId, counter.id, val);
              Navigator.pop(ctx);
            },
            child: const Text("Save"),
          ),
        ],
      ),
    );
  }

  void _showHistoryDialog(BuildContext context, KnitCounter counter) {
    showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.white,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
        builder: (ctx) => Container(
              padding: const EdgeInsets.only(top: 24, left: 16, right: 16, bottom: 16),
              height: MediaQuery.of(context).size.height * 0.65,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text("${counter.name} — Action Log", style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const Divider(),
                  Expanded(
                    child: counter.history.isEmpty
                        ? const Center(child: Text("No actions recorded yet.", style: TextStyle(color: Colors.grey)))
                        : ListView.builder(
                            itemCount: counter.history.length,
                            itemBuilder: (c, i) => ListTile(
                              leading: const Icon(Icons.history, size: 22, color: Colors.grey),
                              title: Text(counter.history[i], style: const TextStyle(fontSize: 14)),
                              dense: true,
                            ),
                          ),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(width: double.infinity, child: FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text("Close")),)
                ],
              ),
            ));
  }

  void _showAddRemindersDialog(BuildContext context, KnitCounter counter) {
    final patternController = TextEditingController();
    showAdaptiveDialog(
      context: context,
      builder: (ctx) => AlertDialog.adaptive(
        title: const Text("Paste Knitting Pattern"),
        content: Material(
          color: Colors.transparent,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text("Paste your sequence here. Repeated rows will be saved individually step-by-step.", style: TextStyle(fontSize: 12, color: Colors.grey)),
              const SizedBox(height: 8),
              TextField(
                controller: patternController,
                maxLines: 6,
                decoration: const InputDecoration(border: OutlineInputBorder(), hintText: "Paste instructions..."),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Cancel")),
          TextButton(
            onPressed: () {
              if (patternController.text.trim().isNotEmpty) {
                ref.read(projectProvider.notifier).addReminders(
                      widget.projectId,
                      widget.partId,
                      counter.id,
                      0,
                      patternController.text,
                    );
              }
              Navigator.pop(ctx);
            },
            child: const Text("Save Steps"),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final project = ref.watch(projectProvider).firstWhere((p) => p.id == widget.projectId);
    final part = project.parts.firstWhere((pt) => pt.id == widget.partId);
    final prefs = ref.watch(prefsProvider);

    ref.listen<AppPrefs>(prefsProvider, (previous, next) {
      if (previous?.keepAwake != next.keepAwake) {
        try {
          if (next.keepAwake) WakelockPlus.enable(); else WakelockPlus.disable();
        } catch (_) {}
      }
    });

    if (part.counters.isEmpty) {
      return const Scaffold(body: Center(child: Text("Empty configuration space.")));
    }
    final mainCounter = part.counters.first;
    final secondaryCounters = part.counters.skip(1).toList();

    if (_selectedReminderCounterId == null) {
      final savedCounterId = prefs.lastSelectedReminderCounterId;
      if (savedCounterId != null && part.counters.any((c) => c.id == savedCounterId)) {
        _selectedReminderCounterId = savedCounterId;
      } else {
        _selectedReminderCounterId = mainCounter.id;
      }
    }
    final activeReminderCounter = part.counters.firstWhere((c) => c.id == _selectedReminderCounterId, orElse: () => mainCounter);
    final activeCounterColor = Color(activeReminderCounter.colorValue ?? 0xFF64B5F6);

    // Dynamic extraction of the sequential instruction based on the current row index position
    ReminderStep? currentActiveStep;
    if (activeReminderCounter.reminders.isNotEmpty) {
      int currentIdx = activeReminderCounter.currentRow;
      if (currentIdx >= 0 && currentIdx < activeReminderCounter.reminders.length) {
        currentActiveStep = activeReminderCounter.reminders[currentIdx];
      }
    }

    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) {
          ref.read(prefsProvider.notifier).updatePrefs(clearPart: true);
        }
      },
      child: Scaffold(
        backgroundColor: const Color(0xFFF5EFE9),
        appBar: AppBar(
          backgroundColor: const Color(0xFFF5EFE9),
          surfaceTintColor: Colors.transparent,
          leading: IconButton(
              icon: const Icon(Icons.arrow_back_ios_new),
              onPressed: () {
                ref.read(prefsProvider.notifier).updatePrefs(clearPart: true);
                Navigator.pop(context);
              }),
          title: Text(part.name),
          actions: [
            IconButton(
              icon: Icon(prefs.keepAwake ? Icons.visibility : Icons.visibility_off, color: prefs.keepAwake ? Colors.orange : Colors.grey),
              tooltip: prefs.keepAwake ? "Screen stays awake" : "Screen can sleep",
              onPressed: () {
                final newState = !prefs.keepAwake;
                ref.read(prefsProvider.notifier).updatePrefs(keepAwake: newState);
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(newState ? "Screen Wake Lock Enabled" : "Screen Wake Lock Disabled"), duration: const Duration(seconds: 1)));
              },
            ),
            IconButton(
                icon: const Icon(Icons.add_box_outlined),
                onPressed: () => _showRenameDialog(context, "Append Secondary Tracker", "Row counter name",
                    (n) => ref.read(projectProvider.notifier).addCounter(widget.projectId, widget.partId, n)))
          ],
        ),
        body: Stack(
          children: [
            SingleChildScrollView(
              padding: const EdgeInsets.only(bottom: 240),
              child: Column(
                children: [
                  _buildMainTracker(context, mainCounter, part.counters),
                  const SizedBox(height: 12),
                  if (secondaryCounters.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: GridView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 2, childAspectRatio: 0.82, crossAxisSpacing: 8, mainAxisSpacing: 12),
                        itemCount: secondaryCounters.length,
                        itemBuilder: (ctx, i) => _buildSecondaryTracker(context, secondaryCounters[i], part.counters),
                      ),
                    ),
                ],
              ),
            ),
            
            // --- PATTERN SEQUENCE REMINDER OVERLAY PANEL ---
            Positioned(
              left: prefs.reminderX,
              top: prefs.reminderY,
              child: GestureDetector(
                onPanUpdate: (d) => ref.read(prefsProvider.notifier).updatePrefs(
                      rx: (prefs.reminderX + d.delta.dx).clamp(0.0, MediaQuery.of(context).size.width - 270),
                      ry: (prefs.reminderY + d.delta.dy).clamp(0.0, MediaQuery.of(context).size.height - 220),
                    ),
                child: Container(
                  width: 260,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: activeCounterColor, width: 3),
                    boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 8, spreadRadius: 2)],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: activeCounterColor.withOpacity(0.15),
                          borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            DropdownButton<String>(
                              value: _selectedReminderCounterId,
                              underline: const SizedBox(),
                              icon: const Icon(Icons.arrow_drop_down, size: 18),
                              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.black87),
                              items: part.counters
                                  .map((c) => DropdownMenuItem(value: c.id, child: Text(c.name.length > 12 ? "${c.name.substring(0, 10)}..." : c.name)))
                                  .toList(),
                              onChanged: (v) {
                                if (v != null) {
                                  setState(() {
                                    _selectedReminderCounterId = v;
                                  });
                                  ref.read(prefsProvider.notifier).updatePrefs(lastSelectedReminderCounterId: v);
                                }
                              },
                            ),
                            IconButton(
                              icon: const Icon(Icons.paste_rounded, size: 18, color: Colors.blueGrey),
                              dense: true,
                              visualDensity: VisualDensity.compact,
                              tooltip: "Paste Pattern Text",
                              onPressed: () => _showAddRemindersDialog(context, activeReminderCounter),
                            )
                          ],
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.all(12),
                        child: activeReminderCounter.reminders.isEmpty
                            ? InkWell(
                                onTap: () => _showAddRemindersDialog(context, activeReminderCounter),
                                child: const Padding(
                                  padding: EdgeInsets.symmetric(vertical: 20),
                                  child: Column(
                                    children: [
                                      Icon(Icons.add_comment_outlined, color: Colors.grey, size: 32),
                                      SizedBox(height: 6),
                                      Text("Tap to Paste Pattern Instructions", textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: Colors.grey)),
                                    ],
                                  ),
                                ),
                              )
                            : Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(
                                        currentActiveStep != null ? currentActiveStep.label : "Finished",
                                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.blueGrey),
                                      ),
                                      Text(
                                        "Step ${activeReminderCounter.currentRow + 1} of ${activeReminderCounter.reminders.length}",
                                        style: const TextStyle(fontSize: 10, color: Colors.grey, fontWeight: FontWeight.w600),
                                      ),
                                    ],
                                  ),
                                  const Divider(height: 10),
                                  Container(
                                    constraints: const BoxConstraints(maxHeight: 70),
                                    width: double.infinity,
                                    child: SingleChildScrollView(
                                      child: Text(
                                        currentActiveStep != null && currentActiveStep.instruction.isNotEmpty
                                            ? currentActiveStep.instruction
                                            : (currentActiveStep != null ? "(Plain Row Label)" : "Pattern complete! Clear or repaste text parameters."),
                                        style: const TextStyle(fontSize: 13, height: 1.3, color: Colors.blackDE),
                                      ),
                                    ),
                                  ),
                                  if (activeReminderCounter.reminders.isNotEmpty) ...[
                                    const SizedBox(height: 4),
                                    Align(
                                      alignment: Alignment.centerRight,
                                      child: TextButton.icon(
                                        style: TextButton.styleFrom(visualDensity: VisualDensity.compact, padding: EdgeInsets.zero),
                                        onPressed: () {
                                          setState(() {
                                            activeReminderCounter.reminders.clear();
                                          });
                                          ref.read(projectProvider.notifier).save();
                                        },
                                        icon: const Icon(Icons.clear_all, size: 14, color: Colors.redAccent),
                                        label: const Text("Clear Pattern", style: TextStyle(fontSize: 11, color: Colors.redAccent)),
                                      ),
                                    )
                                  ]
                                ],
                              ),
                      ),
                    ],
                  ),
                ),
              ),
            )
          ],
        ),
      ),
    );
  }

  // --- TRADITIONAL MONOLITHIC STEP DISPLAY ---
  Widget _buildMainTracker(BuildContext context, KnitCounter counter, List<KnitCounter> all) {
    final themeColor = Color(counter.colorValue ?? 0xFF64B5F6);
    return Container(
      margin: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(24), boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 6)]),
      child: Column(
        children: [
          ListTile(
            title: Text(counter.name, style: const TextStyle(fontWeight: FontWeight.bold)),
            trailing: _buildCounterMenu(counter),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Text('${counter.currentRow}', style: TextStyle(fontSize: 80, fontWeight: FontWeight.bold, color: themeColor)),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              IconButton.filled(
                backgroundColor: Colors.grey.shade200,
                icon: const Icon(Icons.remove, color: Colors.black),
                onPressed: () => ref.read(projectProvider.notifier).updateRow(widget.projectId, widget.partId, counter.id, -1),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: themeColor, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 15)),
                onPressed: () => ref.read(projectProvider.notifier).updateRow(widget.projectId, widget.partId, counter.id, 1),
                child: const Text("NEXT ROW", style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ],
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _buildSecondaryTracker(BuildContext context, KnitCounter counter, List<KnitCounter> all) {
    final themeColor = Color(counter.colorValue ?? 0xFFFFCA28);
    return Container(
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 4)]),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Padding(
                padding: const EdgeInsets.only(left: 12),
                child: Text(counter.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
              ),
              _buildCounterMenu(counter),
            ],
          ),
          Text('${counter.currentRow}', style: TextStyle(fontSize: 36, fontWeight: FontWeight.bold, color: themeColor)),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              IconButton.filled(
                constraints: const BoxConstraints(),
                padding: const EdgeInsets.all(6),
                backgroundColor: Colors.grey.shade100,
                icon: const Icon(Icons.remove, size: 16, color: Colors.black),
                onPressed: () => ref.read(projectProvider.notifier).updateRow(widget.projectId, widget.partId, counter.id, -1),
              ),
              IconButton.filled(
                constraints: const BoxConstraints(),
                padding: const EdgeInsets.all(6),
                backgroundColor: themeColor,
                icon: const Icon(Icons.add, size: 16, color: Colors.white),
                onPressed: () => ref.read(projectProvider.notifier).updateRow(widget.projectId, widget.partId, counter.id, 1),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCounterMenu(KnitCounter counter) {
    return PopupMenuButton<String>(
      color: Colors.white,
      icon: const Icon(Icons.more_vert, size: 20),
      itemBuilder: (ctx) => [
        const PopupMenuItem(value: 'set', child: Text("Set Exact Value")),
        const PopupMenuItem(value: 'reset', child: Text("Reset to Zero")),
        const PopupMenuItem(value: 'autoreset', child: Text("Set Auto-Reset Rule")),
        const PopupMenuItem(value: 'rename', child: Text("Rename Tracker")),
        const PopupMenuItem(value: 'history', child: Text("View Action Log")),
        const PopupMenuItem(value: 'color', child: Text("Change Accent Color")),
        const PopupMenuItem(value: 'delete', child: Text("Delete Tracker", style: TextStyle(color: Colors.red))),
      ],
      onSelected: (val) {
        if (val == 'set') _showSetRowDialog(context, counter);
        if (val == 'reset') _showResetToZeroConfirmation(context, counter);
        if (val == 'autoreset') _showAutoResetDialog(context, counter);
        if (val == 'rename') {
          _showRenameDialog(context, "Rename Tracker", counter.name,
              (n) => ref.read(projectProvider.notifier).renameCounter(widget.projectId, widget.partId, counter.id, n));
        }
        if (val == 'history') _showHistoryDialog(context, counter);
        if (val == 'color') _showColorPickModal(context, counter);
        if (val == 'delete') {
          _showDeleteConfirmation(context, "Remove Tracker Link", "Are you sure you want to delete this specific counter?",
              () => ref.read(projectProvider.notifier).deleteCounter(widget.projectId, widget.partId, counter.id));
        }
      },
    );
  }

  void _showColorPickModal(BuildContext context, KnitCounter counter) {
    final colors = [0xFF64B5F6, 0xFFFFCA28, 0xFF81C784, 0xFFE57373, 0xFFBA68C8, 0xFF90A4AE];
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text("Select Tracker Color Theme", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: colors
                  .map((c) => GestureDetector(
                        onTap: () {
                          ref.read(projectProvider.notifier).setCounterColor(widget.projectId, widget.partId, counter.id, c);
                          Navigator.pop(ctx);
                        },
                        child: CircleAvatar(backgroundColor: Color(c), radius: 20),
                      ))
                  .toList(),
            )
          ],
        ),
      ),
    );
  }
}

// --- REUSABLE TEXT ENTRY MODAL ---

void _showRenameDialog(BuildContext context, String title, String hintText, Function(String) onSave) {
  final controller = TextEditingController();
  showAdaptiveDialog(
    context: context,
    builder: (ctx) => AlertDialog.adaptive(
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
      content: Material(
        color: Colors.transparent,
        child: TextField(controller: controller, autofocus: true, decoration: InputDecoration(hintText: hintText, border: const OutlineInputBorder())),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Cancel")),
        TextButton(
          onPressed: () {
            if (controller.text.trim().isNotEmpty) {
              onSave(controller.text.trim());
            }
            Navigator.pop(ctx);
          },
          child: const Text("Save"),
        ),
      ],
    ),
  );
}
