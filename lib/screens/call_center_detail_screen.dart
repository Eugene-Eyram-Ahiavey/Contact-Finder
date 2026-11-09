import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import 'package:qara/database/app_database.dart';
import 'package:qara/models/call_center.dart';
import 'package:qara/models/contact.dart';
import 'package:qara/screens/contact_detail_modal.dart';
import 'package:qara/screens/import_modal.dart';
import 'package:qara/screens/report_preview_screen.dart';
import 'package:qara/services/caller_id_service.dart';
import 'package:qara/services/phone_dialer_service.dart';
import 'package:qara/theme/app_theme.dart';
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
    } else if (_selectedFilter.startsWith('status:')) {
      final statusName = _selectedFilter.substring(7);
      _contacts = _allContacts
          .where((c) =>
              c.callStatus != null &&
              c.callStatus!.trim().toLowerCase() == statusName.toLowerCase())
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

  List<String> get _availableStatuses {
    final statuses = _allContacts
        .map((c) => c.callStatus?.trim())
        .where((st) => st != null && st.isNotEmpty)
        .cast<String>()
        .toSet()
        .toList();
    statuses.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return statuses;
  }

  void _openReportPreview() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ReportPreviewScreen(
          callCenterName: _currentCenter.name,
          contacts: _allContacts,
        ),
      ),
    );
  }

  Color _getStatusColor(String status) {
    final lower = status.toLowerCase();
    if (lower.contains('coming') ||
        lower.contains('confirm') ||
        lower.contains('yes')) {
      return Colors.green.shade700;
    }
    if (lower.contains('not coming') ||
        lower.contains('busy') ||
        lower.contains('sick') ||
        lower.contains('can\'t') ||
        lower.contains('cannot')) {
      return Colors.red.shade700;
    }
    if (lower.contains('no answer') ||
        lower.contains('unreachable') ||
        lower.contains('not reachable') ||
        lower.contains('didn\'t answer') ||
        lower.contains('not answering')) {
      return Colors.orange.shade800;
    }
    if (lower.contains('wrong') ||
        lower.contains('invalid') ||
        lower.contains('incorrect')) {
      return Colors.deepPurple.shade700;
    }
    if (lower.contains('call back') ||
        lower.contains('call again') ||
        lower.contains('later')) {
      return Colors.blue.shade700;
    }
    if (lower.contains('not sure') || lower.contains('maybe')) {
      return Colors.amber.shade900;
    }
    return Colors.blueGrey.shade700;
  }

  Future<void> _showStatusPicker(Contact contact) async {
    final existingStatuses =
        await widget.database.getUniqueStatusesInCallCenter(_currentCenter.id);

    const defaultSuggestions = [
      'Coming',
      'Not Sure',
      'No Answer',
      'Wrong Number',
      'Call Back',
      'Busy',
      'Not Coming',
    ];

    final suggestions = <String>[...existingStatuses];
    for (final def in defaultSuggestions) {
      if (!suggestions.any((s) => s.toLowerCase() == def.toLowerCase())) {
        suggestions.add(def);
      }
    }

    final controller = TextEditingController(text: contact.callStatus ?? '');

    if (!mounted) return;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (modalCtx, setModalState) {
            final currentText = controller.text.trim();
            final bottomInset = MediaQuery.of(modalCtx).viewInsets.bottom;

            return Padding(
              padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + bottomInset),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        CircleAvatar(
                          radius: 16,
                          backgroundColor: Colors.indigo.shade50,
                          child: Text(
                            contact.name.isNotEmpty
                                ? contact.name[0].toUpperCase()
                                : '?',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              color: Colors.indigo.shade700,
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                contact.name,
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              Text(
                                PhoneNumberNormalizer.formatForDisplay(
                                    contact.phoneNumber),
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey.shade600,
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: () => Navigator.of(ctx).pop(),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Call Outcome / Status',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: Colors.grey.shade700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: controller,
                      autofocus: contact.callStatus == null,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: InputDecoration(
                        hintText: 'e.g. Coming, Invalid Number, Call Back...',
                        filled: true,
                        fillColor: Colors.grey.shade50,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 12,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide(color: Colors.grey.shade300),
                        ),
                        suffixIcon: currentText.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear, size: 18),
                                onPressed: () {
                                  controller.clear();
                                  setModalState(() {});
                                },
                              )
                            : null,
                      ),
                      onChanged: (_) => setModalState(() {}),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Suggestions',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: Colors.grey.shade500,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: suggestions.map((status) {
                        final isSelected =
                            currentText.toLowerCase() == status.toLowerCase();
                        return FilterChip(
                          label: Text(status),
                          selected: isSelected,
                          onSelected: (selected) {
                            setModalState(() {
                              controller.text = selected ? status : '';
                            });
                          },
                          selectedColor: Colors.indigo.shade100,
                          labelStyle: TextStyle(
                            fontSize: 12,
                            fontWeight: isSelected
                                ? FontWeight.bold
                                : FontWeight.normal,
                            color: isSelected
                                ? Colors.indigo.shade900
                                : Colors.grey.shade800,
                          ),
                          backgroundColor: Colors.grey.shade100,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                            side: BorderSide(
                              color: isSelected
                                  ? Colors.indigo.shade400
                                  : Colors.grey.shade300,
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        if (contact.callStatus != null &&
                            contact.callStatus!.trim().isNotEmpty) ...[
                          OutlinedButton.icon(
                            onPressed: () async {
                              await widget.database
                                  .updateContactStatus(contact.id, null);
                              if (ctx.mounted) Navigator.of(ctx).pop();
                              _loadContacts();
                              widget.onCenterUpdated();
                            },
                            icon: const Icon(Icons.delete_outline, size: 16),
                            label: const Text('Clear'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.red.shade600,
                              side: BorderSide(color: Colors.red.shade200),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 12,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                        ],
                        Expanded(
                          child: ElevatedButton(
                            onPressed: () async {
                              final newStatus = controller.text.trim();
                              await widget.database.updateContactStatus(
                                contact.id,
                                newStatus.isEmpty ? null : newStatus,
                              );
                              if (ctx.mounted) Navigator.of(ctx).pop();
                              _loadContacts();
                              widget.onCenterUpdated();
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.indigo.shade700,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                            child: const Text(
                              'Save Status',
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
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
    ).then((_) {
      // Re-sync after closing contact detail in case status was updated
      _syncCallDirectory();
    });
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
    final locationController =
        TextEditingController(text: _currentCenter.location ?? '');
    final descController =
        TextEditingController(text: _currentCenter.description ?? '');

    const themePalette = [
      '#3F51B5', // Indigo
      '#00897B', // Teal
      '#D81B60', // Rose / Pink
      '#5E35B1', // Deep Purple
      '#008AEC', // Electric Blue
    ];
    String selectedColor = _currentCenter.colorHex ?? themePalette.first;

    await showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (dialogCtx, setDialogState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              title: const Text('Edit Call Center'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(
                      controller: nameController,
                      decoration: const InputDecoration(
                        labelText: 'Call Center Name',
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: locationController,
                      decoration: const InputDecoration(
                        labelText: 'Target Area / Location',
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: descController,
                      maxLines: 2,
                      decoration: const InputDecoration(
                        labelText: 'Description / Notes',
                      ),
                    ),
                    const SizedBox(height: 14),
                    const Text(
                      'Theme Color',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      children: themePalette.map((colorHex) {
                        final color = Color(
                          int.parse(colorHex.replaceAll('#', '0xff')),
                        );
                        final isSelected = selectedColor == colorHex;

                        return GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () {
                            setDialogState(() => selectedColor = colorHex);
                          },
                          child: Container(
                            padding: const EdgeInsets.all(4),
                            child: Container(
                              width: 30,
                              height: 30,
                              decoration: BoxDecoration(
                                color: color,
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: isSelected
                                      ? AppColors.brandDarkTeal
                                      : Colors.transparent,
                                  width: 2.8,
                                ),
                                boxShadow: [
                                  if (isSelected)
                                    BoxShadow(
                                      color: color.withOpacity(0.5),
                                      blurRadius: 6,
                                      offset: const Offset(0, 2),
                                    ),
                                ],
                              ),
                            ),
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
                      colorHex: selectedColor,
                      updatedAt: DateTime.now(),
                    );

                    await widget.database.updateCallCenter(updated);
                    if (mounted) {
                      setState(() => _currentCenter = updated);
                      widget.onCenterUpdated();
                      Navigator.of(ctx).pop();
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.brandDarkTeal,
                    foregroundColor: Colors.white,
                  ),
                  child: const Text('Save Changes'),
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
    _searchController.dispose();
    super.dispose();
  }

  LinearGradient _getHeaderGradient(Color baseColor) {
    final hsl = HSLColor.fromColor(baseColor);
    final topColor =
        hsl.withLightness((hsl.lightness - 0.06).clamp(0.0, 1.0)).toColor();
    final bottomColor =
        hsl.withLightness((hsl.lightness + 0.08).clamp(0.0, 1.0)).toColor();
    return LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [topColor, bottomColor],
    );
  }

  @override
  Widget build(BuildContext context) {
    final centerColor = _currentCenter.colorHex != null
        ? Color(int.parse(_currentCenter.colorHex!.replaceAll('#', '0xff')))
        : AppColors.brandDarkTeal;

    return Scaffold(
      backgroundColor: AppColors.mintBackgroundCenter,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
          tooltip: 'Back',
          onPressed: () => Navigator.of(context).pop(),
        ),
        titleSpacing: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _currentCenter.name,
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 18,
                color: Colors.white,
                letterSpacing: -0.2,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              '${_allContacts.length} Contacts',
              style: TextStyle(
                fontSize: 11,
                color: Colors.white.withOpacity(0.85),
                fontWeight: FontWeight.w400,
              ),
            ),
          ],
        ),
        flexibleSpace: Container(
          decoration: BoxDecoration(
            gradient: _getHeaderGradient(centerColor),
          ),
        ),
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          if (_allContacts.isNotEmpty) ...[
            IconButton(
              icon: const Icon(Icons.person_add_alt_1_outlined),
              tooltip: 'Add Contact',
              onPressed: _showAddContactDialog,
            ),
            IconButton(
              icon: const Icon(Icons.content_paste_outlined),
              tooltip: 'Paste / Import Contacts',
              onPressed: _openImportModal,
            ),
          ],
          PopupMenuButton<String>(
            icon: Icon(Icons.more_vert, color: Colors.white.withOpacity(0.9)),
            onSelected: (val) {
              if (val == 'report') {
                _openReportPreview();
              } else if (val == 'edit') {
                _showEditCenterDialog();
              } else if (val == 'import') {
                _openImportModal();
              }
            },
            itemBuilder: (ctx) => [
              const PopupMenuItem(
                value: 'report',
                child: Row(
                  children: [
                    Icon(Icons.assessment_outlined, size: 20),
                    SizedBox(width: 8),
                    Text('Generate Call Report'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'import',
                child: Row(
                  children: [
                    Icon(Icons.content_paste_outlined, size: 20),
                    SizedBox(width: 8),
                    Text('Import / Paste Contacts'),
                  ],
                ),
              ),
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
      body: Container(
        decoration: const BoxDecoration(
          gradient: AppColors.welcomeGradient,
        ),
        child: Column(
          children: [
            // In-Center Pill Search Bar (Screen 1 & 5)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: const Color(0xFFCDE2DE),
                    width: 1.0,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.03),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: TextField(
                  controller: _searchController,
                  onChanged: _onSearchChanged,
                  style: const TextStyle(
                    fontSize: 14,
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w500,
                  ),
                  decoration: InputDecoration(
                    hintText: 'Search in ${_currentCenter.name}...',
                    hintStyle: const TextStyle(
                      color: Color(0xFF7A8E92),
                      fontSize: 14,
                      fontWeight: FontWeight.w400,
                    ),
                    prefixIcon: const Icon(
                      Icons.search_rounded,
                      color: Color(0xFF4A6469),
                      size: 20,
                    ),
                    suffixIcon: _searchQuery.isNotEmpty
                        ? IconButton(
                            icon: const Icon(
                              Icons.clear,
                              size: 18,
                              color: Color(0xFF7A8E92),
                            ),
                            onPressed: () {
                              _searchController.clear();
                              _onSearchChanged('');
                            },
                          )
                        : null,
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
            ),

            // Location & Notes Filter Chips (Only shown when contacts exist)
            _buildFilterChips(),

            // Contacts List / Empty State
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
                                  Flexible(
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
                                      margin: const EdgeInsets.only(left: 6),
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
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const SizedBox(height: 2),
                                  Text(
                                    displayPhone,
                                    style: TextStyle(
                                      color: Colors.grey.shade600,
                                      fontSize: 13,
                                    ),
                                  ),
                                  const SizedBox(height: 5),
                                  Wrap(
                                    spacing: 6,
                                    runSpacing: 4,
                                    crossAxisAlignment: WrapCrossAlignment.center,
                                    children: [
                                      // Call Status Badge (Tappable to set / update status)
                                      InkWell(
                                        onTap: () => _showStatusPicker(contact),
                                        borderRadius: BorderRadius.circular(4),
                                        child: contact.callStatus != null &&
                                                contact.callStatus!.trim().isNotEmpty
                                            ? Container(
                                                padding: const EdgeInsets.symmetric(
                                                  horizontal: 6,
                                                  vertical: 2,
                                                ),
                                                decoration: BoxDecoration(
                                                  color: _getStatusColor(contact.callStatus!)
                                                      .withOpacity(0.1),
                                                  borderRadius: BorderRadius.circular(4),
                                                  border: Border.all(
                                                    color: _getStatusColor(contact.callStatus!)
                                                        .withOpacity(0.35),
                                                  ),
                                                ),
                                                child: Row(
                                                  mainAxisSize: MainAxisSize.min,
                                                  children: [
                                                    Icon(
                                                      Icons.bookmark,
                                                      size: 11,
                                                      color: _getStatusColor(contact.callStatus!),
                                                    ),
                                                    const SizedBox(width: 3),
                                                    Text(
                                                      contact.callStatus!,
                                                      style: TextStyle(
                                                        fontSize: 11,
                                                        color: _getStatusColor(contact.callStatus!),
                                                        fontWeight: FontWeight.bold,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              )
                                            : Container(
                                                padding: const EdgeInsets.symmetric(
                                                  horizontal: 6,
                                                  vertical: 2,
                                                ),
                                                decoration: BoxDecoration(
                                                  color: Colors.grey.shade100,
                                                  borderRadius: BorderRadius.circular(4),
                                                  border: Border.all(
                                                    color: Colors.grey.shade300,
                                                  ),
                                                ),
                                                child: Row(
                                                  mainAxisSize: MainAxisSize.min,
                                                  children: [
                                                    Icon(
                                                      Icons.add_task,
                                                      size: 11,
                                                      color: Colors.grey.shade600,
                                                    ),
                                                    const SizedBox(width: 3),
                                                    Text(
                                                      'Add Status',
                                                      style: TextStyle(
                                                        fontSize: 10,
                                                        color: Colors.grey.shade600,
                                                        fontWeight: FontWeight.w500,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                      ),
                                      if (contact.location != null && contact.location!.isNotEmpty)
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 6,
                                            vertical: 2,
                                          ),
                                          decoration: BoxDecoration(
                                            color: Colors.blueGrey.shade50,
                                            borderRadius: BorderRadius.circular(4),
                                          ),
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Icon(
                                                Icons.location_on_outlined,
                                                size: 11,
                                                color: Colors.blueGrey.shade700,
                                              ),
                                              const SizedBox(width: 3),
                                              Text(
                                                contact.location!,
                                                style: TextStyle(
                                                  fontSize: 11,
                                                  color: Colors.blueGrey.shade800,
                                                  fontWeight: FontWeight.w500,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      if (contact.notes != null && contact.notes!.isNotEmpty)
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 6,
                                            vertical: 2,
                                          ),
                                          decoration: BoxDecoration(
                                            color: Colors.amber.shade50,
                                            borderRadius: BorderRadius.circular(4),
                                          ),
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Icon(
                                                Icons.notes_outlined,
                                                size: 11,
                                                color: Colors.amber.shade900,
                                              ),
                                              const SizedBox(width: 3),
                                              Text(
                                                contact.notes!,
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: TextStyle(
                                                  fontSize: 11,
                                                  color: Colors.amber.shade900,
                                                  fontWeight: FontWeight.w500,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                    ],
                                  ),
                                ],
                              ),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
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
    ),
    floatingActionButton: _contacts.isEmpty
          ? null
          : FloatingActionButton.extended(
              onPressed: _openImportModal,
              backgroundColor: centerColor,
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
          ..._availableStatuses.map((status) {
            final count = _allContacts
                .where((c) =>
                    c.callStatus != null &&
                    c.callStatus!.trim().toLowerCase() == status.toLowerCase())
                .length;
            final filterKey = 'status:$status';
            final isSelected = _selectedFilter == filterKey;
            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                label: Text('🏷️ $status ($count)'),
                selected: isSelected,
                onSelected: (_) =>
                    _onFilterSelected(isSelected ? 'All' : filterKey),
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
    if (_searchQuery.isNotEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                  border: Border.all(color: const Color(0xFFD6E8E6)),
                ),
                child: const Icon(
                  Icons.search_off_rounded,
                  size: 44,
                  color: Color(0xFF7A8E92),
                ),
              ),
              const SizedBox(height: 18),
              Text(
                'No contacts matching "$_searchQuery"',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Check your spelling or try searching by phone number or location.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
              ),
            ],
          ),
        ),
      );
    }

    // Figma Screen 1: Call Center Workspace Empty State
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Soft mint circle with two-person user group icon
            Container(
              width: 84,
              height: 84,
              decoration: const BoxDecoration(
                color: Color(0xFFD4F5E9),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.people_outline_rounded,
                size: 42,
                color: Color(0xFF229E64),
              ),
            ),
            const SizedBox(height: 24),
            // Headline: "No Contacts here yet"
            const Text(
              'No Contacts here yet',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 19,
                fontWeight: FontWeight.w700,
                color: Color(0xFF102024),
                letterSpacing: -0.2,
              ),
            ),
            const SizedBox(height: 12),
            // Subtitle
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 320),
              child: const Text(
                'Add a Contact or Paste your outreach contacts from Apple Notes, WhatsApp, or Excel to populate this Call Center.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w400,
                  color: Color(0xFF5A6E73),
                  height: 1.45,
                ),
              ),
            ),
            const SizedBox(height: 32),
            // Stacked Action Pill Buttons
            // 1. Add Contact button (Obsidian Dark Teal)
            ElevatedButton.icon(
              onPressed: _showAddContactDialog,
              icon: const Icon(
                Icons.person_add_alt_1_outlined,
                size: 18,
                color: Colors.white,
              ),
              label: const Text(
                'Add Contact',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                  letterSpacing: 0.1,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF10222C),
                foregroundColor: Colors.white,
                elevation: 4,
                shadowColor: const Color(0xFF10222C).withOpacity(0.35),
                padding:
                    const EdgeInsets.symmetric(horizontal: 26, vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(24),
                ),
              ),
            ),
            const SizedBox(height: 14),
            // 2. Upload/Paste Contacts button (Slate Teal)
            ElevatedButton.icon(
              onPressed: _openImportModal,
              icon: const Icon(
                Icons.content_paste_outlined,
                size: 18,
                color: Colors.white,
              ),
              label: const Text(
                'Upload/Paste Contacts',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                  letterSpacing: 0.1,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF164756),
                foregroundColor: Colors.white,
                elevation: 3,
                shadowColor: const Color(0xFF164756).withOpacity(0.3),
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(24),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

