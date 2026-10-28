import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import 'package:qara/database/app_database.dart';
import 'package:qara/models/call_center.dart';
import 'package:qara/screens/call_center_detail_screen.dart';
import 'package:qara/services/caller_id_service.dart';

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

  final TextEditingController _searchController = TextEditingController();

  static const List<String> _colorPalette = [
    '#3F51B5', // Indigo
    '#00897B', // Teal
    '#D81B60', // Pink / Rose
    '#E65100', // Deep Orange
    '#5E35B1', // Deep Purple
    '#1E88E5', // Blue
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadCallCenters();
    _checkCallerIdStatus();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkCallerIdStatus();
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
    final nameController = TextEditingController();
    final locationController = TextEditingController();
    final descController = TextEditingController();
    String selectedColor = _colorPalette.first;
    String? validationError;

    await showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (dialogCtx, setDialogState) {
            return AlertDialog(
              title: const Row(
                children: [
                  Icon(Icons.hub_outlined, color: Colors.indigo),
                  SizedBox(width: 8),
                  Text('New Call Center'),
                ],
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Create a workspace for a specific outreach event, campaign, or team zone.',
                      style: TextStyle(fontSize: 12, color: Colors.black54),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: nameController,
                      decoration: InputDecoration(
                        labelText: 'Call Center Name *',
                        hintText: 'e.g. Spintex Saturday Outreach',
                        errorText: validationError,
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: locationController,
                      decoration: const InputDecoration(
                        labelText: 'Location / Target Area',
                        hintText: 'e.g. Spintex Road',
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: descController,
                      maxLines: 2,
                      decoration: const InputDecoration(
                        labelText: 'Description / Purpose (Optional)',
                        hintText: 'e.g. Easter revival follow-up center',
                      ),
                    ),
                    const SizedBox(height: 14),
                    const Text(
                      'Theme Color',
                      style:
                          TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      children: _colorPalette.map((colorHex) {
                        final color = Color(
                          int.parse(colorHex.replaceAll('#', '0xff')),
                        );
                        final isSelected = selectedColor == colorHex;
                        return InkWell(
                          onTap: () {
                            setDialogState(() => selectedColor = colorHex);
                          },
                          borderRadius: BorderRadius.circular(16),
                          child: Container(
                            width: 32,
                            height: 32,
                            decoration: BoxDecoration(
                              color: color,
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: isSelected ? Colors.black : Colors.white,
                                width: isSelected ? 2.5 : 1,
                              ),
                            ),
                            child: isSelected
                                ? const Icon(Icons.check,
                                    size: 16, color: Colors.white)
                                : null,
                          ),
                        );
                      }).toList(),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: () async {
                    final name = nameController.text.trim();
                    if (name.isEmpty) {
                      setDialogState(() {
                        validationError = 'Please enter a name for the Call Center';
                      });
                      return;
                    }

                    final newCenter = CallCenter(
                      id: _uuid.v4(),
                      name: name,
                      location: locationController.text.trim().isNotEmpty
                          ? locationController.text.trim()
                          : null,
                      description: descController.text.trim().isNotEmpty
                          ? descController.text.trim()
                          : null,
                      colorHex: selectedColor,
                      createdAt: DateTime.now(),
                      updatedAt: DateTime.now(),
                    );

                    await widget.database.insertCallCenter(newCenter);
                    if (context.mounted) {
                      Navigator.of(ctx).pop();
                      await _loadCallCenters();
                      // Navigate straight into the newly created Call Center!
                      _openCallCenterDetail(newCenter);
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.indigo.shade700,
                    foregroundColor: Colors.white,
                  ),
                  child: const Text('Create Center'),
                ),
              ],
            );
          },
        );
      },
    );
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
              _allCenters.isEmpty
                  ? 'Organize outreach by project / gem'
                  : '${_allCenters.length} ${_allCenters.length == 1 ? "center" : "centers"} • $totalContacts total contacts',
              style: TextStyle(fontSize: 11, color: Colors.indigo.shade100),
            ),
          ],
        ),
        backgroundColor: Colors.indigo.shade700,
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
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _allCenters.isEmpty
                    ? _buildOnboardingWelcomeState()
                    : _filteredCenters.isEmpty
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
        backgroundColor: Colors.indigo.shade700,
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
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.indigo.shade50,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.hub_outlined,
                size: 56,
                color: Colors.indigo.shade600,
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'Welcome to Qara',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            Text(
              'Start by creating your first Call Center. Contacts are organized into dedicated campaigns or project centers (like Gems or Projects) so you can paste, import, and follow up with clarity.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey.shade600, fontSize: 13, height: 1.4),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _showCreateCenterDialog,
              icon: const Icon(Icons.add),
              label: const Text('Create Your First Call Center'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.indigo.shade700,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 14,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ],
        ),
      ),
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

      return Container(
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
              onPressed: () => CallerIdService.openAppSettings(),
              child: const Text('Settings'),
            ),
          ],
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
}

