import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import 'package:evangelism_caller_id/database/app_database.dart';
import 'package:evangelism_caller_id/models/contact.dart';
import 'package:evangelism_caller_id/screens/contact_detail_modal.dart';
import 'package:evangelism_caller_id/screens/import_modal.dart';
import 'package:evangelism_caller_id/services/caller_id_service.dart';
import 'package:evangelism_caller_id/services/phone_dialer_service.dart';
import 'package:evangelism_caller_id/utils/phone_number_normalizer.dart';

/// HomeScreen
///
/// The central mobile dashboard for church outreach teams:
/// - Real-time search across names, phone numbers, and locations
/// - Fast mobile-first contact cards
/// - Quick import from Notes/Excel
/// - Caller ID system status indicator
class HomeScreen extends StatefulWidget {
  final AppDatabase database;

  const HomeScreen({super.key, required this.database});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  static const _uuid = Uuid();
  List<Contact> _allContacts = [];
  List<Contact> _contacts = [];
  bool _isLoading = true;
  String _searchQuery = '';
  String _selectedFilter = 'All';
  bool _isCallerIdEnabled = false;
  bool _isOverlayEnabled = false;

  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadContacts();
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

  Future<void> _requestCallerId() async {
    final granted = await CallerIdService.requestCallerIdRole();
    if (mounted) {
      _checkCallerIdStatus();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            granted
                ? 'Caller ID permissions granted!'
                : 'Caller ID role was not granted.',
          ),
        ),
      );
    }
  }

  Future<void> _requestOverlay() async {
    await CallerIdService.requestOverlayPermission();
  }

  Future<void> _loadContacts() async {
    final list = _searchQuery.isEmpty
        ? await widget.database.getAllContacts()
        : await widget.database.searchContacts(_searchQuery);

    if (mounted) {
      setState(() {
        _allContacts = list;
        _applyFilter();
        _isLoading = false;
      });
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
        onImportCompleted: _loadContacts,
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
        onDataChanged: _loadContacts,
      ),
    );
  }

  Future<void> _showAddContactDialog() async {
    final nameController = TextEditingController();
    final phoneController = TextEditingController();
    final locationController = TextEditingController();
    final notesController = TextEditingController();

    String? validationError;

    await showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Add Evangelism Contact'),
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

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
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
            const Text(
              'Evangelism Contacts',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 19),
            ),
            Text(
              _allContacts.isEmpty
                  ? '0 outreach contacts'
                  : _selectedFilter == 'All' && _searchQuery.isEmpty
                      ? '${_allContacts.length} outreach ${_allContacts.length == 1 ? "contact" : "contacts"}'
                      : '${_contacts.length} of ${_allContacts.length} contacts',
              style: TextStyle(fontSize: 12, color: Colors.indigo.shade100),
            ),
          ],
        ),
        backgroundColor: Colors.indigo.shade700,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.paste),
            tooltip: 'Paste from Notes',
            onPressed: _openImportModal,
          ),
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: 'Add Single Contact',
            onPressed: _showAddContactDialog,
          ),
        ],
      ),
      body: Column(
        children: [
          // Caller ID & Overlay Status Banner
          _buildStatusBanner(),

          // Search Bar
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 8),
            child: TextField(
              controller: _searchController,
              onChanged: _onSearchChanged,
              decoration: InputDecoration(
                hintText: 'Search by name, number (024...), or area...',
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

          // Contact List or Empty State
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
                              leading: CircleAvatar(
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
                              title: Text(
                                contact.name,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 15,
                                ),
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
                                    icon: const Icon(Icons.phone_outlined, color: Colors.green),
                                    tooltip: 'Call ${contact.name}',
                                    onPressed: () => PhoneDialerService.dial(contact.phoneNumber),
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
                  : 'No Evangelism Contacts Yet',
              style: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _searchQuery.isNotEmpty
                  ? 'Check your spelling or try searching by location/phone.'
                  : 'Paste your outreach contacts from Apple Notes, WhatsApp, or Excel to get started.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
            ),
            const SizedBox(height: 20),
            if (_searchQuery.isEmpty)
              ElevatedButton.icon(
                onPressed: _openImportModal,
                icon: const Icon(Icons.paste),
                label: const Text('Paste from Notes'),
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

  Widget _buildStatusBanner() {
    final bool allActive = _isCallerIdEnabled && _isOverlayEnabled;

    if (allActive) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        color: Colors.teal.shade50,
        child: Row(
          children: [
            Icon(Icons.check_circle, size: 20, color: Colors.teal.shade800),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Floating Caller ID Active on Screen',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Colors.teal.shade900,
                ),
              ),
            ),
          ],
        ),
      );
    }

    if (!_isCallerIdEnabled) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        color: Colors.amber.shade50,
        child: Row(
          children: [
            Icon(Icons.phone_disabled_outlined, size: 20, color: Colors.amber.shade900),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Caller ID Role required to identify callers',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Colors.amber.shade900,
                ),
              ),
            ),
            TextButton(
              onPressed: _requestCallerId,
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                visualDensity: VisualDensity.compact,
              ),
              child: const Text('Enable Role'),
            ),
          ],
        ),
      );
    }

    // Caller ID role is enabled, but overlay permission is missing
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      color: Colors.indigo.shade50,
      child: Row(
        children: [
          Icon(Icons.layers_outlined, size: 20, color: Colors.indigo.shade800),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Enable Floating Screen Card ("Display over apps")',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Colors.indigo.shade900,
              ),
            ),
          ),
          ElevatedButton(
            onPressed: _requestOverlay,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.indigo.shade700,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              visualDensity: VisualDensity.compact,
            ),
            child: const Text('Turn On', style: TextStyle(fontSize: 12)),
          ),
        ],
      ),
    );
  }
}
