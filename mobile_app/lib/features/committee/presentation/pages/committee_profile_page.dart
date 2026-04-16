// lib/features/committee/presentation/pages/committee_profile_page.dart

import 'package:flutter/material.dart';
import '../../../../services/auth_service.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../../../main.dart' show AppColors;
import '../../../../models/committee_member_model.dart';

class CommitteeProfilePage extends StatelessWidget {
  final CommitteeMember member;
  const CommitteeProfilePage({super.key, required this.member});

  Future<void> _signOut(BuildContext context) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Sign Out',
            style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.primary)),
        content: const Text('Are you sure you want to sign out?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.rejected, foregroundColor: Colors.white),
            child: const Text('Sign Out'),
          ),
        ],
      ),
    );
    if (confirm == true) await AuthService.instance.signOut();
  }

  @override
  Widget build(BuildContext context) {
    final email = FirebaseAuth.instance.currentUser?.email ?? member.email;
    final displayName = member.name.isNotEmpty ? member.name : member.committee.label;
    final initials = displayName.split(' ').map((w) => w.isNotEmpty ? w[0] : '').take(2).join().toUpperCase();

    return Scaffold(
      backgroundColor: const Color(0xFFF5F6FA),
      body: CustomScrollView(
        slivers: [
          // Header
          SliverAppBar(
            expandedHeight: 200,
            pinned: true,
            automaticallyImplyLeading: false,
            backgroundColor: AppColors.primary,
            flexibleSpace: FlexibleSpaceBar(
              background: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFF1A237E), Color(0xFF283593)],
                  ),
                ),
                child: SafeArea(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const SizedBox(height: 16),
                      Container(
                        width: 80, height: 80,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.15),
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white.withValues(alpha: 0.4), width: 2),
                        ),
                        child: Center(
                          child: Text(initials,
                              style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.white)),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(displayName,
                          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
                      const SizedBox(height: 4),
                      Text(email,
                          style: const TextStyle(fontSize: 13, color: Colors.white60)),
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(member.committee.label,
                            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Colors.white)),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),

          // Content
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Committee info card
                  _InfoCard(children: [
                    _InfoTile(icon: Icons.business_center_outlined,
                        label: 'Committee', value: member.committee.fullName),
                    _InfoTile(icon: Icons.badge_outlined,
                        label: 'Designation', value: member.designation),
                    _InfoTile(icon: Icons.category_outlined,
                        label: 'Handles',
                        value: member.committee.categories
                            .map((c) => c[0].toUpperCase() + c.substring(1)).join(', '),
                        isLast: true),
                  ]),

                  const SizedBox(height: 12),

                  // Account card
                  _InfoCard(children: [
                    _InfoTile(icon: Icons.email_outlined, label: 'Email', value: email, isLast: true),
                  ]),

                  const SizedBox(height: 12),

                  // Sign out
                  Material(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(14),
                      onTap: () => _signOut(context),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: AppColors.border),
                        ),
                        child: Row(children: [
                          Container(
                            width: 36, height: 36,
                            decoration: BoxDecoration(
                                color: AppColors.redTint, borderRadius: BorderRadius.circular(10)),
                            child: const Icon(Icons.logout_rounded, size: 18, color: AppColors.rejected),
                          ),
                          const SizedBox(width: 14),
                          const Text('Sign Out',
                              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.rejected)),
                          const Spacer(),
                          const Icon(Icons.chevron_right_rounded, color: AppColors.textLight),
                        ]),
                      ),
                    ),
                  ),

                  const SizedBox(height: 32),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  final List<Widget> children;
  const _InfoCard({required this.children});

  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: AppColors.border),
    ),
    child: Column(children: children),
  );
}

class _InfoTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final bool isLast;
  const _InfoTile({required this.icon, required this.label, required this.value, this.isLast = false});

  @override
  Widget build(BuildContext context) => Column(children: [
    Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
      child: Row(children: [
        Container(
          width: 36, height: 36,
          decoration: BoxDecoration(color: AppColors.accentLight, borderRadius: BorderRadius.circular(10)),
          child: Icon(icon, size: 18, color: AppColors.accent),
        ),
        const SizedBox(width: 14),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: const TextStyle(fontSize: 12, color: AppColors.textLight)),
          const SizedBox(height: 2),
          Text(value, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: AppColors.textDark)),
        ])),
      ]),
    ),
    if (!isLast) const Divider(height: 1, indent: 66, color: AppColors.border),
  ]);
}
