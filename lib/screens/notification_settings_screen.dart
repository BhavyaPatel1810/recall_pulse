import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/deck.dart';
import '../models/flashcard.dart';
import '../services/database_helper.dart';
import '../services/notification_service.dart';
import '../theme/pulse_theme.dart';

class NotificationSettingsScreen extends StatefulWidget {
  const NotificationSettingsScreen({super.key});

  @override
  State<NotificationSettingsScreen> createState() => _NotificationSettingsScreenState();
}

class _NotificationSettingsScreenState extends State<NotificationSettingsScreen> {
  NotificationConfig _config = const NotificationConfig();
  List<Deck> _decks = [];
  int _starredCardCount = 0;
  int _totalDueCount = 0;
  bool _isLoading = true;
  bool _isSendingTest = false;

  @override
  void initState() {
    super.initState();
    _loadNotificationState();
  }

  Future<void> _loadNotificationState() async {
    await NotificationService.instance.initialize();
    final config = await NotificationService.instance.loadConfig();
    final decks = await DatabaseHelper.instance.getAllDecks();
    final starred = await DatabaseHelper.instance.getStarredCards();
    final totalDue = await DatabaseHelper.instance.getTotalDueCount();

    if (!mounted) return;
    setState(() {
      _config = config.copyWith(
        targetDeckId: config.targetDeckId ?? (decks.isNotEmpty ? decks.first.id : null),
      );
      _decks = decks;
      _starredCardCount = starred.length;
      _totalDueCount = totalDue;
      _isLoading = false;
    });
  }

  Future<void> _updateConfig(NotificationConfig updated, {bool showSnack = false}) async {
    setState(() {
      _config = updated;
    });

    if (updated.isEnabled) {
      await NotificationService.instance.requestPermissions();
    }

    await NotificationService.instance.saveConfig(updated);

    if (!mounted || !showSnack) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: PulseTheme.surfaceElevated,
        content: Text(
          updated.isEnabled
              ? 'Scheduled ${updated.dailyFrequency} daily active recall pulses.'
              : 'Daily flashcard notifications paused.',
          style: const TextStyle(color: Colors.white),
        ),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Future<void> _pickTime({required bool isStart}) async {
    final initial = isStart ? _config.startTime : _config.endTime;
    final picked = await showTimePicker(
      context: context,
      initialTime: initial,
      builder: (context, child) {
        return Theme(
          data: PulseTheme.darkTheme.copyWith(
            colorScheme: const ColorScheme.dark(
              primary: PulseTheme.neonIndigo,
              surface: PulseTheme.surfaceElevated,
              onSurface: Colors.white,
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked == null || !mounted) return;
    HapticFeedback.selectionClick();

    final nextConfig = isStart
        ? _config.copyWith(startTime: picked)
        : _config.copyWith(endTime: picked);

    await _updateConfig(nextConfig, showSnack: true);
  }

  Future<void> _openCustomCardPickerModal() async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) {
        return _CustomCardPickerModal(decks: _decks);
      },
    );

    if (!mounted) return;
    final starred = await DatabaseHelper.instance.getStarredCards();
    if (!mounted) return;

    setState(() {
      _starredCardCount = starred.length;
    });

    if (_config.isEnabled) {
      await NotificationService.instance.scheduleDailyNotifications(config: _config);
    }
  }

  Future<void> _triggerTestNotification() async {
    setState(() {
      _isSendingTest = true;
    });
    HapticFeedback.mediumImpact();

    final success = await NotificationService.instance.sendTestNotificationNow(config: _config);

    if (!mounted) return;
    setState(() {
      _isSendingTest = false;
    });

    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: success ? PulseTheme.neonEmerald : PulseTheme.neonCoral,
        content: Text(
          success
              ? 'Test flashcard notification dispatched! Check your system notification bar.'
              : 'Could not dispatch notification. Ensure you have at least 1 card and permissions enabled.',
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }

  String _formatTimeOfDay(TimeOfDay time) {
    final hour = time.hourOfPeriod == 0 ? 12 : time.hourOfPeriod;
    final min = time.minute.toString().padLeft(2, '0');
    final period = time.period == DayPeriod.am ? 'AM' : 'PM';
    return '$hour:$min $period';
  }

  @override
  Widget build(BuildContext context) {
    final triggerSlots = NotificationService.instance.calculateTriggerTimes(
      startTime: _config.startTime,
      endTime: _config.endTime,
      frequency: _config.dailyFrequency,
    );

    return Scaffold(
      backgroundColor: PulseTheme.bgPrimary,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Row(
          children: [
            Icon(Icons.notifications_active_outlined, color: PulseTheme.neonAmber, size: 20),
            SizedBox(width: 8),
            Text(
              'Smart Pulse Notifications',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
            ),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: PulseTheme.neonIndigo))
          : ListView(
              padding: const EdgeInsets.all(16),
              physics: const BouncingScrollPhysics(),
              children: [
                _buildMasterSwitchCard(),
                const SizedBox(height: 18),
                _buildSelectionModeSection(),
                const SizedBox(height: 18),
                _buildScheduleAndWindowSection(triggerSlots),
                const SizedBox(height: 36),
              ],
            ),
    );
  }

  Widget _buildMasterSwitchCard() {
    return PulseGlassPanel(
      padding: const EdgeInsets.all(20),
      borderColor: _config.isEnabled ? PulseTheme.neonEmerald.withOpacity(0.5) : PulseTheme.borderSubtle,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            activeColor: PulseTheme.neonEmerald,
            title: const Text(
              'Enable Daily Recall Pulses',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            subtitle: Text(
              _config.isEnabled
                  ? 'Active: Delivering ${_config.dailyFrequency} flashcards/day between ${_formatTimeOfDay(_config.startTime)} and ${_formatTimeOfDay(_config.endTime)}.'
                  : 'Turn on to receive passive spaced-repetition prompts throughout your day.',
              style: const TextStyle(fontSize: 12, color: PulseTheme.textSecondary, height: 1.4),
            ),
            value: _config.isEnabled,
            onChanged: (val) {
              HapticFeedback.lightImpact();
              _updateConfig(_config.copyWith(isEnabled: val), showSnack: true);
            },
          ),
          const Divider(color: PulseTheme.borderSubtle, height: 24),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white,
                side: const BorderSide(color: PulseTheme.neonIndigo),
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              icon: _isSendingTest
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2, color: PulseTheme.neonIndigo),
                    )
                  : const Icon(Icons.send_to_mobile_rounded, color: PulseTheme.neonIndigo, size: 18),
              label: Text(
                _isSendingTest ? 'Dispatching Test Pulse...' : 'Send Test Notification Now',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              onPressed: _isSendingTest ? null : _triggerTestNotification,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSelectionModeSection() {
    return PulseGlassPanel(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.filter_List_rounded, color: PulseTheme.neonIndigo, size: 20),
              SizedBox(width: 8),
              Text(
                'Flashcard Source Mode',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 6),
          const Text(
            'Choose which flashcards are selected for your daily notification bar prompts.',
            style: TextStyle(fontSize: 12, color: PulseTheme.textSecondary),
          ),
          const SizedBox(height: 16),

          // Mode A: Custom Selected Cards
          _buildModeOptionTile(
            mode: NotificationCardMode.customStarred,
            title: 'Mode A: Custom Selected Flashcards',
            subtitle: 'Only notify me with high-priority cards I have explicitly starred/checked ($_starredCardCount selected).',
            icon: Icons.star_rounded,
            accentColor: PulseTheme.neonAmber,
            trailingAction: Padding(
              padding: const EdgeInsets.only(top: 12),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: PulseTheme.neonIndigo,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 11),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  icon: const Icon(Icons.checklist_rtl_rounded, size: 18),
                  label: Text(
                    'Select Custom Flashcards ($_starredCardCount Selected)',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                  onPressed: _openCustomCardPickerModal,
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),

          // Mode B: Specific Deck Due Cards
          _buildModeOptionTile(
            mode: NotificationCardMode.specificDeck,
            title: 'Mode B: Specific Deck Due Cards',
            subtitle: 'Focus notifications exclusively on due cards from a single target deck.',
            icon: Icons.folder_special_outlined,
            accentColor: PulseTheme.neonBlue,
            trailingAction: _config.mode == NotificationCardMode.specificDeck && _decks.isNotEmpty
                ? Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: DropdownButtonFormField<String>(
                      value: _decks.any((d) => d.id == _config.targetDeckId)
                          ? _config.targetDeckId
                          : _decks.first.id,
                      dropdownColor: PulseTheme.surfaceElevated,
                      decoration: const InputDecoration(
                        labelText: 'Target Deck',
                        contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      ),
                      items: _decks.map((deck) {
                        return DropdownMenuItem<String>(
                          value: deck.id,
                          child: Text(
                            deck.title,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                          ),
                        );
                      }).toList(),
                      onChanged: (val) {
                        if (val != null) {
                          _updateConfig(_config.copyWith(targetDeckId: val), showSnack: true);
                        }
                      },
                    ),
                  )
                : null,
          ),
          const SizedBox(height: 12),

          // Mode C: All Due Cards
          _buildModeOptionTile(
            mode: NotificationCardMode.allDue,
            title: 'Mode C: All Due Cards Across Decks',
            subtitle: 'Pull randomly from all currently due flashcards across your entire database ($_totalDueCount due now).',
            icon: Icons.all_inclusive_rounded,
            accentColor: PulseTheme.neonEmerald,
          ),
        ],
      ),
    );
  }

  Widget _buildModeOptionTile({
    required NotificationCardMode mode,
    required String title,
    required String subtitle,
    required IconData icon,
    required Color accentColor,
    Widget? trailingAction,
  }) {
    final isSelected = _config.mode == mode;

    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        _updateConfig(_config.copyWith(mode: mode), showSnack: true);
      },
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isSelected ? accentColor.withOpacity(0.1) : PulseTheme.surfaceElevated,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isSelected ? accentColor : PulseTheme.borderSubtle,
            width: isSelected ? 1.5 : 1.0,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  isSelected ? Icons.radio_button_checked : Icons.radio_button_off,
                  color: isSelected ? accentColor : PulseTheme.textTertiary,
                  size: 20,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(icon, size: 16, color: accentColor),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              title,
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        style: const TextStyle(fontSize: 12, color: PulseTheme.textSecondary, height: 1.35),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (trailingAction != null) trailingAction,
          ],
        ),
      ),
    );
  }

  Widget _buildScheduleAndWindowSection(List<TimeOfDay> triggerSlots) {
    return PulseGlassPanel(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.schedule_rounded, color: PulseTheme.neonEmerald, size: 20),
              SizedBox(width: 8),
              Text(
                'Daily Frequency & Active Window',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Daily Notification Frequency',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: PulseTheme.neonIndigo.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '${_config.dailyFrequency}x / day',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: PulseTheme.neonIndigo,
                  ),
                ),
              ),
            ],
          ),
          Slider(
            value: _config.dailyFrequency.toDouble(),
            min: 1,
            max: 15,
            divisions: 14,
            activeColor: PulseTheme.neonIndigo,
            inactiveColor: PulseTheme.surfaceElevated,
            onChanged: (val) {
              setState(() {
                _config = _config.copyWith(dailyFrequency: val.round());
              });
            },
            onChangeEnd: (val) {
              _updateConfig(_config.copyWith(dailyFrequency: val.round()), showSnack: true);
            },
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _buildTimePickerBox(
                  label: 'Start Window',
                  timeText: _formatTimeOfDay(_config.startTime),
                  icon: Icons.wb_sunny_outlined,
                  onTap: () => _pickTime(isStart: true),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildTimePickerBox(
                  label: 'End Window',
                  timeText: _formatTimeOfDay(_config.endTime),
                  icon: Icons.nights_stay_outlined,
                  onTap: () => _pickTime(isStart: false),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          const Text(
            'Calculated Daily Trigger Timeline',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: PulseTheme.textSecondary),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: triggerSlots.map((slot) {
              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: PulseTheme.surfaceElevated,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: PulseTheme.borderSubtle),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.bolt, size: 13, color: PulseTheme.neonAmber),
                    const SizedBox(width: 4),
                    Text(
                      _formatTimeOfDay(slot),
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildTimePickerBox({
    required String label,
    required String timeText,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: PulseTheme.surfaceElevated,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: PulseTheme.borderSubtle),
        ),
        child: Row(
          children: [
            Icon(icon, size: 18, color: PulseTheme.neonIndigo),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: const TextStyle(fontSize: 11, color: PulseTheme.textTertiary),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    timeText,
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),
            const Icon(Icons.edit_calendar_outlined, size: 16, color: PulseTheme.textTertiary),
          ],
        ),
      ),
    );
  }
}

class _CustomCardPickerModal extends StatefulWidget {
  final List<Deck> decks;

  const _CustomCardPickerModal({required this.decks});

  @override
  State<_CustomCardPickerModal> createState() => _CustomCardPickerModalState();
}

class _CustomCardPickerModalState extends State<_CustomCardPickerModal> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  String _selectedDeckFilter = 'ALL';
  bool _isLoading = true;

  List<Flashcard> _allCards = [];
  Map<String, String> _deckTitles = {};

  @override
  void initState() {
    super.initState();
    _loadAllCards();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadAllCards() async {
    final Map<String, String> titles = {};
    final List<Flashcard> loadedCards = [];

    for (final deck in widget.decks) {
      titles[deck.id] = deck.title;
      final cards = await DatabaseHelper.instance.getFlashcardsForDeck(deck.id);
      loadedCards.addAll(cards);
    }

    if (!mounted) return;
    setState(() {
      _deckTitles = titles;
      _allCards = loadedCards;
      _isLoading = false;
    });
  }

  List<Flashcard> get _filteredCards {
    return _allCards.where((card) {
      if (_selectedDeckFilter != 'ALL' && card.deckId != _selectedDeckFilter) {
        return false;
      }
      if (_searchQuery.trim().isEmpty) return true;
      final q = _searchQuery.toLowerCase();
      final deckTitle = (_deckTitles[card.deckId] ?? '').toLowerCase();
      return card.question.toLowerCase().contains(q) ||
          card.answer.toLowerCase().contains(q) ||
          deckTitle.contains(q);
    }).toList();
  }

  int get _starredCount => _allCards.where((c) => c.isStarredForNotification).length;

  Future<void> _toggleCardSelection(Flashcard card) async {
    final nextVal = !card.isStarredForNotification;
    HapticFeedback.selectionClick();

    await DatabaseHelper.instance.toggleStarredForNotification(card.id, nextVal);
    if (!mounted) return;

    setState(() {
      final idx = _allCards.indexWhere((c) => c.id == card.id);
      if (idx != -1) {
        _allCards[idx] = card.copyWith(isStarredForNotification: nextVal);
      }
    });
  }

  Future<void> _bulkToggleVisible(bool selectAll) async {
    final visible = _filteredCards;
    if (visible.isEmpty) return;
    HapticFeedback.mediumImpact();

    for (final card in visible) {
      if (card.isStarredForNotification != selectAll) {
        await DatabaseHelper.instance.toggleStarredForNotification(card.id, selectAll);
      }
    }

    if (!mounted) return;
    await _loadAllCards();
  }

  @override
  Widget build(BuildContext context) {
    final visibleCards = _filteredCards;

    return Container(
      height: MediaQuery.of(context).size.height * 0.88,
      decoration: const BoxDecoration(
        color: PulseTheme.surfaceCard,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        border: Border(top: BorderSide(color: PulseTheme.borderSubtle, width: 1.5)),
      ),
      child: Column(
        children: [
          const SizedBox(height: 10),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: PulseTheme.textTertiary.withOpacity(0.4),
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 16, 8),
            child: Row(
              children: [
                const Icon(Icons.checklist_rtl_rounded, color: PulseTheme.neonAmber, size: 22),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Select Custom Notification Cards',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                      Text(
                        '$_starredCount flashcards starred for daily notification pulses',
                        style: const TextStyle(fontSize: 12, color: PulseTheme.textSecondary),
                      ),
                    ],
                  ),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: PulseTheme.neonIndigo,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Done', style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: TextField(
              controller: _searchController,
              onChanged: (val) {
                setState(() {
                  _searchQuery = val;
                });
              },
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search, size: 18, color: PulseTheme.textTertiary),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, size: 16),
                        onPressed: () {
                          _searchController.clear();
                          setState(() {
                            _searchQuery = '';
                          });
                        },
                      )
                    : null,
                hintText: 'Search flashcards to star/unstar...',
              ),
            ),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                ChoiceChip(
                  label: const Text('All Decks'),
                  selected: _selectedDeckFilter == 'ALL',
                  selectedColor: PulseTheme.neonIndigo,
                  backgroundColor: PulseTheme.surfaceElevated,
                  labelStyle: TextStyle(
                    fontSize: 12,
                    color: _selectedDeckFilter == 'ALL' ? Colors.white : PulseTheme.textSecondary,
                  ),
                  onSelected: (_) {
                    setState(() {
                      _selectedDeckFilter = 'ALL';
                    });
                  },
                ),
                const SizedBox(width: 8),
                ...widget.decks.map((deck) {
                  final selected = _selectedDeckFilter == deck.id;
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(deck.title),
                      selected: selected,
                      selectedColor: PulseTheme.neonIndigo,
                      backgroundColor: PulseTheme.surfaceElevated,
                      labelStyle: TextStyle(
                        fontSize: 12,
                        color: selected ? Colors.white : PulseTheme.textSecondary,
                      ),
                      onSelected: (_) {
                        setState(() {
                          _selectedDeckFilter = deck.id;
                        });
                      },
                    ),
                  );
                }),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Showing ${visibleCards.length} cards',
                  style: const TextStyle(fontSize: 12, color: PulseTheme.textTertiary),
                ),
                Row(
                  children: [
                    TextButton(
                      onPressed: () => _bulkToggleVisible(true),
                      child: const Text(
                        'Select All Visible',
                        style: TextStyle(fontSize: 12, color: PulseTheme.neonIndigo),
                      ),
                    ),
                    TextButton(
                      onPressed: () => _bulkToggleVisible(false),
                      child: const Text(
                        'Clear Visible',
                        style: TextStyle(fontSize: 12, color: PulseTheme.textSecondary),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const Divider(color: PulseTheme.borderSubtle, height: 1),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator(color: PulseTheme.neonIndigo))
                : visibleCards.isEmpty
                    ? const Center(
                        child: Text(
                          'No flashcards match your filter.',
                          style: TextStyle(color: PulseTheme.textSecondary),
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: visibleCards.length,
                        itemBuilder: (context, index) {
                          final card = visibleCards[index];
                          final deckName = _deckTitles[card.deckId] ?? 'Deck';
                          final isStarred = card.isStarredForNotification;

                          return Container(
                            margin: const EdgeInsets.only(bottom: 10),
                            decoration: BoxDecoration(
                              color: isStarred
                                  ? PulseTheme.neonAmber.withOpacity(0.08)
                                  : PulseTheme.surfaceElevated,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: isStarred
                                    ? PulseTheme.neonAmber.withOpacity(0.5)
                                    : PulseTheme.borderSubtle,
                              ),
                            ),
                            child: CheckboxListTile(
                              value: isStarred,
                              activeColor: PulseTheme.neonAmber,
                              checkColor: Colors.black,
                              onChanged: (_) => _toggleCardSelection(card),
                              title: Text(
                                card.question,
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                              ),
                              subtitle: Padding(
                                padding: const EdgeInsets.only(top: 6),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      card.answer,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontSize: 12,
                                        color: PulseTheme.textSecondary,
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: PulseTheme.bgPrimary,
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Text(
                                        deckName,
                                        style: const TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.w600,
                                          color: PulseTheme.neonIndigo,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
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