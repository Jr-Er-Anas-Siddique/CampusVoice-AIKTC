// lib/features/report/presentation/pages/report_issue_page.dart
//
// Design matches login/signup pages:
// Primary: Color(0xFF1A237E), Background: Color(0xFFF5F7FF)
// Cards: white, borderRadius 20, shadow indigo 0.08
// Inputs: fillColor 0xFFF8F9FF, borderRadius 12, focused border 1A237E
// Buttons: height 52, borderRadius 14, backgroundColor 1A237E

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:geolocator/geolocator.dart';
import '../../../../models/post_model.dart';
import '../../../../services/post_service.dart';
import '../../../../config/campus_locations.dart';
import '../../../../config/complaint_categories.dart';
import '../../../../core/utils/campus_boundary.dart';

// Replace with your actual auth service import
import '../../../../services/auth_service.dart';

class ReportIssuePage extends StatefulWidget {
  /// Pass an existing draft to edit it, or null to create new.
  final PostModel? existingDraft;

  const ReportIssuePage({super.key, this.existingDraft});

  @override
  State<ReportIssuePage> createState() => _ReportIssuePageState();
}

class _ReportIssuePageState extends State<ReportIssuePage> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _roomController = TextEditingController();

  // Selections
  ComplaintCategory? _selectedCategory;
  String? _selectedBuilding;
  String? _selectedFloor;

  // Images
  final List<File> _selectedImages = [];
  static const int _maxImages = 3;

  // GPS
  GpsCoordinates? _gpsCoordinates;
  bool? _isOnCampus;
  bool _isCapturingGps = false;
  String? _gpsError;

  // State
  bool _isSubmitting = false;
  bool _isSavingDraft = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _populateFromDraft();
  }

  void _populateFromDraft() {
    final draft = widget.existingDraft;
    if (draft == null) return;

    _titleController.text = draft.title;
    _descriptionController.text = draft.description;
    _roomController.text = draft.roomNumber ?? '';
    _selectedCategory = draft.category;
    _selectedBuilding = draft.building.isEmpty ? null : draft.building;
    _selectedFloor = draft.floor;
    _gpsCoordinates = draft.gpsCoordinates;
    _isOnCampus = draft.isOnCampus;
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _roomController.dispose();
    super.dispose();
  }

  // ─── Helpers ──────────────────────────────────────────────────────────────

  bool get _isOutdoor =>
      _selectedBuilding != null &&
      CampusLocations.isOutdoor(_selectedBuilding!);

  bool get _requiresGps =>
      _selectedCategory != null &&
      ComplaintCategories.requiresGps(_selectedCategory!);

  bool get _cameraOnly =>
      _selectedCategory != null &&
      ComplaintCategories.cameraOnly(_selectedCategory!);

  bool get _gpsVerified => _gpsCoordinates != null && _isOnCampus == true;

  // ─── GPS ──────────────────────────────────────────────────────────────────

  Future<void> _captureGps() async {
    setState(() {
      _isCapturingGps = true;
      _gpsError = null;
    });

    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        setState(() => _gpsError = 'Location services are disabled. Please enable GPS.');
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          setState(() => _gpsError = 'Location permission denied.');
          return;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        setState(() =>
            _gpsError = 'Location permission permanently denied. Enable in settings.');
        return;
      }

      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      final coords = GpsCoordinates(
        latitude: position.latitude,
        longitude: position.longitude,
        accuracy: position.accuracy,
      );

      final onCampus =
          CampusBoundary.isOnCampus(position.latitude, position.longitude);

      setState(() {
        _gpsCoordinates = coords;
        _isOnCampus = onCampus;
        _gpsError = onCampus
            ? null
            : 'You appear to be outside the campus boundary. Infrastructure complaints must be filed on campus.';
      });
    } catch (e) {
      setState(() => _gpsError = 'Failed to get location: $e');
    } finally {
      if (mounted) setState(() => _isCapturingGps = false);
    }
  }

  // ─── Image picker ─────────────────────────────────────────────────────────

  Future<void> _pickImage(ImageSource source) async {
    if (_selectedImages.length >= _maxImages) {
      _showSnack('Maximum $_maxImages images allowed.');
      return;
    }

    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source: source,
      imageQuality: 80,
      maxWidth: 1920,
    );

    if (picked != null) {
      setState(() => _selectedImages.add(File(picked.path)));
    }
  }

  void _removeImage(int index) {
    setState(() => _selectedImages.removeAt(index));
  }

  void _showImageSourceSheet() {
    if (_cameraOnly) {
      _pickImage(ImageSource.camera);
      return;
    }

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 16),
              ListTile(
                leading: const Icon(Icons.camera_alt_rounded,
                    color: Color(0xFF1A237E)),
                title: const Text('Take Photo'),
                onTap: () {
                  Navigator.pop(context);
                  _pickImage(ImageSource.camera);
                },
              ),
              ListTile(
                leading: const Icon(Icons.photo_library_rounded,
                    color: Color(0xFF1A237E)),
                title: const Text('Choose from Gallery'),
                onTap: () {
                  Navigator.pop(context);
                  _pickImage(ImageSource.gallery);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ─── Validation ───────────────────────────────────────────────────────────

  String? _validate() {
    if (_selectedCategory == null) return 'Please select a complaint category.';
    if (_selectedBuilding == null) return 'Please select a location.';
    if (!_isOutdoor && _selectedFloor == null) {
      return 'Please select a floor for indoor locations.';
    }
    if (_requiresGps && !_gpsVerified) {
      return 'Infrastructure complaints require GPS verification on campus.';
    }
    return null;
  }

  // ─── Build draft ──────────────────────────────────────────────────────────

  PostModel _buildPost({required ComplaintStatus status}) {
    final user = AuthService.instance.currentUser!;
    final now = DateTime.now();

    return PostModel(
      id: widget.existingDraft?.id,
      userId: user.uid,
      userEmail: user.email ?? '',
      userName: user.displayName ?? '',
      title: _titleController.text.trim(),
      description: _descriptionController.text.trim(),
      category: _selectedCategory!,
      building: _selectedBuilding!,
      floor: _isOutdoor ? null : _selectedFloor,
      roomNumber: _roomController.text.trim().isEmpty
          ? null
          : _roomController.text.trim(),
      imageUrls: widget.existingDraft?.imageUrls ?? [],
      localImagePaths: _selectedImages.map((f) => f.path).toList(),
      gpsCoordinates: _gpsCoordinates,
      isOnCampus: _isOnCampus,
      status: status,
      createdAt: widget.existingDraft?.createdAt ?? now,
      updatedAt: now,
    );
  }

  // ─── Actions ──────────────────────────────────────────────────────────────

  Future<void> _saveDraft() async {
    if (_selectedCategory == null && _selectedBuilding == null &&
        _titleController.text.trim().isEmpty) {
      _showSnack('Nothing to save yet.');
      return;
    }

    // Use defaults if incomplete
    final category = _selectedCategory ?? ComplaintCategory.other;
    final building = _selectedBuilding ?? CampusLocations.allLocations.first;

    setState(() => _isSavingDraft = true);

    try {
      final draft = PostModel(
        id: widget.existingDraft?.id,
        userId: AuthService.instance.currentUser!.uid,
        userEmail: AuthService.instance.currentUser!.email ?? '',
        userName: AuthService.instance.currentUser!.displayName ?? '',
        title: _titleController.text.trim(),
        description: _descriptionController.text.trim(),
        category: category,
        building: building,
        floor: _selectedFloor,
        roomNumber: _roomController.text.trim().isEmpty
            ? null
            : _roomController.text.trim(),
        localImagePaths: _selectedImages.map((f) => f.path).toList(),
        gpsCoordinates: _gpsCoordinates,
        isOnCampus: _isOnCampus,
        status: ComplaintStatus.draft,
        createdAt: widget.existingDraft?.createdAt ?? DateTime.now(),
        updatedAt: DateTime.now(),
      );

      await PostService.instance.saveDraft(draft);
      if (mounted) {
        _showSnack('Draft saved successfully.', isSuccess: true);
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      setState(() => _errorMessage = e.toString());
    } finally {
      if (mounted) setState(() => _isSavingDraft = false);
    }
  }

  Future<void> _submit() async {
    setState(() => _errorMessage = null);

    if (!_formKey.currentState!.validate()) return;

    final validationError = _validate();
    if (validationError != null) {
      setState(() => _errorMessage = validationError);
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      final post = _buildPost(status: ComplaintStatus.submitted);
      await PostService.instance.submitComplaint(
        post: post,
        imageFiles: _selectedImages,
      );

      if (mounted) {
        _showSnack('Complaint submitted successfully!', isSuccess: true);
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      setState(() => _errorMessage = e.toString());
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  void _showSnack(String message, {bool isSuccess = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isSuccess ? Colors.green.shade700 : Colors.red.shade700,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  // ─── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.existingDraft != null;

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FF),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1A237E),
        foregroundColor: Colors.white,
        elevation: 0,
        title: Text(
          isEditing ? 'Edit Draft' : 'Report an Issue',
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 18),
        ),
        actions: [
          TextButton.icon(
            onPressed: (_isSavingDraft || _isSubmitting) ? null : _saveDraft,
            icon: _isSavingDraft
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                        color: Colors.white, strokeWidth: 2),
                  )
                : const Icon(Icons.save_outlined, color: Colors.white, size: 18),
            label: const Text('Save Draft',
                style: TextStyle(color: Colors.white, fontSize: 13)),
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Error banner
              if (_errorMessage != null) ...[
                _ErrorBanner(message: _errorMessage!),
                const SizedBox(height: 16),
              ],

              // Section 1: Basic Info
              _SectionCard(
                title: 'Issue Details',
                icon: Icons.report_problem_outlined,
                children: [
                  _FieldLabel('Title'),
                  const SizedBox(height: 6),
                  TextFormField(
                    controller: _titleController,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: _inputDeco(
                      hint: 'Brief title of the issue',
                      icon: Icons.title_rounded,
                    ),
                    validator: (v) => (v == null || v.trim().length < 5)
                        ? 'Title must be at least 5 characters.'
                        : null,
                  ),
                  const SizedBox(height: 16),
                  _FieldLabel('Description'),
                  const SizedBox(height: 6),
                  TextFormField(
                    controller: _descriptionController,
                    maxLines: 4,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: _inputDeco(
                      hint: 'Describe the issue in detail...',
                      icon: Icons.description_outlined,
                    ),
                    validator: (v) => (v == null || v.trim().length < 10)
                        ? 'Description must be at least 10 characters.'
                        : null,
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Section 2: Category
              _SectionCard(
                title: 'Category',
                icon: Icons.category_outlined,
                children: [
                  _FieldLabel('Complaint Category'),
                  const SizedBox(height: 10),
                  _CategoryGrid(
                    selected: _selectedCategory,
                    onSelected: (cat) {
                      setState(() {
                        _selectedCategory = cat;
                        // Reset GPS if not infrastructure
                        if (!ComplaintCategories.requiresGps(cat)) {
                          _gpsCoordinates = null;
                          _isOnCampus = null;
                          _gpsError = null;
                        }
                        // Clear images if switching away from infra
                        if (!ComplaintCategories.cameraOnly(cat)) {
                          _selectedImages.clear();
                        }
                      });
                    },
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Section 3: Location
              _SectionCard(
                title: 'Location',
                icon: Icons.location_on_outlined,
                children: [
                  _FieldLabel('Building / Area'),
                  const SizedBox(height: 6),
                  _StyledDropdown<String>(
                    value: _selectedBuilding,
                    hint: 'Select location',
                    icon: Icons.apartment_rounded,
                    items: [
                      const DropdownMenuItem(
                        enabled: false,
                        value: null,
                        child: Text('── Indoor Buildings ──',
                            style: TextStyle(
                                color: Colors.grey,
                                fontSize: 12,
                                fontStyle: FontStyle.italic)),
                      ),
                      ...CampusLocations.indoorBuildings.map((b) =>
                          DropdownMenuItem(value: b, child: Text(b))),
                      const DropdownMenuItem(
                        enabled: false,
                        value: null,
                        child: Text('── Outdoor Areas ──',
                            style: TextStyle(
                                color: Colors.grey,
                                fontSize: 12,
                                fontStyle: FontStyle.italic)),
                      ),
                      ...CampusLocations.outdoorAreas.map((b) =>
                          DropdownMenuItem(value: b, child: Text(b))),
                    ],
                    onChanged: (val) {
                      setState(() {
                        _selectedBuilding = val;
                        _selectedFloor = null;
                      });
                    },
                  ),

                  // Floor — only for indoor
                  if (_selectedBuilding != null && !_isOutdoor) ...[
                    const SizedBox(height: 16),
                    _FieldLabel('Floor'),
                    const SizedBox(height: 6),
                    _StyledDropdown<String>(
                      value: _selectedFloor,
                      hint: 'Select floor',
                      icon: Icons.layers_outlined,
                      items: CampusLocations.floors
                          .map((f) => DropdownMenuItem(value: f, child: Text(f)))
                          .toList(),
                      onChanged: (val) => setState(() => _selectedFloor = val),
                    ),
                  ],

                  // Room (optional, indoor only)
                  if (_selectedBuilding != null && !_isOutdoor) ...[
                    const SizedBox(height: 16),
                    _FieldLabel('Room Number (Optional)'),
                    const SizedBox(height: 6),
                    TextFormField(
                      controller: _roomController,
                      decoration: _inputDeco(
                        hint: 'e.g. 204, Lab 3',
                        icon: Icons.door_back_door_outlined,
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 16),

              // Section 4: GPS (Infrastructure only)
              if (_requiresGps) ...[
                _SectionCard(
                  title: 'GPS Verification',
                  icon: Icons.my_location_rounded,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.amber.shade50,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.amber.shade300),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.info_outline,
                              color: Colors.amber.shade700, size: 18),
                          const SizedBox(width: 10),
                          const Expanded(
                            child: Text(
                              'Infrastructure complaints require GPS verification to confirm you are on campus.',
                              style: TextStyle(fontSize: 12),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),

                    // GPS Status
                    if (_gpsCoordinates != null) ...[
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: _isOnCampus == true
                              ? Colors.green.shade50
                              : Colors.red.shade50,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                              color: _isOnCampus == true
                                  ? Colors.green.shade300
                                  : Colors.red.shade300),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              _isOnCampus == true
                                  ? Icons.check_circle_outline
                                  : Icons.cancel_outlined,
                              color: _isOnCampus == true
                                  ? Colors.green.shade700
                                  : Colors.red.shade700,
                              size: 18,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    _isOnCampus == true
                                        ? 'On campus verified ✓'
                                        : 'Outside campus boundary',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 13,
                                      color: _isOnCampus == true
                                          ? Colors.green.shade700
                                          : Colors.red.shade700,
                                    ),
                                  ),
                                  Text(
                                    'Lat: ${_gpsCoordinates!.latitude.toStringAsFixed(6)}, '
                                    'Lng: ${_gpsCoordinates!.longitude.toStringAsFixed(6)}',
                                    style: TextStyle(
                                        fontSize: 11,
                                        color: Colors.grey.shade600),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 10),
                    ],

                    if (_gpsError != null) ...[
                      _ErrorBanner(message: _gpsError!),
                      const SizedBox(height: 10),
                    ],

                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: OutlinedButton.icon(
                        onPressed: _isCapturingGps ? null : _captureGps,
                        icon: _isCapturingGps
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Color(0xFF1A237E)),
                              )
                            : const Icon(Icons.gps_fixed_rounded),
                        label: Text(_gpsCoordinates != null
                            ? 'Re-capture GPS'
                            : 'Capture GPS Location'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFF1A237E),
                          side: const BorderSide(color: Color(0xFF1A237E)),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
              ],

              // Section 5: Evidence Images
              _SectionCard(
                title: 'Evidence Images',
                icon: Icons.photo_camera_outlined,
                children: [
                  if (_cameraOnly)
                    Container(
                      padding: const EdgeInsets.all(10),
                      margin: const EdgeInsets.only(bottom: 12),
                      decoration: BoxDecoration(
                        color: Colors.blue.shade50,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.blue.shade200),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.camera_alt_outlined,
                              color: Colors.blue.shade700, size: 16),
                          const SizedBox(width: 8),
                          Text(
                            'Infrastructure: camera capture only.',
                            style: TextStyle(
                                fontSize: 12, color: Colors.blue.shade700),
                          ),
                        ],
                      ),
                    ),

                  // Image grid
                  if (_selectedImages.isNotEmpty) ...[
                    GridView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: _selectedImages.length,
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 3,
                        crossAxisSpacing: 8,
                        mainAxisSpacing: 8,
                      ),
                      itemBuilder: (ctx, i) => _ImageTile(
                        file: _selectedImages[i],
                        onRemove: () => _removeImage(i),
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],

                  // Add image button
                  if (_selectedImages.length < _maxImages)
                    GestureDetector(
                      onTap: _selectedCategory == null
                          ? () => _showSnack('Select a category first.')
                          : _showImageSourceSheet,
                      child: Container(
                        height: 80,
                        decoration: BoxDecoration(
                          color: const Color(0xFFF8F9FF),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: Colors.grey.shade300,
                            style: BorderStyle.solid,
                          ),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.add_photo_alternate_outlined,
                                color: Colors.grey.shade500, size: 24),
                            const SizedBox(width: 8),
                            Text(
                              'Add Photo (${_selectedImages.length}/$_maxImages)',
                              style: TextStyle(
                                  color: Colors.grey.shade500, fontSize: 13),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 28),

              // Submit button
              SizedBox(
                height: 52,
                child: ElevatedButton(
                  onPressed: (_isSubmitting || _isSavingDraft) ? null : _submit,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1A237E),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                    elevation: 2,
                  ),
                  child: _isSubmitting
                      ? const SizedBox(
                          height: 22,
                          width: 22,
                          child: CircularProgressIndicator(
                              color: Colors.white, strokeWidth: 2.5),
                        )
                      : const Text(
                          'Submit Complaint',
                          style: TextStyle(
                              fontSize: 16, fontWeight: FontWeight.w600),
                        ),
                ),
              ),
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }

  InputDecoration _inputDeco({required String hint, required IconData icon}) {
    return InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 14),
      prefixIcon: Icon(icon, size: 20, color: Colors.grey.shade500),
      filled: true,
      fillColor: const Color(0xFFF8F9FF),
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.grey.shade200)),
      enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.grey.shade200)),
      focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFF1A237E), width: 1.5)),
      errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Colors.redAccent)),
      focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Colors.redAccent, width: 1.5)),
    );
  }
}

// ─── Reusable Widgets ─────────────────────────────────────────────────────────

class _SectionCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final List<Widget> children;

  const _SectionCard({
    required this.title,
    required this.icon,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.indigo.withOpacity(0.08),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFFE8EAF6),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, size: 18, color: const Color(0xFF1A237E)),
              ),
              const SizedBox(width: 10),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF1A237E),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Divider(height: 1),
          const SizedBox(height: 16),
          ...children,
        ],
      ),
    );
  }
}

class _FieldLabel extends StatelessWidget {
  final String label;
  const _FieldLabel(this.label);

  @override
  Widget build(BuildContext context) => Text(
        label,
        style: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: Color(0xFF37474F),
        ),
      );
}

class _ErrorBanner extends StatelessWidget {
  final String message;
  const _ErrorBanner({required this.message});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.red.shade50,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.red.shade200),
        ),
        child: Row(
          children: [
            Icon(Icons.error_outline, color: Colors.red.shade700, size: 18),
            const SizedBox(width: 10),
            Expanded(
              child: Text(message,
                  style:
                      TextStyle(color: Colors.red.shade700, fontSize: 13)),
            ),
          ],
        ),
      );
}

class _CategoryGrid extends StatelessWidget {
  final ComplaintCategory? selected;
  final ValueChanged<ComplaintCategory> onSelected;

  const _CategoryGrid({required this.selected, required this.onSelected});

  @override
  Widget build(BuildContext context) {
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisSpacing: 10,
      mainAxisSpacing: 10,
      childAspectRatio: 2.8,
      children: ComplaintCategory.values.map((cat) {
        final isSelected = selected == cat;
        return GestureDetector(
          onTap: () => onSelected(cat),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: isSelected
                  ? const Color(0xFF1A237E)
                  : const Color(0xFFF8F9FF),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isSelected
                    ? const Color(0xFF1A237E)
                    : Colors.grey.shade200,
                width: isSelected ? 1.5 : 1,
              ),
            ),
            child: Row(
              children: [
                Text(cat.icon, style: const TextStyle(fontSize: 16)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    cat.label,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: isSelected ? Colors.white : const Color(0xFF37474F),
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }
}

class _StyledDropdown<T> extends StatelessWidget {
  final T? value;
  final String hint;
  final IconData icon;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?> onChanged;

  const _StyledDropdown({
    required this.value,
    required this.hint,
    required this.icon,
    required this.items,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<T>(
      value: value,
      onChanged: onChanged,
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 14),
        prefixIcon: Icon(icon, size: 20, color: Colors.grey.shade500),
        filled: true,
        fillColor: const Color(0xFFF8F9FF),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: Colors.grey.shade200)),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: Colors.grey.shade200)),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide:
                const BorderSide(color: Color(0xFF1A237E), width: 1.5)),
      ),
      dropdownColor: Colors.white,
      borderRadius: BorderRadius.circular(12),
      items: items,
    );
  }
}

class _ImageTile extends StatelessWidget {
  final File file;
  final VoidCallback onRemove;

  const _ImageTile({required this.file, required this.onRemove});

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: Image.file(file,
              fit: BoxFit.cover, width: double.infinity, height: double.infinity),
        ),
        Positioned(
          top: 4,
          right: 4,
          child: GestureDetector(
            onTap: onRemove,
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: const BoxDecoration(
                color: Colors.black54,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.close, color: Colors.white, size: 14),
            ),
          ),
        ),
      ],
    );
  }
}
