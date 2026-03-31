// lib/features/feed/presentation/pages/my_complaints_page.dart

import 'package:flutter/material.dart';
import '../../../../main.dart' show AppColors, draftRefreshNotifier;
import '../../../../models/post_model.dart';
import '../../../../services/auth_service.dart';
import '../../../../services/post_service.dart';
import 'complaint_detail_page.dart';
import '../../../posts/presentation/pages/report_issue_page.dart';

class MyComplaintsPage extends StatefulWidget {
  const MyComplaintsPage({super.key});

  @override
  State<MyComplaintsPage> createState() => _MyComplaintsPageState();
}

class _MyComplaintsPageState extends State<MyComplaintsPage>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late TabController _tabController;
  List<PostModel> _drafts = [];
  bool _loadingDrafts = true;
  ComplaintStatus? _statusFilter;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _tabController = TabController(length: 2, vsync: this);
    _loadDrafts();
    _tabController.addListener(() => setState(() {}));
    // Listen for draft saves/submits from ReportIssuePage
    draftRefreshNotifier.addListener(_loadDrafts);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    draftRefreshNotifier.removeListener(_loadDrafts);
    _tabController.dispose();
    super.dispose();
  }

  // Reload drafts whenever app comes back to foreground
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _loadDrafts();
  }

  String _statusFilterLabel() {
    switch (_statusFilter) {
      case ComplaintStatus.pendingReview: return 'pending review';
      case ComplaintStatus.underReview:   return 'under review';
      case ComplaintStatus.inProgress:    return 'in progress';
      case ComplaintStatus.resolved:      return 'resolved';
      case ComplaintStatus.rejected:      return 'rejected';
      case ComplaintStatus.flagged:       return 'flagged';
      default:                            return 'matching';
    }
  }

  Future<void> _loadDrafts() async {
    final uid = AuthService.instance.currentUser?.uid ?? '';
    final all = await PostService.instance.getDrafts();
    if (mounted) {
      setState(() {
        _drafts = all.where((d) => d.userId == uid).toList()
          ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
        _loadingDrafts = false;
      });
    }
  }

  Future<void> _deleteDraft(PostModel draft) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Delete Draft',
            style: TextStyle(
                fontWeight: FontWeight.bold, color: Color(0xFF1A237E))),
        content: Text('Delete "${draft.title.isEmpty ? 'Untitled' : draft.title}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red, foregroundColor: Colors.white),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirm == true && draft.id != null) {
      await PostService.instance.deleteDraft(draft.id!);
      _loadDrafts();
    }
  }

  @override
  Widget build(BuildContext context) {
    final uid = AuthService.instance.currentUser?.uid ?? '';

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        automaticallyImplyLeading: false,
        title: const Text('My Complaints',
            style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w600)),
        elevation: 0,
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.white,
          indicatorWeight: 3,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white60,
          labelStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
          tabs: const [
            Tab(text: 'Submitted'),
            Tab(text: 'Drafts'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          // ── Submitted tab ──────────────────────────────────────────
          StreamBuilder<List<PostModel>>(
            stream: PostService.instance.myComplaintsStream(uid),
            builder: (context, snap) {
              if (snap.connectionState == ConnectionState.waiting) {
                return const Center(
                    child: CircularProgressIndicator(
                        color: Color(0xFF1A237E)));
              }
              if (snap.hasError) {
                return _EmptyState(
                  icon: Icons.error_outline_rounded,
                  title: 'Something went wrong',
                  subtitle: snap.error.toString(),
                );
              }
              final all = snap.data ?? [];
              if (all.isEmpty) {
                return _EmptyState(
                  icon: Icons.assignment_outlined,
                  title: 'No complaints yet',
                  subtitle: 'Tap the + button below to report your first issue',
                );
              }

              // Apply status filter
              final complaints = _statusFilter == null
                  ? all
                  : all
                      .where((p) => p.status == _statusFilter)
                      .toList();

              return Column(
                children: [
                  // ── Summary counts ──────────────────────────────
                  Container(
                    color: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Row(
                        children: [
                          _SummaryChip(
                            label: 'All',
                            count: all.length,
                            color: const Color(0xFF1A237E),
                            selected: _statusFilter == null,
                            onTap: () => setState(() => _statusFilter = null),
                          ),
                          const SizedBox(width: 8),
                          _SummaryChip(
                            label: 'Pending Review',
                            count: all.where((p) => p.status == ComplaintStatus.pendingReview).length,
                            color: Colors.orange,
                            selected: _statusFilter == ComplaintStatus.pendingReview,
                            onTap: () => setState(() => _statusFilter = ComplaintStatus.pendingReview),
                          ),
                          const SizedBox(width: 8),
                          _SummaryChip(
                            label: 'Under Review',
                            count: all.where((p) => p.status == ComplaintStatus.underReview).length,
                            color: Colors.blueGrey,
                            selected: _statusFilter == ComplaintStatus.underReview,
                            onTap: () => setState(() => _statusFilter = ComplaintStatus.underReview),
                          ),
                          const SizedBox(width: 8),
                          _SummaryChip(
                            label: 'In Progress',
                            count: all.where((p) => p.status == ComplaintStatus.inProgress).length,
                            color: Colors.blue,
                            selected: _statusFilter == ComplaintStatus.inProgress,
                            onTap: () => setState(() => _statusFilter = ComplaintStatus.inProgress),
                          ),
                          const SizedBox(width: 8),
                          _SummaryChip(
                            label: 'Resolved',
                            count: all.where((p) => p.status == ComplaintStatus.resolved).length,
                            color: Colors.green,
                            selected: _statusFilter == ComplaintStatus.resolved,
                            onTap: () => setState(() => _statusFilter = ComplaintStatus.resolved),
                          ),
                          const SizedBox(width: 8),
                          _SummaryChip(
                            label: 'Rejected',
                            count: all.where((p) => p.status == ComplaintStatus.rejected).length,
                            color: Colors.red,
                            selected: _statusFilter == ComplaintStatus.rejected,
                            onTap: () => setState(() => _statusFilter = ComplaintStatus.rejected),
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 4),

                  // ── Filtered list ───────────────────────────────
                  Expanded(
                    child: complaints.isEmpty
                        ? _EmptyState(
                            icon: Icons.filter_list_off_rounded,
                            title: 'No ${_statusFilterLabel()} complaints',
                            subtitle: 'Try a different filter',
                          )
                        : ListView.separated(
                            padding: const EdgeInsets.all(12),
                            itemCount: complaints.length,
                            separatorBuilder: (_, _) =>
                                const SizedBox(height: 8),
                            itemBuilder: (_, i) => _ComplaintTile(
                              post: complaints[i],
                              onTap: () => Navigator.of(context).push(
                                MaterialPageRoute(
                                    builder: (_) => ComplaintDetailPage(
                                        post: complaints[i])),
                              ),
                            ),
                          ),
                  ),
                ],
              );
            },
          ),

          // ── Drafts tab ─────────────────────────────────────────────
          _loadingDrafts
              ? const Center(
                  child: CircularProgressIndicator(
                      color: Color(0xFF1A237E)))
              : _drafts.isEmpty
                  ? _EmptyState(
                      icon: Icons.edit_note_rounded,
                      title: 'No drafts saved',
                      subtitle: 'Start a complaint and save it as draft',
                    )
                  : RefreshIndicator(
                      onRefresh: _loadDrafts,
                      color: const Color(0xFF1A237E),
                      child: ListView.separated(
                        padding: const EdgeInsets.all(12),
                        itemCount: _drafts.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 8),
                        itemBuilder: (_, i) => _DraftTile(
                          draft: _drafts[i],
                          onEdit: () async {
                            await Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => ReportIssuePage(
                                    existingDraft: _drafts[i]),
                              ),
                            );
                            _loadDrafts();
                          },
                          onDelete: () => _deleteDraft(_drafts[i]),
                        ),
                      ),
                    ),
        ],
      ),
    );
  }
}

// ── Complaint Tile ────────────────────────────────────────────────────────────

class _ComplaintTile extends StatelessWidget {
  final PostModel post;
  final VoidCallback onTap;
  const _ComplaintTile({required this.post, required this.onTap});

  Color _statusColor(ComplaintStatus s) {
    switch (s) {
      case ComplaintStatus.pendingReview: return Colors.orange;
      case ComplaintStatus.approved:      return Colors.blue;
      case ComplaintStatus.underReview:   return Colors.blueGrey;
      case ComplaintStatus.inProgress:    return Colors.blue;
      case ComplaintStatus.resolved:      return Colors.green;
      case ComplaintStatus.rejected:      return Colors.red;
      case ComplaintStatus.flagged:       return Colors.deepOrange;
      default:                            return Colors.grey;
    }
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
      default:                            return 'Unknown';
    }
  }

  IconData _statusIcon(ComplaintStatus s) {
    switch (s) {
      case ComplaintStatus.pendingReview: return Icons.hourglass_top_rounded;
      case ComplaintStatus.approved:      return Icons.thumb_up_outlined;
      case ComplaintStatus.underReview:   return Icons.manage_search_rounded;
      case ComplaintStatus.inProgress:    return Icons.autorenew_rounded;
      case ComplaintStatus.resolved:      return Icons.check_circle_rounded;
      case ComplaintStatus.rejected:      return Icons.cancel_rounded;
      case ComplaintStatus.flagged:       return Icons.flag_rounded;
      default:                            return Icons.help_outline_rounded;
    }
  }

  String _timeAgo(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${dt.day}/${dt.month}/${dt.year}';
  }

  @override
  Widget build(BuildContext context) {
    final color = _statusColor(post.status);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 8,
                offset: const Offset(0, 2))
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Status bar at top
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(16)),
              ),
              child: Row(
                children: [
                  Icon(_statusIcon(post.status), size: 16, color: color),
                  const SizedBox(width: 6),
                  Text(_statusLabel(post.status),
                      style: TextStyle(
                          color: color,
                          fontSize: 13,
                          fontWeight: FontWeight.w700)),
                  const Spacer(),
                  Text(_timeAgo(post.createdAt),
                      style: TextStyle(
                          color: Colors.grey.shade500, fontSize: 12)),
                ],
              ),
            ),

            // Content
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Category + title
                  Row(
                    children: [
                      Text(post.category.icon,
                          style: const TextStyle(fontSize: 13)),
                      const SizedBox(width: 6),
                      Text(post.category.label,
                          style: TextStyle(
                              fontSize: 12,
                              color: Colors.indigo.shade400,
                              fontWeight: FontWeight.w600)),
                      if (!post.isPublic) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.grey.shade100,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.lock_outline_rounded,
                                  size: 10, color: Colors.grey.shade500),
                              const SizedBox(width: 3),
                              Text('Private',
                                  style: TextStyle(
                                      fontSize: 10,
                                      color: Colors.grey.shade500)),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    post.title.isEmpty ? 'Untitled' : post.title,
                    style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF1A237E)),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    post.description,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 13,
                        color: Colors.grey.shade600,
                        height: 1.4),
                  ),
                  const SizedBox(height: 10),

                  // Footer — location + media + social counts
                  Row(
                    children: [
                      Icon(Icons.location_on_outlined,
                          size: 13, color: Colors.grey.shade400),
                      const SizedBox(width: 3),
                      Expanded(
                        child: Text(
                          [
                            post.building,
                            if (post.floor != null) post.floor!,
                          ].join(', '),
                          style: TextStyle(
                              fontSize: 12, color: Colors.grey.shade500),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (post.imageUrls.isNotEmpty) ...[
                        Icon(Icons.photo_outlined,
                            size: 13, color: Colors.grey.shade400),
                        const SizedBox(width: 2),
                        Text('${post.imageUrls.length}',
                            style: TextStyle(
                                fontSize: 12, color: Colors.grey.shade400)),
                        const SizedBox(width: 8),
                      ],
                      Icon(Icons.thumb_up_outlined,
                          size: 13, color: Colors.grey.shade400),
                      const SizedBox(width: 2),
                      Text('${post.supportCount}',
                          style: TextStyle(
                              fontSize: 12, color: Colors.grey.shade400)),
                      const SizedBox(width: 8),
                      Icon(Icons.chat_bubble_outline_rounded,
                          size: 13, color: Colors.grey.shade400),
                      const SizedBox(width: 2),
                      Text('${post.commentCount}',
                          style: TextStyle(
                              fontSize: 12, color: Colors.grey.shade400)),
                    ],
                  ),
                ],
              ),
            ),

            // Progress indicator bar at bottom
            ClipRRect(
              borderRadius:
                  const BorderRadius.vertical(bottom: Radius.circular(16)),
              child: LinearProgressIndicator(
                value: _progressValue(post.status),
                backgroundColor: Colors.grey.shade100,
                valueColor: AlwaysStoppedAnimation<Color>(color),
                minHeight: 3,
              ),
            ),
          ],
        ),
      ),
    );
  }

  double _progressValue(ComplaintStatus s) {
    switch (s) {
      case ComplaintStatus.pendingReview: return 0.15;
      case ComplaintStatus.approved:      return 0.30;
      case ComplaintStatus.underReview:   return 0.50;
      case ComplaintStatus.inProgress:    return 0.75;
      case ComplaintStatus.resolved:      return 1.0;
      case ComplaintStatus.rejected:      return 1.0;
      case ComplaintStatus.flagged:       return 0.15;
      default:                            return 0.0;
    }
  }
}

// ── Draft Tile ────────────────────────────────────────────────────────────────

class _DraftTile extends StatelessWidget {
  final PostModel draft;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  const _DraftTile(
      {required this.draft, required this.onEdit, required this.onDelete});

  String _timeAgo(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${dt.day}/${dt.month}/${dt.year}';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.03),
              blurRadius: 6,
              offset: const Offset(0, 2))
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Draft header
          Container(
            width: double.infinity,
            padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.grey.shade50,
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(16)),
            ),
            child: Row(
              children: [
                Icon(Icons.edit_note_rounded,
                    size: 16, color: Colors.grey.shade500),
                const SizedBox(width: 6),
                Text('Draft',
                    style: TextStyle(
                        color: Colors.grey.shade600,
                        fontSize: 13,
                        fontWeight: FontWeight.w700)),
                const Spacer(),
                Text('Saved ${_timeAgo(draft.updatedAt)}',
                    style: TextStyle(
                        color: Colors.grey.shade400, fontSize: 12)),
              ],
            ),
          ),

          // Content
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                    children: [
                      Text(draft.category.icon,
                          style: const TextStyle(fontSize: 13)),
                      const SizedBox(width: 6),
                      Text(draft.category.label,
                          style: TextStyle(
                              fontSize: 12,
                              color: Colors.indigo.shade400,
                              fontWeight: FontWeight.w600)),
                    ],
                  ),
                const SizedBox(height: 4),
                Text(
                  draft.title.isEmpty ? 'Untitled draft' : draft.title,
                  style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF1A237E)),
                ),
                if (draft.description.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    draft.description,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 13,
                        color: Colors.grey.shade600,
                        height: 1.4),
                  ),
                ],
                const SizedBox(height: 12),

                // Action buttons
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: onEdit,
                        icon: const Icon(Icons.edit_rounded, size: 16),
                        label: const Text('Continue editing'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFF1A237E),
                          side: const BorderSide(color: Color(0xFF1A237E)),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10)),
                          padding:
                              const EdgeInsets.symmetric(vertical: 8),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      onPressed: onDelete,
                      icon: const Icon(Icons.delete_outline_rounded),
                      color: Colors.red.shade400,
                      style: IconButton.styleFrom(
                        backgroundColor: Colors.red.shade50,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Empty State ───────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Widget? action;
  const _EmptyState({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.action,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: const Color(0xFF1A237E).withValues(alpha: 0.08),
                shape: BoxShape.circle,
              ),
              child: Icon(icon,
                  size: 40,
                  color: const Color(0xFF1A237E).withValues(alpha: 0.5)),
            ),
            const SizedBox(height: 20),
            Text(title,
                style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF1A237E))),
            const SizedBox(height: 8),
            Text(subtitle,
                textAlign: TextAlign.center,
                style:
                    TextStyle(fontSize: 14, color: Colors.grey.shade500)),
            if (action != null) ...[
              const SizedBox(height: 24),
              action!,
            ],
          ],
        ),
      ),
    );
  }
}

// ── Summary Chip ──────────────────────────────────────────────────────────────

class _SummaryChip extends StatelessWidget {
  final String label;
  final int count;
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  const _SummaryChip({
    required this.label,
    required this.count,
    required this.color,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? color : color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? color : color.withValues(alpha: 0.3),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: selected ? Colors.white : color,
              ),
            ),
            const SizedBox(width: 5),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(
                color: selected
                    ? Colors.white.withValues(alpha: 0.3)
                    : color.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '$count',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: selected ? Colors.white : color,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
