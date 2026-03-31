// lib/features/feed/presentation/pages/feed_page.dart

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:video_player/video_player.dart';
import '../../../../main.dart' show AppColors;
import '../../../../models/post_model.dart';
import '../../../../services/auth_service.dart';
import '../../../../services/social_service.dart';
import 'complaint_detail_page.dart';

class FeedPage extends StatefulWidget {
  const FeedPage({super.key});
  @override
  State<FeedPage> createState() => _FeedPageState();
}

class _FeedPageState extends State<FeedPage> {
  ComplaintCategory? _filterCategory;
  final _searchController = TextEditingController();
  String _searchQuery = '';
  final _scrollController = ScrollController();
  bool _showElevation = false;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(() {
      final elevated = _scrollController.offset > 4;
      if (elevated != _showElevation) setState(() => _showElevation = elevated);
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Stream<List<PostModel>> get _feedStream {
    Query<Map<String, dynamic>> query = FirebaseFirestore.instance
        .collection('complaints')
        .where('status', isEqualTo: 'approved')
        .orderBy('createdAt', descending: true);
    if (_filterCategory != null) {
      query = query.where('category', isEqualTo: _filterCategory!.name);
    }
    return query.snapshots().map((snap) {
      var posts = snap.docs
          .map((doc) => PostModel.fromFirestore(doc.data(), doc.id))
          .where((p) => p.isPublic)
          .toList();
      if (_searchQuery.isNotEmpty) {
        final q = _searchQuery.toLowerCase();
        posts = posts
            .where((p) =>
                p.title.toLowerCase().contains(q) ||
                p.description.toLowerCase().contains(q) ||
                p.building.toLowerCase().contains(q))
            .toList();
      }
      return posts;
    });
  }

  @override
  Widget build(BuildContext context) {
    final user = AuthService.instance.currentUser;
    final name = user?.displayName?.split(' ').first ?? 'Student';

    return Scaffold(
      backgroundColor: AppColors.background,
      body: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        behavior: HitTestBehavior.translucent,
        child: SafeArea(
        child: RefreshIndicator(
          color: AppColors.primary,
          displacement: 20,
          onRefresh: () async => setState(() {}),
          child: CustomScrollView(
            controller: _scrollController,
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              // ── Sticky header ──────────────────────────────────────
              SliverAppBar(
                pinned: true,
                floating: false,
                backgroundColor: AppColors.surface,
                elevation: _showElevation ? 2 : 0,
                shadowColor: Colors.black12,
                surfaceTintColor: Colors.transparent,
                automaticallyImplyLeading: false,
                titleSpacing: 0,
                toolbarHeight: 64,
                title: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Row(
                    children: [
                      // Logo mark
                      Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          color: AppColors.primary,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(Icons.campaign_rounded,
                            color: Colors.white, size: 22),
                      ),
                      const SizedBox(width: 10),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text('CampusVoice',
                              style: TextStyle(
                                  fontSize: 17,
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.textDark,
                                  height: 1.1)),
                          Text('Hey $name 👋',
                              style: const TextStyle(
                                  fontSize: 12,
                                  color: AppColors.textMid,
                                  height: 1.1)),
                        ],
                      ),
                      const Spacer(),
                      // Avatar
                      CircleAvatar(
                        radius: 18,
                        backgroundColor: AppColors.accentLight,
                        child: Text(
                          name.isNotEmpty ? name[0].toUpperCase() : 'S',
                          style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: AppColors.primary),
                        ),
                      ),
                    ],
                  ),
                ),
                bottom: PreferredSize(
                  preferredSize: const Size.fromHeight(1),
                  child: Container(height: 1, color: AppColors.border),
                ),
              ),

              // ── Search bar ─────────────────────────────────────────
              SliverToBoxAdapter(
                child: Container(
                  color: AppColors.surface,
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                  child: TextField(
                    controller: _searchController,
                    onChanged: (v) => setState(() => _searchQuery = v.trim()),
                    style: const TextStyle(
                        fontSize: 14, color: AppColors.textDark),
                    decoration: InputDecoration(
                      hintText: 'Search complaints, locations...',
                      hintStyle: const TextStyle(
                          color: AppColors.textLight, fontSize: 14),
                      prefixIcon: const Icon(Icons.search_rounded,
                          color: AppColors.textLight, size: 20),
                      suffixIcon: _searchQuery.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.close_rounded,
                                  color: AppColors.textLight, size: 18),
                              onPressed: () {
                                _searchController.clear();
                                setState(() => _searchQuery = '');
                              },
                            )
                          : null,
                      filled: true,
                      fillColor: AppColors.background,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 12),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide.none,
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide:
                            const BorderSide(color: AppColors.border),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: const BorderSide(
                            color: AppColors.accent, width: 1.5),
                      ),
                    ),
                  ),
                ),
              ),

              // ── Category filter chips ──────────────────────────────
              SliverToBoxAdapter(
                child: Container(
                  color: AppColors.surface,
                  child: Column(
                    children: [
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                        child: Row(
                          children: [
                            _CategoryChip(
                              label: 'All',
                              emoji: '📋',
                              isSelected: _filterCategory == null,
                              onTap: () =>
                                  setState(() => _filterCategory = null),
                            ),
                            ...ComplaintCategory.values.map(
                              (cat) => _CategoryChip(
                                label: cat.label,
                                emoji: cat.icon,
                                isSelected: _filterCategory == cat,
                                onTap: () => setState(() =>
                                    _filterCategory =
                                        _filterCategory == cat ? null : cat),
                              ),
                            ),
                          ],
                        ),
                      ),
                      Container(height: 1, color: AppColors.border),
                    ],
                  ),
                ),
              ),

              const SliverToBoxAdapter(child: SizedBox(height: 12)),

              // ── Feed list ──────────────────────────────────────────
              StreamBuilder<List<PostModel>>(
                stream: _feedStream,
                builder: (context, snap) {
                  if (snap.connectionState == ConnectionState.waiting) {
                    return const SliverFillRemaining(
                      child: Center(
                        child: CircularProgressIndicator(
                            color: AppColors.accent),
                      ),
                    );
                  }
                  if (snap.hasError) {
                    return SliverFillRemaining(
                      child: _EmptyFeed(
                        icon: Icons.error_outline_rounded,
                        title: 'Something went wrong',
                        subtitle: snap.error.toString(),
                      ),
                    );
                  }
                  final posts = snap.data ?? [];
                  if (posts.isEmpty) {
                    return SliverFillRemaining(
                      child: _EmptyFeed(
                        icon: _searchQuery.isNotEmpty
                            ? Icons.search_off_rounded
                            : Icons.inbox_outlined,
                        title: _searchQuery.isNotEmpty
                            ? 'No results for "$_searchQuery"'
                            : _filterCategory != null
                                ? 'No ${_filterCategory!.label} complaints'
                                : 'No complaints yet',
                        subtitle: _searchQuery.isNotEmpty
                            ? 'Try different keywords'
                            : 'Be the first to report an issue on campus',
                      ),
                    );
                  }
                  return SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (_, i) => Padding(
                        padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
                        child: ComplaintCard(post: posts[i]),
                      ),
                      childCount: posts.length,
                    ),
                  );
                },
              ),

              const SliverToBoxAdapter(child: SizedBox(height: 100)),
            ],
          ),
        ),
        ), // closes GestureDetector
      ),
    );
  }
}

// ── Category Chip ─────────────────────────────────────────────────────────────
class _CategoryChip extends StatelessWidget {
  final String label, emoji;
  final bool isSelected;
  final VoidCallback onTap;
  const _CategoryChip({
    required this.label,
    required this.emoji,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        margin: const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primary : AppColors.background,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? AppColors.primary : AppColors.border,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(emoji, style: const TextStyle(fontSize: 13)),
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: isSelected ? Colors.white : AppColors.textMid,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Empty Feed ────────────────────────────────────────────────────────────────
class _EmptyFeed extends StatelessWidget {
  final IconData icon;
  final String title, subtitle;
  const _EmptyFeed(
      {required this.icon, required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 90,
              height: 90,
              decoration: BoxDecoration(
                color: AppColors.accentLight,
                shape: BoxShape.circle,
              ),
              child: Icon(icon,
                  size: 44,
                  color: AppColors.accent.withValues(alpha: 0.7)),
            ),
            const SizedBox(height: 20),
            Text(title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textDark)),
            const SizedBox(height: 8),
            Text(subtitle,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontSize: 14,
                    color: AppColors.textMid,
                    height: 1.5)),
          ],
        ),
      ),
    );
  }
}

// ── Complaint Card ────────────────────────────────────────────────────────────
class ComplaintCard extends StatelessWidget {
  final PostModel post;
  const ComplaintCard({super.key, required this.post});

  Color _statusColor(ComplaintStatus s) {
    switch (s) {
      case ComplaintStatus.pendingReview: return AppColors.pending;
      case ComplaintStatus.approved:      return AppColors.inProgress;
      case ComplaintStatus.underReview:   return AppColors.inProgress;
      case ComplaintStatus.inProgress:    return AppColors.inProgress;
      case ComplaintStatus.resolved:      return AppColors.resolved;
      case ComplaintStatus.rejected:      return AppColors.rejected;
      case ComplaintStatus.flagged:       return AppColors.rejected;
      default:                            return AppColors.textLight;
    }
  }

  Color _statusBg(ComplaintStatus s) {
    switch (s) {
      case ComplaintStatus.pendingReview: return AppColors.orangeTint;
      case ComplaintStatus.approved:      return AppColors.blueTint;
      case ComplaintStatus.underReview:   return AppColors.blueTint;
      case ComplaintStatus.inProgress:    return AppColors.blueTint;
      case ComplaintStatus.resolved:      return AppColors.greenTint;
      case ComplaintStatus.rejected:      return AppColors.redTint;
      case ComplaintStatus.flagged:       return AppColors.redTint;
      default:                            return AppColors.background;
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
    final uid = AuthService.instance.currentUser?.uid ?? '';
    final hasMedia = post.imageUrls.isNotEmpty || post.videoPaths.isNotEmpty;

    return GestureDetector(
      onTap: () => Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => ComplaintDetailPage(post: post))),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 12,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [

            // ── Header: avatar + name + time + status ────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 14, 14, 0),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 20,
                    backgroundColor: AppColors.accentLight,
                    child: Text(
                      post.userName.isNotEmpty
                          ? post.userName[0].toUpperCase()
                          : 'S',
                      style: const TextStyle(
                          color: AppColors.primary,
                          fontWeight: FontWeight.bold,
                          fontSize: 16),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(post.userName,
                            style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 14,
                                color: AppColors.textDark)),
                        Row(
                          children: [
                            const Icon(Icons.location_on_outlined,
                                size: 11, color: AppColors.textLight),
                            const SizedBox(width: 2),
                            Text(
                              '${post.building}  ·  ${_timeAgo(post.createdAt)}',
                              style: const TextStyle(
                                  fontSize: 11,
                                  color: AppColors.textLight),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  // Status badge
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: _statusBg(post.status),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      _statusLabel(post.status),
                      style: TextStyle(
                          color: _statusColor(post.status),
                          fontSize: 11,
                          fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
              ),
            ),

            // ── Category + Title + Description ───────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Category pill
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: AppColors.accentLight,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(post.category.icon,
                            style: const TextStyle(fontSize: 11)),
                        const SizedBox(width: 4),
                        Text(post.category.label,
                            style: const TextStyle(
                                fontSize: 11,
                                color: AppColors.accent,
                                fontWeight: FontWeight.w700)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 7),
                  // Title
                  Text(
                    post.title,
                    style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textDark,
                        height: 1.3),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 5),
                  // Description
                  Text(
                    post.description,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 13,
                        color: AppColors.textMid,
                        height: 1.45),
                  ),
                ],
              ),
            ),

            // ── Full-width media carousel ────────────────────────
            if (hasMedia) ...[
              const SizedBox(height: 12),
              FeedMediaCarousel(
                imageUrls: post.imageUrls,
                videoPaths: post.videoPaths,
              ),
            ],

            // ── Divider ───────────────────────────────────────────
            Padding(
              padding: EdgeInsets.symmetric(
                  horizontal: hasMedia ? 0 : 14),
              child: const Divider(
                  height: 20, thickness: 0.5, color: AppColors.border),
            ),

            // ── Action bar ────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
              child: Row(
                children: [
                  // Support button — live
                  StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                    stream: FirebaseFirestore.instance
                        .collection('complaints')
                        .doc(post.id)
                        .collection('supporters')
                        .doc(uid)
                        .snapshots(),
                    builder: (context, snap) {
                      final supported = snap.data?.exists ?? false;
                      return GestureDetector(
                        onTap: () => SocialService.instance.toggleSupport(
                            complaintId: post.id!, userId: uid),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 7),
                          decoration: BoxDecoration(
                            color: supported
                                ? AppColors.accentLight
                                : AppColors.background,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: supported
                                  ? AppColors.accent
                                  : AppColors.border,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              AnimatedSwitcher(
                                duration: const Duration(milliseconds: 200),
                                child: Icon(
                                  supported
                                      ? Icons.thumb_up_rounded
                                      : Icons.thumb_up_alt_outlined,
                                  key: ValueKey(supported),
                                  size: 15,
                                  color: supported
                                      ? AppColors.accent
                                      : AppColors.textLight,
                                ),
                              ),
                              const SizedBox(width: 5),
                              StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                                stream: FirebaseFirestore.instance
                                    .collection('complaints')
                                    .doc(post.id)
                                    .snapshots(),
                                builder: (context, countSnap) {
                                  final count = countSnap.hasData
                                      ? ((countSnap.data!.data()?[
                                                  'supportCount'] ??
                                              post.supportCount) as int)
                                      : post.supportCount;
                                  return Text(
                                    '$count Support${count == 1 ? '' : 's'}',
                                    style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                        color: supported
                                            ? AppColors.accent
                                            : AppColors.textLight),
                                  );
                                },
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),

                  const SizedBox(width: 10),

                  // Comment count — live
                  StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                    stream: FirebaseFirestore.instance
                        .collection('complaints')
                        .doc(post.id)
                        .snapshots(),
                    builder: (context, snap) {
                      final count = snap.hasData
                          ? ((snap.data!.data()?['commentCount'] ??
                              post.commentCount) as int)
                          : post.commentCount;
                      return Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 7),
                        decoration: BoxDecoration(
                          color: AppColors.background,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: AppColors.border),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                                Icons.chat_bubble_outline_rounded,
                                size: 15,
                                color: AppColors.textLight),
                            const SizedBox(width: 5),
                            Text('$count',
                                style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.textLight)),
                          ],
                        ),
                      );
                    },
                  ),

                  const Spacer(),

                  // GPS verified
                  if (post.isOnCampus == true)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 5),
                      decoration: BoxDecoration(
                        color: AppColors.greenTint,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.verified_rounded,
                              size: 12, color: AppColors.resolved),
                          const SizedBox(width: 3),
                          Text('Verified',
                              style: TextStyle(
                                  fontSize: 11,
                                  color: AppColors.resolved,
                                  fontWeight: FontWeight.w600)),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Card Media Preview ────────────────────────────────────────────────────────
// ── Media Item Model ──────────────────────────────────────────────────────────
enum MediaType { image, video }

class MediaItem {
  final String url;
  final MediaType type;
  const MediaItem({required this.url, required this.type});
}

// ── Feed Media Carousel ───────────────────────────────────────────────────────
class FeedMediaCarousel extends StatefulWidget {
  final List<String> imageUrls;
  final List<String> videoPaths;
  const FeedMediaCarousel(
      {super.key, required this.imageUrls, required this.videoPaths});

  @override
  State<FeedMediaCarousel> createState() => _FeedMediaCarouselState();
}

class _FeedMediaCarouselState extends State<FeedMediaCarousel> {
  int _current = 0;

  List<MediaItem> get _items => [
        ...widget.imageUrls
            .map((u) => MediaItem(url: u, type: MediaType.image)),
        ...widget.videoPaths
            .map((p) => MediaItem(url: p, type: MediaType.video)),
      ];

  void _openFullscreen(int index) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => FullScreenMediaViewer(
        items: _items,
        initialIndex: index,
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final items = _items;
    if (items.isEmpty) return const SizedBox.shrink();

    return Column(
      children: [
        SizedBox(
          height: 220,
          child: PageView.builder(
            itemCount: items.length,
            onPageChanged: (i) => setState(() => _current = i),
            itemBuilder: (_, i) {
              final item = items[i];
              return item.type == MediaType.image
                  ? _CarouselImage(
                      url: item.url, onTap: () => _openFullscreen(i))
                  : _CarouselVideo(
                      path: item.url,
                      onTapFullscreen: () => _openFullscreen(i));
            },
          ),
        ),
        if (items.length > 1) ...[
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(
              items.length,
              (i) => AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                margin: const EdgeInsets.symmetric(horizontal: 3),
                width: _current == i ? 16 : 6,
                height: 6,
                decoration: BoxDecoration(
                  color: _current == i
                      ? AppColors.accent
                      : AppColors.border,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

// ── Carousel Image ────────────────────────────────────────────────────────────
class _CarouselImage extends StatelessWidget {
  final String url;
  final VoidCallback onTap;
  const _CarouselImage({required this.url, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Image.network(url,
              fit: BoxFit.cover,
              loadingBuilder: (_, child, progress) => progress == null
                  ? child
                  : Container(
                      color: AppColors.border,
                      child: const Center(
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: AppColors.accent))),
              errorBuilder: (_, _, _) => Container(
                  color: AppColors.border,
                  child: const Icon(Icons.broken_image,
                      size: 48, color: AppColors.textLight))),
          Positioned(
            top: 8,
            right: 8,
            child: Container(
              padding: const EdgeInsets.all(5),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.45),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.zoom_out_map_rounded,
                  color: Colors.white, size: 14),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Carousel Video ────────────────────────────────────────────────────────────
class _CarouselVideo extends StatefulWidget {
  final String path;
  final VoidCallback onTapFullscreen;
  const _CarouselVideo(
      {required this.path, required this.onTapFullscreen});

  @override
  State<_CarouselVideo> createState() => _CarouselVideoState();
}

class _CarouselVideoState extends State<_CarouselVideo> {
  VideoPlayerController? _controller;
  bool _initialized = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final ctrl = widget.path.startsWith('http')
        ? VideoPlayerController.networkUrl(Uri.parse(widget.path))
        : VideoPlayerController.file(File(widget.path));
    _controller = ctrl;
    await ctrl.initialize();
    await ctrl.seekTo(Duration.zero);
    if (mounted) setState(() => _initialized = true);
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  String _fmt(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black,
      child: !_initialized
          ? const Center(
              child: CircularProgressIndicator(color: Colors.white))
          : Stack(
              fit: StackFit.expand,
              children: [
                FittedBox(
                  fit: BoxFit.contain,
                  child: SizedBox(
                    width: _controller!.value.size.width,
                    height: _controller!.value.size.height,
                    child: VideoPlayer(_controller!),
                  ),
                ),
                ValueListenableBuilder(
                  valueListenable: _controller!,
                  builder: (_, v, _) => GestureDetector(
                    onTap: () => setState(() => v.isPlaying
                        ? _controller!.pause()
                        : _controller!.play()),
                    child: AnimatedOpacity(
                      opacity: v.isPlaying ? 0.0 : 1.0,
                      duration: const Duration(milliseconds: 200),
                      child: Container(
                        color: Colors.transparent,
                        child: Center(
                          child: Container(
                            width: 52,
                            height: 52,
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.6),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.play_arrow_rounded,
                                color: Colors.white, size: 30),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                if (_initialized)
                  Positioned(
                    top: 8,
                    right: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 3),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.65),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.videocam_rounded,
                              color: Colors.white, size: 12),
                          const SizedBox(width: 3),
                          Text(
                            _fmt(_controller!.value.duration),
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                    ),
                  ),
                Positioned(
                  bottom: 28,
                  right: 8,
                  child: GestureDetector(
                    onTap: () {
                      _controller?.pause();
                      widget.onTapFullscreen();
                    },
                    child: Container(
                      padding: const EdgeInsets.all(5),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.5),
                        borderRadius: BorderRadius.circular(7),
                      ),
                      child: const Icon(Icons.fullscreen_rounded,
                          color: Colors.white, size: 18),
                    ),
                  ),
                ),
                Positioned(
                  bottom: 6,
                  left: 8,
                  right: 8,
                  child: VideoProgressIndicator(_controller!,
                      allowScrubbing: true,
                      colors: const VideoProgressColors(
                          playedColor: AppColors.accent,
                          bufferedColor: Colors.white38,
                          backgroundColor: Colors.white12)),
                ),
              ],
            ),
    );
  }
}

// ── Full Screen Media Viewer ──────────────────────────────────────────────────
class FullScreenMediaViewer extends StatefulWidget {
  final List<MediaItem> items;
  final int initialIndex;
  const FullScreenMediaViewer(
      {super.key, required this.items, required this.initialIndex});

  @override
  State<FullScreenMediaViewer> createState() =>
      _FullScreenMediaViewerState();
}

class _FullScreenMediaViewerState extends State<FullScreenMediaViewer> {
  late PageController _pageController;
  late int _current;
  bool _showUI = true;

  @override
  void initState() {
    super.initState();
    _current = widget.initialIndex;
    _pageController = PageController(initialPage: widget.initialIndex);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        onTap: () => setState(() => _showUI = !_showUI),
        child: Stack(
          children: [
            PageView.builder(
              controller: _pageController,
              itemCount: widget.items.length,
              onPageChanged: (i) => setState(() => _current = i),
              itemBuilder: (_, i) {
                final item = widget.items[i];
                return item.type == MediaType.image
                    ? _FullscreenImage(url: item.url)
                    : _FullscreenVideo(path: item.url);
              },
            ),
            AnimatedOpacity(
              opacity: _showUI ? 1.0 : 0.0,
              duration: const Duration(milliseconds: 200),
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 4),
                  child: Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.close_rounded,
                            color: Colors.white, size: 28),
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                      const Spacer(),
                      if (widget.items.length > 1)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 5),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.5),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            '${_current + 1} / ${widget.items.length}',
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 14,
                                fontWeight: FontWeight.w600),
                          ),
                        ),
                      const SizedBox(width: 8),
                    ],
                  ),
                ),
              ),
            ),
            if (widget.items.length > 1)
              AnimatedOpacity(
                opacity: _showUI ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 200),
                child: Positioned(
                  bottom: 32,
                  left: 0,
                  right: 0,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(
                      widget.items.length,
                      (i) => AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        margin: const EdgeInsets.symmetric(horizontal: 3),
                        width: _current == i ? 20 : 6,
                        height: 6,
                        decoration: BoxDecoration(
                          color: _current == i
                              ? Colors.white
                              : Colors.white38,
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _FullscreenImage extends StatelessWidget {
  final String url;
  const _FullscreenImage({required this.url});

  @override
  Widget build(BuildContext context) => InteractiveViewer(
        minScale: 0.5,
        maxScale: 5.0,
        child: Center(
          child: Image.network(url,
              fit: BoxFit.contain,
              loadingBuilder: (_, child, p) => p == null
                  ? child
                  : const Center(
                      child: CircularProgressIndicator(
                          color: Colors.white)),
              errorBuilder: (_, _, _) => const Icon(
                  Icons.broken_image,
                  size: 64,
                  color: Colors.white54)),
        ),
      );
}

class _FullscreenVideo extends StatefulWidget {
  final String path;
  const _FullscreenVideo({required this.path});

  @override
  State<_FullscreenVideo> createState() => _FullscreenVideoState();
}

class _FullscreenVideoState extends State<_FullscreenVideo> {
  VideoPlayerController? _controller;
  bool _initialized = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final ctrl = widget.path.startsWith('http')
        ? VideoPlayerController.networkUrl(Uri.parse(widget.path))
        : VideoPlayerController.file(File(widget.path));
    _controller = ctrl;
    await ctrl.initialize();
    await ctrl.play();
    if (mounted) setState(() => _initialized = true);
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  String _fmt(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    if (!_initialized) {
      return const Center(
          child: CircularProgressIndicator(color: Colors.white));
    }
    return Stack(
      alignment: Alignment.center,
      children: [
        Center(
          child: AspectRatio(
            aspectRatio: _controller!.value.aspectRatio,
            child: VideoPlayer(_controller!),
          ),
        ),
        ValueListenableBuilder(
          valueListenable: _controller!,
          builder: (_, v, _) => GestureDetector(
            onTap: () => setState(() =>
                v.isPlaying ? _controller!.pause() : _controller!.play()),
            child: AnimatedOpacity(
              opacity: v.isPlaying ? 0.0 : 1.0,
              duration: const Duration(milliseconds: 200),
              child: Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.6),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.play_arrow_rounded,
                    color: Colors.white, size: 44),
              ),
            ),
          ),
        ),
        Positioned(
          bottom: 48,
          left: 16,
          right: 16,
          child: Column(
            children: [
              VideoProgressIndicator(_controller!,
                  allowScrubbing: true,
                  colors: const VideoProgressColors(
                      playedColor: Colors.white,
                      bufferedColor: Colors.white38,
                      backgroundColor: Colors.white24)),
              const SizedBox(height: 6),
              ValueListenableBuilder(
                valueListenable: _controller!,
                builder: (_, v, _) => Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(_fmt(v.position),
                        style: const TextStyle(
                            color: Colors.white, fontSize: 12)),
                    Text(_fmt(v.duration),
                        style: const TextStyle(
                            color: Colors.white54, fontSize: 12)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
