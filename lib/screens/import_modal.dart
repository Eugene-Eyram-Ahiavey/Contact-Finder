import 'dart:convert';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:qara/database/app_database.dart';
import 'package:qara/models/contact.dart';
import 'package:qara/services/contact_importer.dart';
import 'package:qara/utils/phone_number_normalizer.dart';

/// ImportNotesModal
///
/// Allows evangelism team members to import outreach contacts into a Call Center via:
/// 1. Picking CSV or Excel (.xlsx) spreadsheet files directly from device storage.
/// 2. Pasting raw text copied from Apple Notes, Google Keep, WhatsApp, or email.
///
/// Provides an interactive preview table where workers can review parsed contacts,
/// fix ambiguous numbers, and batch-save into the local SQLite database.
class ImportNotesModal extends StatefulWidget {
  final AppDatabase database;
  final VoidCallback onImportCompleted;
  final String? callCenterId;
  final String? callCenterName;

  const ImportNotesModal({
    super.key,
    required this.database,
    required this.onImportCompleted,
    this.callCenterId,
    this.callCenterName,
  });

  @override
  State<ImportNotesModal> createState() => _ImportNotesModalState();
}

class _ImportNotesModalState extends State<ImportNotesModal> {
  final TextEditingController _textController = TextEditingController();
  ImportBatchResult? _previewResult;
  bool _isSaving = false;
  bool _isLoadingFile = false;
  String? _errorMessage;
  String? _selectedFileName;

  void _parsePastedText() {
    final text = _textController.text.trim();
    if (text.isEmpty) {
      setState(() {
        _errorMessage = 'Please paste some contact lines or pick a file first.';
        _previewResult = null;
      });
      return;
    }

    final result = ContactImporter.parseText(
      text,
      callCenterId: widget.callCenterId,
    );
    setState(() {
      _previewResult = result;
      _errorMessage = null;
    });
  }

  Future<void> _pickSpreadsheetFile() async {
    setState(() {
      _isLoadingFile = true;
      _errorMessage = null;
    });

    try {
      final files = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['csv', 'xlsx', 'txt'],
      );

      if (files.isEmpty) {
        setState(() => _isLoadingFile = false);
        return;
      }

      final file = files.first;
      final extension = file.extension?.toLowerCase();
      _selectedFileName = file.name;
      final bytes = await file.readAsBytes();

      if (extension == 'xlsx') {
        final parsed = ContactImporter.parseExcelBytes(
          bytes,
          callCenterId: widget.callCenterId,
        );
        setState(() {
          _previewResult = parsed;
          _isLoadingFile = false;
        });
        return;
      }

      // Handle CSV or plain text
      final content = utf8.decode(bytes, allowMalformed: true);
      _textController.text = content;
      final parsed = ContactImporter.parseText(
        content,
        callCenterId: widget.callCenterId,
      );
      setState(() {
        _previewResult = parsed;
        _isLoadingFile = false;
      });
    } catch (e) {
      setState(() {
        _isLoadingFile = false;
        _errorMessage = 'Failed to load file: $e';
      });
    }
  }

  Future<void> _confirmAndSave() async {
    if (_previewResult == null || _previewResult!.validContacts.isEmpty) return;

    setState(() => _isSaving = true);

    int savedCount = 0;
    int duplicateCount = 0;

    for (final contact in _previewResult!.validContacts) {
      try {
        final contactWithCenter = contact.callCenterId != null
            ? contact
            : contact.copyWith(callCenterId: widget.callCenterId);
        await widget.database.insertContact(contactWithCenter);
        savedCount++;
      } on DuplicatePhoneNumberException {
        duplicateCount++;
      } catch (_) {
        // Continue saving remaining
      }
    }

    if (mounted) {
      setState(() => _isSaving = false);
      widget.onImportCompleted();
      Navigator.of(context).pop();

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Saved $savedCount contacts${duplicateCount > 0 ? " ($duplicateCount duplicate numbers skipped)" : ""}',
          ),
          backgroundColor: Colors.teal.shade700,
        ),
      );
    }
  }

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isPreviewing = _previewResult != null;

    return Container(
      height: MediaQuery.of(context).size.height * 0.88,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Drag handle
          Center(
            child: Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),

          // Header
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isPreviewing ? 'Preview Contacts' : 'Import Contacts',
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: Colors.blueGrey.shade900,
                      ),
                    ),
                    if (widget.callCenterName != null)
                      Text(
                        'Target: ${widget.callCenterName}',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.indigo.shade700,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
          const SizedBox(height: 8),

          if (!isPreviewing) ...[
            Text(
              'Pick a CSV or Excel spreadsheet file, or paste your notes directly below. '
              'Names, phone numbers, locations, and notes will be extracted automatically.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: Colors.grey.shade600,
              ),
            ),
            const SizedBox(height: 12),

            // File Upload Action Banner
            InkWell(
              onTap: _isLoadingFile ? null : _pickSpreadsheetFile,
              borderRadius: BorderRadius.circular(12),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                decoration: BoxDecoration(
                  color: Colors.indigo.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.indigo.shade200),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.indigo.shade600,
                        shape: BoxShape.circle,
                      ),
                      child: _isLoadingFile
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                            )
                          : const Icon(Icons.upload_file, color: Colors.white, size: 20),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _selectedFileName ?? 'Upload Spreadsheet File (.csv, .xlsx)',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Colors.indigo.shade900,
                              fontSize: 14,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Auto-detects Name, Phone, Location, and Notes columns',
                            style: TextStyle(
                              color: Colors.indigo.shade700,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Icon(Icons.chevron_right, color: Colors.indigo.shade400),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(child: Divider(color: Colors.grey.shade300)),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  child: Text(
                    'OR PASTE RAW NOTES',
                    style: TextStyle(fontSize: 11, color: Colors.grey.shade500, fontWeight: FontWeight.bold),
                  ),
                ),
                Expanded(child: Divider(color: Colors.grey.shade300)),
              ],
            ),
            const SizedBox(height: 8),

            // Text Input Field
            Expanded(
              child: TextField(
                controller: _textController,
                maxLines: null,
                expands: true,
                textAlignVertical: TextAlignVertical.top,
                decoration: InputDecoration(
                  hintText: 'Paste notes or WhatsApp lines here...\n\nExamples:\n'
                      '• Kofi Mensah - 0244123456 - Tema - Prayed for healing\n'
                      '• Ama Serwaa, 0551122334, Spintex\n'
                      '• 0277889900 - Kwabena (Madina)\n'
                      '• Pastor John: 0201234567',
                  hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 13),
                  filled: true,
                  fillColor: Colors.grey.shade50,
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
            if (_errorMessage != null) ...[
              const SizedBox(height: 8),
              Text(
                _errorMessage!,
                style: const TextStyle(color: Colors.red, fontSize: 12),
              ),
            ],
            const SizedBox(height: 12),
            ElevatedButton.icon(
              onPressed: _parsePastedText,
              icon: const Icon(Icons.table_chart_outlined),
              label: const Text('Parse & Preview Contacts'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.indigo.shade700,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ] else ...[
            // Preview Stats Bar
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _buildStatItem(
                    label: 'Ready to Save',
                    count: _previewResult!.validContacts.length,
                    color: Colors.green.shade700,
                  ),
                  _buildStatItem(
                    label: 'Duplicates',
                    count: _previewResult!.duplicateInBatch.length,
                    color: Colors.orange.shade800,
                  ),
                  _buildStatItem(
                    label: 'Skipped',
                    count: _previewResult!.skippedLines.length,
                    color: Colors.red.shade700,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),

            // Preview Table of Valid Contacts
            Expanded(
              child: _previewResult!.validContacts.isEmpty
                  ? Center(
                      child: Text(
                        'No valid contacts detected in this input.\nCheck that each line contains a valid phone number.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.grey.shade600),
                      ),
                    )
                  : ListView.builder(
                      itemCount: _previewResult!.validContacts.length,
                      itemBuilder: (context, index) {
                        final contact = _previewResult!.validContacts[index];
                        final displayPhone =
                            PhoneNumberNormalizer.formatForDisplay(
                          contact.phoneNumber,
                        );

                        return Card(
                          margin: const EdgeInsets.only(bottom: 8),
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                            side: BorderSide(color: Colors.grey.shade200),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(10),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                CircleAvatar(
                                  radius: 18,
                                  backgroundColor: Colors.indigo.shade50,
                                  child: Text(
                                    contact.name.isNotEmpty
                                        ? contact.name[0].toUpperCase()
                                        : '?',
                                    style: TextStyle(
                                      color: Colors.indigo.shade700,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 14,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        contact.name,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 14,
                                        ),
                                      ),
                                      Text(
                                        displayPhone,
                                        style: TextStyle(
                                          color: Colors.grey.shade700,
                                          fontSize: 12,
                                        ),
                                      ),
                                      if (contact.location != null)
                                        Padding(
                                          padding:
                                              const EdgeInsets.only(top: 2),
                                          child: Text(
                                            '📍 ${contact.location}',
                                            style: TextStyle(
                                              color: Colors.blueGrey.shade600,
                                              fontSize: 11,
                                            ),
                                          ),
                                        ),
                                      if (contact.notes != null)
                                        Padding(
                                          padding:
                                              const EdgeInsets.only(top: 2),
                                          child: Text(
                                            '📝 ${contact.notes}',
                                            style: TextStyle(
                                              color: Colors.grey.shade600,
                                              fontSize: 11,
                                            ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.delete_outline,
                                      size: 18, color: Colors.grey),
                                  onPressed: () {
                                    setState(() {
                                      _previewResult!.validContacts
                                          .removeAt(index);
                                    });
                                  },
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
            const SizedBox(height: 12),

            // Action Buttons
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () {
                      setState(() {
                        _previewResult = null;
                      });
                    },
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text('Back to Paste'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: ElevatedButton.icon(
                    onPressed: (_isSaving ||
                            _previewResult!.validContacts.isEmpty)
                        ? null
                        : _confirmAndSave,
                    icon: _isSaving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.check),
                    label: Text(_isSaving
                        ? 'Saving...'
                        : 'Save ${_previewResult!.validContacts.length} Contacts'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.teal.shade700,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildStatItem({
    required String label,
    required int count,
    required Color color,
  }) {
    return Column(
      children: [
        Text(
          '$count',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: Colors.grey.shade600,
          ),
        ),
      ],
    );
  }
}
