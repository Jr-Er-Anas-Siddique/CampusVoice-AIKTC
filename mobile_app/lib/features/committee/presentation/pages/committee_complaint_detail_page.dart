// lib/features/committee/presentation/pages/committee_complaint_detail_page.dart

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:video_player/video_player.dart';
import '../../../../main.dart' show AppColors;
import '../../../../models/post_model.dart';
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
        if (newStatus == ComplaintStatus.resolved ||
            newStatus == ComplaintStatus.rejected)
          'resolutionNote': note,
        'statusHistory': updatedHistory.map((e) => e.toMap()).toList(),
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Status updated to ${_statusLabel(newStatus)}'),
          backgroundColor: AppColors.resolved,
          behavior: SnackBarBehavior.floating,
        ));
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Failed: $e'),
          backgroundColor: AppColors.rejected,
          behavior: SnackBarBehavior.floating,
        ));
      }
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
              backgroundColor: targetStatus == ComplaintStatus.rejected
                  ? AppColors.rejected
                  : AppColors.primary,
              foregroundColor: Colors.white,
            ),
            child: Text(targetStatus == ComplaintStatus.resolved ? 'Mark Resolved' : 'Confirm'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await _updateStatus(targetStatus, _noteController.text.trim());
    }
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

    return Scaffold(
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
                _InfoRow(icon: Icons.access_time_rounded, text: _timeAgo(post.createdAt)),
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
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          crossAxisSpacing: 8,
                          mainAxisSpacing: 8,
                          childAspectRatio: 1.2),
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
                    child: _CommitteeVideoPlayer(path: path),
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
    );
  }

  void _openFullscreenImage(BuildContext context, List<String> urls, int index) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.black,
          foregroundColor: Colors.white,
          title: Text('${index + 1} / ${urls.length}',
              style: const TextStyle(color: Colors.white)),
          leading: IconButton(
            icon: const Icon(Icons.close_rounded, color: Colors.white),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ),
        body: PageView.builder(
          controller: PageController(initialPage: index),
          itemCount: urls.length,
          itemBuilder: (_, i) => Center(
            child: InteractiveViewer(
              child: Image.network(urls[i], fit: BoxFit.contain),
            ),
          ),
        ),
      ),
    ));
  }
}

// ── Committee Video Player ────────────────────────────────────────────────────

class _CommitteeVideoPlayer extends StatefulWidget {
  final String path;
  const _CommitteeVideoPlayer({required this.path});

  @override
  State<_CommitteeVideoPlayer> createState() => _CommitteeVideoPlayerState();
}

class _CommitteeVideoPlayerState extends State<_CommitteeVideoPlayer> {
  VideoPlayerController? _controller;
  bool _initializing = true;
  bool _error = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      final path = widget.path;
      // Only attempt network URLs — local paths will always fail on committee side
      if (!path.startsWith('http')) {
        if (mounted) setState(() { _initializing = false; _error = true; });
        return;
      }
      _controller = VideoPlayerController.networkUrl(Uri.parse(path));
      await _controller!.initialize();
      if (mounted) setState(() => _initializing = false);
    } catch (_) {
      if (mounted) setState(() { _initializing = false; _error = true; });
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
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

    final duration = _controller!.value.duration;
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds % 60;

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
                ValueListenableBuilder(
                  valueListenable: _controller!,
                  builder: (_, value, __) => GestureDetector(
                    onTap: () {
                      if (value.isPlaying) {
                        _controller!.pause();
                      } else {
                        _controller!.play();
                      }
                      setState(() {});
                    },
                    child: Icon(
                      value.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                      color: Colors.white, size: 28,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}',
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
                const Spacer(),
                const Icon(Icons.videocam_rounded, color: Colors.white54, size: 16),
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

  String _timeAgo(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1)  return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24)   return '${diff.inHours}h ago';
    return '${dt.day}/${dt.month}/${dt.year}';
  }

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
              final rollNo = comment.userId.split('@').first.toUpperCase();
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
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
                          Text(comment.userName,
                              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textDark)),
                          const SizedBox(width: 6),
                          Text('($rollNo)',
                              style: const TextStyle(fontSize: 11, color: AppColors.textLight)),
                          const Spacer(),
                          Text(_timeAgo(comment.createdAt),
                              style: const TextStyle(fontSize: 11, color: AppColors.textLight)),
                        ]),
                        const SizedBox(height: 3),
                        Text(comment.text,
                            style: const TextStyle(fontSize: 13, color: AppColors.textMid, height: 1.4)),
                      ],
                    )),
                  ],
                ),
              );
            }).toList(),
          ),
        );
      },
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
          if (entry.note != null)
            Text(entry.note!, style: const TextStyle(fontSize: 12, color: AppColors.textMid, height: 1.4)),
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
