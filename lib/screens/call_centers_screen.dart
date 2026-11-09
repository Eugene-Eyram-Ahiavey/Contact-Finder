import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import 'package:qara/database/app_database.dart';
import 'package:qara/models/call_center.dart';
import 'package:qara/screens/call_center_detail_screen.dart';
import 'package:qara/services/caller_id_service.dart';
import 'package:qara/theme/app_theme.dart';
import 'package:qara/widgets/create_call_center_dialog.dart';
import 'package:qara/widgets/welcome_call_center_view.dart';

/// CallCentersScreen
///
/// Top-level hub displaying organized Call Centers (outreach projects/gems).
///
/// Features:
/// 1. First-launch onboarding state prompting user to create their first Call Center.
/// 2. Grid/list of active Call Centers with live contact counts and location tags.
/// 3. Search and quick management (create, edit, delete with cascade).
/// 4. System Caller ID & Overlay status banner.
class CallCentersScreen extends StatefulWidget {
  final AppDatabase database;

  const CallCentersScreen({super.key, required this.database});

  @override
  State<CallCentersScreen> createState() => _CallCentersScreenState();
}

class _CallCentersScreenState extends State<CallCentersScreen>
    with WidgetsBindingObserver {
  static const _uuid = Uuid();
  List<CallCenter> _allCenters = [];
  List<CallCenter> _filteredCenters = [];
  bool _isLoading = true;
  String _searchQuery = '';
  bool _isCallerIdEnabled = false;
  bool _isOverlayEnabled = false;
  bool _isSyncing = false;

  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadCallCenters();
    _checkCallerIdStatus();
    _syncGlobalCallerId();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkCallerIdStatus();
      _syncGlobalCallerId();
    }
  }

  Future<void> _syncGlobalCallerId() async {
    try {
      final allContacts = await widget.database.getAllContacts();
      await CallerIdService.syncContactsToCallDirectory(allContacts);
    } catch (_) {
      // Background sync
    }
  }

  Future<void> _handleManualSync() async {
    if (_isSyncing) return;
    setState(() => _isSyncing = true);
    try {
      final allContacts = await widget.database.getAllContacts();
      await CallerIdService.syncContactsToCallDirectory(allContacts);
      await _checkCallerIdStatus();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle, color: AppColors.brandLime, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    allContacts.isEmpty
                        ? 'Caller ID directory synchronized (ready for contacts)'
                        : 'Caller ID directory synchronized (${allContacts.length} contacts)',
                    style: const TextStyle(color: Colors.white, fontSize: 13),
                  ),
                ),
              ],
            ),
            backgroundColor: AppColors.brandDarkTeal,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Sync failed: $e'),
            backgroundColor: Colors.red.shade800,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSyncing = false);
      }
    }
  }

  Future<void> _checkCallerIdStatus() async {
    final callerIdEnabled = await CallerIdService.isCallerIdEnabled();
    final overlayEnabled = await CallerIdService.isOverlayPermissionGranted();
    if (mounted) {
      setState(() {
        _isCallerIdEnabled = callerIdEnabled;
        _isOverlayEnabled = overlayEnabled;
      });
    }
  }

  Future<void> _loadCallCenters() async {
    final list = await widget.database.getAllCallCenters();
    if (mounted) {
      setState(() {
        _allCenters = list;
        _applySearch();
        _isLoading = false;
      });
    }
  }

  void _applySearch() {
    if (_searchQuery.trim().isEmpty) {
      _filteredCenters = _allCenters;
    } else {
      final q = _searchQuery.trim().toLowerCase();
      _filteredCenters = _allCenters.where((center) {
        final matchesName = center.name.toLowerCase().contains(q);
        final matchesLoc = center.location?.toLowerCase().contains(q) ?? false;
        final matchesDesc =
            center.description?.toLowerCase().contains(q) ?? false;
        return matchesName || matchesLoc || matchesDesc;
      }).toList();
    }
  }

  void _onSearchChanged(String query) {
    setState(() {
      _searchQuery = query;
      _applySearch();
    });
  }

  Future<void> _showCreateCenterDialog() async {
    final newCenter = await CreateCallCenterDialog.show(context);
    if (newCenter == null) return;

    await widget.database.insertCallCenter(newCenter);
    await _loadCallCenters();
    if (mounted) {
      _openCallCenterDetail(newCenter);
    }
  }

  void _openCallCenterDetail(CallCenter center) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => CallCenterDetailScreen(
          callCenter: center,
          database: widget.database,
          onCenterUpdated: _loadCallCenters,
        ),
      ),
    );
  }

  Future<void> _confirmDeleteCenter(CallCenter center) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('Delete Call Center?'),
          content: Text(
            'Are you sure you want to delete "${center.name}"?\n\n'
            'This will permanently delete all ${center.contactCount} contacts and follow-up interaction history in this center.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red.shade700,
                foregroundColor: Colors.white,
              ),
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );

    if (confirmed == true) {
      await widget.database.deleteCallCenter(center.id);
      _loadCallCenters();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Deleted "${center.name}"')),
        );
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        backgroundColor: AppColors.mintBackgroundCenter,
        body: Center(
          child: CircularProgressIndicator(
            valueColor: AlwaysStoppedAnimation<Color>(AppColors.brandDarkTeal),
          ),
        ),
      );
    }

    if (_allCenters.isEmpty) {
      return Scaffold(
        body: WelcomeCallCenterView(
          onCreateCenterPressed: _showCreateCenterDialog,
          onSyncPressed: _handleManualSync,
          isSyncing: _isSyncing,
        ),
      );
    }

    final totalContacts = _allCenters.fold<int>(
      0,
      (sum, item) => sum + item.contactCount,
    );

    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Qara Call Centers',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 19),
            ),
            Text(
              '${_allCenters.length} ${_allCenters.length == 1 ? "center" : "centers"} • $totalContacts total contacts',
              style: TextStyle(fontSize: 11, color: Colors.indigo.shade100),
            ),
          ],
        ),
        backgroundColor: AppColors.brandDarkTeal,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: 'New Call Center',
            onPressed: _showCreateCenterDialog,
          ),
        ],
      ),
      body: Column(
        children: [
          _buildStatusBanner(),
          if (_allCenters.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 14, 14, 8),
              child: TextField(
                controller: _searchController,
                onChanged: _onSearchChanged,
                decoration: InputDecoration(
                  hintText: 'Search Call Centers by name or area...',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _searchQuery.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear),
                          onPressed: () {
                            _searchController.clear();
                            _onSearchChanged('');
                          },
                        )
                      : null,
                  filled: true,
                  fillColor: Colors.white,
                  contentPadding: const EdgeInsets.symmetric(vertical: 12),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: Colors.grey.shade300),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: Colors.grey.shade300),
                  ),
                ),
              ),
            ),
          ],
          Expanded(
            child: _filteredCenters.isEmpty
                ? _buildSearchEmptyState()
                : ListView.builder(
                    itemCount: _filteredCenters.length,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 6,
                    ),
                    itemBuilder: (context, index) {
                      final center = _filteredCenters[index];
                      return _buildCallCenterCard(center);
                    },
                  ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showCreateCenterDialog,
        backgroundColor: AppColors.brandDarkTeal,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add),
        label: const Text('New Center'),
      ),
    );
  }

  Widget _buildCallCenterCard(CallCenter center) {
    final color = center.colorHex != null
        ? Color(int.parse(center.colorHex!.replaceAll('#', '0xff')))
        : Colors.indigo.shade700;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: InkWell(
        onTap: () => _openCallCenterDetail(center),
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Visual accent pill
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: color.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(Icons.hub_outlined, color: color, size: 26),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            center.name,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                        ),
                        PopupMenuButton<String>(
                          icon: const Icon(Icons.more_vert, size: 18, color: Colors.grey),
                          padding: EdgeInsets.zero,
                          onSelected: (val) {
                            if (val == 'delete') {
                              _confirmDeleteCenter(center);
                            }
                          },
                          itemBuilder: (ctx) => [
                            const PopupMenuItem(
                              value: 'delete',
                              child: Row(
                                children: [
                                  Icon(Icons.delete_outline, color: Colors.red, size: 18),
                                  SizedBox(width: 8),
                                  Text('Delete Center', style: TextStyle(color: Colors.red)),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    if (center.description != null &&
                        center.description!.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(
                        center.description!,
                        style: TextStyle(
                          color: Colors.grey.shade600,
                          fontSize: 12,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.indigo.shade50,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.people_outline,
                                  size: 13, color: Colors.indigo.shade700),
                              const SizedBox(width: 4),
                              Text(
                                '${center.contactCount} ${center.contactCount == 1 ? "contact" : "contacts"}',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.indigo.shade900,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (center.location != null &&
                            center.location!.isNotEmpty) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.blueGrey.shade50,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.location_on_outlined,
                                    size: 13,
                                    color: Colors.blueGrey.shade700),
                                const SizedBox(width: 4),
                                Text(
                                  center.location!,
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: Colors.blueGrey.shade800,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildOnboardingWelcomeState() {
    return WelcomeCallCenterView(
      onCreateCenterPressed: _showCreateCenterDialog,
      onSyncPressed: _handleManualSync,
      isSyncing: _isSyncing,
    );
  }

  Widget _buildSearchEmptyState() {
    return Center(
      child: Text(
        'No Call Centers matching "$_searchQuery"',
        style: TextStyle(color: Colors.grey.shade600),
      ),
    );
  }

  Widget _buildStatusBanner() {
    final isIOS = Theme.of(context).platform == TargetPlatform.iOS;

    if (isIOS) {
      if (_isCallerIdEnabled) {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          color: Colors.teal.shade50,
          child: Row(
            children: [
              Icon(Icons.check_circle, size: 20, color: Colors.teal.shade800),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'iOS Call Identification Active across all Centers',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Colors.teal.shade900,
                  ),
                ),
              ),
            ],
          ),
        );
      }

      return InkWell(
        onTap: _showIOSCallKitGuideDialog,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          color: Colors.amber.shade50,
          child: Row(
            children: [
              Icon(Icons.phone_disabled_outlined, size: 20, color: Colors.amber.shade900),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Enable Qara in Settings ➔ Phone ➔ Call Blocking & Identification',
                  style: TextStyle(fontSize: 11, color: Colors.amber.shade900),
                ),
              ),
              TextButton(
                onPressed: _showIOSCallKitGuideDialog,
                child: const Text('Guide'),
              ),
            ],
          ),
        ),
      );
    }

    final bool allActive = _isCallerIdEnabled && _isOverlayEnabled;
    if (allActive) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        color: Colors.teal.shade50,
        child: Row(
          children: [
            Icon(Icons.check_circle, size: 18, color: Colors.teal.shade800),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Caller ID & Floating Overlay Active across all Centers',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Colors.teal.shade900,
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: Colors.amber.shade50,
      child: Row(
        children: [
          Icon(Icons.warning_amber_rounded, size: 18, color: Colors.amber.shade900),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Grant Call Screening & Overlay permissions to identify callers',
              style: TextStyle(fontSize: 11, color: Colors.amber.shade900),
            ),
          ),
          TextButton(
            onPressed: () async {
              if (!_isCallerIdEnabled) {
                await CallerIdService.requestCallerIdRole();
              }
              if (!_isOverlayEnabled) {
                await CallerIdService.requestOverlayPermission();
              }
              _checkCallerIdStatus();
            },
            child: const Text('Enable'),
          ),
        ],
      ),
    );
  }

  void _showIOSCallKitGuideDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.phone_callback_rounded, color: Colors.indigo),
            SizedBox(width: 8),
            Text('Enable Caller ID', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Apple requires Call Directory extensions to be activated manually in your iPhone Settings for privacy:\n',
              style: TextStyle(fontSize: 13, color: Colors.black87),
            ),
            _buildGuideStep('1', 'Open your iPhone Settings app'),
            _buildGuideStep('2', 'Scroll down and tap Phone'),
            _buildGuideStep('3', 'Tap Call Blocking & Identification'),
            _buildGuideStep('4', 'Turn the switch ON for Qara', isHighlighted: true),
            const SizedBox(height: 12),
            Text(
              'Once enabled, incoming calls from your outreach contacts will instantly show their name and Call Center.',
              style: TextStyle(fontSize: 11, color: Colors.grey.shade600, fontStyle: FontStyle.italic),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Close'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              CallerIdService.openAppSettings();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.indigo.shade700,
              foregroundColor: Colors.white,
            ),
            child: const Text('Open Settings'),
          ),
        ],
      ),
    );
  }

  Widget _buildGuideStep(String number, String text, {bool isHighlighted = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 20,
            height: 20,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: isHighlighted ? Colors.teal.shade700 : Colors.indigo.shade100,
              shape: BoxShape.circle,
            ),
            child: Text(
              number,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: isHighlighted ? Colors.white : Colors.indigo.shade900,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 13,
                fontWeight: isHighlighted ? FontWeight.bold : FontWeight.w500,
                color: isHighlighted ? Colors.teal.shade900 : Colors.black87,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

