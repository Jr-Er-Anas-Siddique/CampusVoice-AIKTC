// lib/features/posts/presentation/pages/report_issue_page.dart

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:geolocator/geolocator.dart';
import 'package:video_player/video_player.dart';
import '../../../../models/post_model.dart';
import '../../../../services/post_service.dart';
import '../../../../services/storage_service.dart';
import '../../../../config/campus_locations.dart';
import '../../../../config/complaint_categories.dart';
import '../../../../core/utils/campus_boundary.dart';
import '../../../../services/auth_service.dart';
import '../../../../services/duplicate_detection_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../../services/social_service.dart';
import '../../../feed/presentation/pages/complaint_detail_page.dart';
import '../../../../main.dart' show draftRefreshNotifier;

class ReportIssuePage extends StatefulWidget {
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

  ComplaintCategory? _selectedCategory;
  String? _selectedBuilding;
  String? _selectedFloor;

  // Media — shared pool of 3 slots total
  static const int _totalMediaSlots = 3;
  final List<File> _selectedImages = [];
  final List<File> _selectedVideos = [];
  final List<VideoPlayerController?> _videoControllers = [];
  final List<bool> _videoInitializing = [];
  // Cloudinary URLs from flagged/submitted complaints being edited
  final List<String> _existingImageUrls = [];

  // Computed limits
  int get _usedSlots => _selectedImages.length + _selectedVideos.length + _existingImageUrls.length;
  int get _remainingSlots => _totalMediaSlots - _usedSlots;
  int get _maxMoreImages => _remainingSlots;
  int get _maxMoreVideos => _remainingSlots;

  // GPS
  GpsCoordinates? _gpsCoordinates;
  bool? _isOnCampus;
  bool _isCapturingGps = false;
  String? _gpsError;

  // State
  bool _isPublic = true; // default public
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
    _isPublic = draft.isPublic;

    // Restore local images if files still exist on device
    for (final path in draft.localImagePaths) {
      final file = File(path);
      if (file.existsSync()) {
        _selectedImages.add(file);
      }
    }

    // Restore videos if files still exist on device
    for (final path in draft.videoPaths) {
      final file = File(path);
      if (file.existsSync()) {
        final index = _selectedVideos.length;
        _selectedVideos.add(file);
        _videoControllers.add(null);
        _videoInitializing.add(false);
        _initVideoController(index, file);
      }
    }

    // For flagged/submitted complaints being edited:
    // imageUrls are Cloudinary URLs — carry them forward so they aren't lost
    // They will be reused on resubmit (already uploaded, no re-upload needed)
    if (draft.imageUrls.isNotEmpty && _selectedImages.isEmpty) {
      // imageUrls exist but no local files — populate _existingImageUrls
      // so they show in UI and get passed through on submit
      _existingImageUrls.addAll(draft.imageUrls);
    }
  }

  Future<void> _initVideoController(int index, File file) async {
    if (index >= _videoControllers.length) return;
    setState(() => _videoInitializing[index] = true);
    await _videoControllers[index]?.dispose();
    final controller = VideoPlayerController.file(file);
    _videoControllers[index] = controller;
    await controller.initialize();
    if (mounted) setState(() => _videoInitializing[index] = false);
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _roomController.dispose();
    for (final c in _videoControllers) {
      c?.dispose();
    }
    super.dispose();
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

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

  // ── GPS ───────────────────────────────────────────────────────────────────

  Future<void> _captureGps() async {
    setState(() {
      _isCapturingGps = true;
      _gpsError = null;
    });
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        setState(() => _gpsError = 'Location services are disabled.');
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
        setState(() => _gpsError = 'Location permission permanently denied.');
        return;
      }
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
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
            : 'You appear to be outside the campus boundary.';
      });
    } catch (e) {
      setState(() => _gpsError = 'Failed to get location: $e');
    } finally {
      if (mounted) setState(() => _isCapturingGps = false);
    }
  }

  // ── Image picker ──────────────────────────────────────────────────────────

  Future<void> _pickImage(ImageSource source) async {
    if (_maxMoreImages <= 0) {
      _showSnack('Total media limit reached (max $_totalMediaSlots files).');
      return;
    }
    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source: source,
      imageQuality: 80,
      maxWidth: 1920,
    );
    if (picked != null) setState(() => _selectedImages.add(File(picked.path)));
  }

  void _removeImage(int index) =>
      setState(() => _selectedImages.removeAt(index));

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
      builder: (_) => _MediaSourceSheet(
        title: 'Add Photo',
        onCamera: () {
          Navigator.pop(context);
          _pickImage(ImageSource.camera);
        },
        onGallery: () {
          Navigator.pop(context);
          _pickImage(ImageSource.gallery);
        },
      ),
    );
  }

  // ── Video picker ──────────────────────────────────────────────────────────

  Future<void> _pickVideo(ImageSource source) async {
    if (_maxMoreVideos <= 0) {
      _showSnack('Total media limit reached (max $_totalMediaSlots files).');
      return;
    }
    final picker = ImagePicker();
    final picked = await picker.pickVideo(
      source: source,
      maxDuration: const Duration(seconds: 30),
    );
    if (picked == null) return;

    final file = File(picked.path);

    // Validate duration using a temporary controller
    final tempController = VideoPlayerController.file(file);
    await tempController.initialize();
    final duration = tempController.value.duration;
    await tempController.dispose();

    if (duration.inSeconds > 30) {
      if (mounted) {
        _showSnack('Video exceeds 30 seconds. Please choose a shorter clip.');
      }
      return;
    }

    final index = _selectedVideos.length;
    setState(() {
      _selectedVideos.add(file);
      _videoControllers.add(null);
      _videoInitializing.add(false);
    });
    await _initVideoController(index, file);
  }

  void _removeVideo(int index) {
    _videoControllers[index]?.dispose();
    setState(() {
      _selectedVideos.removeAt(index);
      _videoControllers.removeAt(index);
      _videoInitializing.removeAt(index);
    });
  }

  void _showVideoSourceSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _MediaSourceSheet(
        title: 'Add Video',
        cameraLabel: 'Record Video',
        galleryLabel: 'Choose from Gallery',
        onCamera: () {
          Navigator.pop(context);
          _pickVideo(ImageSource.camera);
        },
        onGallery: () {
          Navigator.pop(context);
          _pickVideo(ImageSource.gallery);
        },
      ),
    );
  }

  // ── Validation ────────────────────────────────────────────────────────────

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

  // ── Duplicate Detection ───────────────────────────────────────────────────

  Future<_DuplicateChoice?> _showDuplicateDialog(PostModel duplicate) async {
    return showDialog<_DuplicateChoice>(
      context: context,
      barrierDismissible: true,
      builder: (_) => _DuplicateDialog(duplicate: duplicate),
    );
  }

  Future<void> _supportExistingComplaint(
      PostModel duplicate, String uid) async {
    try {
      // Check if already supported — don't toggle off accidentally
      final alreadySupported = await FirebaseFirestore.instance
          .collection('complaints')
          .doc(duplicate.id)
          .collection('supporters')
          .doc(uid)
          .get()
          .then((d) => d.exists);

      if (alreadySupported) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('You have already supported this complaint.'),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
        return;
      }

      await SocialService.instance.toggleSupport(
        complaintId: duplicate.id!,
        userId: uid,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('You supported the existing complaint!'),
            backgroundColor: Colors.green,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (_) {}
  }

  // ── Submit / Draft ────────────────────────────────────────────────────────

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
      final user = AuthService.instance.currentUser!;
      final now = DateTime.now();
      final docId = DateTime.now().millisecondsSinceEpoch.toString();

      // ── Duplicate detection ─────────────────────────────────────────
      // Check before uploading media — no wasted upload if user decides
      // to support the existing complaint instead
      final duplicate = await DuplicateDetectionService.instance.findSimilar(
        building: _selectedBuilding!,
        category: _selectedCategory!,
        currentUserId: user.uid,
      );

      if (duplicate != null && mounted) {
        setState(() => _isSubmitting = false);
        final choice = await _showDuplicateDialog(duplicate);
        if (!mounted) return;

        if (choice == _DuplicateChoice.supportExisting) {
          // Toggle support on the existing complaint
          await _supportExistingComplaint(duplicate, user.uid);
          if (mounted) Navigator.of(context).pop(true);
          return;
        } else if (choice == null) {
          // User dismissed — do nothing
          return;
        }
        // choice == _DuplicateChoice.submitAnyway — continue with submission
        setState(() => _isSubmitting = true);
      }

      // Upload any new images picked by user
      List<String> newImagePaths = [];
      if (_selectedImages.isNotEmpty) {
        newImagePaths = await StorageService.instance.uploadComplaintImages(
          userId: user.uid,
          complaintId: docId,
          files: _selectedImages,
        );
      }
      // Merge existing Cloudinary URLs (from flagged edit) with new uploads
      final List<String> imagePaths = [..._existingImageUrls, ...newImagePaths];

      // Save all videos
      List<String> videoPaths = [];
      for (int i = 0; i < _selectedVideos.length; i++) {
        final path = await StorageService.instance.saveVideoLocally(
          userId: user.uid,
          complaintId: '$docId/video_$i',
          videoFile: _selectedVideos[i],
        );
        videoPaths.add(path);
      }

      final post = PostModel(
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
        imageUrls: imagePaths,
        videoPaths: videoPaths,
        gpsCoordinates: _gpsCoordinates,
        isOnCampus: _isOnCampus,
        isPublic: _isPublic,
        status: ComplaintStatus.pendingReview,
        createdAt: widget.existingDraft?.createdAt ?? now,
        updatedAt: now,
        // Preserve history from flagged complaint + add resubmit entry
        statusHistory: [
          ...?widget.existingDraft?.statusHistory,
          StatusHistoryEntry(
            status: ComplaintStatus.pendingReview,
            changedAt: now,
            changedBy: user.displayName ?? '',
            note: widget.existingDraft?.status == ComplaintStatus.flagged
                ? 'Resubmitted after editing'
                : 'Issue submitted — awaiting moderation',
          ),
        ],
      );

      final result = await PostService.instance.submitComplaint(
        post: post,
        imageFiles: [],
      );

      if (mounted) {
        draftRefreshNotifier.value++;
        if (result.autoPrivate) {
          _showSnack(
            'Submitted as Private — sensitive content auto-switched for your privacy.',
            isSuccess: true,
          );
        } else if (result.approved) {
          _showSnack('Complaint submitted and approved!', isSuccess: true);
        } else {
          _showSnack(
            'Complaint flagged: ${result.reason}',
            isSuccess: false,
          );
        }
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      setState(() => _errorMessage = e.toString());
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  // popAfterSave=true  → called from Save button (needs to pop itself)
  // popAfterSave=false → called from _onWillPop (PopScope handles the pop)
  Future<void> _saveDraft({bool popAfterSave = true}) async {
    if (_selectedCategory == null &&
        _selectedBuilding == null &&
        _titleController.text.trim().isEmpty) {
      _showSnack('Nothing to save yet.');
      return;
    }
    setState(() => _isSavingDraft = true);
    try {
      final user = AuthService.instance.currentUser!;
      final now = DateTime.now();

      final draft = PostModel(
        id: widget.existingDraft?.id,
        userId: user.uid,
        userEmail: user.email ?? '',
        userName: user.displayName ?? '',
        title: _titleController.text.trim(),
        description: _descriptionController.text.trim(),
        category: _selectedCategory ?? ComplaintCategory.other,
        building: _selectedBuilding ?? '',
        floor: _selectedFloor,
        roomNumber: _roomController.text.trim().isEmpty
            ? null
            : _roomController.text.trim(),
        localImagePaths: _selectedImages.map((f) => f.path).toList(),
        videoPaths: _selectedVideos.map((f) => f.path).toList(),
        gpsCoordinates: _gpsCoordinates,
        isOnCampus: _isOnCampus,
        isPublic: _isPublic,
        status: ComplaintStatus.draft,
        createdAt: widget.existingDraft?.createdAt ?? now,
        updatedAt: now,
      );

      await PostService.instance.saveDraft(draft);
      draftRefreshNotifier.value++;
      if (mounted) {
        _showSnack('Draft saved.', isSuccess: true);
        if (popAfterSave) Navigator.of(context).pop(true);
      }
    } catch (e) {
      setState(() => _errorMessage = e.toString());
    } finally {
      if (mounted) setState(() => _isSavingDraft = false);
    }
  }

  void _showSnack(String message, {bool isSuccess = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor:
            isSuccess ? Colors.green.shade700 : Colors.red.shade700,
        behavior: SnackBarBehavior.floating,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  bool get _hasContent =>
      _titleController.text.trim().isNotEmpty ||
      _descriptionController.text.trim().isNotEmpty ||
      _selectedCategory != null ||
      _selectedImages.isNotEmpty ||
      _selectedVideos.isNotEmpty;

  // True only when draft had media paths but files no longer exist on device
  bool get _hasMissingDraftMedia {
    final draft = widget.existingDraft;
    if (draft == null) return false;
    // Count both local paths and cloud URLs
    final draftImageCount =
        draft.localImagePaths.length + draft.imageUrls.length;
    final draftVideoCount = draft.videoPaths.length;
    if (draftImageCount == 0 && draftVideoCount == 0) return false;
    final restoredImages = _selectedImages.length + _existingImageUrls.length;
    return restoredImages < draftImageCount ||
        _selectedVideos.length < draftVideoCount;
  }

  Future<bool> _onWillPop() async {
    if (!_hasContent) return true;
    final result = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Leave this page?',
            style: TextStyle(
                fontWeight: FontWeight.bold, color: Color(0xFF1A237E))),
        content: const Text(
            'You have unsaved changes. Would you like to save as a draft or discard?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, 'discard'),
            child: Text('Discard',
                style: TextStyle(color: Colors.red.shade400)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, 'draft'),
            child: const Text('Save Draft',
                style: TextStyle(
                    color: Color(0xFF1A237E),
                    fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
    if (result == 'draft') {
      await _saveDraft(popAfterSave: false);
      return true;
    }
    return result == 'discard';
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final nav = Navigator.of(context);
        final shouldPop = await _onWillPop();
        if (shouldPop && mounted) nav.pop();
      },
      child: Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1A237E),
        foregroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded,
              color: Colors.white),
          onPressed: () async {
            final nav = Navigator.of(context);
            final shouldPop = await _onWillPop();
            if (shouldPop && mounted) nav.pop();
          },
        ),
        title: Text(
          widget.existingDraft != null ? 'Edit Draft' : 'Report an Issue',
          style:
              const TextStyle(fontWeight: FontWeight.w600, fontSize: 18),
        ),
        actions: [
          TextButton.icon(
            onPressed:
                (_isSavingDraft || _isSubmitting) ? null : _saveDraft,
            icon: _isSavingDraft
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                        color: Colors.white, strokeWidth: 2),
                  )
                : const Icon(Icons.save_outlined,
                    color: Colors.white, size: 18),
            label: const Text('Save Draft',
                style: TextStyle(color: Colors.white, fontSize: 13)),
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: SingleChildScrollView(
          padding:
              const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_errorMessage != null) ...[
                _ErrorBanner(message: _errorMessage!),
                const SizedBox(height: 16),
              ],

              // ── Section 1: Issue Details ──────────────────────────────
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

              // ── Section: Visibility ───────────────────────────────
              _SectionCard(
                title: 'Post Visibility',
                icon: Icons.visibility_outlined,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: GestureDetector(
                          onTap: () => setState(() => _isPublic = true),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            padding: const EdgeInsets.symmetric(
                                vertical: 14, horizontal: 12),
                            decoration: BoxDecoration(
                              color: _isPublic
                                  ? const Color(0xFF1A237E)
                                  : const Color(0xFFF8F9FF),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: _isPublic
                                    ? const Color(0xFF1A237E)
                                    : Colors.grey.shade200,
                              ),
                            ),
                            child: Column(
                              children: [
                                Icon(Icons.public_rounded,
                                    color: _isPublic
                                        ? Colors.white
                                        : Colors.grey.shade500,
                                    size: 22),
                                const SizedBox(height: 6),
                                Text('Public',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 13,
                                      color: _isPublic
                                          ? Colors.white
                                          : const Color(0xFF37474F),
                                    )),
                                const SizedBox(height: 4),
                                Text(
                                  'Visible to all students',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: _isPublic
                                        ? Colors.white70
                                        : Colors.grey.shade500,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: GestureDetector(
                          onTap: () => setState(() => _isPublic = false),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            padding: const EdgeInsets.symmetric(
                                vertical: 14, horizontal: 12),
                            decoration: BoxDecoration(
                              color: !_isPublic
                                  ? const Color(0xFF1A237E)
                                  : const Color(0xFFF8F9FF),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: !_isPublic
                                    ? const Color(0xFF1A237E)
                                    : Colors.grey.shade200,
                              ),
                            ),
                            child: Column(
                              children: [
                                Icon(Icons.lock_outline_rounded,
                                    color: !_isPublic
                                        ? Colors.white
                                        : Colors.grey.shade500,
                                    size: 22),
                                const SizedBox(height: 6),
                                Text('Private',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 13,
                                      color: !_isPublic
                                          ? Colors.white
                                          : const Color(0xFF37474F),
                                    )),
                                const SizedBox(height: 4),
                                Text(
                                  'Only moderators & committee',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: !_isPublic
                                        ? Colors.white70
                                        : Colors.grey.shade500,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),

              const SizedBox(height: 24),

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
                        if (!ComplaintCategories.requiresGps(cat)) {
                          _gpsCoordinates = null;
                          _isOnCampus = null;
                          _gpsError = null;
                        }
                        if (!ComplaintCategories.cameraOnly(cat)) {
                          _selectedImages.clear();
                        }
                      });
                    },
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // ── Section 3: Location ───────────────────────────────────
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
                    onChanged: (val) => setState(() {
                      _selectedBuilding = val;
                      _selectedFloor = null;
                    }),
                  ),
                  if (_selectedBuilding != null && !_isOutdoor) ...[
                    const SizedBox(height: 16),
                    _FieldLabel('Floor'),
                    const SizedBox(height: 6),
                    _StyledDropdown<String>(
                      value: _selectedFloor,
                      hint: 'Select floor',
                      icon: Icons.layers_outlined,
                      items: CampusLocations.floors
                          .map((f) =>
                              DropdownMenuItem(value: f, child: Text(f)))
                          .toList(),
                      onChanged: (val) =>
                          setState(() => _selectedFloor = val),
                    ),
                  ],
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

              // ── Section 4: GPS (Infrastructure only) ─────────────────
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
                              'Infrastructure complaints require GPS verification.',
                              style: TextStyle(fontSize: 12),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
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
                                crossAxisAlignment:
                                    CrossAxisAlignment.start,
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
                          side: const BorderSide(
                              color: Color(0xFF1A237E)),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
              ],

              // ── Draft media notice — only if media failed to restore ───
              if (widget.existingDraft != null && _hasMissingDraftMedia)
                Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.amber.shade50,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.amber.shade300),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.info_outline_rounded,
                          color: Colors.amber.shade700, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Media files from your draft could not be restored as they were cleared by your device. Please re-attach your images and videos.',
                          style: TextStyle(
                              fontSize: 12,
                              color: Colors.amber.shade800,
                              height: 1.4),
                        ),
                      ),
                    ],
                  ),
                ),

              // ── Section 5: Evidence Images ────────────────────────────
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
                                fontSize: 12,
                                color: Colors.blue.shade700),
                          ),
                        ],
                      ),
                    ),
                  // Existing cloud images (from flagged complaint edit)
                  if (_existingImageUrls.isNotEmpty) ...[
                    GridView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: _existingImageUrls.length,
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 3,
                        crossAxisSpacing: 8,
                        mainAxisSpacing: 8,
                      ),
                      itemBuilder: (ctx, i) => Stack(
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(10),
                            child: Image.network(
                              _existingImageUrls[i],
                              fit: BoxFit.cover,
                              width: double.infinity,
                              height: double.infinity,
                              errorBuilder: (context, error, stackTrace) => Container(
                                color: Colors.grey.shade200,
                                child: const Icon(Icons.broken_image),
                              ),
                            ),
                          ),
                          Positioned(
                            top: 4,
                            right: 4,
                            child: GestureDetector(
                              onTap: () => setState(
                                  () => _existingImageUrls.removeAt(i)),
                              child: Container(
                                padding: const EdgeInsets.all(4),
                                decoration: const BoxDecoration(
                                  color: Colors.black54,
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(Icons.close,
                                    color: Colors.white, size: 14),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                  // New locally picked images
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
                  if (_maxMoreImages > 0)
                    GestureDetector(
                      onTap: _selectedCategory == null
                          ? () => _showSnack('Select a category first.')
                          : _showImageSourceSheet,
                      child: _AddMediaButton(
                        icon: Icons.add_photo_alternate_outlined,
                        label:
                            'Add Photo (${_selectedImages.length} photos • $_remainingSlots slot${_remainingSlots == 1 ? '' : 's'} left)',
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 16),

              // ── Section 6: Evidence Video ─────────────────────────────
              _SectionCard(
                title: 'Evidence Video',
                icon: Icons.videocam_outlined,
                children: [
                  // Info note
                  Container(
                    padding: const EdgeInsets.all(10),
                    margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(
                      color: Colors.purple.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.purple.shade200),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.info_outline,
                            color: Colors.purple.shade700, size: 16),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Max 30 seconds per video • Total media limit: $_totalMediaSlots files.',
                            style: TextStyle(
                                fontSize: 12,
                                color: Colors.purple.shade700),
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Video previews
                  for (int i = 0; i < _selectedVideos.length; i++) ...[
                    _VideoPreviewTile(
                      controller: _videoControllers[i],
                      isInitializing: _videoInitializing[i],
                      onRemove: () => _removeVideo(i),
                    ),
                    const SizedBox(height: 12),
                  ],

                  // Add video button (only if slots remain)
                  if (_maxMoreVideos > 0)
                    GestureDetector(
                      onTap: _showVideoSourceSheet,
                      child: _AddMediaButton(
                        icon: Icons.video_call_outlined,
                        label:
                            'Add Video (${_selectedVideos.length} video${_selectedVideos.length == 1 ? '' : 's'} • $_remainingSlots slot${_remainingSlots == 1 ? '' : 's'} left)',
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 28),

              // ── Submit ────────────────────────────────────────────────
              SizedBox(
                height: 52,
                child: ElevatedButton(
                  onPressed:
                      (_isSubmitting || _isSavingDraft) ? null : _submit,
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
      ), // closes Scaffold
    ), // closes child: parameter of PopScope
  ); // closes PopScope / return
  }

  InputDecoration _inputDeco(
      {required String hint, required IconData icon}) {
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
          borderSide:
              const BorderSide(color: Color(0xFF1A237E), width: 1.5)),
      errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Colors.redAccent)),
      focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide:
              const BorderSide(color: Colors.redAccent, width: 1.5)),
    );
  }
} // closes _ReportIssuePageState

// ── Reusable Widgets ──────────────────────────────────────────────────────────

class _SectionCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final List<Widget> children;

  const _SectionCard(
      {required this.title,
      required this.icon,
      required this.children});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.indigo.withValues(alpha: 0.08),
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
                child:
                    Icon(icon, size: 18, color: const Color(0xFF1A237E)),
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
  Widget build(BuildContext context) => Text(label,
      style: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: Color(0xFF37474F)));
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
            Icon(Icons.error_outline,
                color: Colors.red.shade700, size: 18),
            const SizedBox(width: 10),
            Expanded(
              child: Text(message,
                  style: TextStyle(
                      color: Colors.red.shade700, fontSize: 13)),
            ),
          ],
        ),
      );
}

class _AddMediaButton extends StatelessWidget {
  final IconData icon;
  final String label;
  const _AddMediaButton({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 80,
      decoration: BoxDecoration(
        color: const Color(0xFFF8F9FF),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: Colors.grey.shade500, size: 24),
          const SizedBox(width: 8),
          Text(label,
              style:
                  TextStyle(color: Colors.grey.shade500, fontSize: 13)),
        ],
      ),
    );
  }
}

class _CategoryGrid extends StatelessWidget {
  final ComplaintCategory? selected;
  final ValueChanged<ComplaintCategory> onSelected;

  const _CategoryGrid(
      {required this.selected, required this.onSelected});

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
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
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
                      color: isSelected
                          ? Colors.white
                          : const Color(0xFF37474F),
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
      initialValue: value,
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
              fit: BoxFit.cover,
              width: double.infinity,
              height: double.infinity),
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
              child: const Icon(Icons.close,
                  color: Colors.white, size: 14),
            ),
          ),
        ),
      ],
    );
  }
}

class _VideoPreviewTile extends StatelessWidget {
  final VideoPlayerController? controller;
  final bool isInitializing;
  final VoidCallback onRemove;

  const _VideoPreviewTile({
    required this.controller,
    required this.isInitializing,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 200,
      decoration: BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Video preview
          if (!isInitializing &&
              controller != null &&
              controller!.value.isInitialized)
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: AspectRatio(
                aspectRatio: controller!.value.aspectRatio,
                child: VideoPlayer(controller!),
              ),
            )
          else
            const CircularProgressIndicator(color: Colors.white),

          // Play/pause button
          if (!isInitializing &&
              controller != null &&
              controller!.value.isInitialized)
            GestureDetector(
              onTap: () {
                controller!.value.isPlaying
                    ? controller!.pause()
                    : controller!.play();
              },
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: const BoxDecoration(
                  color: Colors.black45,
                  shape: BoxShape.circle,
                ),
                child: StatefulBuilder(
                  builder: (ctx, setLocalState) {
                    return ValueListenableBuilder<VideoPlayerValue>(
                      valueListenable: controller!,
                      builder: (_, value, _) => Icon(
                        value.isPlaying
                            ? Icons.pause_rounded
                            : Icons.play_arrow_rounded,
                        color: Colors.white,
                        size: 36,
                      ),
                    );
                  },
                ),
              ),
            ),

          // Duration badge
          if (!isInitializing &&
              controller != null &&
              controller!.value.isInitialized)
            Positioned(
              bottom: 8,
              left: 10,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  _formatDuration(controller!.value.duration),
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w500),
                ),
              ),
            ),

          // Remove button
          Positioned(
            top: 8,
            right: 8,
            child: GestureDetector(
              onTap: onRemove,
              child: Container(
                padding: const EdgeInsets.all(6),
                decoration: const BoxDecoration(
                  color: Colors.black54,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.close,
                    color: Colors.white, size: 16),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _formatDuration(Duration d) {
    final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }
}

class _MediaSourceSheet extends StatelessWidget {
  final String title;
  final String cameraLabel;
  final String galleryLabel;
  final VoidCallback onCamera;
  final VoidCallback onGallery;

  const _MediaSourceSheet({
    required this.title,
    this.cameraLabel = 'Take Photo',
    this.galleryLabel = 'Choose from Gallery',
    required this.onCamera,
    required this.onGallery,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
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
            const SizedBox(height: 12),
            Text(title,
                style: const TextStyle(
                    fontWeight: FontWeight.w600, fontSize: 15)),
            const SizedBox(height: 4),
            ListTile(
              leading: const Icon(Icons.camera_alt_rounded,
                  color: Color(0xFF1A237E)),
              title: Text(cameraLabel),
              onTap: onCamera,
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_rounded,
                  color: Color(0xFF1A237E)),
              title: Text(galleryLabel),
              onTap: onGallery,
            ),
          ],
        ),
      ),
    );
  }
}

// ── Duplicate Choice ──────────────────────────────────────────────────────────

enum _DuplicateChoice { supportExisting, submitAnyway }

// ── Duplicate Dialog ──────────────────────────────────────────────────────────

class _DuplicateDialog extends StatelessWidget {
  final PostModel duplicate;
  const _DuplicateDialog({required this.duplicate});

  String _timeAgo(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${dt.day}/${dt.month}/${dt.year}';
  }

  String _statusLabel(ComplaintStatus s) {
    switch (s) {
      case ComplaintStatus.approved:    return 'Approved';
      case ComplaintStatus.underReview: return 'Under Review';
      case ComplaintStatus.inProgress:  return 'In Progress';
      default:                          return s.name;
    }
  }

  Color _statusColor(ComplaintStatus s) {
    switch (s) {
      case ComplaintStatus.approved:    return Colors.blue;
      case ComplaintStatus.underReview: return Colors.blueGrey;
      case ComplaintStatus.inProgress:  return Colors.orange;
      default:                          return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.orange.shade50,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(Icons.warning_amber_rounded,
                      color: Colors.orange.shade700, size: 22),
                ),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text(
                    'Similar Issue Found',
                    style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF1A237E)),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'A similar complaint already exists for this location.',
              style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
            ),

            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFFF5F6FA),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFEEEFF4)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Title
                  Text(
                    duplicate.title,
                    style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF1C1C2E)),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 6),
                  // Description
                  Text(
                    duplicate.description,
                    style: TextStyle(
                        fontSize: 13, color: Colors.grey.shade600, height: 1.4),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 10),
                  // Stats row
                  Row(
                    children: [
                      // Status badge
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: _statusColor(duplicate.status)
                              .withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          _statusLabel(duplicate.status),
                          style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: _statusColor(duplicate.status)),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Icon(Icons.thumb_up_outlined,
                          size: 13, color: Colors.grey.shade500),
                      const SizedBox(width: 3),
                      Text('${duplicate.supportCount} supports',
                          style: TextStyle(
                              fontSize: 12, color: Colors.grey.shade500)),
                      const Spacer(),
                      Text(_timeAgo(duplicate.createdAt),
                          style: TextStyle(
                              fontSize: 11, color: Colors.grey.shade400)),
                    ],
                  ),
                  const SizedBox(height: 10),
                  // View full issue button
                  GestureDetector(
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) =>
                              ComplaintDetailPage(post: duplicate),
                        ),
                      );
                    },
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.open_in_new_rounded,
                            size: 13,
                            color: const Color(0xFF1A237E)
                                .withValues(alpha: 0.7)),
                        const SizedBox(width: 4),
                        Text(
                          'View Full Issue',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: const Color(0xFF1A237E)
                                .withValues(alpha: 0.7),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // Action buttons
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () => Navigator.of(context)
                    .pop(_DuplicateChoice.supportExisting),
                icon: const Icon(Icons.thumb_up_rounded, size: 16),
                label: const Text('Support Existing Issue',
                    style: TextStyle(fontWeight: FontWeight.w600)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1A237E),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: () => Navigator.of(context)
                    .pop(_DuplicateChoice.submitAnyway),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF1A237E),
                  side: const BorderSide(color: Color(0xFF1A237E)),
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                child: const Text('Submit New Issue Anyway',
                    style: TextStyle(fontWeight: FontWeight.w600)),
              ),
            ),
            const SizedBox(height: 4),
            Center(
              child: TextButton(
                onPressed: () => Navigator.of(context).pop(null),
                child: Text('Cancel',
                    style: TextStyle(color: Colors.grey.shade500)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
