import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import 'package:qara/database/app_database.dart';
import 'package:qara/models/call_center.dart';
import 'package:qara/models/contact.dart';
import 'package:qara/screens/contact_detail_modal.dart';
import 'package:qara/screens/import_modal.dart';
import 'package:qara/services/caller_id_service.dart';
import 'package:qara/services/phone_dialer_service.dart';
import 'package:qara/utils/phone_number_normalizer.dart';

/// CallCenterDetailScreen
///
/// Dedicated workspace for a specific Call Center project/campaign.
///
/// Guarantees:
/// 1. New additions always appear at the top (`created_at DESC`).
/// 2. In-center search and location/notes filter chips.
/// 3. Targeted contact import and single contact creation scoped to this center.
/// 4. Auto-sync to native Android and iOS Caller ID systems.
class CallCenterDetailScreen extends StatefulWidget {
  final CallCenter callCenter;
  final AppDatabase database;
  final VoidCallback onCenterUpdated;

  const CallCenterDetailScreen({
    super.key,
    required this.callCenter,
    required this.database,
    required this.onCenterUpdated,
  });

  @override
  State<CallCenterDetailScreen> createState() => _CallCenterDetailScreenState();
}

class _CallCenterDetailScreenState extends State<CallCenterDetailScreen> {
  static const _uuid = Uuid();
  late CallCenter _currentCenter;
  List<Contact> _allContacts = [];
  List<Contact> _contacts = [];
  bool _isLoading = true;
  String _searchQuery = '';
  String _selectedFilter = 'All';

  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _currentCenter = widget.callCenter;
    _loadContacts();
  }

  Future<void> _loadContacts() async {
    final list = _searchQuery.isEmpty
        ? await widget.database.getContactsByCallCenter(_currentCenter.id)
        : await widget.database.searchContactsInCallCenter(
            _currentCenter.id,
            _searchQuery,
          );

    if (mounted) {
      setState(() {
        _allContacts = list;
        _applyFilter();
        _isLoading = false;
      });
    }

    _syncCallDirectory();
  }

  Future<void> _syncCallDirectory() async {
    try {
      final all = await widget.database.getAllContacts();
      await CallerIdService.syncContactsToCallDirectory(all);
    } catch (_) {
      // Silently continue if platform channel fails
    }
  }

  void _applyFilter() {
    if (_selectedFilter == 'All') {
      _contacts = _allContacts;
    } else if (_selectedFilter == 'Has Notes') {
      _contacts = _allContacts
          .where((c) => c.notes != null && c.notes!.trim().isNotEmpty)
          .toList();
    } else {
      _contacts = _allContacts
          .where((c) =>
              c.location != null &&
              c.location!.trim().toLowerCase() == _selectedFilter.toLowerCase())
          .toList();
    }
  }

  void _onFilterSelected(String filter) {
    setState(() {
      _selectedFilter = filter;
      _applyFilter();
    });
  }

  List<String> get _availableLocations {
    final locs = _allContacts
        .map((c) => c.location?.trim())
        .where((loc) => loc != null && loc.isNotEmpty)
        .cast<String>()
        .toSet()
        .toList();
    locs.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return locs;
  }

  void _onSearchChanged(String query) {
    setState(() => _searchQuery = query);
    _loadContacts();
  }

  void _openImportModal() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => ImportNotesModal(
        database: widget.database,
        callCenterId: _currentCenter.id,
        callCenterName: _currentCenter.name,
        onImportCompleted: () {
          _loadContacts();
          widget.onCenterUpdated();
        },
      ),
    );
  }

  void _openContactDetail(Contact contact) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => ContactDetailModal(
        contact: contact,
        database: widget.database,
        onDataChanged: () {
          _loadContacts();
          widget.onCenterUpdated();
        },
      ),
    );
  }

  Future<void> _showAddContactDialog() async {
    final nameController = TextEditingController();
    final phoneController = TextEditingController();
    final locationController = TextEditingController(
      text: _currentCenter.location ?? '',
    );
    final notesController = TextEditingController();

    String? validationError;

    await showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Add Contact to Call Center'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: nameController,
                      decoration: const InputDecoration(labelText: 'Full Name'),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: phoneController,
                      keyboardType: TextInputType.phone,
                      decoration: InputDecoration(
                        labelText: 'Phone Number (e.g. 0244123456)',
                        errorText: validationError,
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: locationController,
                      decoration: const InputDecoration(labelText: 'Location / Area'),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: notesController,
                      maxLines: 2,
                      decoration: const InputDecoration(labelText: 'Outreach Notes'),
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
                    final rawPhone = phoneController.text.trim();
                    final normalized = PhoneNumberNormalizer.normalize(rawPhone);

                    if (normalized == null) {
                      setDialogState(() {
                        validationError = 'Please enter a valid phone number';
                      });
                      return;
                    }

                    final newContact = Contact(
                      id: _uuid.v4(),
                      callCenterId: _currentCenter.id,
                      name: nameController.text.trim().isNotEmpty
                          ? nameController.text.trim()
                          : 'Unknown Contact',
                      phoneNumber: rawPhone,
                      normalizedPhoneNumber: normalized,
                      location: locationController.text.trim().isNotEmpty
                          ? locationController.text.trim()
                          : null,
                      notes: notesController.text.trim().isNotEmpty
                          ? notesController.text.trim()
                          : null,
                      createdAt: DateTime.now(),
                      updatedAt: DateTime.now(),
                    );

                    try {
                      await widget.database.insertContact(newContact);
                      if (context.mounted) {
                        Navigator.of(ctx).pop();
                        _loadContacts();
                        widget.onCenterUpdated();
                      }
                    } on DuplicatePhoneNumberException catch (e) {
                      setDialogState(() {
                        validationError = e.message;
                      });
                    }
                  },
                  child: const Text('Save Contact'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _showEditCenterDialog() async {
    final nameController = TextEditingController(text: _currentCenter.name);
    final locationController = TextEditingController(text: _currentCenter.location ?? '');
    final descController = TextEditingController(text: _currentCenter.description ?? '');

    await showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('Edit Call Center'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameController,
                  decoration: const InputDecoration(labelText: 'Call Center Name'),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: locationController,
                  decoration: const InputDecoration(labelText: 'Target Area / Location'),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: descController,
                  maxLines: 2,
                  decoration: const InputDecoration(labelText: 'Description / Notes'),
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
                final newName = nameController.text.trim();
                if (newName.isEmpty) return;

                final updated = _currentCenter.copyWith(
                  name: newName,
                  location: locationController.text.trim().isNotEmpty
                      ? locationController.text.trim()
                      : null,
                  description: descController.text.trim().isNotEmpty
                      ? descController.text.trim()
                      : null,
                  updatedAt: DateTime.now(),
                );

                await widget.database.updateCallCenter(updated);
                if (mounted) {
                  setState(() => _currentCenter = updated);
                  widget.onCenterUpdated();
                  Navigator.of(ctx).pop();
                }
              },
              child: const Text('Save Changes'),
            ),
          ],
        );
      },
    );
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _currentCenter.name,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
            ),
            Text(
              _allContacts.isEmpty
                  ? '0 contacts'
                  : _selectedFilter == 'All' && _searchQuery.isEmpty
                      ? '${_allContacts.length} contacts (Newest on top)'
                      : '${_contacts.length} of ${_allContacts.length} contacts',
              style: TextStyle(fontSize: 11, color: Colors.indigo.shade100),
            ),
          ],
        ),
        backgroundColor: Colors.indigo.shade700,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.paste),
            tooltip: 'Paste / Import Contacts',
            onPressed: _openImportModal,
          ),
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: 'Add Single Contact',
            onPressed: _showAddContactDialog,
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            onSelected: (val) {
              if (val == 'edit') {
                _showEditCenterDialog();
              }
            },
            itemBuilder: (ctx) => [
              const PopupMenuItem(
                value: 'edit',
                child: Row(
                  children: [
                    Icon(Icons.edit_outlined, size: 20),
                    SizedBox(width: 8),
                    Text('Edit Center Info'),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          // In-Center Search Bar
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 8),
            child: TextField(
              controller: _searchController,
              onChanged: _onSearchChanged,
              decoration: InputDecoration(
                hintText: 'Search in ${_currentCenter.name}...',
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

          // Location & Notes Filter Chips
          _buildFilterChips(),

          // Contacts List
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _contacts.isEmpty
                    ? _buildEmptyState()
                    : ListView.builder(
                        itemCount: _contacts.length,
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                        itemBuilder: (context, index) {
                          final contact = _contacts[index];
                          final displayPhone =
                              PhoneNumberNormalizer.formatForDisplay(
                            contact.phoneNumber,
                          );

                          // Check if added within the last 24 hours to badge "NEW"
                          final isNew = DateTime.now()
                                  .difference(contact.createdAt)
                                  .inHours <
                              24;

                          return Card(
                            margin: const EdgeInsets.only(bottom: 8),
                            elevation: 0,
                            color: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                              side: BorderSide(color: Colors.grey.shade200),
                            ),
                            child: ListTile(
                              onTap: () => _openContactDetail(contact),
                              leading: Stack(
                                children: [
                                  CircleAvatar(
                                    backgroundColor: Colors.indigo.shade50,
                                    child: Text(
                                      contact.name.isNotEmpty
                                          ? contact.name[0].toUpperCase()
                                          : '?',
                                      style: TextStyle(
                                        color: Colors.indigo.shade700,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                  if (isNew)
                                    Positioned(
                                      top: 0,
                                      right: 0,
                                      child: Container(
                                        width: 10,
                                        height: 10,
                                        decoration: BoxDecoration(
                                          color: Colors.green.shade600,
                                          shape: BoxShape.circle,
                                          border: Border.all(
                                            color: Colors.white,
                                            width: 1.5,
                                          ),
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                              title: Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      contact.name,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w600,
                                        fontSize: 15,
                                      ),
                                    ),
                                  ),
                                  if (isNew)
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 6,
                                        vertical: 2,
                                      ),
                                      margin: const EdgeInsets.only(left: 4),
                                      decoration: BoxDecoration(
                                        color: Colors.green.shade50,
                                        borderRadius: BorderRadius.circular(4),
                                        border: Border.all(
                                          color: Colors.green.shade300,
                                        ),
                                      ),
                                      child: Text(
                                        'NEW',
                                        style: TextStyle(
                                          fontSize: 9,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.green.shade800,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                              subtitle: Text(
                                displayPhone,
                                style: TextStyle(
                                  color: Colors.grey.shade600,
                                  fontSize: 13,
                                ),
                              ),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (contact.location != null)
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 4,
                                      ),
                                      decoration: BoxDecoration(
                                        color: Colors.blueGrey.shade50,
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Text(
                                        contact.location!,
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Colors.blueGrey.shade700,
                                        ),
                                      ),
                                    ),
                                  const SizedBox(width: 4),
                                  IconButton(
                                    icon: const Icon(
                                      Icons.phone_outlined,
                                      color: Colors.green,
                                    ),
                                    tooltip: 'Call ${contact.name}',
                                    onPressed: () =>
                                        PhoneDialerService.dial(contact.phoneNumber),
                                  ),
                                  Icon(
                                    Icons.chevron_right,
                                    color: Colors.grey.shade400,
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openImportModal,
        backgroundColor: Colors.indigo.shade700,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.paste),
        label: const Text('Paste Notes'),
      ),
    );
  }

  Widget _buildFilterChips() {
    final locations = _availableLocations;
    final hasNotesCount = _allContacts
        .where((c) => c.notes != null && c.notes!.trim().isNotEmpty)
        .length;

    if (_allContacts.isEmpty) return const SizedBox.shrink();

    return Container(
      height: 38,
      margin: const EdgeInsets.only(bottom: 8),
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        children: [
          ChoiceChip(
            label: Text('All (${_allContacts.length})'),
            selected: _selectedFilter == 'All',
            onSelected: (_) => _onFilterSelected('All'),
            selectedColor: Colors.indigo.shade100,
            backgroundColor: Colors.white,
            visualDensity: VisualDensity.compact,
            side: BorderSide(
              color: _selectedFilter == 'All'
                  ? Colors.indigo
                  : Colors.grey.shade300,
            ),
            labelStyle: TextStyle(
              color: _selectedFilter == 'All'
                  ? Colors.indigo.shade900
                  : Colors.grey.shade700,
              fontWeight: _selectedFilter == 'All'
                  ? FontWeight.bold
                  : FontWeight.normal,
              fontSize: 12,
            ),
          ),
          const SizedBox(width: 8),
          if (hasNotesCount > 0) ...[
            ChoiceChip(
              label: Text('📝 Has Notes ($hasNotesCount)'),
              selected: _selectedFilter == 'Has Notes',
              onSelected: (_) => _onFilterSelected('Has Notes'),
              selectedColor: Colors.indigo.shade100,
              backgroundColor: Colors.white,
              visualDensity: VisualDensity.compact,
              side: BorderSide(
                color: _selectedFilter == 'Has Notes'
                    ? Colors.indigo
                    : Colors.grey.shade300,
              ),
              labelStyle: TextStyle(
                color: _selectedFilter == 'Has Notes'
                    ? Colors.indigo.shade900
                    : Colors.grey.shade700,
                fontWeight: _selectedFilter == 'Has Notes'
                    ? FontWeight.bold
                    : FontWeight.normal,
                fontSize: 12,
              ),
            ),
            const SizedBox(width: 8),
          ],
          ...locations.map((loc) {
            final count = _allContacts
                .where((c) =>
                    c.location != null &&
                    c.location!.trim().toLowerCase() == loc.toLowerCase())
                .length;
            final isSelected =
                _selectedFilter.toLowerCase() == loc.toLowerCase();
            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                label: Text('📍 $loc ($count)'),
                selected: isSelected,
                onSelected: (_) => _onFilterSelected(loc),
                selectedColor: Colors.indigo.shade100,
                backgroundColor: Colors.white,
                visualDensity: VisualDensity.compact,
                side: BorderSide(
                  color: isSelected ? Colors.indigo : Colors.grey.shade300,
                ),
                labelStyle: TextStyle(
                  color: isSelected
                      ? Colors.indigo.shade900
                      : Colors.grey.shade700,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                  fontSize: 12,
                ),
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.indigo.shade50,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.people_outline,
                size: 48,
                color: Colors.indigo.shade600,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              _searchQuery.isNotEmpty
                  ? 'No contacts matching "$_searchQuery"'
                  : 'No Contacts in this Center Yet',
              style: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _searchQuery.isNotEmpty
                  ? 'Check your spelling or try searching by location/phone.'
                  : 'Paste your outreach contacts from Apple Notes, WhatsApp, or Excel to populate this Call Center.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
            ),
            const SizedBox(height: 20),
            if (_searchQuery.isEmpty)
              ElevatedButton.icon(
                onPressed: _openImportModal,
                icon: const Icon(Icons.paste),
                label: const Text('Paste Contacts Here'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.indigo.shade700,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 12,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

