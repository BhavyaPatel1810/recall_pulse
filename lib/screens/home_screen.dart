import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:uuid/uuid.dart';
import '../models/deck.dart';
import '../services/auth_service.dart';
import '../services/database_helper.dart';
import '../services/sync_service.dart';
import '../theme/pulse_theme.dart';
import 'ai_card_creator_screen.dart';
import 'auth_screen.dart';
import 'deck_detail_screen.dart';
import 'notification_settings_screen.dart';
import 'review_screen.dart';
import 'settings_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with SingleTickerProviderStateMixin {
  List<Deck> _decks = [];
  Map<String, DeckStats> _stats = {};
  int _totalDue = 0;
  int _unsyncedCount = 0;
  SyncStatusState _syncState = SyncStatusState.offlineOrGuest;
  bool _isLoading = true;
  String _searchQuery = '';

  final TextEditingController _searchController = TextEditingController();
  late AnimationController _syncSpinController;

  @override
  void initState() {
    super.initState();
    _syncSpinController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );
    _initializeAndSyncOnStartup();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _syncSpinController.dispose();
    super.dispose();
  }

  Future<void> _initializeAndSyncOnStartup() async {
    await _loadDashboardData();
    await AuthService.instance.initialize();
    if (!mounted) return;

    if (AuthService.instance.isLoggedIn) {
      await _triggerCloudSync(silent: true);
    } else {
      await _refreshSyncBadge();
    }
  }

  Future<void> _refreshSyncBadge() async {
    final state = await SyncService.instance.evaluateCurrentSyncState();
    final unsynced = await DatabaseHelper.instance.getUnsyncedCount();
    if (!mounted) return;
    setState(() {
      _syncState = state;
      _unsyncedCount = unsynced;
    });
  }

  Future<void> _triggerCloudSync({bool silent = false}) async {
    if (!AuthService.instance.isLoggedIn) {
      await Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const AuthScreen()),
      );
      if (!mounted) return;
      await _loadDashboardData();
      return;
    }

    _syncSpinController.repeat();
    setState(() {
      _syncState = SyncStatusState.syncing;
    });

    final report = await SyncService.instance.syncAllData();
    if (!mounted) return;

    _syncSpinController.stop();
    _syncSpinController.reset();

    await _loadDashboardData();
    if (!mounted) return;

    if (!silent) {
      HapticFeedback.lightImpact();
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: report.success ? PulseTheme.neonEmerald : PulseTheme.neonCoral,
          content: Text(
            report.message,
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          ),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  Future<void> _loadDashboardData() async {
    final decks = await DatabaseHelper.instance.getAllDecks();
    final stats = await DatabaseHelper.instance.getAllDeckStats();
    final totalDue = await DatabaseHelper.instance.getTotalDueCount();
    final unsynced = await DatabaseHelper.instance.getUnsyncedCount();
    final syncState = await SyncService.instance.evaluateCurrentSyncState();

    if (!mounted) return;
    setState(() {
      _decks = decks;
      _stats = stats;
      _totalDue = totalDue;
      _unsyncedCount = unsynced;
      _syncState = syncState;
      _isLoading = false;
    });
  }

  List<Deck> get _filteredDecks {
    if (_searchQuery.trim().isEmpty) return _decks;
    final query = _searchQuery.toLowerCase();
    return _decks.where((deck) {
      return deck.title.toLowerCase().contains(query) ||
          deck.category.toLowerCase().contains(query) ||
          deck.description.toLowerCase().contains(query);
    }).toList();
  }

  int get _totalMasteredAcrossDecks {
    int total = 0;
    for (final stat in _stats.values) {
      total += stat.masteredCards;
    }
    return total;
  }

  int get _totalCardsAcrossDecks {
    int total = 0;
    for (final stat in _stats.values) {
      total += stat.totalCards;
    }
    return total;
  }

  void _showCreateDeckDialog() {
    final titleController = TextEditingController();
    final descController = TextEditingController();
    final catController = TextEditingController(text: 'General');

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogCtx) {
        return AlertDialog(
          backgroundColor: PulseTheme.surfaceElevated,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: const BorderSide(color: PulseTheme.borderSubtle),
          ),
          title: const Text(
            'New Pulse Deck',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: titleController,
                  autofocus: true,
                  decoration: const InputDecoration(
                    labelText: 'Deck Title',
                    hintText: 'e.g. Distributed Computing',
                  ),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: catController,
                  decoration: const InputDecoration(
                    labelText: 'Category',
                    hintText: 'e.g. Computer Science',
                  ),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: descController,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'Description',
                    hintText: 'Focus areas, exam targets, or scope...',
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogCtx).pop(),
              child: const Text('Cancel', style: TextStyle(color: PulseTheme.textSecondary)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: PulseTheme.neonIndigo,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: () async {
                final title = titleController.text.trim();
                final desc = descController.text.trim();
                final cat = catController.text.trim().isEmpty ? 'General' : catController.text.trim();

                if (title.isEmpty) return;

                Navigator.of(dialogCtx).pop();
                if (!mounted) return;

                final nowUtc = DateTime.now().toUtc();
                final newDeck = Deck(
                  id: const Uuid().v4(),
                  title: title,
                  description: desc,
                  category: cat,
                  createdAt: nowUtc,
                  updatedAt: nowUtc,
                  isSynced: false,
                );

                await DatabaseHelper.instance.insertDeck(newDeck);
                if (!mounted) return;
                await _loadDashboardData();
              },
              child: const Text('Create Deck'),
            ),
          ],
        );
      },
    );
  }

  void _showEditDeckDialog(Deck deck) {
    final titleController = TextEditingController(text: deck.title);
    final descController = TextEditingController(text: deck.description);
    final catController = TextEditingController(text: deck.category);

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogCtx) {
        return AlertDialog(
          backgroundColor: PulseTheme.surfaceElevated,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: const BorderSide(color: PulseTheme.borderSubtle),
          ),
          title: const Text('Edit Deck Details'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: titleController,
                  decoration: const InputDecoration(labelText: 'Deck Title'),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: catController,
                  decoration: const InputDecoration(labelText: 'Category'),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: descController,
                  maxLines: 3,
                  decoration: const InputDecoration(labelText: 'Description'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogCtx).pop(),
              child: const Text('Cancel', style: TextStyle(color: PulseTheme.textSecondary)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: PulseTheme.neonIndigo,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: () async {
                final title = titleController.text.trim();
                final desc = descController.text.trim();
                final cat = catController.text.trim();

                if (title.isEmpty) return;

                Navigator.of(dialogCtx).pop();
                if (!mounted) return;

                final updated = deck.copyWith(
                  title: title,
                  description: desc,
                  category: cat.isEmpty ? 'General' : cat,
                );

                await DatabaseHelper.instance.updateDeck(updated);
                if (!mounted) return;
                await _loadDashboardData();
              },
              child: const Text('Save Changes'),
            ),
          ],
        );
      },
    );
  }

  void _confirmDeleteDeck(Deck deck) {
    showDialog(
      context: context,
      builder: (dialogCtx) {
        return AlertDialog(
          backgroundColor: PulseTheme.surfaceElevated,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: const BorderSide(color: PulseTheme.borderSubtle),
          ),
          title: const Text('Delete Deck?'),
          content: Text(
            'Are you sure you want to delete "${deck.title}"? This soft-delete will also propagate to your cloud sync.',
            style: const TextStyle(color: PulseTheme.textSecondary),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogCtx).pop(),
              child: const Text('Keep', style: TextStyle(color: PulseTheme.textSecondary)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: PulseTheme.neonCoral,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: () async {
                Navigator.of(dialogCtx).pop();
                if (!mounted) return;

                await DatabaseHelper.instance.deleteDeck(deck.id);
                if (!mounted) return;
                await _loadDashboardData();
              },
              child: const Text('Delete Deck'),
            ),
          ],
        );
      },
    );
  }

  Widget _buildAnimatedSyncStatusAction() {
    final isLoggedIn = AuthService.instance.isLoggedIn;
    Color badgeColor;
    String statusLabel;
    IconData iconData;

    if (_syncState == SyncStatusState.syncing) {
      badgeColor = PulseTheme.neonIndigo;
      statusLabel = 'Syncing';
      iconData = Icons.sync_rounded;
    } else if (!isLoggedIn) {
      badgeColor = _unsyncedCount > 0 ? PulseTheme.neonAmber : PulseTheme.textSecondary;
      statusLabel = _unsyncedCount > 0 ? 'Local ($_unsyncedCount)' : 'Cloud Login';
      iconData = Icons.cloud_upload_outlined;
    } else if (_unsyncedCount > 0 || _syncState == SyncStatusState.unsyncedChanges) {
      badgeColor = PulseTheme.neonAmber;
      statusLabel = 'Unsynced ($_unsyncedCount)';
      iconData = Icons.cloud_sync_outlined;
    } else if (_syncState == SyncStatusState.error) {
      badgeColor = PulseTheme.neonCoral;
      statusLabel = 'Sync Retry';
      iconData = Icons.cloud_off_rounded;
    } else {
      badgeColor = PulseTheme.neonEmerald;
      statusLabel = 'Synced';
      iconData = Icons.cloud_done_rounded;
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () => _triggerCloudSync(silent: false),
        onLongPress: () async {
          await Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const AuthScreen()),
          );
          if (!mounted) return;
          _loadDashboardData();
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: badgeColor.withOpacity(0.14),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: badgeColor.withOpacity(0.45), width: 1.2),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              RotationTransition(
                turns: _syncSpinController,
                child: Icon(iconData, size: 15, color: badgeColor),
              ),
              const SizedBox(width: 6),
              Text(
                statusLabel,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: badgeColor,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: PulseTheme.bgPrimary,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [PulseTheme.neonIndigo, Color(0xFF818CF8)],
                ),
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: PulseTheme.neonIndigo.withOpacity(0.4),
                    blurRadius: 10,
                  ),
                ],
              ),
              child: const Icon(Icons.bolt, color: Colors.white, size: 20),
            ),
            const SizedBox(width: 10),
            const Text(
              'RecallPulse',
              style: TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 20,
                letterSpacing: -0.5,
              ),
            ),
          ],
        ),
        actions: [
          _buildAnimatedSyncStatusAction(),
          IconButton(
            tooltip: 'AI Flashcard Studio',
            icon: const Icon(Icons.auto_awesome, color: PulseTheme.neonIndigo, size: 20),
            onPressed: () async {
              await Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const AiCardCreatorScreen()),
              );
              if (!mounted) return;
              _loadDashboardData();
            },
          ),
          IconButton(
            tooltip: 'Smart Notifications',
            icon: const Icon(Icons.notifications_active_outlined, color: PulseTheme.neonAmber, size: 20),
            onPressed: () async {
              await Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const NotificationSettingsScreen()),
              );
              if (!mounted) return;
              _loadDashboardData();
            },
          ),
          IconButton(
            tooltip: 'AI & Study Settings',
            icon: const Icon(Icons.settings_outlined, color: PulseTheme.textSecondary, size: 20),
            onPressed: () async {
              await Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const SettingsScreen()),
              );
              if (!mounted) return;
              _loadDashboardData();
            },
          ),
          const SizedBox(width: 4),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: PulseTheme.neonIndigo,
        icon: const Icon(Icons.add, color: Colors.white),
        label: const Text(
          'New Deck',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        onPressed: _showCreateDeckDialog,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: PulseTheme.neonIndigo))
          : RefreshIndicator(
              onRefresh: () => _triggerCloudSync(silent: false),
              color: PulseTheme.neonIndigo,
              backgroundColor: PulseTheme.surfaceElevated,
              child: CustomScrollView(
                physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
                slivers: [
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildStreakAndStatsHeader(),
                          const SizedBox(height: 18),
                          _buildSearchBar(),
                          const SizedBox(height: 24),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'Decks (${_filteredDecks.length})',
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: -0.3,
                                ),
                              ),
                              GestureDetector(
                                onTap: () async {
                                  await Navigator.of(context).push(
                                    MaterialPageRoute(builder: (_) => const AuthScreen()),
                                  );
                                  if (!mounted) return;
                                  _loadDashboardData();
                                },
                                child: Text(
                                  AuthService.instance.isLoggedIn
                                      ? 'Cloud Account Linked'
                                      : 'Offline Guest Mode • Tap to Link',
                                  style: TextStyle(
                                    color: AuthService.instance.isLoggedIn
                                        ? PulseTheme.neonEmerald
                                        : PulseTheme.neonIndigo,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                        ],
                      ),
                    ),
                  ),
                  _filteredDecks.isEmpty
                      ? SliverToBoxAdapter(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 40),
                            child: Center(
                              child: Column(
                                children: [
                                  const Icon(Icons.inventory_2_outlined, size: 48, color: PulseTheme.textTertiary),
                                  const SizedBox(height: 12),
                                  Text(
                                    _searchQuery.isEmpty ? 'No decks yet. Tap + to begin.' : 'No decks match "$_searchQuery"',
                                    style: const TextStyle(color: PulseTheme.textSecondary),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        )
                      : SliverPadding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          sliver: SliverList(
                            delegate: SliverChildBuilderDelegate(
                              (context, index) {
                                final deck = _filteredDecks[index];
                                final stat = _stats[deck.id] ??
                                    const DeckStats(totalCards: 0, dueCards: 0, masteredCards: 0);
                                return _buildDeckCard(deck, stat);
                              },
                              childCount: _filteredDecks.length,
                            ),
                          ),
                        ),
                  const SliverToBoxAdapter(
                    child: SizedBox(height: 80),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildStreakAndStatsHeader() {
    final learningCount = (_totalCardsAcrossDecks - _totalDue - _totalMasteredAcrossDecks).clamp(0, 99999);

    return PulseGlassPanel(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: PulseTheme.neonAmber.withOpacity(0.15),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.local_fire_department, color: PulseTheme.neonAmber, size: 24),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '5 Day Study Streak',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _totalDue > 0
                          ? '$_totalDue flashcards scheduled for retention recall today.'
                          : 'You are completely caught up! Great job.',
                      style: const TextStyle(color: PulseTheme.textSecondary, fontSize: 13),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          SizedBox(
            height: 120,
            child: Row(
              children: [
                SizedBox(
                  width: 120,
                  height: 120,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      PieChart(
                        PieChartData(
                          sectionsSpace: 2,
                          centerSpaceRadius: 36,
                          startDegreeOffset: -90,
                          sections: [
                            PieChartSectionData(
                              value: _totalDue == 0 && _totalCardsAcrossDecks == 0 ? 1 : _totalDue.toDouble(),
                              color: _totalDue > 0 ? PulseTheme.neonCoral : PulseTheme.borderSubtle,
                              showTitle: false,
                              radius: 12,
                            ),
                            PieChartSectionData(
                              value: _totalMasteredAcrossDecks.toDouble(),
                              color: PulseTheme.neonEmerald,
                              showTitle: false,
                              radius: 12,
                            ),
                            PieChartSectionData(
                              value: learningCount.toDouble(),
                              color: PulseTheme.neonIndigo,
                              showTitle: false,
                              radius: 12,
                            ),
                          ],
                        ),
                      ),
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            '$_totalDue',
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                          const Text(
                            'Due',
                            style: TextStyle(fontSize: 10, color: PulseTheme.textTertiary),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 24),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildMetricRow('Due for Review', '$_totalDue', PulseTheme.neonCoral),
                      const SizedBox(height: 8),
                      _buildMetricRow('Learning / New', '$learningCount', PulseTheme.neonIndigo),
                      const SizedBox(height: 8),
                      _buildMetricRow('Mastered (>=21d)', '$_totalMasteredAcrossDecks', PulseTheme.neonEmerald),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMetricRow(String label, String value, Color color) {
    return Row(
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            label,
            style: const TextStyle(fontSize: 12, color: PulseTheme.textSecondary),
          ),
        ),
        Text(
          value,
          style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: color),
        ),
      ],
    );
  }

  Widget _buildSearchBar() {
    return TextField(
      controller: _searchController,
      onChanged: (val) {
        setState(() {
          _searchQuery = val;
        });
      },
      decoration: InputDecoration(
        prefixIcon: const Icon(Icons.search, color: PulseTheme.textTertiary, size: 20),
        suffixIcon: _searchQuery.isNotEmpty
            ? IconButton(
                icon: const Icon(Icons.clear, color: PulseTheme.textTertiary, size: 18),
                onPressed: () {
                  _searchController.clear();
                  setState(() {
                    _searchQuery = '';
                  });
                },
              )
            : null,
        hintText: 'Search decks by title or category...',
      ),
    );
  }

  Widget _buildDeckCard(Deck deck, DeckStats stat) {
    final hasDue = stat.dueCards > 0;

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: PulseTheme.surfaceCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: hasDue ? PulseTheme.neonIndigo.withOpacity(0.3) : PulseTheme.borderSubtle,
          width: 1.2,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () async {
            await Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => DeckDetailScreen(deck: deck),
              ),
            );
            if (!mounted) return;
            await _loadDashboardData();
          },
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: PulseTheme.neonIndigo.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        deck.category.toUpperCase(),
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.5,
                          color: PulseTheme.neonIndigo,
                        ),
                      ),
                    ),
                    PopupMenuButton<String>(
                      icon: const Icon(Icons.more_vert, color: PulseTheme.textSecondary, size: 20),
                      color: PulseTheme.surfaceElevated,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      onSelected: (val) {
                        if (val == 'edit') {
                          _showEditDeckDialog(deck);
                        } else if (val == 'delete') {
                          _confirmDeleteDeck(deck);
                        }
                      },
                      itemBuilder: (ctx) => [
                        const PopupMenuItem(
                          value: 'edit',
                          child: Row(
                            children: [
                              Icon(Icons.edit, size: 16, color: PulseTheme.textSecondary),
                              SizedBox(width: 8),
                              Text('Edit Details'),
                            ],
                          ),
                        ),
                        const PopupMenuItem(
                          value: 'delete',
                          child: Row(
                            children: [
                              Icon(Icons.delete_outline, size: 16, color: PulseTheme.neonCoral),
                              SizedBox(width: 8),
                              Text('Delete Deck', style: TextStyle(color: PulseTheme.neonCoral)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  deck.title,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    letterSpacing: -0.3,
                  ),
                ),
                if (deck.description.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    deck.description,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: PulseTheme.textSecondary, fontSize: 13),
                  ),
                ],
                const SizedBox(height: 16),
                Row(
                  children: [
                    PulseStatPill(
                      icon: Icons.layers_outlined,
                      label: 'Total',
                      value: '${stat.totalCards}',
                      color: PulseTheme.textSecondary,
                    ),
                    const SizedBox(width: 8),
                    PulseStatPill(
                      icon: Icons.alarm,
                      label: 'Due',
                      value: '${stat.dueCards}',
                      color: hasDue ? PulseTheme.neonCoral : PulseTheme.textTertiary,
                    ),
                    const SizedBox(width: 8),
                    PulseStatPill(
                      icon: Icons.verified_outlined,
                      label: 'Mastered',
                      value: '${stat.masteredCards}',
                      color: PulseTheme.neonEmerald,
                    ),
                    const Spacer(),
                    IconButton(
                      tooltip: hasDue ? 'Start Due Review' : 'Practice Deck',
                      style: IconButton.styleFrom(
                        backgroundColor: hasDue
                            ? PulseTheme.neonIndigo
                            : PulseTheme.surfaceElevated,
                        foregroundColor: Colors.white,
                      ),
                      icon: const Icon(Icons.play_arrow_rounded, size: 22),
                      onPressed: stat.totalCards == 0
                          ? null
                          : () async {
                              await Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => ReviewScreen(deck: deck),
                                ),
                              );
                              if (!mounted) return;
                              await _loadDashboardData();
                              if (AuthService.instance.isLoggedIn) {
                                await _triggerCloudSync(silent: true);
                              }
                            },
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}