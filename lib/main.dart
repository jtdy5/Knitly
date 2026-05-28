import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'package:uuid/uuid.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

// --- MODELS ---\n
class KnitCounter {
  final String id;
  String name;
  int currentRow;
  Map<int, String> reminders;
  String? linkedCounterId;
  String linkMode;
  int? colorValue;
  List<String> history;
  int? autoResetThreshold;

  KnitCounter({
    required this.id,
    required this.name,
    this.currentRow = 0,
    this.reminders = const {},
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
        'reminders': reminders.map((k, v) => MapEntry(k.toString(), v)),
        'linkedCounterId': linkedCounterId,
        'linkMode': linkMode,
        'colorValue': colorValue,
        'history': history,
        'autoResetThreshold': autoResetThreshold,
      };

  factory KnitCounter.fromJson(Map<String, dynamic> json) {
    Map<int, String> parsedReminders = {};
    if (json['reminders'] != null) {
      (json['reminders'] as Map).forEach((k, v) {
        final keyInt = int.tryParse(k.toString());
        if (keyInt != null) {
          parsedReminders[keyInt] = v.toString();
        }
      });
    }
    return KnitCounter(
      id: json['id'] ?? const Uuid().v4(),
      name: json['name'] ?? 'Counter',
      currentRow: json['currentRow'] ?? 0,
      reminders: parsedReminders,
      linkedCounterId: json['linkedCounterId'],
      linkMode: json['linkMode'] ?? 'none',
      colorValue: json['colorValue'],
      history: List<String>.from(json['history'] ?? []),
      autoResetThreshold: json['autoResetThreshold'],
    );
  }

  KnitCounter copyWith({
    String? name,
    int? currentRow,
    Map<int, String>? reminders,
    String? linkedCounterId,
    String? linkMode,
    int? colorValue,
    List<String>? history,
    int? autoResetThreshold,
  }) {
    return KnitCounter(
      id: id,
      name: name ?? this.name,
      currentRow: currentRow ?? this.currentRow,
      reminders: reminders ?? this.reminders,
      linkedCounterId: linkedCounterId ?? this.linkedCounterId,
      linkMode: linkMode ?? this.linkMode,
      colorValue: colorValue ?? this.colorValue,
      history: history ?? this.history,
      autoResetThreshold: autoResetThreshold ?? this.autoResetThreshold,
    );
  }
}

class Project {
  final String id;
  String name;
  List<KnitCounter> counters;
  String? activeCounterId;
  String notes;

  Project({
    required this.id,
    required this.name,
    required this.counters,
    this.activeCounterId,
    this.notes = "",
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'counters': counters.map((c) => c.toJson()).toList(),
        'activeCounterId': activeCounterId,
        'notes': notes,
      };

  factory Project.fromJson(Map<String, dynamic> json) {
    var countersList = (json['counters'] as List? ?? [])
        .map((c) => KnitCounter.fromJson(c))
        .toList();
    return Project(
      id: json['id'] ?? const Uuid().v4(),
      name: json['name'] ?? 'Project',
      counters: countersList,
      activeCounterId: json['activeCounterId'],
      notes: json['notes'] ?? "",
    );
  }
}

// --- STATE MANAGEMENT (RIVERPOD) ---

class ProjectNotifier extends StateNotifier<List<Project>> {
  ProjectNotifier() : super([]) {
    _loadData();
  }

  static const _storageKey = 'knitly_projects_data';

  Future<void> _loadData() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_storageKey);
    if (raw != null) {
      try {
        final List decoded = jsonDecode(raw);
        state = decoded.map((p) => Project.fromJson(p)).toList();
      } catch (_) {
        state = [];
      }
    }
    if (state.isEmpty) {
      _createInitialProject();
    }
  }

  Future<void> _saveData() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = jsonEncode(state.map((p) => p.toJson()).toList());
    await prefs.setString(_storageKey, raw);
  }

  void _createInitialProject() {
    final initialCounter = KnitCounter(id: const Uuid().v4(), name: "Main Row Counter");
    final initialProject = Project(
      id: const Uuid().v4(),
      name: "My First Project",
      counters: [initialCounter],
      activeCounterId: initialCounter.id,
    );
    state = [initialProject];
    _saveData();
  }

  void addProject(String name) {
    final initialCounter = KnitCounter(id: const Uuid().v4(), name: "Main Row Counter");
    final newProj = Project(
      id: const Uuid().v4(),
      name: name,
      counters: [initialCounter],
      activeCounterId: initialCounter.id,
    );
    state = [...state, newProj];
    _saveData();
  }

  void renameProject(String projectId, String newName) {
    state = [
      for (final p in state)
        if (p.id == projectId)
          Project(id: p.id, name: newName, counters: p.counters, activeCounterId: p.activeCounterId, notes: p.notes)
        else
          p
    ];
    _saveData();
  }

  void deleteProject(String projectId) {
    state = state.where((p) => p.id != projectId).toList();
    if (state.isEmpty) {
      _createInitialProject();
    } else {
      _saveData();
    }
  }

  void updateNotes(String projectId, String rawNotes) {
    state = [
      for (final p in state)
        if (p.id == projectId)
          Project(id: p.id, name: p.name, counters: p.counters, activeCounterId: p.activeCounterId, notes: rawNotes)
        else
          p
    ];
    _saveData();
  }

  void addCounter(String projectId, String name) {
    state = [
      for (final p in state)
        if (p.id == projectId)
          (() {
            final newC = KnitCounter(id: const Uuid().v4(), name: name);
            final updatedCounters = [...p.counters, newC];
            return Project(
              id: p.id,
              name: p.name,
              counters: updatedCounters,
              activeCounterId: p.activeCounterId ?? newC.id,
              notes: p.notes,
            );
          })()
        else
          p
    ];
    _saveData();
  }

  void selectActiveCounter(String projectId, String counterId) {
    state = [
      for (final p in state)
        if (p.id == projectId)
          Project(id: p.id, name: p.name, counters: p.counters, activeCounterId: counterId, notes: p.notes)
        else
          p
    ];
    _saveData();
  }

  void updateCounter(String projectId, String counterId, KnitCounter updatedCounter) {
    state = [
      for (final p in state)
        if (p.id == projectId)
          Project(
            id: p.id,
            name: p.name,
            counters: [
              for (final c in p.counters)
                if (c.id == counterId) updatedCounter else c
            ],
            activeCounterId: p.activeCounterId,
            notes: p.notes,
          )
        else
          p
    ];
    _saveData();
  }

  void deleteCounter(String projectId, String counterId) {
    state = [
      for (final p in state)
        if (p.id == projectId)
          (() {
            final filtered = p.counters.where((c) => c.id != counterId).toList();
            String? nextActive = p.activeCounterId;
            if (nextActive == counterId) {
              nextActive = filtered.isNotEmpty ? filtered.first.id : null;
            }
            // Clean up any broken links pointing to this deleted counter
            final cleaned = filtered.map((c) {
              if (c.linkedCounterId == counterId) {
                return c.copyWith(linkedCounterId: null, linkMode: 'none');
              }
              return c;
            }).toList();

            return Project(
              id: p.id,
              name: p.name,
              counters: cleaned,
              activeCounterId: nextActive,
              notes: p.notes,
            );
          })()
        else
          p
    ];
    _saveData();
  }

  void incrementCounterRow(String projectId, String counterId) {
    _adjustCounterRow(projectId, counterId, 1);
  }

  void decrementCounterRow(String projectId, String counterId) {
    _adjustCounterRow(projectId, counterId, -1);
  }

  void _adjustCounterRow(String projectId, String counterId, int delta) {
    final projIdx = state.indexWhere((p) => p.id == projectId);
    if (projIdx == -1) return;
    final proj = state[projIdx];

    final cIdx = proj.counters.indexWhere((c) => c.id == counterId);
    if (cIdx == -1) return;
    final counter = proj.counters[cIdx];

    int targetVal = counter.currentRow + delta;
    if (targetVal < 0) targetVal = 0;

    if (counter.autoResetThreshold != null &&
        counter.autoResetThreshold! > 0 &&
        targetVal >= counter.autoResetThreshold!) {
      targetVal = 0;
    }

    final nowStr = DateTime.now().toIso8601String();
    final updatedHistory = [...counter.history, "$targetVal|$nowStr"];

    KnitCounter updatedPrimary = counter.copyWith(
      currentRow: targetVal,
      history: updatedHistory,
    );

    List<KnitCounter> currentCounters = List.from(proj.counters);
    currentCounters[cIdx] = updatedPrimary;

    if (updatedPrimary.linkedCounterId != null && updatedPrimary.linkMode != 'none') {
      final lIdx = currentCounters.indexWhere((c) => c.id == updatedPrimary.linkedCounterId);
      if (lIdx != -1) {
        final linkedC = currentCounters[lIdx];
        int linkedDelta = 0;

        if (updatedPrimary.linkMode == 'match_always') {
          linkedDelta = delta;
        } else if (updatedPrimary.linkMode == 'match_up_only' && delta > 0) {
          linkedDelta = 1;
        } else if (updatedPrimary.linkMode == 'match_down_only' && delta < 0) {
          linkedDelta = -1;
        } else if (updatedPrimary.linkMode == 'on_reset' && targetVal == 0 && delta > 0) {
          linkedDelta = 1;
        }

        if (linkedDelta != 0) {
          int lTarget = linkedC.currentRow + linkedDelta;
          if (lTarget < 0) lTarget = 0;
          if (linkedC.autoResetThreshold != null &&
              linkedC.autoResetThreshold! > 0 &&
              lTarget >= linkedC.autoResetThreshold!) {
            lTarget = 0;
          }
          currentCounters[lIdx] = linkedC.copyWith(
            currentRow: lTarget,
            history: [...linkedC.history, "$lTarget|$nowStr"],
          );
        }
      }
    }

    state = [
      for (int i = 0; i < state.length; i++)
        if (i == projIdx)
          Project(
            id: proj.id,
            name: proj.name,
            counters: currentCounters,
            activeCounterId: proj.activeCounterId,
            notes: proj.notes,
          )
        else
          state[i]
    ];
    _saveData();
  }

  void resetCounterRow(String projectId, String counterId) {
    final projIdx = state.indexWhere((p) => p.id == projectId);
    if (projIdx == -1) return;
    final proj = state[projIdx];

    final cIdx = proj.counters.indexWhere((c) => c.id == counterId);
    if (cIdx == -1) return;
    final counter = proj.counters[cIdx];

    final nowStr = DateTime.now().toIso8601String();
    final updatedPrimary = counter.copyWith(
      currentRow: 0,
      history: [...counter.history, "0|$nowStr"],
    );

    List<KnitCounter> currentCounters = List.from(proj.counters);
    currentCounters[cIdx] = updatedPrimary;

    if (updatedPrimary.linkedCounterId != null && updatedPrimary.linkMode == 'on_reset') {
      final lIdx = currentCounters.indexWhere((c) => c.id == updatedPrimary.linkedCounterId);
      if (lIdx != -1) {
        final linkedC = currentCounters[lIdx];
        int lTarget = linkedC.currentRow + 1;
        if (linkedC.autoResetThreshold != null &&
            linkedC.autoResetThreshold! > 0 &&
            lTarget >= linkedC.autoResetThreshold!) {
          lTarget = 0;
        }
        currentCounters[lIdx] = linkedC.copyWith(
          currentRow: lTarget,
          history: [...linkedC.history, "$lTarget|$nowStr"],
        );
      }
    }

    state = [
      for (int i = 0; i < state.length; i++)
        if (i == projIdx)
          Project(
            id: proj.id,
            name: proj.name,
            counters: currentCounters,
            activeCounterId: proj.activeCounterId,
            notes: proj.notes,
          )
        else
          state[i]
    ];
    _saveData();
  }
}

final projectsProvider = StateNotifierProvider<ProjectNotifier, List<Project>>((ref) {
  return ProjectNotifier();
});

final activeProjectIdProvider = StateProvider<String?>((ref) {
  final list = ref.watch(projectsProvider);
  return list.isNotEmpty ? list.first.id : null;
});

final keepScreenOnProvider = StateProvider<bool>((ref) => false);

// --- MAIN APPLICATION ENTRY ---

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  runApp(const ProviderScope(child: KnitlyApp()));
}

class KnitlyApp extends StatelessWidget {
  const KnitlyApp({super.key});

  @override
  Widget build(BuildContext context) {
    final customThemeColor = Colors.teal;

    return MaterialApp(
      title: 'Knitly',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: customThemeColor,
          brightness: Brightness.light,
          primary: customThemeColor,
          surface: Colors.grey.shade50,
        ),
        scaffoldBackgroundColor: Colors.grey.shade50,
        cardTheme: CardTheme(
          elevation: 2,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          color: Colors.white,
        ),
        appBarTheme: AppBarTheme(
          backgroundColor: Colors.grey.shade50,
          elevation: 0,
          centerTitle: false,
          titleTextStyle: const TextStyle(
            color: Colors.black87,
            fontSize: 22,
            fontWeight: FontWeight.bold,
          ),
          iconTheme: const IconThemeData(color: Colors.black87),
        ),
      ),
      home: const MainDashboardScreen(),
    );
  }
}

// --- CORE UI SCREENS ---

class MainDashboardScreen extends ConsumerStatefulWidget {
  const MainDashboardScreen({super.key});

  @override
  ConsumerState<MainDashboardScreen> createState() => _MainDashboardScreenState();
}

class _MainDashboardScreenState extends ConsumerState<MainDashboardScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final projects = ref.watch(projectsProvider);
    final activeId = ref.watch(activeProjectIdProvider);

    if (projects.isEmpty) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final activeProject = projects.firstWhere(
      (p) => p.id == activeId,
      orElse: () => projects.first,
    );

    final themeColor = Theme.of(context).primaryColor;

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: themeColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(Icons.gesture, color: themeColor, size: 24),
            ),
            const SizedBox(width: 12),
            const Text("Knitly"),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.folder_open_outlined),
            onPressed: () => _showProjectSelectorBottomSheet(context),
            tooltip: "Switch Project",
          ),
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => _showGlobalSettingsBottomSheet(context),
            tooltip: "Settings",
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Column(
        children: [
          // Project Title Bar Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        activeProject.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        "${activeProject.counters.length} Active Counter${activeProject.counters.length == 1 ? '' : 's'}",
                        style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.edit_note, size: 22),
                  onPressed: () {
                    _showRenameDialog(context, "Rename Project", activeProject.name, (val) {
                      ref.read(projectsProvider.notifier).renameProject(activeProject.id, val);
                    });
                  },
                ),
              ],
            ),
          ),
          // Clean Custom Segmented Tab Bar Control
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
            child: Container(
              height: 46,
              decoration: BoxDecoration(
                color: Colors.grey.shade200,
                borderRadius: BorderRadius.circular(12),
              ),
              child: TabBar(
                controller: _tabController,
                indicatorSize: TabBarIndicatorSize.tab,
                dividerColor: Colors.transparent,
                indicator: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(10),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.05),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    )
                  ],
                ),
                labelColor: themeColor,
                unselectedLabelColor: Colors.grey.shade600,
                labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.normal, fontSize: 13),
                tabs: const [
                  Tab(text: "Counter"),
                  Tab(text: "All Manage"),
                  Tab(text: "Notes"),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          // Screen Tab Views Content Areas
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                CounterFocusView(project: activeProject),
                CountersManagerListView(project: activeProject),
                ProjectNotesTextEditView(project: activeProject),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // Bottom Modal Component Sheet views
  void _showProjectSelectorBottomSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => const ProjectSelectorModalWidget(),
    );
  }

  void _showGlobalSettingsBottomSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => const GlobalSettingsModalWidget(),
    );
  }
}

// --- SUB-VIEWS FOR TABS ---

class CounterFocusView extends ConsumerWidget {
  final Project project;
  const CounterFocusView({super.key, required this.project});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (project.counters.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.unarchive_outlined, size: 64, color: Colors.grey.shade400),
            const SizedBox(height: 16),
            const Text("No counters added yet", style: TextStyle(fontSize: 16, color: Colors.grey)),
          ],
        ),
      );
    }

    final activeCounter = project.counters.firstWhere(
      (c) => c.id == project.activeCounterId,
      orElse: () => project.counters.first,
    );

    final themeColor = Theme.of(context).primaryColor;
    final counterColor = activeCounter.colorValue != null
        ? Color(activeCounter.colorValue!)
        : themeColor;

    // Detect if there is a reminder message for the current row
    final currentReminder = activeCounter.reminders[activeCounter.currentRow];

    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Row Counter Selector Pills Row Strip if multiple counters exist
          if (project.counters.length > 1) ...[
            SizedBox(
              height: 38,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                physics: const BouncingScrollPhysics(),
                itemCount: project.counters.length,
                itemBuilder: (ctx, idx) {
                  final c = project.counters[idx];
                  final isSel = c.id == activeCounter.id;
                  final pillColor = c.colorValue != null ? Color(c.colorValue!) : themeColor;
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(c.name),
                      selected: isSel,
                      selectedColor: pillColor.withOpacity(0.15),
                      labelStyle: TextStyle(
                        fontWeight: isSel ? FontWeight.bold : FontWeight.normal,
                        color: isSel ? pillColor : Colors.grey.shade700,
                        fontSize: 12,
                      ),
                      onSelected: (_) {
                        ref.read(projectsProvider.notifier).selectActiveCounter(project.id, c.id);
                      },
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      showCheckmark: false,
                      side: BorderSide(
                        color: isSel ? pillColor.withOpacity(0.3) : Colors.grey.shade300,
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 16),
          ],

          // Active Dynamic Interactive Primary Counter Large Card Frame
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  color: counterColor.withOpacity(0.06),
                  blurRadius: 16,
                  offset: const Offset(0, 8),
                )
              ],
              border: Border.all(color: counterColor.withOpacity(0.1), width: 1),
            ),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(color: counterColor, shape: BoxShape.circle),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      activeCounter.name.toUpperCase(),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.2,
                        color: Colors.grey.shade500,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                // Main Numerical Central Display area
                GestureDetector(
                  onTap: () {
                    HapticFeedback.lightImpact();
                    ref.read(projectsProvider.notifier).incrementCounterRow(project.id, activeCounter.id);
                  },
                  behavior: HitTestBehavior.opaque,
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 36),
                    alignment: Alignment.center,
                    child: Text(
                      "${activeCounter.currentRow}",
                      style: TextStyle(
                        fontSize: 96,
                        fontWeight: FontWeight.w900,
                        color: counterColor,
                        letterSpacing: -2,
                        height: 1,
                      ),
                    ),
                  ),
                ),
                // Max Limit threshold info label notice
                if (activeCounter.autoResetThreshold != null && activeCounter.autoResetThreshold! > 0)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(
                      "Resets automatically at row ${activeCounter.autoResetThreshold}",
                      style: TextStyle(color: Colors.grey.shade500, fontSize: 12, fontStyle: FontStyle.italic),
                    ),
                  ),
                const SizedBox(height: 12),
                // Big Control Button Deck Actions Bar
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          side: BorderSide(color: Colors.grey.shade300),
                        ),
                        onPressed: () {
                          HapticFeedback.mediumImpact();
                          ref.read(projectsProvider.notifier).decrementCounterRow(project.id, activeCounter.id);
                        },
                        icon: const Icon(Icons.remove, size: 18, color: Colors.black87),
                        label: const Text("Minus", style: TextStyle(color: Colors.black87, fontWeight: FontWeight.bold)),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: counterColor,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          elevation: 1,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        onPressed: () {
                          HapticFeedback.mediumImpact();
                          ref.read(projectsProvider.notifier).incrementCounterRow(project.id, activeCounter.id);
                        },
                        icon: const Icon(Icons.add, size: 18),
                        label: const Text("Count Row", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Active Reminders Alerts Popup Banner Container Block if valid
          if (currentReminder != null) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.amber.shade50,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.amber.shade300, width: 1),
              ),
              child: Row(
                children: [
                  Icon(Icons.notification_important, color: Colors.amber.shade900, size: 24),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          "Instruction Alert (Row ${activeCounter.currentRow})",
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.amber.shade900),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          currentReminder,
                          style: TextStyle(fontSize: 14, color: Colors.amber.shade900, fontWeight: FontWeight.w500),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],

          const SizedBox(height: 16),

          // Secondary Fast Controls Panel Footer strip
          Row(
            children: [
              Expanded(
                child: Card(
                  margin: EdgeInsets.zero,
                  child: InkWell(
                    onTap: () => _showResetConfirmation(context, ref, activeCounter),
                    borderRadius: BorderRadius.circular(16),
                    child: const Padding(
                      padding: EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.refresh, size: 16, color: Colors.redCurve),
                          SizedBox(width: 6),
                          Text("Reset", style: TextStyle(color: Colors.redCurve, fontWeight: FontWeight.bold, fontSize: 13)),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Card(
                  margin: EdgeInsets.zero,
                  child: InkWell(
                    onTap: () => _showQuickConfigureRemindersModal(context, ref, activeCounter),
                    borderRadius: BorderRadius.circular(16),
                    child: const Padding(
                      padding: EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.alarm, size: 16, color: Colors.blueAccent),
                          SizedBox(width: 6),
                          Text("Reminders", style: TextStyle(color: Colors.blueAccent, fontWeight: FontWeight.bold, fontSize: 13)),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 20),

          // History Log Section List Header
          const Padding(
            padding: EdgeInsets.only(left: 4, bottom: 8),
            child: Text("Recent Count Log", style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
          ),

          if (activeCounter.history.isEmpty)
            Card(
              margin: EdgeInsets.zero,
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Center(
                  child: Text(
                    "Log updates as you count your project.",
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey.shade500, fontSize: 13),
                  ),
                ),
              ),
            )
          else
            Card(
              margin: EdgeInsets.zero,
              child: ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: activeCounter.history.length > 5 ? 5 : activeCounter.history.length,
                separatorBuilder: (ctx, idx) => Divider(color: Colors.grey.shade100, height: 1),
                itemBuilder: (ctx, idx) {
                  // Standard reverse lookups index for history list items log entries
                  final revIdx = activeCounter.history.length - 1 - idx;
                  final rawEntry = activeCounter.history[revIdx];
                  final parts = rawEntry.split('|');
                  final val = parts[0];
                  final timeStr = parts.length > 1 ? parts[1] : '';

                  String formattedTime = '';
                  if (timeStr.isNotEmpty) {
                    try {
                      final dt = DateTime.parse(timeStr);
                      formattedTime = "${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}";
                    } catch (_) {}
                  }

                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.between,
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 6,
                              height: 6,
                              decoration: BoxDecoration(color: counterColor, shape: BoxShape.circle),
                            ),
                            const SizedBox(width: 10),
                            Text("Updated value state to row", style: TextStyle(color: Colors.grey.shade700, fontSize: 13)),
                            const SizedBox(width: 4),
                            Text(val, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                          ],
                        ),
                        Text(formattedTime, style: TextStyle(color: Colors.grey.shade400, fontSize: 12)),
                      ],
                    ),
                  );
                },
              ),
            ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  void _showResetConfirmation(BuildContext context, WidgetRef ref, KnitCounter target) {
    showAdaptiveDialog(
      context: context,
      builder: (ctx) => AlertDialog.adaptive(
        title: const Text("Reset Counter?"),
        content: const Text("Are you sure you want to clear this counter back down to row 0? This logs a reset state update."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Cancel")),
          TextButton(
            onPressed: () {
              ref.read(projectsProvider.notifier).resetCounterRow(project.id, target.id);
              Navigator.pop(ctx);
            },
            child: const Text("Reset", style: TextStyle(color: Colors.redCurve)),
          ),
        ],
      ),
    );
  }

  void _showQuickConfigureRemindersModal(BuildContext context, WidgetRef ref, KnitCounter counter) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => CounterRemindersEditorWidget(project: project, counter: counter),
    );
  }
}

// --- TAB VIEW: ALL COUNTERS MANAGEMENT LIST VIEW ---

class CountersManagerListView extends ConsumerWidget {
  final Project project;
  const CountersManagerListView({super.key, required this.project});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeColor = Theme.of(context).primaryColor;

    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          _showRenameDialog(context, "New Counter Name", "", (val) {
            ref.read(projectsProvider.notifier).addCounter(project.id, val);
          });
        },
        icon: const Icon(Icons.add),
        label: const Text("Add Counter"),
      ),
      body: ListView.builder(
        padding: const EdgeInsets.only(left: 20, right: 20, top: 4, bottom: 84),
        physics: const BouncingScrollPhysics(),
        itemCount: project.counters.length,
        itemBuilder: (ctx, idx) {
          final c = project.counters[idx];
          final cColor = c.colorValue != null ? Color(c.colorValue!) : themeColor;
          final isActive = c.id == project.activeCounterId;

          return Card(
            margin: const EdgeInsets.only(bottom: 12),
            child: InkWell(
              onTap: () {
                ref.read(projectsProvider.notifier).selectActiveCounter(project.id, c.id);
              },
              borderRadius: BorderRadius.circular(16),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 14,
                          height: 14,
                          decoration: BoxDecoration(color: cColor, shape: BoxShape.circle),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                c.name,
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: isActive ? FontWeight.bold : FontWeight.w600,
                                ),
                              ),
                              if (c.linkedCounterId != null && c.linkMode != 'none')
                                Padding(
                                  padding: const EdgeInsets.only(top: 2),
                                  child: Text(
                                    "Linked automation active",
                                    style: TextStyle(color: themeColor, fontSize: 12, fontWeight: FontWeight.w500),
                                  ),
                                ),
                            ],
                          ),
                        ),
                        // Current numerical summary bubble indicator badge
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                          decoration: BoxDecoration(
                            color: cColor.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            "Row ${c.currentRow}",
                            style: TextStyle(color: cColor, fontWeight: FontWeight.bold, fontSize: 13),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Divider(color: Colors.grey.shade100, height: 1),
                    const SizedBox(height: 8),
                    // Action settings strip options row layout button strip links
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        if (!isActive)
                          TextButton.icon(
                            onPressed: () {
                              ref.read(projectsProvider.notifier).selectActiveCounter(project.id, c.id);
                            },
                            icon: const Icon(Icons.check, size: 16),
                            label: const Text("Select"),
                            style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                          ),
                        TextButton.icon(
                          onPressed: () => _showCounterDeepSettings(context, ref, c),
                          icon: const Icon(Icons.tune, size: 16),
                          label: const Text("Configure"),
                          style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                        ),
                        TextButton.icon(
                          onPressed: () => _showDeleteCounterConfirmation(context, ref, c),
                          icon: const Icon(Icons.delete_outline, size: 16, color: Colors.redCurve),
                          label: const Text("Delete", style: TextStyle(color: Colors.redCurve)),
                          style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  void _showCounterDeepSettings(BuildContext context, WidgetRef ref, KnitCounter counter) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => CounterConfiguratorDetailsModalWidget(project: project, counter: counter),
    );
  }

  void _showDeleteCounterConfirmation(BuildContext context, WidgetRef ref, KnitCounter counter) {
    showAdaptiveDialog(
      context: context,
      builder: (ctx) => AlertDialog.adaptive(
        title: const Text("Delete Counter?"),
        content: Text("Are you sure you want to completely delete '${counter.name}'? This cannot be undone."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Cancel")),
          TextButton(
            onPressed: () {
              ref.read(projectsProvider.notifier).deleteCounter(project.id, counter.id);
              Navigator.pop(ctx);
            },
            child: const Text("Delete", style: TextStyle(color: Colors.redCurve)),
          ),
        ],
      ),
    );
  }
}

// --- TAB VIEW: NOTES SYSTEM WRITER EDITOR VIEW ---

class ProjectNotesTextEditView extends ConsumerStatefulWidget {
  final Project project;
  const ProjectNotesTextEditView({super.key, required this.project});

  @override
  ConsumerState<ProjectNotesTextEditView> createState() => _ProjectNotesTextEditViewState();
}

class _ProjectNotesTextEditViewState extends ConsumerState<ProjectNotesTextEditView> {
  late TextEditingController _notesController;

  @override
  void initState() {
    super.initState();
    _notesController = TextEditingController(text: widget.project.notes);
  }

  @override
  void didUpdateWidget(covariant ProjectNotesTextEditView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.project.id != widget.project.id) {
      _notesController.text = widget.project.notes;
    }
  }

  @override
  void dispose() {
    _notesController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 20, right: 20, bottom: 20),
      child: Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: TextField(
            controller: _notesController,
            maxLines: null,
            keyboardType: TextInputType.multiline,
            textCapitalization: TextCapitalization.sentences,
            style: const TextStyle(fontSize: 15, height: 1.4, color: Colors.black87),
            decoration: const InputDecoration(
              hintText: "Write down pattern adjustments, yarn details, needle sizes, gauge notes or custom instructions here...",
              border: InputBorder.none,
            ),
            onChanged: (val) {
              ref.read(projectsProvider.notifier).updateNotes(widget.project.id, val);
            },
          ),
        ),
      ),
    );
  }
}

// --- PROJECT SWITCHER DIALOG COMPONENT ---

class ProjectSelectorModalWidget extends ConsumerWidget {
  const ProjectSelectorModalWidget({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final projects = ref.watch(projectsProvider);
    final activeId = ref.watch(activeProjectIdProvider);
    final themeColor = Theme.of(context).primaryColor;

    return Padding(
      padding: EdgeInsets.only(
        top: 24,
        left: 24,
        right: 24,
        bottom: MediaQuery.of(context).viewInsets.bottom + 32,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.between,
            children: [
              const Text("My Projects", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              IconButton(
                icon: const Icon(Icons.add_circle_outline, color: Colors.blueAccent),
                onPressed: () {
                  Navigator.pop(context);
                  _showRenameDialog(context, "Create Project", "", (val) {
                    ref.read(projectsProvider.notifier).addProject(val);
                  });
                },
              )
            ],
          ),
          const SizedBox(height: 16),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 300),
            child: ListView.builder(
              shrinkWrap: true,
              physics: const BouncingScrollPhysics(),
              itemCount: projects.length,
              itemBuilder: (ctx, idx) {
                final p = projects[idx];
                final isCurrent = p.id == activeId;
                return Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  decoration: BoxDecoration(
                    color: isCurrent ? themeColor.withOpacity(0.08) : Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isCurrent ? themeColor.withOpacity(0.3) : Colors.transparent,
                    ),
                  ),
                  child: ListTile(
                    title: Text(p.name, style: TextStyle(fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal)),
                    subtitle: Text("${p.counters.length} counter${p.counters.length == 1 ? '' : 's'}"),
                    trailing: isCurrent ? Icon(Icons.check_circle, color: themeColor) : null,
                    onTap: () {
                      ref.read(activeProjectIdProvider.notifier).state = p.id;
                      Navigator.pop(context);
                    },
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// --- REMINDERS EDITOR INTERFACE DIALOG ---

class CounterRemindersEditorWidget extends ConsumerStatefulWidget {
  final Project project;
  final KnitCounter counter;
  const CounterRemindersEditorWidget({super.key, required this.project, required this.counter});

  @override
  ConsumerState<CounterRemindersEditorWidget> createState() => _CounterRemindersEditorWidgetState();
}

class _CounterRemindersEditorWidgetState extends ConsumerState<CounterRemindersEditorWidget> {
  final _rowController = TextEditingController();
  final _textController = TextEditingController();

  @override
  void dispose() {
    _rowController.dispose();
    _textController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final themeColor = Theme.of(context).primaryColor;
    final counterColor = widget.counter.colorValue != null ? Color(widget.counter.colorValue!) : themeColor;

    return Padding(
      padding: EdgeInsets.only(
        top: 24,
        left: 24,
        right: 24,
        bottom: MediaQuery.of(context).viewInsets.bottom + 32,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            "${widget.counter.name}: Row Alerts",
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          const Text(
            "Add alert prompts that display automatically whenever the counter hits specific row target levels.",
            style: TextStyle(fontSize: 12, color: Colors.grey),
          ),
          const SizedBox(height: 16),
          // Form inputs area stack
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 76,
                child: TextField(
                  controller: _rowController,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: const InputDecoration(
                    labelText: "Row",
                    hintText: "10",
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _textController,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(
                    labelText: "Instruction Reminder Note",
                    hintText: "Cable turn / Decrease 1 st...",
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filled(
                style: IconButton.styleFrom(backgroundColor: counterColor),
                onPressed: () {
                  final rowVal = int.tryParse(_rowController.text);
                  final textVal = _textController.text.trim();
                  if (rowVal != null && textVal.isNotEmpty) {
                    Map<int, String> nextReminders = Map.from(widget.counter.reminders);
                    nextReminders[rowVal] = textVal;
                    final updated = widget.counter.copyWith(reminders: nextReminders);
                    ref.read(projectsProvider.notifier).updateCounter(widget.project.id, widget.counter.id, updated);
                    _rowController.clear();
                    _textController.clear();
                    setState(() {});
                  }
                },
                icon: const Icon(Icons.add),
              )
            ],
          ),
          const SizedBox(height: 20),
          const Text("Existing Active Reminders", style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          if (widget.counter.reminders.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Center(
                  child: Text("No custom alerts configured yet.",
                      style: TextStyle(color: Colors.grey.shade400, fontSize: 13))),
            )
          else
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 200),
              child: ListView(
                shrinkWrap: true,
                physics: const BouncingScrollPhysics(),
                children: widget.counter.reminders.entries.map((e) {
                  return Card(
                    color: Colors.grey.shade50,
                    elevation: 0,
                    margin: const EdgeInsets.only(bottom: 6),
                    child: ListTile(
                      visualDensity: VisualDensity.compact,
                      leading: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(color: counterColor.withOpacity(0.1), borderRadius: BorderRadius.circular(6)),
                        child: Text("R${e.key}", style: TextStyle(color: counterColor, fontWeight: FontWeight.bold, fontSize: 12)),
                      ),
                      title: Text(e.value, style: const TextStyle(fontSize: 14)),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete_outline, size: 18, color: Colors.redCurve),
                        onPressed: () {
                          Map<int, String> nextReminders = Map.from(widget.counter.reminders);
                          nextReminders.remove(e.key);
                          final updated = widget.counter.copyWith(reminders: nextReminders);
                          ref.read(projectsProvider.notifier).updateCounter(widget.project.id, widget.counter.id, updated);
                          setState(() {});
                        },
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
        ],
      ),
    );
  }
}

// --- DEEP CONFIGURATOR SETTINGS SCREEN SHEET MODAL ---

class CounterConfiguratorDetailsModalWidget extends ConsumerStatefulWidget {
  final Project project;
  final KnitCounter counter;
  const CounterConfiguratorDetailsModalWidget({super.key, required this.project, required this.counter});

  @override
  ConsumerState<CounterConfiguratorDetailsModalWidget> createState() => _CounterConfiguratorDetailsModalWidgetState();
}

class _CounterConfiguratorDetailsModalWidgetState extends ConsumerState<CounterConfiguratorDetailsModalWidget> {
  late TextEditingController _nameController;
  late TextEditingController _thresholdController;
  String? _selectedLinkedId;
  late String _linkMode;
  int? _currentColorValue;

  final List<Color> _swatchColors = [
    Colors.teal,
    Colors.blue,
    Colors.indigo,
    Colors.purple,
    Colors.pink,
    Colors.red,
    Colors.orange,
    Colors.amber,
    Colors.green,
    Colors.blueGrey,
  ];

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.counter.name);
    _thresholdController = TextEditingController(
      text: widget.counter.autoResetThreshold != null && widget.counter.autoResetThreshold! > 0
          ? widget.counter.autoResetThreshold.toString()
          : '',
    );
    _selectedLinkedId = widget.counter.linkedCounterId;
    _linkMode = widget.counter.linkMode;
    _currentColorValue = widget.counter.colorValue;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _thresholdController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Collect potential valid link targets (every counter inside project EXCEPT this one)
    final possibleTargets = widget.project.counters.where((c) => c.id != widget.counter.id).toList();
    final themeColor = Theme.of(context).primaryColor;

    return Padding(
      padding: EdgeInsets.only(
        top: 24,
        left: 24,
        right: 24,
        bottom: MediaQuery.of(context).viewInsets.bottom + 32,
      ),
      child: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text("Configure Counter Settings", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            TextField(
              controller: _nameController,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: "Counter Display Name", border: OutlineInputBorder()),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _thresholdController,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(
                labelText: "Auto-Reset Target Limit (Optional)",
                hintText: "Resets to 0 when counting up to this row target",
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 20),
            const Text("Color Theme Label", style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            SizedBox(
              height: 36,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                physics: const BouncingScrollPhysics(),
                itemCount: _swatchColors.length,
                itemBuilder: (ctx, idx) {
                  final color = _swatchColors[idx];
                  final isSel = _currentColorValue == color.value || (_currentColorValue == null && color == themeColor);
                  return GestureDetector(
                    onTap: () => setState(() => _currentColorValue = color.value),
                    child: Container(
                      width: 36,
                      height: 36,
                      margin: const EdgeInsets.only(right: 10),
                      decoration: BoxDecoration(
                        color: color,
                        shape: BoxShape.circle,
                        border: isSel ? Border.all(color: Colors.black87, width: 3) : null,
                        boxShadow: [if (isSel) const BoxShadow(color: Colors.black26, blurRadius: 4)],
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 24),
            const Text("Chain-Link Automation (Optional)", style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            const Text(
              "Allows this counter to drive or advance a secondary counter automatically whenever it updates.",
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 12),
            if (possibleTargets.isEmpty)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(8)),
                child: const Text("Create additional project counters to enable chain linkages.",
                    style: TextStyle(fontSize: 13, color: Colors.grey, fontStyle: FontStyle.italic)),
              )
            else ...[
              DropdownButtonFormField<String?>(
                value: _selectedLinkedId,
                decoration: const InputDecoration(labelText: "Target Counter to Drive", border: OutlineInputBorder()),
                items: [
                  const DropdownMenuItem<String?>(value: null, child: Text("None (Disabled)")),
                  ...possibleTargets.map((c) => DropdownMenuItem<String?>(value: c.id, child: Text(c.name))),
                ],
                onChanged: (val) => setState(() => _selectedLinkedId = val),
              ),
              if (_selectedLinkedId != null) ...[
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: _linkMode,
                  decoration: const InputDecoration(labelText: "Automation Trigger Rule", border: OutlineInputBorder()),
                  items: const [
                    DropdownMenuItem(value: 'none', child: Text("Do not trigger link")),
                    DropdownMenuItem(value: 'match_always', child: Text("Mirrored match (Plus / Minus updates)")),
                    DropdownMenuItem(value: 'match_up_only', child: Text("Advance target whenever this gains (+1)")),
                    DropdownMenuItem(value: 'match_down_only', child: Text("Regress target whenever this drops (-1)")),
                    DropdownMenuItem(value: 'on_reset', child: Text("Advance target by +1 only when this loops/resets")),
                  ],
                  onChanged: (val) => setState(() => _linkMode = val ?? 'none'),
                ),
              ],
            ],
            const SizedBox(height: 28),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: _currentColorValue != null ? Color(_currentColorValue!) : themeColor,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: () {
                final title = _nameController.text.trim();
                if (title.isNotEmpty) {
                  final thresholdVal = int.tryParse(_thresholdController.text);
                  final updated = widget.counter.copyWith(
                    name: title,
                    autoResetThreshold: thresholdVal,
                    colorValue: _currentColorValue,
                    linkedCounterId: _selectedLinkedId,
                    linkMode: _selectedLinkedId == null ? 'none' : _linkMode,
                  );
                  ref.read(projectsProvider.notifier).updateCounter(widget.project.id, widget.counter.id, updated);
                  Navigator.pop(context);
                }
              },
              child: const Text("Save Configuration Modifications", style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }
}

// --- SYSTEM GLOBAL SETTINGS SHEET MODAL PANEL ---

class GlobalSettingsModalWidget extends ConsumerWidget {
  const GlobalSettingsModalWidget({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final keepScreenOn = ref.watch(keepScreenOnProvider);

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text("Application Options", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            title: const Text("Prevent Screen Sleeping", style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
            subtitle: const Text("Keeps screen active while reading complex patterns"),
            value: keepScreenOn,
            onChanged: (val) {
              ref.read(keepScreenOnProvider.notifier).state = val;
              WakelockPlus.toggle(enable: val);
            },
          ),
          const SizedBox(height: 12),
          Divider(color: Colors.grey.shade200, height: 1),
          const SizedBox(height: 16),
          Center(
            child: Text(
              "Knitly • Native Multi-Counter Companion\nBuild Environment Active",
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: Colors.grey.shade400, height: 1.4),
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

// --- GLOBAL UTILITY SHREDS & DIALOGS MODAL HANDLERS ---

void _showRenameDialog(BuildContext context, String title, String hintText, Function(String) onSave) {
  final controller = TextEditingController(text: hintText);
  showAdaptiveDialog(
    context: context,
    builder: (ctx) => AlertDialog.adaptive(
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
      content: Material(
        color: Colors.transparent,
        child: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.sentences,
          decoration: InputDecoration(hintText: hintText.isEmpty ? "Enter text label..." : hintText, border: const OutlineInputBorder()),
        ),
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

// Global Custom Colors shorthand mapping tokens
class Colors {
  static const Color transparent = Colors.transparent;
  static const Color white = Colors.white;
  static const Color black = Colors.black;
  static const Color teal = Colors.teal;
  static const Color blue = Colors.blue;
  static const Color indigo = Colors.indigo;
  static const Color purple = Colors.purple;
  static const Color pink = Colors.pink;
  static const Color red = Colors.red;
  static const Color orange = Colors.orange;
  static const Color amber = Colors.amber;
  static const Color green = Colors.green;
  static const Color blueGrey = Colors.blueGrey;
  static const Color black87 = Colors.black87;
  static const Color black54 = Colors.black54;
  static const MaterialColor grey = Colors.grey;
  static const Color blueAccent = Colors.blueAccent;
  static const Color redCurve = Color(0xFFD32F2F);
}
