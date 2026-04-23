// lib/features/committee/presentation/pages/committee_complaint_detail_page.dart

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:video_player/video_player.dart';
import '../../../../main.dart' show AppColors;
import 'dart:io';
import 'package:image_picker/image_picker.dart';
import '../../../../models/post_model.dart';
import '../../../../services/storage_service.dart';
import '../../../feed/presentation/pages/feed_page.dart' show FullScreenMediaViewer, MediaItem, MediaType;
import '../../../../models/comment_model.dart';
import '../../../../models/committee_member_model.dart';

class CommitteeComplaintDetailPage extends StatefulWidget {
  final PostModel post;
  final CommitteeMember member;
  const CommitteeComplaintDetailPage({
    super.key,
    required this.post,
    required this.member,
  });

  @override
  State<CommitteeComplaintDetailPage> createState() =>
      _CommitteeComplaintDetailPageState();
}

class _CommitteeComplaintDetailPageState
    extends State<CommitteeComplaintDetailPage> {
  bool _isUpdating = false;
  final _noteController = TextEditingController();
  Map<String, dynamic>? _studentDetails;
  bool _loadingStudent = true;

  @override
  void initState() {
    super.initState();
    _loadStudentDetails();
  }

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _loadStudentDetails() async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('users')
          .doc(widget.post.userId)
          .get();
      if (mounted) {
        setState(() {
          _studentDetails = snap.exists ? snap.data() : null;
          _loadingStudent = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loadingStudent = false);
    }
  }

  Future<void> _updateStatus(ComplaintStatus newStatus, String note) async {
    // Capture context-dependent objects before any async gap
    final messenger = ScaffoldMessenger.of(context);
    final nav = Navigator.of(context);
    setState(() => _isUpdating = true);
    try {
      final now = DateTime.now();
      final newEntry = StatusHistoryEntry(
        status: newStatus,
        changedAt: now,
        changedBy: widget.member.name.isNotEmpty
            ? widget.member.name
            : widget.member.committee.label,
        note: note,
      );
      final updatedHistory = [...widget.post.statusHistory, newEntry];

      await FirebaseFirestore.instance
          .collection('complaints')
          .doc(widget.post.id)
          .update({
        'status': newStatus.name,
        'updatedAt': now.toIso8601String(),
        'isPublic': true,
        if (newStatus == ComplaintStatus.resolved ||
            newStatus == ComplaintStatus.rejected) ...{
          'resolutionNote': note,
        },
        'statusHistory': updatedHistory.map((e) => e.toMap()).toList(),
      });

      messenger.showSnackBar(SnackBar(
        content: Text('Status updated to ${_statusLabel(newStatus)}'),
        backgroundColor: AppColors.resolved,
        behavior: SnackBarBehavior.floating,
      ));
      if (mounted) nav.pop();
    } catch (e) {
      messenger.showSnackBar(SnackBar(
        content: Text('Failed: $e'),
        backgroundColor: AppColors.rejected,
        behavior: SnackBarBehavior.floating,
      ));
    } finally {
      if (mounted) setState(() => _isUpdating = false);
    }
  }

  Future<void> _showNoteDialog({
    required String title,
    required String hint,
    required ComplaintStatus targetStatus,
  }) async {
    _noteController.clear();
    if (targetStatus == ComplaintStatus.resolved) {
      final result = await _showResolutionSheet();
      if (result == null || !mounted) return;
      setState(() => _isUpdating = true);
      final note = result['note'] as String;
      final imageFiles = result['images'] as List<File>;
      try {
        List<String> uploadedUrls = [];
        if (imageFiles.isNotEmpty) {
          uploadedUrls = await StorageService.instance.uploadComplaintImages(
            userId: widget.post.userId,
            complaintId: '${widget.post.id}_resolution',
            files: imageFiles,
          );
        }
        if (!mounted) return;
        final now = DateTime.now();
        final newEntry = StatusHistoryEntry(
          status: ComplaintStatus.resolved,
          changedAt: now,
          changedBy: widget.member.name.isNotEmpty
              ? widget.member.name
              : widget.member.committee.label,
          note: note,
        );
        final updatedHistory = [...widget.post.statusHistory, newEntry];
        await FirebaseFirestore.instance
            .collection('complaints')
            .doc(widget.post.id)
            .update({
          'status': ComplaintStatus.resolved.name,
          'updatedAt': now.toIso8601String(),
          'isPublic': true,
          'resolutionNote': note,
          if (uploadedUrls.isNotEmpty) 'resolutionImages': uploadedUrls,
          'statusHistory': updatedHistory.map((e) => e.toMap()).toList(),
        });
        if (!mounted) return;
        setState(() => _isUpdating = false);
        // Pop directly — noteCtrl dispose fix eliminates the animation crash
        if (mounted) Navigator.of(context).pop();
      } catch (e) {
        if (!mounted) return;
        setState(() => _isUpdating = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Failed to resolve: \$e'),
          backgroundColor: AppColors.rejected,
          behavior: SnackBarBehavior.floating,
        ));
      }
      return;
    }
    // Reject / other — simple dialog
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(title,
            style: const TextStyle(
                fontWeight: FontWeight.bold, color: AppColors.primary, fontSize: 16)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('This note will be visible to the student.',
                style: TextStyle(fontSize: 13, color: Colors.grey.shade600)),
            const SizedBox(height: 12),
            TextField(
              controller: _noteController,
              maxLines: 3,
              decoration: InputDecoration(
                hintText: hint,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              if (_noteController.text.trim().isEmpty) return;
              Navigator.pop(context, true);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.rejected,
              foregroundColor: Colors.white,
            ),
            child: const Text('Confirm'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await _updateStatus(targetStatus, _noteController.text.trim());
    }
  }

  // ── Resolution Sheet (text + images) ─────────────────────────────────────

  // Returns {note, images} or null if cancelled.
  // Uses a dedicated StatefulWidget so TextEditingController is owned
  // by Flutter's widget lifecycle — dispose() only runs after the widget
  // is fully removed from the tree, never during a closing animation.
  Future<Map<String, dynamic>?> _showResolutionSheet() async {
    return showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _ResolutionSheet(
        sheetHeight: MediaQuery.of(context).size.height * 0.88,
      ),
    );
  }


  Widget _buildActionButtons() {
    final status = widget.post.status;

    if (status == ComplaintStatus.approved) {
      return _ActionBtn(
        label: 'Start Review',
        icon: Icons.rate_review_rounded,
        color: const Color(0xFF5C6BC0),
        onTap: _isUpdating ? null : () => _updateStatus(
            ComplaintStatus.underReview, 'Committee has started reviewing this issue.'),
      );
    }

    if (status == ComplaintStatus.underReview) {
      return Row(children: [
        Expanded(child: _ActionBtn(
          label: 'In Progress',
          icon: Icons.engineering_rounded,
          color: AppColors.inProgress,
          onTap: _isUpdating ? null : () => _updateStatus(
              ComplaintStatus.inProgress, 'Work has started on this issue.'),
        )),
        const SizedBox(width: 10),
        Expanded(child: _ActionBtn(
          label: 'Reject',
          icon: Icons.cancel_outlined,
          color: AppColors.rejected,
          onTap: _isUpdating ? null : () => _showNoteDialog(
            title: 'Reject Complaint',
            hint: 'Reason for rejection...',
            targetStatus: ComplaintStatus.rejected,
          ),
        )),
      ]);
    }

    if (status == ComplaintStatus.inProgress) {
      return Row(children: [
        Expanded(child: _ActionBtn(
          label: 'Resolve',
          icon: Icons.check_circle_outline_rounded,
          color: AppColors.resolved,
          onTap: _isUpdating ? null : () => _showNoteDialog(
            title: 'Resolve Complaint',
            hint: 'Describe what was done to resolve this...',
            targetStatus: ComplaintStatus.resolved,
          ),
        )),
        const SizedBox(width: 10),
        Expanded(child: _ActionBtn(
          label: 'Reject',
          icon: Icons.cancel_outlined,
          color: AppColors.rejected,
          onTap: _isUpdating ? null : () => _showNoteDialog(
            title: 'Reject Complaint',
            hint: 'Reason for rejection...',
            targetStatus: ComplaintStatus.rejected,
          ),
        )),
      ]);
    }

    if (status == ComplaintStatus.flagged) {
      return Row(children: [
        Expanded(child: _ActionBtn(
          label: 'Approve',
          icon: Icons.thumb_up_rounded,
          color: AppColors.resolved,
          onTap: _isUpdating ? null : () => _updateStatus(
              ComplaintStatus.approved, 'Manually approved by committee after review.'),
        )),
        const SizedBox(width: 10),
        Expanded(child: _ActionBtn(
          label: 'Reject',
          icon: Icons.cancel_outlined,
          color: AppColors.rejected,
          onTap: _isUpdating ? null : () => _showNoteDialog(
            title: 'Reject Complaint',
            hint: 'Reason for rejection...',
            targetStatus: ComplaintStatus.rejected,
          ),
        )),
      ]);
    }

    final isResolved = status == ComplaintStatus.resolved;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: (isResolved ? AppColors.resolved : AppColors.rejected).withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: (isResolved ? AppColors.resolved : AppColors.rejected).withValues(alpha: 0.3)),
      ),
      child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(isResolved ? Icons.check_circle_rounded : Icons.cancel_rounded,
            color: isResolved ? AppColors.resolved : AppColors.rejected, size: 18),
        const SizedBox(width: 8),
        Text(
          isResolved ? 'This complaint has been resolved' : 'This complaint has been rejected',
          style: TextStyle(
              fontSize: 13, fontWeight: FontWeight.w600,
              color: isResolved ? AppColors.resolved : AppColors.rejected),
        ),
      ]),
    );
  }

  String _statusLabel(ComplaintStatus s) {
    switch (s) {
      case ComplaintStatus.pendingReview: return 'Pending Review';
      case ComplaintStatus.approved:      return 'Approved';
      case ComplaintStatus.underReview:   return 'Under Review';
      case ComplaintStatus.inProgress:    return 'In Progress';
      case ComplaintStatus.resolved:      return 'Resolved';
      case ComplaintStatus.rejected:      return 'Rejected';
      case ComplaintStatus.flagged:       return 'Flagged';
      default:                            return s.name;
    }
  }

  Color _statusColor(ComplaintStatus s) {
    switch (s) {
      case ComplaintStatus.pendingReview: return Colors.grey;
      case ComplaintStatus.approved:      return const Color(0xFF5C6BC0);
      case ComplaintStatus.underReview:   return const Color(0xFFFF9500);
      case ComplaintStatus.inProgress:    return AppColors.inProgress;
      case ComplaintStatus.resolved:      return AppColors.resolved;
      case ComplaintStatus.rejected:      return AppColors.rejected;
      case ComplaintStatus.flagged:       return const Color(0xFFFF6B35);
      default:                            return AppColors.textLight;
    }
  }

  String _timeAgo(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1)  return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24)   return '${diff.inHours}h ago';
    return '${dt.day}/${dt.month}/${dt.year}';
  }

  String _deptLabel(String tag) {
    const map = {
      'co': 'Computer Engineering', 'ce': 'Civil Engineering',
      'me': 'Mechanical Engineering', 'ee': 'Electrical Engineering',
      'ej': 'Electronics Engineering', 'it': 'Information Technology',
      'bit': 'B.Sc. IT', 'bca': 'BCA', 'ai': 'AI & Data Science',
      'ds': 'Data Science', 'et': 'E&TC Engineering',
    };
    return map[tag.toLowerCase()] ?? tag.toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final post = widget.post;

    return PopScope(
      // Block back navigation while an update/upload is in progress
      canPop: !_isUpdating,
      onPopInvokedWithResult: (didPop, result) {
        // If popped normally, nothing to do
      },
      child: Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text('Complaint Details',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: Colors.white)),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [

            // ── Complaint Info ──────────────────────────────────────
            _Card(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Text(post.category.icon, style: const TextStyle(fontSize: 16)),
                  const SizedBox(width: 6),
                  Text(post.category.label,
                      style: const TextStyle(fontSize: 13, color: AppColors.accent, fontWeight: FontWeight.w600)),
                  const Spacer(),
                  if (post.isChallenged) ...[
                    Container(
                      margin: const EdgeInsets.only(right: 6),
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFF6B35).withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(Icons.gavel_rounded, size: 11, color: Color(0xFFFF6B35)),
                        SizedBox(width: 4),
                        Text('Challenged',
                            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFFFF6B35))),
                      ]),
                    ),
                  ],
                  _StatusBadge(label: _statusLabel(post.status), color: _statusColor(post.status)),
                  if (!post.isPublic) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                      decoration: BoxDecoration(
                          color: Colors.grey.shade100, borderRadius: BorderRadius.circular(6)),
                      child: const Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(Icons.lock_outline_rounded, size: 11, color: AppColors.textLight),
                        SizedBox(width: 3),
                        Text('Private', style: TextStyle(fontSize: 11, color: AppColors.textLight)),
                      ]),
                    ),
                  ],
                ]),
                const SizedBox(height: 10),
                Text(post.title,
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.primary)),
                const SizedBox(height: 8),
                Text(post.description,
                    style: const TextStyle(fontSize: 14, color: AppColors.textMid, height: 1.5)),
                const SizedBox(height: 12),
                _InfoRow(icon: Icons.location_on_outlined, text: [
                  post.building,
                  if (post.floor != null) post.floor!,
                  if (post.roomNumber != null) post.roomNumber!,
                ].join(', ')),
                const SizedBox(height: 4),
                _InfoRow(icon: Icons.access_time_rounded, text: _timeAgo(post.updatedAt)),
                const SizedBox(height: 4),
                Row(children: [
                  _InfoRow(icon: Icons.thumb_up_outlined, text: '${post.supportCount} supports'),
                  const SizedBox(width: 16),
                  _InfoRow(icon: Icons.chat_bubble_outline_rounded, text: '${post.commentCount} comments'),
                ]),
                if (post.moderationNote != null) ...[
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                        color: Colors.orange.shade50,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.orange.shade200)),
                    child: Row(children: [
                      Icon(Icons.info_outline_rounded, size: 14, color: Colors.orange.shade700),
                      const SizedBox(width: 6),
                      Expanded(child: Text('System note: ${post.moderationNote}',
                          style: TextStyle(fontSize: 12, color: Colors.orange.shade800))),
                    ]),
                  ),
                ],
              ],
            )),

            const SizedBox(height: 12),

            // ── Reported By ─────────────────────────────────────────
            _SectionLabel('Reported By'),
            _Card(child: _loadingStudent
                ? const Padding(
                    padding: EdgeInsets.symmetric(vertical: 20),
                    child: Center(child: CircularProgressIndicator(color: AppColors.accent, strokeWidth: 2)))
                : Column(children: [
                    _DetailRow(icon: Icons.person_outline_rounded, label: 'Name',
                        value: _studentDetails?['fullName'] ?? post.userName),
                    _DetailRow(icon: Icons.badge_outlined, label: 'Roll No',
                        value: post.userEmail.split('@').first.toUpperCase()),
                    _DetailRow(icon: Icons.school_outlined, label: 'Department',
                        value: _deptLabel(_studentDetails?['departmentTag'] ?? '')),
                    _DetailRow(icon: Icons.calendar_today_outlined, label: 'Admitted',
                        value: '20${_studentDetails?['admissionYear'] ?? ''}',
                        isLast: true),
                  ])),

            const SizedBox(height: 12),

            // ── Media (Images + Videos) ─────────────────────────────
            if (post.imageUrls.isNotEmpty || post.videoPaths.isNotEmpty) ...[
              _SectionLabel('Evidence Media (${post.imageUrls.length + post.videoPaths.length} files)'),
              _Card(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Images — 2 per row, larger
                  if (post.imageUrls.isNotEmpty) ...[
                    GridView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: post.imageUrls.length,
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: post.imageUrls.length == 1 ? 1 : 2,
                          crossAxisSpacing: 8,
                          mainAxisSpacing: 8,
                          childAspectRatio: 0.85),
                      itemBuilder: (_, i) => GestureDetector(
                        onTap: () => _openFullscreenImage(context, post.imageUrls, i),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: Stack(fit: StackFit.expand, children: [
                            Image.network(post.imageUrls[i], fit: BoxFit.cover,
                                errorBuilder: (context, error, stackTrace) => Container(
                                    color: AppColors.surfaceAlt,
                                    child: const Icon(Icons.broken_image, color: AppColors.textLight))),
                            Positioned(top: 6, right: 6,
                                child: Container(
                                  padding: const EdgeInsets.all(4),
                                  decoration: BoxDecoration(
                                      color: Colors.black45, borderRadius: BorderRadius.circular(6)),
                                  child: const Icon(Icons.fullscreen_rounded, color: Colors.white, size: 14),
                                )),
                          ]),
                        ),
                      ),
                    ),
                    if (post.videoPaths.isNotEmpty) const SizedBox(height: 10),
                  ],
                  // Videos
                  ...post.videoPaths.map((path) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: _CommitteeVideoPlayer(
                      path: path,
                      onTapFullscreen: () {
                        final items = [
                          ...post.imageUrls.map((u) => MediaItem(url: u, type: MediaType.image)),
                          ...post.videoPaths.map((v) => MediaItem(url: v, type: MediaType.video)),
                        ];
                        final videoIndex = post.imageUrls.length +
                            post.videoPaths.indexOf(path);
                        Navigator.of(context).push(MaterialPageRoute(
                          builder: (_) => FullScreenMediaViewer(
                            items: items,
                            initialIndex: videoIndex,
                          ),
                        ));
                      },
                    ),
                  )),
                ],
              )),
              const SizedBox(height: 12),
            ],

            // ── Supporters ──────────────────────────────────────────
            if (post.supportCount > 0) ...[
              _SectionLabel('Supporters (${post.supportCount})'),
              _SupportersList(postId: post.id!),
              const SizedBox(height: 12),
            ],

            // ── Comments ────────────────────────────────────────────
            if (post.commentCount > 0) ...[
              _SectionLabel('Comments (${post.commentCount})'),
              _CommentsList(postId: post.id!),
              const SizedBox(height: 12),
            ],

            // ── Timeline ────────────────────────────────────────────
            if (post.statusHistory.isNotEmpty) ...[
              _SectionLabel('Timeline'),
              _Card(child: Column(
                children: post.statusHistory.asMap().entries.map((e) {
                  final isLast = e.key == post.statusHistory.length - 1;
                  return _TimelineEntry(
                    entry: e.value,
                    isLast: isLast,
                    label: _statusLabel(e.value.status),
                    color: _statusColor(e.value.status),
                  );
                }).toList(),
              )),
              const SizedBox(height: 12),
            ],

            // ── Resolution Note ─────────────────────────────────────
            if (post.resolutionNote != null && post.resolutionNote!.isNotEmpty) ...[
              _SectionLabel('Resolution Note'),
              _Card(child: Text(post.resolutionNote!,
                  style: const TextStyle(fontSize: 14, color: AppColors.textMid, height: 1.5))),
              const SizedBox(height: 12),
            ],

            // ── Resolution Evidence (images uploaded by committee) ───
            if (post.resolutionImages.isNotEmpty) ...[
              _SectionLabel('Resolution Evidence (${post.resolutionImages.length})'),
              _Card(child: GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: post.resolutionImages.length,
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: post.resolutionImages.length == 1 ? 1 : 2,
                  crossAxisSpacing: 8,
                  mainAxisSpacing: 8,
                  childAspectRatio: 1,
                ),
                itemBuilder: (_, i) => GestureDetector(
                  onTap: () => _openFullscreenImage(
                      context, post.resolutionImages, i),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Stack(fit: StackFit.expand, children: [
                      Image.network(
                        _cloudinaryOptimized(post.resolutionImages[i]),
                        fit: BoxFit.cover,
                        loadingBuilder: (ctx, child, progress) =>
                          progress == null ? child : Container(
                            color: Colors.grey.shade100,
                            child: const Center(
                              child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.grey)),
                          ),
                        errorBuilder: (c, e, s) => Container(
                          color: Colors.grey.shade200,
                          child: const Icon(Icons.broken_image_rounded,
                              color: Colors.grey, size: 36),
                        ),
                      ),
                      Positioned(
                        top: 6, right: 6,
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.5),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Icon(Icons.fullscreen_rounded,
                              color: Colors.white, size: 16),
                        ),
                      ),
                    ]),
                  ),
                ),
              )),
              const SizedBox(height: 12),
            ],

            // ── Actions ─────────────────────────────────────────────
            _SectionLabel('Actions'),
            _Card(child: _isUpdating
                ? const Padding(
                    padding: EdgeInsets.all(16),
                    child: Center(child: CircularProgressIndicator(color: AppColors.accent)))
                : _buildActionButtons()),

            const SizedBox(height: 32),
          ],
        ),
      ),
    ),
    );
  }

  void _openFullscreenImage(BuildContext context, List<String> urls, int index) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => _FullscreenImageViewer(urls: urls, initialIndex: index),
    ));
  }
}

// ── Committee Video Player ────────────────────────────────────────────────────

class _CommitteeVideoPlayer extends StatefulWidget {
  final String path;
  final VoidCallback? onTapFullscreen;
  const _CommitteeVideoPlayer({required this.path, this.onTapFullscreen});

  @override
  State<_CommitteeVideoPlayer> createState() => _CommitteeVideoPlayerState();
}

class _CommitteeVideoPlayerState extends State<_CommitteeVideoPlayer> {
  VideoPlayerController? _controller;
  bool _initializing = true;
  bool _error = false;
  bool _isMuted = false;
  bool _disposing = false;

  // Listener to rebuild UI when video plays/pauses/progresses
  void _onVideoUpdate() {
    if (mounted && _controller != null) setState(() {});
  }

  @override
  void initState() {
    super.initState();
    _init(widget.path);
  }

  @override
  void didUpdateWidget(_CommitteeVideoPlayer old) {
    super.didUpdateWidget(old);
    if (old.path != widget.path) {
      final old = _controller;
      _controller = null;
      old?.pause();
      Future.microtask(() => old?.dispose());
      if (mounted) setState(() { _initializing = true; _error = false; });
      _init(widget.path);
    }
  }

  Future<void> _init(String path) async {
    if (!path.startsWith('http')) {
      if (mounted) setState(() { _initializing = false; _error = true; });
      return;
    }
    VideoPlayerController? ctrl;
    try {
      ctrl = VideoPlayerController.networkUrl(
        Uri.parse(path),
        videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
      );
      await ctrl.initialize();
      if (_disposing || !mounted) { ctrl.dispose(); return; }
      await ctrl.setLooping(false);
      if (!mounted) { ctrl.dispose(); return; }
      ctrl.addListener(_onVideoUpdate);
      setState(() {
        _controller = ctrl;
        _initializing = false;
      });
    } catch (_) {
      ctrl?.dispose();
      if (mounted) setState(() { _initializing = false; _error = true; });
    }
  }

  @override
  void dispose() {
    _disposing = true;
    final ctrl = _controller;
    ctrl?.removeListener(_onVideoUpdate);  // remove listener FIRST
    _controller = null;   // null field before dispose
    ctrl?.pause();
    // Microtask: VideoPlayer widget deactivates in same frame,
    // disposing immediately causes _dependents.isEmpty assertion.
    Future.microtask(() => ctrl?.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_initializing) {
      return Container(
        height: 200,
        decoration: BoxDecoration(
            color: Colors.black87, borderRadius: BorderRadius.circular(10)),
        child: const Center(
            child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)),
      );
    }

    if (_error || _controller == null || !_controller!.value.isInitialized) {
      return Container(
        height: 200,
        decoration: BoxDecoration(
            color: Colors.black87, borderRadius: BorderRadius.circular(10)),
        child: const Center(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.videocam_off_rounded, color: Colors.white54, size: 40),
          SizedBox(height: 8),
          Text('Video unavailable', style: TextStyle(color: Colors.white54)),
        ])),
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: Container(
        color: Colors.black,
        child: Column(
          children: [
            AspectRatio(
              aspectRatio: _controller!.value.aspectRatio,
              child: VideoPlayer(_controller!),
            ),
            Container(
              color: Colors.black87,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: Row(children: [
                GestureDetector(
                  onTap: () {
                    if (_controller?.value.isPlaying == true) {
                      _controller?.pause();
                    } else {
                      _controller?.play();
                    }
                  },
                  child: Icon(
                    _controller?.value.isPlaying == true
                        ? Icons.pause_rounded
                        : Icons.play_arrow_rounded,
                    color: Colors.white, size: 28,
                  ),
                ),
                const SizedBox(width: 8),
                Builder(builder: (ctx) {
                    String fmtDur(Duration d) {
                      final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
                      final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
                      return '$m:$s';
                    }
                    final pos = _controller?.value.position ?? Duration.zero;
                    final dur = _controller?.value.duration ?? Duration.zero;
                    return Text(
                      '${fmtDur(pos)} / ${fmtDur(dur)}',
                      style: const TextStyle(color: Colors.white70, fontSize: 12),
                    );
                  }),
                const Spacer(),
                GestureDetector(
                  onTap: () {
                    setState(() {
                      _isMuted = !_isMuted;
                      _controller!.setVolume(_isMuted ? 0.0 : 1.0);
                    });
                  },
                  child: Icon(
                    _isMuted ? Icons.volume_off_rounded : Icons.volume_up_rounded,
                    color: Colors.white70, size: 18),
                ),
                const SizedBox(width: 8),
                const Icon(Icons.videocam_rounded, color: Colors.white54, size: 16),
                if (widget.onTapFullscreen != null) ...[
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: () {
                      _controller?.pause();
                      widget.onTapFullscreen!();
                    },
                    child: const Icon(Icons.fullscreen_rounded, color: Colors.white70, size: 22),
                  ),
                ],
              ]),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Supporters List ───────────────────────────────────────────────────────────

class _SupportersList extends StatelessWidget {
  final String postId;
  const _SupportersList({required this.postId});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('complaints')
          .doc(postId)
          .collection('supporters')
          .snapshots(),
      builder: (context, snap) {
        if (!snap.hasData || snap.data!.docs.isEmpty) return const SizedBox.shrink();
        return _Card(
          child: Column(
            children: snap.data!.docs.map((doc) {
              return _SupporterTile(uid: doc.id);
            }).toList(),
          ),
        );
      },
    );
  }
}

class _SupporterTile extends StatefulWidget {
  final String uid;
  const _SupporterTile({required this.uid});

  @override
  State<_SupporterTile> createState() => _SupporterTileState();
}

class _SupporterTileState extends State<_SupporterTile> {
  String _display = '...';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final doc = await FirebaseFirestore.instance.collection('users').doc(widget.uid).get();
      if (doc.exists && mounted) {
        final email = doc.data()?['email'] as String? ?? '';
        final rollNo = email.isNotEmpty
            ? email.split('@').first.toUpperCase()
            : widget.uid.substring(0, 8).toUpperCase();
        setState(() => _display = rollNo);
      } else if (mounted) {
        setState(() => _display = widget.uid.substring(0, 8).toUpperCase());
      }
    } catch (_) {
      if (mounted) setState(() => _display = widget.uid.substring(0, 8).toUpperCase());
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(children: [
        Container(
          width: 32, height: 32,
          decoration: const BoxDecoration(color: AppColors.accentLight, shape: BoxShape.circle),
          child: const Icon(Icons.person_rounded, size: 16, color: AppColors.accent),
        ),
        const SizedBox(width: 10),
        Text(_display,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: AppColors.textDark)),
        const Spacer(),
        const Icon(Icons.thumb_up_rounded, size: 12, color: AppColors.accent),
      ]),
    );
  }
}

// ── Comments List ─────────────────────────────────────────────────────────────

class _CommentsList extends StatelessWidget {
  final String postId;
  const _CommentsList({required this.postId});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('complaints')
          .doc(postId)
          .collection('comments')
          .orderBy('createdAt', descending: false)
          .snapshots(),
      builder: (context, snap) {
        if (!snap.hasData || snap.data!.docs.isEmpty) return const SizedBox.shrink();
        return _Card(
          child: Column(
            children: snap.data!.docs.map((doc) {
              final data = doc.data() as Map<String, dynamic>;
              final comment = CommentModel.fromFirestore(data, doc.id);
              return _CommentTile(comment: comment);
            }).toList(),
          ),
        );
      },
    );
  }
}

class _CommentTile extends StatefulWidget {
  final CommentModel comment;
  const _CommentTile({required this.comment});
  @override
  State<_CommentTile> createState() => _CommentTileState();
}

class _CommentTileState extends State<_CommentTile> {
  String _rollNo = '...';

  @override
  void initState() {
    super.initState();
    _loadRollNo();
  }

  Future<void> _loadRollNo() async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('users').doc(widget.comment.userId).get();
      if (doc.exists && mounted) {
        final email = doc.data()?['email'] as String? ?? '';
        setState(() => _rollNo = email.isNotEmpty
            ? email.split('@').first.toUpperCase()
            : widget.comment.userId.substring(0, 8).toUpperCase());
      } else if (mounted) {
        setState(() => _rollNo = widget.comment.userId.length >= 8
            ? widget.comment.userId.substring(0, 8).toUpperCase()
            : widget.comment.userId.toUpperCase());
      }
    } catch (_) {
      if (mounted) setState(() => _rollNo = '');
    }
  }

  String _timeAgo(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1)  return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24)   return '${diff.inHours}h ago';
    return '${dt.day}/${dt.month}/${dt.year}';
  }

  @override
  Widget build(BuildContext context) {
    final comment = widget.comment;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          width: 32, height: 32,
          decoration: const BoxDecoration(color: AppColors.accentLight, shape: BoxShape.circle),
          child: Center(
            child: Text(
              comment.userName.isNotEmpty ? comment.userName[0].toUpperCase() : 'S',
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AppColors.accent),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Flexible(child: Text(comment.userName,
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textDark),
                  overflow: TextOverflow.ellipsis)),
              if (_rollNo.isNotEmpty) ...[
                const SizedBox(width: 4),
                Text('($_rollNo)',
                    style: const TextStyle(fontSize: 11, color: AppColors.textLight)),
              ],
              const Spacer(),
              Text(_timeAgo(comment.createdAt),
                  style: const TextStyle(fontSize: 11, color: AppColors.textLight)),
            ]),
            const SizedBox(height: 3),
            Text(comment.text,
                style: const TextStyle(fontSize: 13, color: AppColors.textMid, height: 1.4)),
          ],
        )),
      ]),
    );
  }
}

// ── Timeline Entry ────────────────────────────────────────────────────────────

class _TimelineEntry extends StatelessWidget {
  final StatusHistoryEntry entry;
  final bool isLast;
  final String label;
  final Color color;
  const _TimelineEntry({required this.entry, required this.isLast, required this.label, required this.color});

  String _timeAgo(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1)  return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24)   return '${diff.inHours}h ago';
    return '${dt.day}/${dt.month}/${dt.year}';
  }

  @override
  Widget build(BuildContext context) {
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Column(children: [
        Container(width: 12, height: 12,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        if (!isLast) Container(width: 2, height: 44, color: AppColors.border),
      ]),
      const SizedBox(width: 12),
      Expanded(child: Padding(
        padding: EdgeInsets.only(bottom: isLast ? 0 : 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: color)),
          if (entry.note != null) ...[
            Text(entry.note!, style: const TextStyle(fontSize: 12, color: AppColors.textMid, height: 1.4)),
          ],
          Text('by ${entry.changedBy} · ${_timeAgo(entry.changedAt)}',
              style: const TextStyle(fontSize: 11, color: AppColors.textLight)),
        ]),
      )),
    ]);
  }
}

// ── Shared Widgets ────────────────────────────────────────────────────────────

class _Card extends StatelessWidget {
  final Widget child;
  const _Card({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: child,
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Text(text, style: const TextStyle(
        fontSize: 12, fontWeight: FontWeight.w700,
        color: AppColors.textMid, letterSpacing: 0.5)),
  );
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String text;
  const _InfoRow({required this.icon, required this.text});
  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
    Icon(icon, size: 14, color: AppColors.textLight),
    const SizedBox(width: 5),
    Flexible(child: Text(text, style: const TextStyle(fontSize: 13, color: AppColors.textMid), overflow: TextOverflow.ellipsis)),
  ]);
}

class _DetailRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final bool isLast;
  const _DetailRow({required this.icon, required this.label, required this.value, this.isLast = false});
  @override
  Widget build(BuildContext context) => Column(children: [
    Row(children: [
      Icon(icon, size: 16, color: AppColors.accent),
      const SizedBox(width: 10),
      Text('$label: ', style: const TextStyle(fontSize: 13, color: AppColors.textLight)),
      Flexible(child: Text(value, style: const TextStyle(
          fontSize: 13, color: AppColors.textDark, fontWeight: FontWeight.w500),
          overflow: TextOverflow.ellipsis)),
    ]),
    if (!isLast) ...[const SizedBox(height: 8), const Divider(height: 1, color: AppColors.border), const SizedBox(height: 8)],
  ]);
}

class _StatusBadge extends StatelessWidget {
  final String label;
  final Color color;
  const _StatusBadge({required this.label, required this.color});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.1),
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: color.withValues(alpha: 0.3)),
    ),
    child: Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: color)),
  );
}

class _ActionBtn extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback? onTap;
  const _ActionBtn({required this.label, required this.icon, required this.color, required this.onTap});
  @override
  Widget build(BuildContext context) => ElevatedButton.icon(
    onPressed: onTap,
    icon: Icon(icon, size: 16),
    label: Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
    style: ElevatedButton.styleFrom(
      backgroundColor: color, foregroundColor: Colors.white,
      padding: const EdgeInsets.symmetric(vertical: 13),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      elevation: 0,
    ),
  );
}

class _AttachBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _AttachBtn({required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.accentLight,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.accent.withValues(alpha: 0.3)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 16, color: AppColors.accent),
        const SizedBox(width: 6),
        Text(label, style: const TextStyle(fontSize: 13, color: AppColors.accent, fontWeight: FontWeight.w500)),
      ]),
    ),
  );
}

// ── Resolution Sheet Widget ────────────────────────────────────────────────
// Owns TextEditingController in State so Flutter disposes it correctly
// after the widget is fully removed — never during a closing animation.
class _ResolutionSheet extends StatefulWidget {
  final double sheetHeight;
  const _ResolutionSheet({required this.sheetHeight});

  @override
  State<_ResolutionSheet> createState() => _ResolutionSheetState();
}

class _ResolutionSheetState extends State<_ResolutionSheet> {
  // Controller owned by State — disposed by Flutter lifecycle, not manually
  final TextEditingController _noteCtrl = TextEditingController();
  final ImagePicker _picker = ImagePicker();
  final List<File> _images = [];

  @override
  void dispose() {
    _noteCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: widget.sheetHeight,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(children: [
        Container(
          margin: const EdgeInsets.only(top: 12, bottom: 8),
          width: 40, height: 4,
          decoration: BoxDecoration(
            color: Colors.grey.shade300,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 8, 0),
          child: Row(children: [
            const Text('Resolve Complaint',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: AppColors.primary)),
            const Spacer(),
            IconButton(
              icon: const Icon(Icons.close_rounded),
              onPressed: () => Navigator.pop(context),
            ),
          ]),
        ),
        const Divider(height: 1),
        Expanded(
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(16, 16, 16,
                MediaQuery.of(context).viewInsets.bottom + 16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Resolution Message *',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textMid)),
              const SizedBox(height: 8),
              TextField(
                controller: _noteCtrl,
                maxLines: 4,
                decoration: InputDecoration(
                  hintText: 'Describe what was done to resolve this issue...',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  contentPadding: const EdgeInsets.all(12),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: AppColors.accent, width: 2),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Row(children: [
                const Text('Resolution Evidence',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textMid)),
                const SizedBox(width: 6),
                Text('(optional · max 3)',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
              ]),
              const SizedBox(height: 10),
              if (_images.isNotEmpty) ...[
                GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: _images.length,
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 3, crossAxisSpacing: 6, mainAxisSpacing: 6,
                      childAspectRatio: 1),
                  itemBuilder: (_, i) => Stack(children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.file(_images[i],
                          fit: BoxFit.cover, width: double.infinity, height: double.infinity),
                    ),
                    Positioned(
                      top: 2, right: 2,
                      child: GestureDetector(
                        onTap: () => setState(() => _images.removeAt(i)),
                        child: Container(
                          padding: const EdgeInsets.all(3),
                          decoration: const BoxDecoration(
                              color: Colors.black54, shape: BoxShape.circle),
                          child: const Icon(Icons.close_rounded, color: Colors.white, size: 12),
                        ),
                      ),
                    ),
                  ]),
                ),
                const SizedBox(height: 10),
              ],
              if (_images.length < 3) ...[
                Row(children: [
                  _AttachBtn(
                    icon: Icons.camera_alt_rounded,
                    label: 'Camera',
                    onTap: () async {
                      final img = await _picker.pickImage(
                          source: ImageSource.camera, imageQuality: 80);
                      if (img != null) setState(() => _images.add(File(img.path)));
                    },
                  ),
                  const SizedBox(width: 10),
                  _AttachBtn(
                    icon: Icons.photo_library_rounded,
                    label: 'Gallery',
                    onTap: () async {
                      final img = await _picker.pickImage(
                          source: ImageSource.gallery, imageQuality: 80);
                      if (img != null) setState(() => _images.add(File(img.path)));
                    },
                  ),
                ]),
              ],
            ]),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
          child: SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () {
                final note = _noteCtrl.text.trim();
                if (note.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                    content: Text('Please write a resolution message'),
                    behavior: SnackBarBehavior.floating,
                  ));
                  return;
                }
                // Dismiss keyboard before popping to prevent focus callbacks
                // firing on a disposed controller
                FocusScope.of(context).unfocus();
                Navigator.pop(context, {
                  'note': note,
                  'images': List<File>.from(_images),
                });
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.resolved,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                elevation: 0,
              ),
              child: const Text('Mark as Resolved',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
            ),
          ),
        ),
      ]),
    );
  }
}

// Returns a Cloudinary URL with auto-optimization
String _cloudinaryOptimized(String url, {int width = 600}) {
  try {
    final uploadIdx = url.indexOf('/upload/');
    if (uploadIdx == -1) return url;
    final insert = '/upload/w_$width,q_auto,f_auto';
    return url.substring(0, uploadIdx) + insert + url.substring(uploadIdx + 7);
  } catch (_) {
    return url;
  }
}

// ── Fullscreen Image Viewer ────────────────────────────────────────────────
class _FullscreenImageViewer extends StatefulWidget {
  final List<String> urls;
  final int initialIndex;
  const _FullscreenImageViewer({required this.urls, required this.initialIndex});

  @override
  State<_FullscreenImageViewer> createState() => _FullscreenImageViewerState();
}

class _FullscreenImageViewerState extends State<_FullscreenImageViewer> {
  late int _currentIndex;
  late PageController _pageCtrl;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _pageCtrl = PageController(initialPage: widget.initialIndex);
  }

  @override
  void dispose() {
    _pageCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text('${_currentIndex + 1} / ${widget.urls.length}',
            style: const TextStyle(color: Colors.white)),
        leading: IconButton(
          icon: const Icon(Icons.close_rounded, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: PageView.builder(
        controller: _pageCtrl,
        itemCount: widget.urls.length,
        onPageChanged: (i) => setState(() => _currentIndex = i),
        itemBuilder: (_, i) => InteractiveViewer(
          child: Center(
            child: Image.network(
              widget.urls[i],
              fit: BoxFit.contain,
              gaplessPlayback: true,
              loadingBuilder: (ctx, child, progress) {
                if (progress == null) return child;
                return const Center(
                  child: CircularProgressIndicator(
                    color: Colors.white54, strokeWidth: 2),
                );
              },
              errorBuilder: (c, e, s) =>
                  const Icon(Icons.broken_image, color: Colors.white54, size: 64),
            ),
          ),
        ),
      ),
    );
  }
}
