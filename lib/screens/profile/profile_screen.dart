import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:my_app/models/models.dart';
import 'package:my_app/services/pos_service.dart';
import 'package:my_app/core/theme/theme_controller.dart';
import 'package:my_app/core/utils/responsive.dart';
import 'package:my_app/screens/auth/login_screen.dart';

class ProfileScreen extends StatefulWidget {
  final UserProfile userProfile;
  final String restaurantName;
  final ValueChanged<UserProfile>? onProfileUpdated;

  const ProfileScreen({
    super.key,
    required this.userProfile,
    required this.restaurantName,
    this.onProfileUpdated,
  });

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen>
    with SingleTickerProviderStateMixin {
  final _posService = PosService();

  late UserProfile _currentProfile;
  late TabController _tabController;

  // Form Edit Profil
  late TextEditingController _nameController;
  late TextEditingController _phoneController;
  bool _isSavingProfile = false;

  // Form Ganti Password
  final _newPasswordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  bool _obscureNewPass = true;
  bool _obscureConfirmPass = true;
  bool _isSavingPassword = false;

  // Absensi & Kelola Karyawan
  bool _isLoadingAttendance = true;
  DbAttendance? _todayAttendance;
  List<DbAttendance> _attendanceHistory = [];
  List<DbAttendance> _allStaffTodayAttendances = [];
  String _selectedShift = 'Shift Pagi (08:00 - 16:00)';
  final _notesController = TextEditingController();
  bool _isClocking = false;
  Timer? _timer;
  DateTime _currentTime = DateTime.now();

  // Karyawan Restoran
  List<DbEmployee> _employees = [];
  bool _isLoadingEmployees = false;
  DbEmployee? _selectedEmployeeForAttendance;

  // Preferensi Lokal (Mock state / runtime toggles)
  bool _soundEffectsEnabled = true;
  bool _autoPrintReceipt = false;

  final List<String> _shiftOptions = [
    'Shift Pagi (08:00 - 16:00)',
    'Shift Siang (14:00 - 22:00)',
    'Shift Malam (18:00 - 02:00)',
    'Full Shift (Standby Resto)',
  ];

  // Preset avatar URLs untuk resto
  final List<Map<String, String>> _presetAvatars = [
    {
      'label': 'Chef Pria',
      'url':
          'https://images.unsplash.com/photo-1577219491135-ce391730fb2c?w=200&auto=format&fit=crop&q=80',
    },
    {
      'label': 'Chef Wanita',
      'url':
          'https://images.unsplash.com/photo-1581299894007-aaa50297cf16?w=200&auto=format&fit=crop&q=80',
    },
    {
      'label': 'Barista Kopi',
      'url':
          'https://images.unsplash.com/photo-1534528741775-53994a69daeb?w=200&auto=format&fit=crop&q=80',
    },
    {
      'label': 'Kasir Ramah',
      'url':
          'https://images.unsplash.com/photo-1544005313-94ddf0286df2?w=200&auto=format&fit=crop&q=80',
    },
    {
      'label': 'Head Manager',
      'url':
          'https://images.unsplash.com/photo-1507003211169-0a1dd7228f2d?w=200&auto=format&fit=crop&q=80',
    },
    {
      'label': 'Supervisor',
      'url':
          'https://images.unsplash.com/photo-1500648767791-00dcc994a43e?w=200&auto=format&fit=crop&q=80',
    },
    {
      'label': 'Kitchen Crew',
      'url':
          'https://images.unsplash.com/photo-1522075469751-3a6694fb2f61?w=200&auto=format&fit=crop&q=80',
    },
    {
      'label': 'Service Team',
      'url':
          'https://images.unsplash.com/photo-1494790108377-be9c29b29330?w=200&auto=format&fit=crop&q=80',
    },
  ];

  @override
  void initState() {
    super.initState();
    _currentProfile = widget.userProfile;
    _tabController = TabController(length: 5, vsync: this);

    _nameController = TextEditingController(text: _currentProfile.fullName);
    _phoneController = TextEditingController(text: _currentProfile.phone ?? '');

    _loadAttendanceData();
    _loadEmployees();
    initializeDateFormatting('id_ID', null);

    // Clock update timer
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) {
        setState(() {
          _currentTime = DateTime.now();
        });
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _tabController.dispose();
    _nameController.dispose();
    _phoneController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _loadEmployees() async {
    setState(() => _isLoadingEmployees = true);
    try {
      final list = await _posService.fetchEmployees();
      if (mounted) {
        setState(() {
          _employees = list;
          _isLoadingEmployees = false;
        });
      }
    } catch (e) {
      debugPrint('Error load employees: $e');
      if (mounted) {
        setState(() => _isLoadingEmployees = false);
      }
    }
  }

  Future<void> _loadAttendanceData() async {
    setState(() => _isLoadingAttendance = true);
    try {
      DbAttendance? today;
      List<DbAttendance> history = [];

      if (_selectedEmployeeForAttendance != null) {
        today = await _posService.fetchTodayAttendance(
          null,
          _selectedEmployeeForAttendance!.id,
        );
        history = await _posService.fetchUserAttendanceHistory(
          _selectedEmployeeForAttendance!.id,
        );
      } else {
        today = await _posService.fetchTodayAttendance(_currentProfile.id);
        history = await _posService.fetchUserAttendanceHistory(
          _currentProfile.id,
        );
      }

      final staffToday = await _posService.fetchAllAttendancesToday();

      if (mounted) {
        setState(() {
          _todayAttendance = today;
          _attendanceHistory = history;
          _allStaffTodayAttendances = staffToday;
          _isLoadingAttendance = false;
        });
      }
    } catch (e) {
      debugPrint('Error load attendance: $e');
      if (mounted) {
        setState(() => _isLoadingAttendance = false);
      }
    }
  }

  // ---------------------------------------------------------------------------
  // PROFILE ACTIONS
  // ---------------------------------------------------------------------------
  Future<void> _saveProfileChanges() async {
    final newName = _nameController.text.trim();
    if (newName.isEmpty) {
      _showSnackbar('Nama lengkap tidak boleh kosong', isError: true);
      return;
    }

    setState(() => _isSavingProfile = true);
    try {
      final updated = await _posService.updateUserProfile(
        userId: _currentProfile.id,
        fullName: newName,
        phone: _phoneController.text.trim(),
      );

      setState(() {
        _currentProfile = updated;
        _isSavingProfile = false;
      });

      widget.onProfileUpdated?.call(updated);
      _showSnackbar('Profil berhasil diperbarui!');
    } catch (e) {
      setState(() => _isSavingProfile = false);
      _showSnackbar('Gagal memperbarui profil: $e', isError: true);
    }
  }

  void _openAvatarSelectionModal() {
    final isDark = ThemeController.isDark(context);
    final urlController = TextEditingController();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: isDark ? AppColors.darkCard : AppColors.lightCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Padding(
              padding: EdgeInsets.only(
                left: 20,
                right: 20,
                top: 20,
                bottom: MediaQuery.of(context).viewInsets.bottom + 24,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.grey.withAlpha(100),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      const Icon(
                        Icons.account_circle_rounded,
                        color: AppColors.primary,
                        size: 28,
                      ),
                      const SizedBox(width: 10),
                      Text(
                        'Pilih Foto Profil Restoran',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: isDark
                              ? AppColors.darkText
                              : AppColors.lightText,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Pilih avatar staf restoran siap pakai atau masukkan link foto Anda:',
                    style: TextStyle(
                      fontSize: 13,
                      color: isDark
                          ? AppColors.darkMuted
                          : AppColors.lightMuted,
                    ),
                  ),
                  const SizedBox(height: 18),

                  // Preset Grid
                  SizedBox(
                    height: 190,
                    child: GridView.builder(
                      itemCount: _presetAvatars.length,
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 4,
                            mainAxisSpacing: 10,
                            crossAxisSpacing: 10,
                            childAspectRatio: 0.85,
                          ),
                      itemBuilder: (context, i) {
                        final item = _presetAvatars[i];
                        final isSelected =
                            _currentProfile.avatarUrl == item['url'];

                        return InkWell(
                          onTap: () async {
                            Navigator.pop(ctx);
                            await _updateAvatar(item['url']!);
                          },
                          borderRadius: BorderRadius.circular(14),
                          child: Container(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: isSelected
                                    ? AppColors.primary
                                    : (isDark
                                          ? AppColors.darkBorder
                                          : AppColors.lightBorder),
                                width: isSelected ? 2.5 : 1.2,
                              ),
                            ),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                CircleAvatar(
                                  radius: 26,
                                  backgroundImage: NetworkImage(item['url']!),
                                  backgroundColor: AppColors.primary.withAlpha(
                                    40,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  item['label']!,
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: isSelected
                                        ? FontWeight.bold
                                        : FontWeight.normal,
                                    color: isSelected
                                        ? AppColors.primary
                                        : (isDark
                                              ? AppColors.darkText
                                              : AppColors.lightText),
                                  ),
                                  textAlign: TextAlign.center,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),

                  const SizedBox(height: 14),
                  Divider(
                    color: isDark
                        ? AppColors.darkBorder
                        : AppColors.lightBorder,
                  ),
                  const SizedBox(height: 10),

                  // Input URL Kustom
                  Text(
                    'Atau Masukkan URL Gambar Sendiri:',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: isDark ? AppColors.darkText : AppColors.lightText,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: urlController,
                          decoration: const InputDecoration(
                            hintText: 'https://...',
                            prefixIcon: Icon(Icons.link_rounded),
                            isDense: true,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 14,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        onPressed: () async {
                          final text = urlController.text.trim();
                          if (text.isEmpty) {
                            _showSnackbar(
                              'URL gambar tidak boleh kosong',
                              isError: true,
                            );
                            return;
                          }
                          Navigator.pop(ctx);
                          await _updateAvatar(text);
                        },
                        child: const Text('Pasang'),
                      ),
                    ],
                  ),
                  if (_currentProfile.avatarUrl != null) ...[
                    const SizedBox(height: 10),
                    Center(
                      child: TextButton.icon(
                        style: TextButton.styleFrom(
                          foregroundColor: Colors.redAccent,
                        ),
                        icon: const Icon(
                          Icons.delete_outline_rounded,
                          size: 18,
                        ),
                        label: const Text(
                          'Hapus Foto Profil (Gunakan Inisial)',
                        ),
                        onPressed: () async {
                          Navigator.pop(ctx);
                          await _updateAvatar('');
                        },
                      ),
                    ),
                  ],
                ],
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _updateAvatar(String newUrl) async {
    setState(() => _isSavingProfile = true);
    try {
      final updated = await _posService.updateUserProfile(
        userId: _currentProfile.id,
        avatarUrl: newUrl,
      );

      setState(() {
        _currentProfile = updated;
        _isSavingProfile = false;
      });

      widget.onProfileUpdated?.call(updated);
      _showSnackbar('Foto profil berhasil diperbarui!');
    } catch (e) {
      setState(() => _isSavingProfile = false);
      _showSnackbar('Gagal memperbarui avatar: $e', isError: true);
    }
  }

  // ---------------------------------------------------------------------------
  // ATTENDANCE ACTIONS (CLOCK IN / CLOCK OUT)
  // ---------------------------------------------------------------------------
  Future<void> _handleClockIn() async {
    setState(() => _isClocking = true);
    try {
      final isEmp = _selectedEmployeeForAttendance != null;
      final targetUserId = isEmp ? null : _currentProfile.id;
      final targetEmpId = isEmp ? _selectedEmployeeForAttendance!.id : null;
      final targetName = isEmp
          ? _selectedEmployeeForAttendance!.name
          : _currentProfile.fullName;
      final targetRole = isEmp
          ? _selectedEmployeeForAttendance!.role
          : _currentProfile.role;

      final newAtt = await _posService.clockInAttendance(
        userId: targetUserId,
        employeeId: targetEmpId,
        userName: targetName,
        role: targetRole,
        shift: _selectedShift,
        notes: _notesController.text.trim().isNotEmpty
            ? _notesController.text.trim()
            : null,
      );

      _notesController.clear();
      await _loadAttendanceData();

      if (mounted) {
        _showSuccessDialog(
          title: 'Berhasil Absen Masuk!',
          message:
              'Absensi hadir untuk $targetName telah tercatat pada pukul ${DateFormat('HH:mm').format(newAtt.clockIn)} WIB.\nSelamat bertugas di ${widget.restaurantName}!',
          icon: Icons.check_circle_rounded,
          iconColor: AppColors.statusCompleted,
        );
      }
    } catch (e) {
      _showSnackbar('Gagal mencatat kehadiran: $e', isError: true);
    } finally {
      if (mounted) setState(() => _isClocking = false);
    }
  }

  Future<void> _handleClockOut() async {
    if (_todayAttendance == null) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.logout_rounded, color: Colors.amber, size: 26),
            SizedBox(width: 8),
            Text('Konfirmasi Selesai Shift'),
          ],
        ),
        content: Text(
          'Apakah Anda yakin ingin menyelesaikan shift dan melakukan Absen Pulang sekarang?\nDurasi kerja hari ini: ${_todayAttendance!.durationFormatted}.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Batal'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.amber[800]),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Ya, Absen Pulang'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() => _isClocking = true);
    try {
      final updated = await _posService.clockOutAttendance(
        _todayAttendance!.id,
      );
      await _loadAttendanceData();

      if (mounted) {
        _showSuccessDialog(
          title: 'Shift Selesai! Terima Kasih',
          message:
              'Absen pulang berhasil dicatat pada pukul ${DateFormat('HH:mm').format(updated.clockOut!)} WIB.\nTotal jam bertugas: ${updated.durationFormatted}. Istirahatlah dengan baik!',
          icon: Icons.celebration_rounded,
          iconColor: Colors.amber,
        );
      }
    } catch (e) {
      _showSnackbar('Gagal absen pulang: $e', isError: true);
    } finally {
      if (mounted) setState(() => _isClocking = false);
    }
  }

  // ---------------------------------------------------------------------------
  // SECURITY & PASSWORD ACTIONS
  // ---------------------------------------------------------------------------
  Future<void> _handleChangePassword() async {
    final newPass = _newPasswordController.text.trim();
    final confirmPass = _confirmPasswordController.text.trim();

    if (newPass.length < 6) {
      _showSnackbar('Kata sandi baru minimal 6 karakter', isError: true);
      return;
    }

    if (newPass != confirmPass) {
      _showSnackbar('Konfirmasi kata sandi tidak cocok!', isError: true);
      return;
    }

    setState(() => _isSavingPassword = true);
    try {
      await _posService.updatePassword(newPass);

      _newPasswordController.clear();
      _confirmPasswordController.clear();

      if (mounted) {
        _showSuccessDialog(
          title: 'Kata Sandi Diperbarui!',
          message:
              'Kata sandi akun Anda berhasil diganti dengan aman. Gunakan kata sandi baru untuk login berikutnya.',
          icon: Icons.lock_reset_rounded,
          iconColor: AppColors.primary,
        );
      }
    } catch (e) {
      _showSnackbar('Gagal mengubah kata sandi: $e', isError: true);
    } finally {
      if (mounted) setState(() => _isSavingPassword = false);
    }
  }

  // ---------------------------------------------------------------------------
  // KELOLA KARYAWAN RESTORAN
  // ---------------------------------------------------------------------------
  void _openAddEmployeeDialog([DbEmployee? editEmp]) {
    final nameCtrl = TextEditingController(text: editEmp?.name ?? '');
    final phoneCtrl = TextEditingController(text: editEmp?.phone ?? '');
    final emailCtrl = TextEditingController(text: editEmp?.email ?? '');
    String selectedRole = editEmp?.role ?? 'Kasir';
    String selectedShift = editEmp?.shift ?? 'Shift Pagi (08:00 - 16:00)';
    bool isActive = editEmp?.isActive ?? true;
    final formKey = GlobalKey<FormState>();

    final roles = [
      'Kasir',
      'Koki / Dapur',
      'Pelayan (Waiter)',
      'Barista',
      'Supervisor',
      'Manager',
      'Cleaning Crew',
    ];

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.primary.withAlpha(30),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  editEmp != null
                      ? Icons.edit_rounded
                      : Icons.person_add_alt_1_rounded,
                  color: AppColors.primary,
                  size: 22,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  editEmp != null
                      ? 'Edit Data Karyawan'
                      : 'Tambah Karyawan Baru',
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          content: SingleChildScrollView(
            child: Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Nama Lengkap Karyawan *',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                  const SizedBox(height: 6),
                  TextFormField(
                    controller: nameCtrl,
                    decoration: const InputDecoration(
                      hintText: 'Contoh: Ahmad Fauzi / Siti Rahma',
                      prefixIcon: Icon(Icons.badge_rounded),
                      isDense: true,
                    ),
                    validator: (v) => (v == null || v.trim().isEmpty)
                        ? 'Nama wajib diisi'
                        : null,
                  ),
                  const SizedBox(height: 14),

                  const Text(
                    'Posisi / Jabatan *',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                  const SizedBox(height: 6),
                  DropdownButtonFormField<String>(
                    value: selectedRole,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.work_outline_rounded),
                      isDense: true,
                    ),
                    items: roles
                        .map(
                          (r) => DropdownMenuItem(
                            value: r,
                            child: Text(r, overflow: TextOverflow.ellipsis),
                          ),
                        )
                        .toList(),
                    onChanged: (v) {
                      if (v != null) setDialogState(() => selectedRole = v);
                    },
                  ),
                  const SizedBox(height: 14),

                  const Text(
                    'Shift Kerja *',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                  const SizedBox(height: 6),
                  DropdownButtonFormField<String>(
                    value: selectedShift,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.schedule_rounded),
                      isDense: true,
                    ),
                    items: _shiftOptions
                        .map(
                          (s) => DropdownMenuItem(
                            value: s,
                            child: Text(
                              s,
                              style: const TextStyle(fontSize: 13),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: (v) {
                      if (v != null) setDialogState(() => selectedShift = v);
                    },
                  ),
                  const SizedBox(height: 14),

                  const Text(
                    'Nomor WhatsApp / HP',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                  const SizedBox(height: 6),
                  TextFormField(
                    controller: phoneCtrl,
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(
                      hintText: 'Contoh: 081234567890',
                      prefixIcon: Icon(Icons.phone_android_rounded),
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 14),

                  const Text(
                    'Email (Opsional)',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                  const SizedBox(height: 6),
                  TextFormField(
                    controller: emailCtrl,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(
                      hintText: 'karyawan@restokasir.com',
                      prefixIcon: Icon(Icons.email_outlined),
                      isDense: true,
                    ),
                  ),
                  if (editEmp != null) ...[
                    const SizedBox(height: 12),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text(
                        'Status Aktif Bekerja',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      subtitle: Text(
                        isActive ? 'Karyawan aktif' : 'Nonaktif / Resign',
                        style: const TextStyle(fontSize: 11),
                      ),
                      value: isActive,
                      onChanged: (val) => setDialogState(() => isActive = val),
                    ),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Batal'),
            ),
            FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
              onPressed: () async {
                if (!formKey.currentState!.validate()) return;
                Navigator.pop(ctx);
                try {
                  if (editEmp != null) {
                    await _posService.updateEmployee(
                      id: editEmp.id,
                      name: nameCtrl.text.trim(),
                      role: selectedRole,
                      phone: phoneCtrl.text.trim(),
                      email: emailCtrl.text.trim(),
                      shift: selectedShift,
                      isActive: isActive,
                    );
                    _showSnackbar(
                      'Data karyawan "${nameCtrl.text.trim()}" berhasil diperbarui!',
                    );
                  } else {
                    await _posService.addEmployee(
                      name: nameCtrl.text.trim(),
                      role: selectedRole,
                      phone: phoneCtrl.text.trim(),
                      email: emailCtrl.text.trim(),
                      shift: selectedShift,
                    );
                    _showSnackbar(
                      'Karyawan "${nameCtrl.text.trim()}" berhasil disimpan ke database!',
                    );
                  }
                  await _loadEmployees();
                } catch (e) {
                  _showSnackbar('Gagal menyimpan karyawan: $e', isError: true);
                }
              },
              icon: const Icon(Icons.save_rounded, size: 18),
              label: Text(
                editEmp != null ? 'Simpan Perubahan' : 'Simpan Karyawan',
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _deleteEmployee(DbEmployee emp) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Hapus Data Karyawan?'),
        content: Text(
          'Apakah Anda yakin ingin menghapus "${emp.name}" dari sistem restoran?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Batal'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Hapus'),
          ),
        ],
      ),
    );
    if (confirm == true) {
      try {
        await _posService.deleteEmployee(emp.id);
        _showSnackbar('Karyawan "${emp.name}" berhasil dihapus');
        if (_selectedEmployeeForAttendance?.id == emp.id) {
          setState(() => _selectedEmployeeForAttendance = null);
        }
        await _loadEmployees();
        await _loadAttendanceData();
      } catch (e) {
        _showSnackbar('Gagal menghapus karyawan: $e', isError: true);
      }
    }
  }

  void _showStaffIdCardModal() {
    final isDark = ThemeController.isDark(context);

    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 360),
          decoration: BoxDecoration(
            color: isDark ? AppColors.darkCard : Colors.white,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: isDark ? AppColors.darkBorder : AppColors.lightBorder,
              width: 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withAlpha(60),
                blurRadius: 24,
                offset: const Offset(0, 12),
              ),
            ],
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Badge Top Bar
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 16,
                  ),
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      colors: [AppColors.primaryDark, AppColors.primary],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.vertical(
                      top: Radius.circular(22),
                    ),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.badge_rounded,
                        color: Colors.white,
                        size: 24,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'KARTU IDENTITAS KARYAWAN',
                              style: TextStyle(
                                color: Colors.white70,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 1.1,
                              ),
                            ),
                            Text(
                              widget.restaurantName,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, color: Colors.white),
                        onPressed: () => Navigator.pop(ctx),
                      ),
                    ],
                  ),
                ),

                Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    children: [
                      // Photo Frame
                      Stack(
                        alignment: Alignment.center,
                        children: [
                          Container(
                            width: 104,
                            height: 104,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: const LinearGradient(
                                colors: [
                                  AppColors.primary,
                                  AppColors.primaryLight,
                                ],
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: AppColors.primary.withAlpha(80),
                                  blurRadius: 16,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                          ),
                          CircleAvatar(
                            radius: 48,
                            backgroundColor: isDark
                                ? AppColors.darkSurface
                                : AppColors.lightBg,
                            backgroundImage:
                                _currentProfile.avatarUrl != null &&
                                    _currentProfile.avatarUrl!.isNotEmpty
                                ? NetworkImage(_currentProfile.avatarUrl!)
                                : null,
                            child:
                                _currentProfile.avatarUrl == null ||
                                    _currentProfile.avatarUrl!.isEmpty
                                ? Text(
                                    _currentProfile.initials,
                                    style: const TextStyle(
                                      fontSize: 32,
                                      fontWeight: FontWeight.bold,
                                      color: AppColors.primary,
                                    ),
                                  )
                                : null,
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Text(
                        _currentProfile.fullName,
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: isDark
                              ? AppColors.darkText
                              : AppColors.lightText,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _currentProfile.email,
                        style: TextStyle(
                          fontSize: 12,
                          color: isDark
                              ? AppColors.darkMuted
                              : AppColors.lightMuted,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.primary.withAlpha(35),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: AppColors.primary.withAlpha(100),
                          ),
                        ),
                        child: Text(
                          'STAFF RESTO: ${_currentProfile.role.toUpperCase()}',
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: AppColors.primary,
                            letterSpacing: 0.8,
                          ),
                        ),
                      ),

                      const SizedBox(height: 20),
                      Divider(
                        color: isDark
                            ? AppColors.darkBorder
                            : AppColors.lightBorder,
                      ),
                      const SizedBox(height: 12),

                      // ID Details
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'ID Karyawan:',
                            style: TextStyle(
                              fontSize: 12,
                              color: isDark
                                  ? AppColors.darkMuted
                                  : AppColors.lightMuted,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Flexible(
                            child: Text(
                              'EMP-${_currentProfile.id.length >= 8 ? _currentProfile.id.substring(0, 8).toUpperCase() : _currentProfile.id.toUpperCase()}',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                fontFamily: 'monospace',
                                color: isDark
                                    ? AppColors.darkText
                                    : AppColors.lightText,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Status Keaktifan:',
                            style: TextStyle(
                              fontSize: 12,
                              color: isDark
                                  ? AppColors.darkMuted
                                  : AppColors.lightMuted,
                            ),
                          ),
                          const Row(
                            children: [
                              Icon(
                                Icons.circle,
                                size: 8,
                                color: AppColors.statusCompleted,
                              ),
                              SizedBox(width: 4),
                              Text(
                                'Aktif Bekerja',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.statusCompleted,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),

                      const SizedBox(height: 20),
                      // Barcode / QR Graphic Simulation
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: isDark
                              ? AppColors.darkSurface
                              : Colors.grey[100],
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: isDark
                                ? AppColors.darkBorder
                                : AppColors.lightBorder,
                          ),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(
                              Icons.qr_code_2_rounded,
                              size: 32,
                              color: AppColors.primary,
                            ),
                            const SizedBox(width: 12),
                            Flexible(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'RESTOKASIR AUTHENTICATED',
                                    style: TextStyle(
                                      fontSize: 9,
                                      fontWeight: FontWeight.bold,
                                      color: isDark
                                          ? AppColors.darkMuted
                                          : AppColors.lightMuted,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  Text(
                                    'VERIFIED STAFF BADGE',
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                      color: isDark
                                          ? AppColors.darkText
                                          : AppColors.lightText,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showSuccessDialog({
    required String title,
    required String message,
    required IconData icon,
    required Color iconColor,
  }) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: iconColor.withAlpha(30),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: iconColor, size: 48),
            ),
            const SizedBox(height: 18),
            Text(
              title,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 10),
            Text(
              message,
              style: const TextStyle(fontSize: 13, height: 1.4),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primary,
                minimumSize: const Size.fromHeight(44),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Mengerti'),
            ),
          ],
        ),
      ),
    );
  }

  void _showSnackbar(String msg, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: isError ? Colors.redAccent : AppColors.statusCompleted,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  Future<void> _logout() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Keluar Akun'),
        content: const Text(
          'Apakah Anda yakin ingin keluar dari sesi RestoKasir saat ini?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Batal'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Keluar'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      await _posService.supabase.auth.signOut();
    } catch (_) {}

    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (route) => false,
    );
  }

  // ---------------------------------------------------------------------------
  // BUILD
  // ---------------------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    final isDark = ThemeController.isDark(context);
    final phone = Responsive.isPhone(context);

    return Scaffold(
      backgroundColor: isDark ? AppColors.darkBg : AppColors.lightBg,
      appBar: AppBar(
        title: const Text(
          'Profil & Absensi Resto',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
        ),
        actions: [
          IconButton(
            tooltip: 'Kartu Pegawai Digital',
            icon: const Icon(Icons.badge_outlined),
            onPressed: _showStaffIdCardModal,
          ),
          IconButton(
            tooltip: 'Keluar Akun',
            icon: const Icon(Icons.logout_rounded, color: Colors.redAccent),
            onPressed: _logout,
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(48),
          child: Container(
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  color: isDark ? AppColors.darkBorder : AppColors.lightBorder,
                  width: 1,
                ),
              ),
            ),
            child: TabBar(
              controller: _tabController,
              isScrollable: phone,
              labelColor: AppColors.primary,
              unselectedLabelColor: isDark
                  ? AppColors.darkMuted
                  : AppColors.lightMuted,
              indicatorColor: AppColors.primary,
              indicatorWeight: 3,
              labelStyle: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 13,
              ),
              tabs: const [
                Tab(
                  icon: Icon(Icons.timer_outlined, size: 20),
                  text: 'Absensi',
                ),
                Tab(
                  icon: Icon(Icons.badge_outlined, size: 20),
                  text: 'Kelola Karyawan',
                ),
                Tab(
                  icon: Icon(Icons.person_outline_rounded, size: 20),
                  text: 'Edit Profil',
                ),
                Tab(
                  icon: Icon(Icons.security_rounded, size: 20),
                  text: 'Keamanan Sandi',
                ),
                Tab(
                  icon: Icon(Icons.settings_outlined, size: 20),
                  text: 'Preferensi',
                ),
              ],
            ),
          ),
        ),
      ),
      body: Column(
        children: [
          // Top Header Mini Profile Banner
          _buildProfileHeader(isDark, phone),

          // Tab Content
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildAttendanceTab(isDark, phone),
                _buildEmployeesTab(isDark, phone),
                _buildEditProfileTab(isDark, phone),
                _buildSecurityTab(isDark, phone),
                _buildPreferencesTab(isDark, phone),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // PROFILE HEADER WIDGET
  // ---------------------------------------------------------------------------
  Widget _buildProfileHeader(bool isDark, bool phone) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: phone ? 16 : 24, vertical: 14),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkCard : AppColors.lightCard,
        border: Border(
          bottom: BorderSide(
            color: isDark ? AppColors.darkBorder : AppColors.lightBorder,
            width: 1,
          ),
        ),
      ),
      child: Row(
        children: [
          // Avatar with Camera Badge
          Stack(
            children: [
              Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: AppColors.primary.withAlpha(120),
                    width: 2.5,
                  ),
                ),
                child: CircleAvatar(
                  radius: phone ? 28 : 34,
                  backgroundColor: AppColors.primary.withAlpha(40),
                  backgroundImage:
                      _currentProfile.avatarUrl != null &&
                          _currentProfile.avatarUrl!.isNotEmpty
                      ? NetworkImage(_currentProfile.avatarUrl!)
                      : null,
                  child:
                      _currentProfile.avatarUrl == null ||
                          _currentProfile.avatarUrl!.isEmpty
                      ? Text(
                          _currentProfile.initials,
                          style: TextStyle(
                            fontSize: phone ? 20 : 24,
                            fontWeight: FontWeight.bold,
                            color: AppColors.primary,
                          ),
                        )
                      : null,
                ),
              ),
              Positioned(
                bottom: 0,
                right: 0,
                child: InkWell(
                  onTap: _openAvatarSelectionModal,
                  borderRadius: BorderRadius.circular(16),
                  child: Container(
                    padding: const EdgeInsets.all(5),
                    decoration: BoxDecoration(
                      color: AppColors.primary,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: isDark ? AppColors.darkCard : Colors.white,
                        width: 1.5,
                      ),
                    ),
                    child: const Icon(
                      Icons.camera_alt_rounded,
                      size: 13,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(width: 14),
          // User Details
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        _currentProfile.fullName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: phone ? 16 : 18,
                          fontWeight: FontWeight.bold,
                          color: isDark
                              ? AppColors.darkText
                              : AppColors.lightText,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: _currentProfile.isAdmin
                            ? AppColors.primary.withAlpha(35)
                            : AppColors.statusCompleted.withAlpha(35),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: _currentProfile.isAdmin
                              ? AppColors.primary.withAlpha(80)
                              : AppColors.statusCompleted.withAlpha(80),
                        ),
                      ),
                      child: Text(
                        _currentProfile.role.toUpperCase(),
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: _currentProfile.isAdmin
                              ? AppColors.primary
                              : AppColors.statusCompleted,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  _currentProfile.email,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    color: isDark ? AppColors.darkMuted : AppColors.lightMuted,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Icon(
                      Icons.storefront_rounded,
                      size: 13,
                      color: isDark
                          ? AppColors.darkMuted
                          : AppColors.lightMuted,
                    ),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(
                        widget.restaurantName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                          color: isDark
                              ? AppColors.darkMuted
                              : AppColors.lightMuted,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 6),
          // Quick Change Avatar Action
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              padding: EdgeInsets.symmetric(
                horizontal: phone ? 10 : 14,
                vertical: 8,
              ),
              side: BorderSide(
                color: isDark ? AppColors.darkBorder : AppColors.lightBorder,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            icon: const Icon(Icons.image_outlined, size: 16),
            label: Text(
              phone ? 'Foto' : 'Ganti Foto',
              style: const TextStyle(fontSize: 12),
            ),
            onPressed: _openAvatarSelectionModal,
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // TAB 1: ABSENSI KARYAWAN RESTO
  // ---------------------------------------------------------------------------
  Widget _buildAttendanceTab(bool isDark, bool phone) {
    if (_isLoadingAttendance) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.primary),
      );
    }

    final att = _todayAttendance;
    final isClockedIn = att != null && !att.isClockedOut;
    final isShiftFinished = att != null && att.isClockedOut;

    return SingleChildScrollView(
      padding: EdgeInsets.all(phone ? 16 : 24),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 800),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Realtime Clock Card
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: isDark ? AppColors.darkCard : AppColors.yellowSoft,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: isDark
                        ? AppColors.darkBorder
                        : AppColors.amber.withAlpha(90),
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withAlpha(40),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.access_time_filled_rounded,
                        color: AppColors.primary,
                        size: 32,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            () {
                              try {
                                return DateFormat(
                                  'EEEE, d MMMM yyyy',
                                  'id_ID',
                                ).format(_currentTime);
                              } catch (_) {
                                return DateFormat(
                                  'EEEE, d MMMM yyyy',
                                ).format(_currentTime);
                              }
                            }(),
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                              color: isDark
                                  ? AppColors.darkMuted
                                  : AppColors.lightMuted,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            DateFormat('HH:mm:ss').format(_currentTime) +
                                ' WIB',
                            style: TextStyle(
                              fontSize: phone ? 22 : 26,
                              fontWeight: FontWeight.bold,
                              fontFamily: 'monospace',
                              color: isDark
                                  ? AppColors.darkText
                                  : AppColors.lightText,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: isClockedIn
                            ? AppColors.statusCompleted.withAlpha(35)
                            : isShiftFinished
                            ? Colors.grey.withAlpha(40)
                            : Colors.amber.withAlpha(35),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.circle,
                            size: 8,
                            color: isClockedIn
                                ? AppColors.statusCompleted
                                : isShiftFinished
                                ? Colors.grey
                                : Colors.amber,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            isClockedIn
                                ? 'SEDANG BERTUGAS'
                                : isShiftFinished
                                ? 'SHIFT SELESAI'
                                : 'BELUM ABSEN',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: isClockedIn
                                  ? AppColors.statusCompleted
                                  : isShiftFinished
                                  ? Colors.grey
                                  : Colors.amber,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              // Employee Selector Card
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.badge_rounded,
                                  color: AppColors.primary,
                                  size: 22,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    'Pilih Karyawan yang Absen',
                                    style: TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.bold,
                                      color: isDark
                                          ? AppColors.darkText
                                          : AppColors.lightText,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          TextButton.icon(
                            style: TextButton.styleFrom(
                              visualDensity: VisualDensity.compact,
                            ),
                            onPressed: () => _openAddEmployeeDialog(),
                            icon: const Icon(
                              Icons.person_add_rounded,
                              size: 16,
                            ),
                            label: const Text(
                              'Tambah Karyawan',
                              style: TextStyle(fontSize: 12),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      DropdownButtonFormField<String>(
                        value: _selectedEmployeeForAttendance?.id ?? 'self',
                        isExpanded: true,
                        decoration: const InputDecoration(
                          prefixIcon: Icon(Icons.account_circle_rounded),
                          isDense: true,
                        ),
                        dropdownColor: isDark
                            ? AppColors.darkSurface
                            : AppColors.lightSurface,
                        items: [
                          DropdownMenuItem(
                            value: 'self',
                            child: Text(
                              '${_currentProfile.fullName} (${_currentProfile.role.toUpperCase()} - Akun Login)',
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          ..._employees.map(
                            (e) => DropdownMenuItem(
                              value: e.id,
                              child: Text(
                                '${e.name} (${e.role} - ${e.shift})',
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ),
                        ],
                        onChanged: (val) {
                          setState(() {
                            if (val == null || val == 'self') {
                              _selectedEmployeeForAttendance = null;
                            } else {
                              _selectedEmployeeForAttendance = _employees
                                  .firstWhere((e) => e.id == val);
                            }
                          });
                          _loadAttendanceData();
                        },
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 20),

              // Attendance Action Box
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            isClockedIn
                                ? Icons.task_alt_rounded
                                : Icons.how_to_reg_rounded,
                            color: AppColors.primary,
                            size: 24,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Absensi Kehadiran: ${_selectedEmployeeForAttendance != null ? _selectedEmployeeForAttendance!.name : _currentProfile.fullName}',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                    color: isDark
                                        ? AppColors.darkText
                                        : AppColors.lightText,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  _selectedEmployeeForAttendance != null
                                      ? 'Jabatan: ${_selectedEmployeeForAttendance!.role} • ${_selectedEmployeeForAttendance!.shift}'
                                      : 'Jabatan: ${_currentProfile.role.toUpperCase()} • Akun Login Utama',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: isDark
                                        ? AppColors.darkMuted
                                        : AppColors.lightMuted,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),

                      // Status View & Action
                      if (att == null) ...[
                        // Belum Absen Masuk
                        Text(
                          'Pilih Shift Kerja Hari Ini:',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: isDark
                                ? AppColors.darkText
                                : AppColors.lightText,
                          ),
                        ),
                        const SizedBox(height: 8),
                        DropdownButtonFormField<String>(
                          value: _selectedShift,
                          isExpanded: true,
                          decoration: const InputDecoration(
                            isDense: true,
                            prefixIcon: Icon(Icons.schedule_rounded),
                          ),
                          items: _shiftOptions
                              .map(
                                (s) => DropdownMenuItem(
                                  value: s,
                                  child: Text(
                                    s,
                                    style: const TextStyle(fontSize: 13),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              )
                              .toList(),
                          onChanged: (v) {
                            if (v != null) setState(() => _selectedShift = v);
                          },
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _notesController,
                          decoration: const InputDecoration(
                            labelText: 'Catatan Kehadiran (Opsional)',
                            hintText: 'Contoh: Masuk kasir shift pagi kasir 1',
                            prefixIcon: Icon(Icons.edit_note_rounded),
                            isDense: true,
                          ),
                        ),
                        const SizedBox(height: 18),
                        FilledButton.icon(
                          style: FilledButton.styleFrom(
                            backgroundColor: AppColors.statusCompleted,
                            foregroundColor: Colors.white,
                            minimumSize: const Size.fromHeight(48),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          onPressed: _isClocking ? null : _handleClockIn,
                          icon: _isClocking
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Icon(Icons.login_rounded),
                          label: Text(
                            _isClocking
                                ? 'Mencatat Kehadiran...'
                                : 'Absen Masuk Sekarang (Clock In)',
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ] else if (isClockedIn) ...[
                        // Sedang Bertugas (Clocked In)
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: AppColors.statusCompleted.withAlpha(20),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: AppColors.statusCompleted.withAlpha(60),
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  const Icon(
                                    Icons.check_circle_rounded,
                                    color: AppColors.statusCompleted,
                                    size: 20,
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    'Anda Telah Absen Masuk',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: isDark
                                          ? AppColors.darkText
                                          : AppColors.lightText,
                                    ),
                                  ),
                                  const Spacer(),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 3,
                                    ),
                                    decoration: BoxDecoration(
                                      color: AppColors.statusCompleted
                                          .withAlpha(40),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      att.status,
                                      style: const TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                        color: AppColors.statusCompleted,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 10),
                              Text(
                                'Waktu Masuk: ${DateFormat('HH:mm').format(att.clockIn)} WIB | ${att.shift}',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: isDark
                                      ? AppColors.darkMuted
                                      : AppColors.lightMuted,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                'Durasi Bekerja Saat Ini: ${att.durationFormatted}',
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.primary,
                                ),
                              ),
                              if (att.notes != null &&
                                  att.notes!.isNotEmpty) ...[
                                const SizedBox(height: 4),
                                Text(
                                  'Catatan: ${att.notes}',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontStyle: FontStyle.italic,
                                    color: isDark
                                        ? AppColors.darkMuted
                                        : AppColors.lightMuted,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                        FilledButton.icon(
                          style: FilledButton.styleFrom(
                            backgroundColor: Colors.amber[800],
                            foregroundColor: Colors.white,
                            minimumSize: const Size.fromHeight(48),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          onPressed: _isClocking ? null : _handleClockOut,
                          icon: _isClocking
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Icon(Icons.logout_rounded),
                          label: Text(
                            _isClocking
                                ? 'Menyimpan...'
                                : 'Absen Pulang (Selesai Shift)',
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ] else ...[
                        // Shift Selesai Hari Ini
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.blueGrey.withAlpha(25),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: Colors.blueGrey.withAlpha(60),
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Row(
                                children: [
                                  Icon(
                                    Icons.done_all_rounded,
                                    color: AppColors.statusCompleted,
                                    size: 22,
                                  ),
                                  SizedBox(width: 8),
                                  Text(
                                    'Shift Hari Ini Selesai',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 14,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 10),
                              Text(
                                'Masuk: ${DateFormat('HH:mm').format(att.clockIn)} WIB  →  Pulang: ${DateFormat('HH:mm').format(att.clockOut!)} WIB',
                                style: const TextStyle(fontSize: 13),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Total Waktu Bertugas: ${att.durationFormatted} (${att.shift})',
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.primary,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 24),

              // Jika Admin/Owner: Rekap Kehadiran Seluruh Staf Restoran Hari Ini
              if (_currentProfile.isAdmin) ...[
                Row(
                  children: [
                    const Icon(
                      Icons.people_alt_rounded,
                      color: AppColors.primary,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Rekap Kehadiran Karyawan Hari Ini (Admin)',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: isDark
                            ? AppColors.darkText
                            : AppColors.lightText,
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.refresh_rounded, size: 20),
                      onPressed: _loadAttendanceData,
                      tooltip: 'Muat Ulang Kehadiran',
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                if (_allStaffTodayAttendances.isEmpty)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: isDark ? AppColors.darkCard : AppColors.lightCard,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: isDark
                            ? AppColors.darkBorder
                            : AppColors.lightBorder,
                      ),
                    ),
                    child: Text(
                      'Belum ada karyawan lain yang melakukan absensi hari ini.',
                      style: TextStyle(
                        fontSize: 13,
                        color: isDark
                            ? AppColors.darkMuted
                            : AppColors.lightMuted,
                      ),
                    ),
                  )
                else
                  Card(
                    child: ListView.separated(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: _allStaffTodayAttendances.length,
                      separatorBuilder: (_, __) => Divider(
                        height: 1,
                        color: isDark
                            ? AppColors.darkBorder
                            : AppColors.lightBorder,
                      ),
                      itemBuilder: (ctx, i) {
                        final a = _allStaffTodayAttendances[i];
                        final out = a.clockOut != null;

                        return ListTile(
                          leading: CircleAvatar(
                            backgroundColor: AppColors.primary.withAlpha(40),
                            child: Text(
                              a.userName.isNotEmpty
                                  ? a.userName[0].toUpperCase()
                                  : 'S',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                color: AppColors.primary,
                              ),
                            ),
                          ),
                          title: Text(
                            a.userName,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                          ),
                          subtitle: Text(
                            '${a.shift} • In: ${DateFormat('HH:mm').format(a.clockIn)} WIB ${out ? '• Out: ${DateFormat('HH:mm').format(a.clockOut!)}' : '• Aktif'}',
                            style: TextStyle(
                              fontSize: 12,
                              color: isDark
                                  ? AppColors.darkMuted
                                  : AppColors.lightMuted,
                            ),
                          ),
                          trailing: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: out
                                  ? Colors.grey.withAlpha(30)
                                  : AppColors.statusCompleted.withAlpha(35),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              out ? 'Selesai' : 'Bertugas',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: out
                                    ? (isDark
                                          ? Colors.grey[400]
                                          : Colors.grey[700])
                                    : AppColors.statusCompleted,
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                const SizedBox(height: 24),
              ],

              // Riwayat Absensi Saya
              Row(
                children: [
                  const Icon(
                    Icons.history_rounded,
                    color: AppColors.primary,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Riwayat Absensi Saya (30 Hari Terakhir)',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: isDark ? AppColors.darkText : AppColors.lightText,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              if (_attendanceHistory.isEmpty)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: isDark ? AppColors.darkCard : AppColors.lightCard,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: isDark
                          ? AppColors.darkBorder
                          : AppColors.lightBorder,
                    ),
                  ),
                  child: Center(
                    child: Text(
                      'Belum ada riwayat absensi sebelumnya.',
                      style: TextStyle(
                        fontSize: 13,
                        color: isDark
                            ? AppColors.darkMuted
                            : AppColors.lightMuted,
                      ),
                    ),
                  ),
                )
              else
                Card(
                  child: ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: _attendanceHistory.length,
                    separatorBuilder: (_, __) => Divider(
                      height: 1,
                      color: isDark
                          ? AppColors.darkBorder
                          : AppColors.lightBorder,
                    ),
                    itemBuilder: (ctx, i) {
                      final item = _attendanceHistory[i];
                      final dateStr = DateFormat(
                        'dd MMM yyyy',
                      ).format(item.date);
                      final inTime = DateFormat('HH:mm').format(item.clockIn);
                      final outTime = item.clockOut != null
                          ? DateFormat('HH:mm').format(item.clockOut!)
                          : '-';

                      return ListTile(
                        dense: true,
                        leading: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: item.status.contains('Terlambat')
                                ? Colors.amber.withAlpha(40)
                                : AppColors.statusCompleted.withAlpha(40),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(
                            item.status.contains('Terlambat')
                                ? Icons.timer_outlined
                                : Icons.check_circle_outline_rounded,
                            color: item.status.contains('Terlambat')
                                ? Colors.amber[800]
                                : AppColors.statusCompleted,
                            size: 20,
                          ),
                        ),
                        title: Row(
                          children: [
                            Text(
                              dateStr,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              item.shift,
                              style: TextStyle(
                                fontSize: 11,
                                color: isDark
                                    ? AppColors.darkMuted
                                    : AppColors.lightMuted,
                              ),
                            ),
                          ],
                        ),
                        subtitle: Text(
                          'Masuk: $inTime WIB  |  Pulang: $outTime WIB  (${item.durationFormatted})',
                          style: TextStyle(
                            fontSize: 12,
                            color: isDark
                                ? AppColors.darkMuted
                                : AppColors.lightMuted,
                          ),
                        ),
                        trailing: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: item.status.contains('Terlambat')
                                ? Colors.amber.withAlpha(30)
                                : AppColors.statusCompleted.withAlpha(30),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            item.status,
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: item.status.contains('Terlambat')
                                  ? Colors.amber[800]
                                  : AppColors.statusCompleted,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // TAB 2: KELOLA KARYAWAN RESTORAN
  // ---------------------------------------------------------------------------
  Widget _buildEmployeesTab(bool isDark, bool phone) {
    if (_isLoadingEmployees) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.primary),
      );
    }

    final activeCount = _employees.where((e) => e.isActive).length;

    return SingleChildScrollView(
      padding: EdgeInsets.all(phone ? 16 : 24),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 800),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header Card
              Card(
                elevation: 0,
                color: isDark ? AppColors.darkCard : AppColors.lightCard,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: BorderSide(
                    color: isDark
                        ? AppColors.darkBorder
                        : AppColors.lightBorder,
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppColors.primary.withAlpha(25),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.badge_rounded,
                          color: AppColors.primary,
                          size: 26,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Daftar Karyawan Resto',
                              style: TextStyle(
                                fontSize: phone ? 16 : 18,
                                fontWeight: FontWeight.bold,
                                color: isDark
                                    ? AppColors.darkText
                                    : AppColors.lightText,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              'Kelola nama staf, kasir, koki, dan jadwal absensi mereka.',
                              style: TextStyle(
                                fontSize: 12,
                                color: isDark
                                    ? AppColors.darkMuted
                                    : AppColors.lightMuted,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 10),
                      FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: Colors.white,
                          padding: EdgeInsets.symmetric(
                            horizontal: phone ? 12 : 16,
                            vertical: 12,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        onPressed: () => _openAddEmployeeDialog(),
                        icon: const Icon(Icons.person_add_rounded, size: 18),
                        label: Text(
                          phone ? 'Tambah' : 'Tambah Karyawan',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 18),

              // Summary metric chip
              if (_employees.isNotEmpty) ...[
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withAlpha(20),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        'Total: ${_employees.length} Karyawan ($activeCount Aktif)',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: AppColors.primary,
                        ),
                      ),
                    ),
                    const Spacer(),
                    TextButton.icon(
                      onPressed: _loadEmployees,
                      icon: const Icon(Icons.refresh_rounded, size: 16),
                      label: const Text(
                        'Segarkan Data',
                        style: TextStyle(fontSize: 12),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
              ],

              // Empty State
              if (_employees.isEmpty)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    vertical: 40,
                    horizontal: 20,
                  ),
                  decoration: BoxDecoration(
                    color: isDark ? AppColors.darkCard : AppColors.lightCard,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: isDark
                          ? AppColors.darkBorder
                          : AppColors.lightBorder,
                    ),
                  ),
                  child: Column(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(18),
                        decoration: BoxDecoration(
                          color: AppColors.primary.withAlpha(25),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.group_add_outlined,
                          size: 42,
                          color: AppColors.primary,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Belum Ada Karyawan Terdaftar',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: isDark
                              ? AppColors.darkText
                              : AppColors.lightText,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Tambahkan nama karyawan Anda sekarang ke database\nagar staf bisa absen shift kerja.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 13,
                          color: isDark
                              ? AppColors.darkMuted
                              : AppColors.lightMuted,
                        ),
                      ),
                      const SizedBox(height: 20),
                      FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 12,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        onPressed: () => _openAddEmployeeDialog(),
                        icon: const Icon(Icons.person_add_rounded, size: 18),
                        label: const Text('Tambah Karyawan Pertama'),
                      ),
                    ],
                  ),
                )
              else
                ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: _employees.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (ctx, idx) {
                    final emp = _employees[idx];
                    final isSelected =
                        _selectedEmployeeForAttendance?.id == emp.id;

                    return Card(
                      elevation: 0,
                      color: isSelected
                          ? AppColors.primary.withAlpha(20)
                          : (isDark ? AppColors.darkCard : AppColors.lightCard),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                        side: BorderSide(
                          color: isSelected
                              ? AppColors.primary
                              : (isDark
                                    ? AppColors.darkBorder
                                    : AppColors.lightBorder),
                          width: isSelected ? 1.8 : 1.0,
                        ),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Row(
                          children: [
                            // Initials Avatar
                            CircleAvatar(
                              radius: 24,
                              backgroundColor: emp.isActive
                                  ? AppColors.primary.withAlpha(35)
                                  : Colors.grey.withAlpha(40),
                              child: Text(
                                emp.initials,
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 15,
                                  color: emp.isActive
                                      ? AppColors.primary
                                      : Colors.grey,
                                ),
                              ),
                            ),
                            const SizedBox(width: 14),

                            // Info
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Flexible(
                                        child: Text(
                                          emp.name,
                                          style: TextStyle(
                                            fontSize: 15,
                                            fontWeight: FontWeight.bold,
                                            color: isDark
                                                ? AppColors.darkText
                                                : AppColors.lightText,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 7,
                                          vertical: 2,
                                        ),
                                        decoration: BoxDecoration(
                                          color: emp.isActive
                                              ? AppColors.statusCompleted
                                                    .withAlpha(30)
                                              : Colors.grey.withAlpha(30),
                                          borderRadius: BorderRadius.circular(
                                            6,
                                          ),
                                        ),
                                        child: Text(
                                          emp.isActive ? 'Aktif' : 'Nonaktif',
                                          style: TextStyle(
                                            fontSize: 10,
                                            fontWeight: FontWeight.bold,
                                            color: emp.isActive
                                                ? AppColors.statusCompleted
                                                : Colors.grey,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  Row(
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 6,
                                          vertical: 1.5,
                                        ),
                                        decoration: BoxDecoration(
                                          color: AppColors.primary.withAlpha(
                                            20,
                                          ),
                                          borderRadius: BorderRadius.circular(
                                            4,
                                          ),
                                        ),
                                        child: Text(
                                          emp.role,
                                          style: const TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.w600,
                                            color: AppColors.primary,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Icon(
                                        Icons.schedule_rounded,
                                        size: 13,
                                        color: isDark
                                            ? AppColors.darkMuted
                                            : AppColors.lightMuted,
                                      ),
                                      const SizedBox(width: 3),
                                      Flexible(
                                        child: Text(
                                          emp.shift,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            fontSize: 11,
                                            color: isDark
                                                ? AppColors.darkMuted
                                                : AppColors.lightMuted,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  if (emp.phone != null &&
                                      emp.phone!.isNotEmpty) ...[
                                    const SizedBox(height: 3),
                                    Row(
                                      children: [
                                        Icon(
                                          Icons.phone_android_rounded,
                                          size: 12,
                                          color: isDark
                                              ? AppColors.darkMuted
                                              : AppColors.lightMuted,
                                        ),
                                        const SizedBox(width: 3),
                                        Text(
                                          emp.phone!,
                                          style: TextStyle(
                                            fontSize: 11,
                                            color: isDark
                                                ? AppColors.darkMuted
                                                : AppColors.lightMuted,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ],
                              ),
                            ),

                            // Actions
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                // Absen Sekarang Button
                                OutlinedButton.icon(
                                  style: OutlinedButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 8,
                                    ),
                                    side: const BorderSide(
                                      color: AppColors.primary,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                  ),
                                  onPressed: () {
                                    setState(() {
                                      _selectedEmployeeForAttendance = emp;
                                    });
                                    _loadAttendanceData();
                                    _tabController.animateTo(0);
                                    _showSnackbar(
                                      'Beralih ke tab Absensi untuk ${emp.name}',
                                    );
                                  },
                                  icon: const Icon(
                                    Icons.fingerprint_rounded,
                                    size: 15,
                                    color: AppColors.primary,
                                  ),
                                  label: Text(
                                    phone ? 'Absen' : 'Absen Ini',
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: AppColors.primary,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 4),
                                IconButton(
                                  icon: const Icon(
                                    Icons.edit_outlined,
                                    size: 18,
                                  ),
                                  tooltip: 'Edit Data Karyawan',
                                  onPressed: () => _openAddEmployeeDialog(emp),
                                ),
                                IconButton(
                                  icon: const Icon(
                                    Icons.delete_outline_rounded,
                                    size: 18,
                                    color: Colors.redAccent,
                                  ),
                                  tooltip: 'Hapus Karyawan',
                                  onPressed: () => _deleteEmployee(emp),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // TAB 3: EDIT PROFIL & KONTAK
  // ---------------------------------------------------------------------------
  Widget _buildEditProfileTab(bool isDark, bool phone) {
    return SingleChildScrollView(
      padding: EdgeInsets.all(phone ? 16 : 24),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(22),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(
                            Icons.edit_note_rounded,
                            color: AppColors.primary,
                            size: 26,
                          ),
                          const SizedBox(width: 10),
                          Text(
                            'Informasi Data Karyawan',
                            style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.bold,
                              color: isDark
                                  ? AppColors.darkText
                                  : AppColors.lightText,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Pastikan data Anda sesuai dengan identitas resmi pegawai restoran.',
                        style: TextStyle(
                          fontSize: 13,
                          color: isDark
                              ? AppColors.darkMuted
                              : AppColors.lightMuted,
                        ),
                      ),
                      const SizedBox(height: 20),

                      // Nama Lengkap
                      Text(
                        'Nama Lengkap:',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: isDark
                              ? AppColors.darkText
                              : AppColors.lightText,
                        ),
                      ),
                      const SizedBox(height: 6),
                      TextField(
                        controller: _nameController,
                        decoration: const InputDecoration(
                          prefixIcon: Icon(Icons.badge_outlined),
                          hintText: 'Nama lengkap kasir / admin',
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Nomor WhatsApp / Telepon
                      Text(
                        'Nomor Telepon / WhatsApp:',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: isDark
                              ? AppColors.darkText
                              : AppColors.lightText,
                        ),
                      ),
                      const SizedBox(height: 6),
                      TextField(
                        controller: _phoneController,
                        keyboardType: TextInputType.phone,
                        decoration: const InputDecoration(
                          prefixIcon: Icon(Icons.phone_outlined),
                          hintText: '081234567890',
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Email (Read Only)
                      Text(
                        'Email Akun (Terkunci):',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: isDark
                              ? AppColors.darkText
                              : AppColors.lightText,
                        ),
                      ),
                      const SizedBox(height: 6),
                      TextField(
                        readOnly: true,
                        controller: TextEditingController(
                          text: _currentProfile.email,
                        ),
                        decoration: InputDecoration(
                          prefixIcon: const Icon(Icons.email_outlined),
                          filled: true,
                          fillColor: isDark ? Colors.black26 : Colors.grey[100],
                          suffixIcon: const Icon(
                            Icons.lock_outline_rounded,
                            size: 18,
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Role Akun
                      Text(
                        'Peran & Hak Akses (Role):',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: isDark
                              ? AppColors.darkText
                              : AppColors.lightText,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 12,
                        ),
                        decoration: BoxDecoration(
                          color: isDark ? Colors.black26 : Colors.grey[100],
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: isDark
                                ? AppColors.darkBorder
                                : AppColors.lightBorder,
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              _currentProfile.isAdmin
                                  ? Icons.admin_panel_settings_rounded
                                  : Icons.point_of_sale_rounded,
                              color: AppColors.primary,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    _currentProfile.role.toUpperCase(),
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 13,
                                    ),
                                  ),
                                  Text(
                                    _currentProfile.isAdmin
                                        ? 'Hak akses penuh admin: manajemen produk, staf, laporan.'
                                        : 'Akses operasional POS kasir, transaksi pesanan, & struk.',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: isDark
                                          ? AppColors.darkMuted
                                          : AppColors.lightMuted,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),

                      // Button Simpan
                      FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: Colors.white,
                          minimumSize: const Size.fromHeight(48),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        onPressed: _isSavingProfile
                            ? null
                            : _saveProfileChanges,
                        icon: _isSavingProfile
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(Icons.save_rounded),
                        label: Text(
                          _isSavingProfile
                              ? 'Menyimpan Perubahan...'
                              : 'Simpan Perubahan Profil',
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // TAB 3: KEAMANAN & GANTI SANDI
  // ---------------------------------------------------------------------------
  Widget _buildSecurityTab(bool isDark, bool phone) {
    return SingleChildScrollView(
      padding: EdgeInsets.all(phone ? 16 : 24),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(22),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(
                            Icons.lock_reset_rounded,
                            color: AppColors.primary,
                            size: 26,
                          ),
                          const SizedBox(width: 10),
                          Text(
                            'Pengaturan Keamanan & Ganti Sandi',
                            style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.bold,
                              color: isDark
                                  ? AppColors.darkText
                                  : AppColors.lightText,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Amankan akun RestoKasir Anda dengan sandi unik minimal 6 karakter.',
                        style: TextStyle(
                          fontSize: 13,
                          color: isDark
                              ? AppColors.darkMuted
                              : AppColors.lightMuted,
                        ),
                      ),
                      const SizedBox(height: 20),

                      // Password Baru
                      Text(
                        'Kata Sandi Baru:',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: isDark
                              ? AppColors.darkText
                              : AppColors.lightText,
                        ),
                      ),
                      const SizedBox(height: 6),
                      TextField(
                        controller: _newPasswordController,
                        obscureText: _obscureNewPass,
                        decoration: InputDecoration(
                          prefixIcon: const Icon(Icons.key_rounded),
                          hintText: 'Minimal 6 karakter',
                          suffixIcon: IconButton(
                            icon: Icon(
                              _obscureNewPass
                                  ? Icons.visibility_off_rounded
                                  : Icons.visibility_rounded,
                            ),
                            onPressed: () => setState(
                              () => _obscureNewPass = !_obscureNewPass,
                            ),
                          ),
                        ),
                        onChanged: (_) => setState(() {}),
                      ),
                      const SizedBox(height: 8),

                      // Password Strength Indicator
                      _buildPasswordStrengthBar(
                        _newPasswordController.text,
                        isDark,
                      ),
                      const SizedBox(height: 16),

                      // Konfirmasi Password Baru
                      Text(
                        'Konfirmasi Kata Sandi Baru:',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: isDark
                              ? AppColors.darkText
                              : AppColors.lightText,
                        ),
                      ),
                      const SizedBox(height: 6),
                      TextField(
                        controller: _confirmPasswordController,
                        obscureText: _obscureConfirmPass,
                        decoration: InputDecoration(
                          prefixIcon: const Icon(Icons.lock_outline_rounded),
                          hintText: 'Ulangi kata sandi baru',
                          suffixIcon: IconButton(
                            icon: Icon(
                              _obscureConfirmPass
                                  ? Icons.visibility_off_rounded
                                  : Icons.visibility_rounded,
                            ),
                            onPressed: () => setState(
                              () => _obscureConfirmPass = !_obscureConfirmPass,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),

                      FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: Colors.white,
                          minimumSize: const Size.fromHeight(48),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        onPressed: _isSavingPassword
                            ? null
                            : _handleChangePassword,
                        icon: _isSavingPassword
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(Icons.check_rounded),
                        label: Text(
                          _isSavingPassword
                              ? 'Menyimpan Sandi...'
                              : 'Perbarui Kata Sandi Akun',
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 20),

              // Security Audit Card
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(
                            Icons.verified_user_rounded,
                            color: AppColors.statusCompleted,
                            size: 22,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Status Keamanan Sesi',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                              color: isDark
                                  ? AppColors.darkText
                                  : AppColors.lightText,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: AppColors.statusCompleted.withAlpha(30),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(
                            Icons.cloud_done_rounded,
                            color: AppColors.statusCompleted,
                            size: 20,
                          ),
                        ),
                        title: const Text(
                          'Koneksi Cloud Terenkripsi',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        subtitle: Text(
                          'Data profil & transaksi disinkronkan secara aman via Supabase SSL Auth.',
                          style: TextStyle(
                            fontSize: 12,
                            color: isDark
                                ? AppColors.darkMuted
                                : AppColors.lightMuted,
                          ),
                        ),
                      ),
                      const Divider(height: 20),
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.redAccent.withAlpha(30),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(
                            Icons.exit_to_app_rounded,
                            color: Colors.redAccent,
                            size: 20,
                          ),
                        ),
                        title: const Text(
                          'Keluar dari Akun RestoKasir',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: Colors.redAccent,
                          ),
                        ),
                        subtitle: Text(
                          'Hentikan sesi login aktif di perangkat ini dengan aman.',
                          style: TextStyle(
                            fontSize: 12,
                            color: isDark
                                ? AppColors.darkMuted
                                : AppColors.lightMuted,
                          ),
                        ),
                        trailing: OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.redAccent,
                            side: const BorderSide(color: Colors.redAccent),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          onPressed: _logout,
                          child: const Text('Logout'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPasswordStrengthBar(String password, bool isDark) {
    if (password.isEmpty) return const SizedBox.shrink();

    int strength = 0;
    if (password.length >= 6) strength++;
    if (password.length >= 8) strength++;
    if (RegExp(r'[0-9]').hasMatch(password) &&
        RegExp(r'[a-zA-Z]').hasMatch(password)) {
      strength++;
    }

    Color color = Colors.redAccent;
    String label = 'Lemah';
    if (strength == 2) {
      color = Colors.amber;
      label = 'Cukup';
    } else if (strength >= 3) {
      color = AppColors.statusCompleted;
      label = 'Kuat & Aman';
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: strength / 3.0,
                  backgroundColor: isDark
                      ? AppColors.darkBorder
                      : AppColors.lightBorder,
                  color: color,
                  minHeight: 5,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          'Minimal 6 karakter, kombinasikan huruf dan angka untuk keamanan terbaik.',
          style: TextStyle(
            fontSize: 11,
            color: isDark ? AppColors.darkMuted : AppColors.lightMuted,
          ),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // TAB 4: PENGATURAN PREFERENSI & LAIN-LAIN
  // ---------------------------------------------------------------------------
  Widget _buildPreferencesTab(bool isDark, bool phone) {
    return SingleChildScrollView(
      padding: EdgeInsets.all(phone ? 16 : 24),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(
                            Icons.tune_rounded,
                            color: AppColors.primary,
                            size: 24,
                          ),
                          const SizedBox(width: 10),
                          Text(
                            'Pengaturan Operasional Kasir',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: isDark
                                  ? AppColors.darkText
                                  : AppColors.lightText,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text(
                          'Efek Suara Transaksi',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        subtitle: Text(
                          'Bunyi feedback saat menambah menu ke keranjang dan menyelesaikan pesanan.',
                          style: TextStyle(
                            fontSize: 12,
                            color: isDark
                                ? AppColors.darkMuted
                                : AppColors.lightMuted,
                          ),
                        ),
                        secondary: const Icon(
                          Icons.volume_up_rounded,
                          color: AppColors.primary,
                        ),
                        value: _soundEffectsEnabled,
                        onChanged: (val) {
                          setState(() => _soundEffectsEnabled = val);
                          _showSnackbar(
                            val
                                ? 'Efek suara diaktifkan'
                                : 'Efek suara dinonaktifkan',
                          );
                        },
                      ),
                      const Divider(),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text(
                          'Cetak Struk Otomatis',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        subtitle: Text(
                          'Buka jendela print struk thermal otomatis begitu pembayaran tunai/QRIS sukses.',
                          style: TextStyle(
                            fontSize: 12,
                            color: isDark
                                ? AppColors.darkMuted
                                : AppColors.lightMuted,
                          ),
                        ),
                        secondary: const Icon(
                          Icons.print_rounded,
                          color: AppColors.primary,
                        ),
                        value: _autoPrintReceipt,
                        onChanged: (val) {
                          setState(() => _autoPrintReceipt = val);
                          _showSnackbar(
                            val
                                ? 'Cetak struk otomatis diaktifkan'
                                : 'Cetak struk otomatis dimatikan',
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 16),

              // Info Aplikasi Resto
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(
                            Icons.info_outline_rounded,
                            color: AppColors.primary,
                            size: 24,
                          ),
                          const SizedBox(width: 10),
                          Text(
                            'Informasi Sistem RestoKasir',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: isDark
                                  ? AppColors.darkText
                                  : AppColors.lightText,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Versi Aplikasi:',
                            style: TextStyle(
                              fontSize: 13,
                              color: isDark
                                  ? AppColors.darkMuted
                                  : AppColors.lightMuted,
                            ),
                          ),
                          const Text(
                            'v1.2.0 (Build Resto Pro)',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Database Cloud:',
                            style: TextStyle(
                              fontSize: 13,
                              color: isDark
                                  ? AppColors.darkMuted
                                  : AppColors.lightMuted,
                            ),
                          ),
                          const Row(
                            children: [
                              Icon(
                                Icons.check_circle_rounded,
                                size: 14,
                                color: AppColors.statusCompleted,
                              ),
                              SizedBox(width: 4),
                              Text(
                                'Supabase PostgreSQL Terhubung',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.statusCompleted,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Nama Restoran:',
                            style: TextStyle(
                              fontSize: 13,
                              color: isDark
                                  ? AppColors.darkMuted
                                  : AppColors.lightMuted,
                            ),
                          ),
                          Text(
                            widget.restaurantName,
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
