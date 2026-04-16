// lib/features/profile/presentation/pages/user_profile_page.dart

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../../main.dart' show AppColors;
import '../../../../services/auth_service.dart';
import '../../../../services/post_service.dart';
import '../../../../models/post_model.dart';

class UserProfilePage extends StatefulWidget {
  final void Function(int)? onSwitchTab;
  const UserProfilePage({super.key, this.onSwitchTab});

  @override
  State<UserProfilePage> createState() => _UserProfilePageState();
}

class _UserProfilePageState extends State<UserProfilePage> {
  final _nameController = TextEditingController();
  bool _isEditingName = false;
  bool _isSavingName = false;

  @override
  void initState() {
    super.initState();
    final user = FirebaseAuth.instance.currentUser;
    _nameController.text = user?.displayName ?? '';
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  // ── Parse department label from tag ───────────────────────────────────────

  String _departmentLabel(String tag) {
    switch (tag.toLowerCase()) {
      case 'co':  return 'Computer Engineering';
      case 'ce':  return 'Civil Engineering';
      case 'me':  return 'Mechanical Engineering';
      case 'ee':  return 'Electrical Engineering';
      case 'ej':  return 'Electronics Engineering';
      case 'it':  return 'Information Technology';
      case 'bit': return 'B.Sc. IT';
      case 'bca': return 'BCA';
      case 'mba': return 'MBA';
      case 'mca': return 'MCA';
      case 'arc': return 'Architecture';
      case 'ph':  return 'Pharmacy';
      default:    return tag.toUpperCase();
    }
  }

  String _admissionYearLabel(String yr, bool isDirect) {
    final year = int.tryParse(yr) ?? 0;
    final fullYear = 2000 + year;
    if (isDirect) return 'Direct Second Year ($fullYear)';
    return 'Admitted $fullYear';
  }

  // ── Name moderation ───────────────────────────────────────────────────────

  static const List<String> _bannedNameWords = [
    'fuck', 'shit', 'bitch', 'bastard', 'asshole', 'cunt', 'porn',
    'nude', 'idiot', 'stupid', 'moron', 'retard',
    'pagal', 'jhahil', 'chutiya', 'harami', 'gaandu', 'madarchod',
    'behenchod', 'bhenchod', 'randi', 'kutta', 'saala', 'bsdk',
  ];

  String? _validateName(String name) {
    if (name.trim().isEmpty) return 'Name cannot be empty.';
    if (name.trim().length < 2) return 'Name must be at least 2 characters.';
    if (name.trim().length > 50) return 'Name must be under 50 characters.';
    final lower = name.toLowerCase();
    for (final word in _bannedNameWords) {
      if (lower.contains(word)) {
        return 'Display name contains inappropriate content.';
      }
    }
    return null;
  }

  // ── Save display name ─────────────────────────────────────────────────────

  Future<void> _saveName() async {
    final name = _nameController.text.trim();
    final error = _validateName(name);
    if (error != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(error),
        backgroundColor: Colors.red,
        behavior: SnackBarBehavior.floating,
      ));
      return;
    }
    setState(() => _isSavingName = true);
    try {
      final user = FirebaseAuth.instance.currentUser!;
      await user.updateDisplayName(name);
      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .update({'displayName': name});
      if (mounted) {
        setState(() => _isEditingName = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Name updated successfully.'),
            backgroundColor: Colors.green,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to update: $e'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSavingName = false);
    }
  }

  // ── Sign out ──────────────────────────────────────────────────────────────

  Future<void> _signOut() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Sign Out',
            style: TextStyle(
                fontWeight: FontWeight.bold,
                color: AppColors.primary)),
        content:
            const Text('Are you sure you want to sign out?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.rejected,
                foregroundColor: Colors.white),
            child: const Text('Sign Out'),
          ),
        ],
      ),
    );
    if (confirm == true) {
      await AuthService.instance.signOut();
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final email = user?.email ?? '';
    final emailInfo = AuthService.instance.parseAiktcEmail(email);
    final name = user?.displayName ?? 'Student';
    final initials = name.isNotEmpty ? name[0].toUpperCase() : 'S';

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: SingleChildScrollView(
          child: Column(
            children: [
              // ── Header card ─────────────────────────────────────────
              Container(
                width: double.infinity,
                color: AppColors.surface,
                padding: const EdgeInsets.fromLTRB(20, 28, 20, 24),
                child: Column(
                  children: [
                    // Avatar
                    Container(
                      width: 88,
                      height: 88,
                      decoration: BoxDecoration(
                        color: AppColors.accentLight,
                        shape: BoxShape.circle,
                        border: Border.all(
                            color: AppColors.border, width: 3),
                      ),
                      child: Center(
                        child: Text(
                          initials,
                          style: const TextStyle(
                              fontSize: 36,
                              fontWeight: FontWeight.bold,
                              color: AppColors.primary),
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),

                    // Name + edit
                    _isEditingName
                        ? Column(
                            children: [
                              TextField(
                                controller: _nameController,
                                autofocus: true,
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                    fontSize: 16,
                                    color: AppColors.textDark),
                                decoration: InputDecoration(
                                  hintText: 'Enter your name',
                                  filled: true,
                                  fillColor: AppColors.surfaceAlt,
                                  contentPadding:
                                      const EdgeInsets.symmetric(
                                          horizontal: 16, vertical: 12),
                                  border: OutlineInputBorder(
                                      borderRadius:
                                          BorderRadius.circular(12),
                                      borderSide: const BorderSide(
                                          color: AppColors.border)),
                                  focusedBorder: OutlineInputBorder(
                                    borderRadius:
                                        BorderRadius.circular(12),
                                    borderSide: const BorderSide(
                                        color: AppColors.accent,
                                        width: 1.5),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 10),
                              Row(
                                children: [
                                  Expanded(
                                    child: OutlinedButton(
                                      onPressed: () => setState(
                                          () => _isEditingName = false),
                                      style: OutlinedButton.styleFrom(
                                        foregroundColor:
                                            AppColors.textMid,
                                        side: const BorderSide(
                                            color: AppColors.border),
                                        shape: RoundedRectangleBorder(
                                            borderRadius:
                                                BorderRadius.circular(
                                                    10)),
                                      ),
                                      child: const Text('Cancel'),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: ElevatedButton(
                                      onPressed:
                                          _isSavingName ? null : _saveName,
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: AppColors.primary,
                                        foregroundColor: Colors.white,
                                        shape: RoundedRectangleBorder(
                                            borderRadius:
                                                BorderRadius.circular(
                                                    10)),
                                      ),
                                      child: _isSavingName
                                          ? const SizedBox(
                                              width: 18,
                                              height: 18,
                                              child:
                                                  CircularProgressIndicator(
                                                      strokeWidth: 2,
                                                      color: Colors.white))
                                          : const Text('Save'),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          )
                        : Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(name,
                                  style: const TextStyle(
                                      fontSize: 20,
                                      fontWeight: FontWeight.bold,
                                      color: AppColors.textDark)),
                              const SizedBox(width: 6),
                              GestureDetector(
                                onTap: () => setState(
                                    () => _isEditingName = true),
                                child: const Icon(
                                    Icons.edit_outlined,
                                    size: 16,
                                    color: AppColors.textLight),
                              ),
                            ],
                          ),

                    const SizedBox(height: 4),
                    Text(email,
                        style: const TextStyle(
                            fontSize: 13, color: AppColors.textMid)),

                    // Department + year from email
                    if (emailInfo != null) ...[
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: AppColors.accentLight,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          _departmentLabel(emailInfo.departmentTag),
                          style: const TextStyle(
                              fontSize: 12,
                              color: AppColors.accent,
                              fontWeight: FontWeight.w600),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _admissionYearLabel(
                            emailInfo.admissionYear, emailInfo.isDirect),
                        style: const TextStyle(
                            fontSize: 12, color: AppColors.textLight),
                      ),
                    ],
                  ],
                ),
              ),

              const SizedBox(height: 8),

              // ── Stats row ────────────────────────────────────────────
              StreamBuilder<List<PostModel>>(
                stream: PostService.instance
                    .myComplaintsStream(user?.uid ?? ''),
                builder: (context, snap) {
                  final complaints = snap.data ?? [];
                  final total = complaints.length;
                  final resolved = complaints
                      .where((c) =>
                          c.status == ComplaintStatus.resolved)
                      .length;
                  final pending = complaints
                      .where((c) =>
                          c.status == ComplaintStatus.pendingReview ||
                          c.status == ComplaintStatus.approved ||
                          c.status == ComplaintStatus.underReview ||
                          c.status == ComplaintStatus.inProgress)
                      .length;

                  return Container(
                    color: AppColors.surface,
                    padding: const EdgeInsets.symmetric(vertical: 20),
                    child: Row(
                      children: [
                        _StatCell(
                            value: total.toString(), label: 'Total'),
                        _Divider(),
                        _StatCell(
                            value: resolved.toString(),
                            label: 'Resolved',
                            color: AppColors.resolved),
                        _Divider(),
                        _StatCell(
                            value: pending.toString(),
                            label: 'Active',
                            color: AppColors.inProgress),
                      ],
                    ),
                  );
                },
              ),

              const SizedBox(height: 8),

              // ── Menu items ───────────────────────────────────────────
              Container(
                color: AppColors.surface,
                child: Column(
                  children: [
                    _MenuItem(
                      icon: Icons.assignment_outlined,
                      label: 'My Complaints',
                      subtitle: 'View all your submitted issues',
                      onTap: () {
                        // Switch to My Issues tab (index 1) with bottom nav
                        if (widget.onSwitchTab != null) {
                          widget.onSwitchTab!(1);
                        }
                      },
                    ),
                    _MenuItem(
                      icon: Icons.school_outlined,
                      label: 'Student ID',
                      subtitle: email.split('@').first.toUpperCase(),
                      onTap: null,
                    ),
                    _MenuItem(
                      icon: Icons.info_outline_rounded,
                      label: 'About CampusVoice',
                      subtitle: 'Version 1.0.0 — AIKTC',
                      onTap: null,
                    ),
                    _MenuItem(
                      icon: Icons.logout_rounded,
                      label: 'Sign Out',
                      isDestructive: true,
                      onTap: _signOut,
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Stat Cell ─────────────────────────────────────────────────────────────────

class _StatCell extends StatelessWidget {
  final String value;
  final String label;
  final Color color;

  const _StatCell({
    required this.value,
    required this.label,
    this.color = AppColors.textDark,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Text(value,
              style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: color)),
          const SizedBox(height: 2),
          Text(label,
              style: const TextStyle(
                  fontSize: 12, color: AppColors.textMid)),
        ],
      ),
    );
  }
}

class _Divider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
        width: 1, height: 36, color: AppColors.border);
  }
}

// ── Menu Item ─────────────────────────────────────────────────────────────────

class _MenuItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final String? subtitle;
  final VoidCallback? onTap;
  final bool isDestructive;

  const _MenuItem({
    required this.icon,
    required this.label,
    this.subtitle,
    required this.onTap,
    this.isDestructive = false,
  });

  @override
  Widget build(BuildContext context) {
    final color =
        isDestructive ? AppColors.rejected : AppColors.textDark;
    final iconColor =
        isDestructive ? AppColors.rejected : AppColors.accent;
    final iconBg = isDestructive ? AppColors.redTint : AppColors.accentLight;

    return InkWell(
      onTap: onTap,
      child: Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        decoration: const BoxDecoration(
          border: Border(
            bottom: BorderSide(color: AppColors.border, width: 0.5),
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: iconBg,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, size: 18, color: iconColor),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w500,
                          color: color)),
                  if (subtitle != null)
                    Text(subtitle!,
                        style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.textLight)),
                ],
              ),
            ),
            if (onTap != null)
              Icon(Icons.chevron_right_rounded,
                  size: 20, color: AppColors.textLight),
          ],
        ),
      ),
    );
  }
}
