import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:my_app/models/models.dart';
import 'package:my_app/services/pos_service.dart';
import 'package:my_app/core/theme/theme_controller.dart';
import 'package:my_app/core/utils/responsive.dart';
import 'package:my_app/widgets/product_image_view.dart';

class AddProductScreen extends StatefulWidget {
  final VoidCallback? onProductAdded;
  final DbProduct? productToEdit;

  const AddProductScreen({
    super.key,
    this.onProductAdded,
    this.productToEdit,
  });

  @override
  State<AddProductScreen> createState() => _AddProductScreenState();
}

class _AddProductScreenState extends State<AddProductScreen> {
  final _formKey = GlobalKey<FormState>();
  final _posService = PosService();
  final _picker = ImagePicker();

  final _nameController = TextEditingController();
  final _priceController = TextEditingController();
  final _stockController = TextEditingController(text: '10');
  final _descriptionController = TextEditingController();
  final _imageUrlController = TextEditingController();

  String _selectedCategory = 'Makanan Utama';
  String _selectedIcon = 'fastfood';
  bool _isLoading = false;

  bool get _isEditing => widget.productToEdit != null;

  @override
  void initState() {
    super.initState();
    if (_isEditing) {
      final p = widget.productToEdit!;
      _nameController.text = p.name;
      _priceController.text = p.price.toString();
      _stockController.text = p.stock.toString();
      _descriptionController.text = p.description ?? '';
      _imageUrlController.text = p.imageUrl ?? '';
      _selectedCategory = p.category;
      _selectedIcon = p.iconName;
      if (p.imageUrl != null && p.imageUrl!.isNotEmpty) {
        _showUrlOption = true;
      }
    }
  }

  // Foto dari Kamera / Galeri
  Uint8List? _selectedImageBytes;
  String? _selectedImageExt;
  String? _selectedImageName;
  bool _showUrlOption = false;

  final List<String> _categories = [
    'Makanan Utama',
    'Snack & Camilan',
    'Minuman',
    'Dessert',
    'Paket Spesial',
  ];

  final Map<String, IconData> _iconOptions = {
    'rice_bowl': Icons.rice_bowl_rounded,
    'lunch_dining': Icons.lunch_dining_rounded,
    'ramen_dining': Icons.ramen_dining_rounded,
    'local_cafe': Icons.local_cafe_rounded,
    'local_drink': Icons.local_drink_rounded,
    'cake': Icons.cake_rounded,
    'bakery_dining': Icons.bakery_dining_rounded,
    'fastfood': Icons.fastfood_rounded,
  };

  @override
  void dispose() {
    _nameController.dispose();
    _priceController.dispose();
    _stockController.dispose();
    _descriptionController.dispose();
    _imageUrlController.dispose();
    super.dispose();
  }

  Future<void> _pickImage(ImageSource source) async {
    try {
      final XFile? file = await _picker.pickImage(
        source: source,
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 85,
      );

      if (file == null) return;

      final bytes = await file.readAsBytes();
      final ext = file.name.contains('.') ? file.name.split('.').last.toLowerCase() : 'jpg';

      setState(() {
        _selectedImageBytes = bytes;
        _selectedImageExt = ext;
        _selectedImageName = file.name;
        _imageUrlController.clear();
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Gagal mengambil foto: $e'),
          backgroundColor: AppColors.statusCancelled,
        ),
      );
    }
  }

  void _showImageSourcePicker() {
    final isDark = ThemeController.isDark(context);

    showModalBottomSheet(
      context: context,
      backgroundColor: isDark ? AppColors.darkCard : AppColors.lightCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
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
              Text(
                'Pilih Sumber Foto Produk',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: isDark ? AppColors.darkText : AppColors.lightText,
                ),
              ),
              const SizedBox(height: 14),
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withAlpha(30),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.camera_alt_rounded, color: AppColors.primary),
                ),
                title: const Text('Ambil Foto dari Kamera', style: TextStyle(fontWeight: FontWeight.w600)),
                subtitle: const Text('Gunakan kamera ponsel untuk memotret makanan/minuman'),
                onTap: () {
                  Navigator.pop(ctx);
                  _pickImage(ImageSource.camera);
                },
              ),
              const SizedBox(height: 8),
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColors.amber.withAlpha(30),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.photo_library_rounded, color: AppColors.amber),
                ),
                title: const Text('Pilih dari Galeri HP', style: TextStyle(fontWeight: FontWeight.w600)),
                subtitle: const Text('Pilih foto makanan yang tersimpan di perangkat'),
                onTap: () {
                  Navigator.pop(ctx);
                  _pickImage(ImageSource.gallery);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _submitProduct() async {
    if (!_formKey.currentState!.validate()) return;

    final name = _nameController.text.trim();
    final price = int.tryParse(_priceController.text.trim()) ?? 0;
    final stock = int.tryParse(_stockController.text.trim()) ?? 0;
    final description = _descriptionController.text.trim();
    String? finalImageUrl = _imageUrlController.text.trim();

    setState(() => _isLoading = true);

    try {
      // Jika pengguna memilih file foto dari Kamera / Galeri, upload ke Supabase Storage
      if (_selectedImageBytes != null) {
        final uploadedUrl = await _posService.uploadProductImageBytes(
          _selectedImageBytes!,
          _selectedImageExt ?? 'jpg',
        );
        if (uploadedUrl != null && uploadedUrl.isNotEmpty) {
          finalImageUrl = uploadedUrl;
        }
      }

      if (_isEditing) {
        await _posService.updateProduct(
          productId: widget.productToEdit!.id,
          name: name,
          category: _selectedCategory,
          price: price,
          stock: stock,
          description: description.isNotEmpty ? description : null,
          imageUrl: finalImageUrl.isNotEmpty ? finalImageUrl : null,
          iconName: _selectedIcon,
        );
      } else {
        await _posService.addProduct(
          name: name,
          category: _selectedCategory,
          price: price,
          stock: stock,
          description: description.isNotEmpty ? description : null,
          imageUrl: finalImageUrl.isNotEmpty ? finalImageUrl : null,
          iconName: _selectedIcon,
        );
      }

      if (!mounted) return;

      final successMsg = _isEditing
          ? 'Perubahan produk "$name" berhasil disimpan!'
          : 'Produk "$name" berhasil disimpan ke database!';

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(successMsg),
          backgroundColor: AppColors.statusCompleted,
          behavior: SnackBarBehavior.floating,
        ),
      );

      widget.onProductAdded?.call();
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Gagal menyimpan produk: $e'),
          backgroundColor: AppColors.statusCancelled,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = ThemeController.isDark(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          _isEditing ? 'Ubah Produk Restoran' : 'Tambah Produk Restoran',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.all(Responsive.pick(context, phone: 16.0, tablet: 24.0)),
          child: MaxWidthBox(
            maxWidth: 680,
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Info Banner
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: isDark ? AppColors.yellowSoftDark : AppColors.yellowSoft,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: isDark ? AppColors.amber.withAlpha(80) : AppColors.amber.withAlpha(120),
                      ),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.restaurant_rounded, color: AppColors.primary, size: 22),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'Tambahkan menu restoran Anda lengkap dengan nama, harga, stok, dan foto agar tampil di kasir maupun website meja.',
                            style: TextStyle(
                              fontSize: 13,
                              color: isDark ? AppColors.darkText : AppColors.lightText,
                              height: 1.4,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),

                  // FOTO PRODUK (UPLOAD DARI GALERI / KAMERA)
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Foto Produk',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                          color: isDark ? AppColors.darkText : AppColors.lightText,
                        ),
                      ),
                      TextButton.icon(
                        style: TextButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                        ),
                        onPressed: () => setState(() => _showUrlOption = !_showUrlOption),
                        icon: Icon(_showUrlOption ? Icons.expand_less : Icons.link_rounded, size: 16),
                        label: Text(_showUrlOption ? 'Sembunyikan URL' : 'Input via URL', style: const TextStyle(fontSize: 12)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),

                  // Container Foto Utama
                  _buildPhotoUploaderBox(isDark),

                  if (_showUrlOption) ...[
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _imageUrlController,
                      decoration: const InputDecoration(
                        labelText: 'Atau Masukkan URL Gambar (Opsional)',
                        hintText: 'https://...',
                        prefixIcon: Icon(Icons.link_rounded),
                        isDense: true,
                      ),
                      onChanged: (val) {
                        if (val.isNotEmpty && _selectedImageBytes != null) {
                          setState(() {
                            _selectedImageBytes = null;
                            _selectedImageName = null;
                          });
                        }
                      },
                    ),
                  ],
                  const SizedBox(height: 24),

                  // Nama Produk
                  Text(
                    'Nama Produk / Menu *',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      color: isDark ? AppColors.darkText : AppColors.lightText,
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: _nameController,
                    decoration: const InputDecoration(
                      hintText: 'Contoh: Nasi Goreng Spesial / Es Kopi Gula Aren',
                      prefixIcon: Icon(Icons.restaurant_menu_rounded),
                    ),
                    validator: (val) {
                      if (val == null || val.trim().isEmpty) {
                        return 'Nama produk wajib diisi';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 20),

                  // Kategori Menu
                  Text(
                    'Kategori Menu *',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      color: isDark ? AppColors.darkText : AppColors.lightText,
                    ),
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    initialValue: _selectedCategory,
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.category_rounded),
                    ),
                    dropdownColor: isDark ? AppColors.darkSurface : AppColors.lightSurface,
                    items: _categories.map((cat) {
                      return DropdownMenuItem(
                        value: cat,
                        child: Text(cat),
                      );
                    }).toList(),
                    onChanged: (val) {
                      if (val != null) {
                        setState(() => _selectedCategory = val);
                      }
                    },
                  ),
                  const SizedBox(height: 20),

                  // Harga & Stok
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final isNarrow = constraints.maxWidth < 420;

                      final priceField = Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Harga Jual (Rp) *',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                              color: isDark ? AppColors.darkText : AppColors.lightText,
                            ),
                          ),
                          const SizedBox(height: 8),
                          TextFormField(
                            controller: _priceController,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              hintText: '25000',
                              prefixText: 'Rp ',
                            ),
                            validator: (val) {
                              if (val == null || val.trim().isEmpty) {
                                return 'Harga wajib diisi';
                              }
                              final p = int.tryParse(val.trim());
                              if (p == null || p <= 0) {
                                return 'Harga harus lebih dari 0';
                              }
                              return null;
                            },
                          ),
                        ],
                      );

                      final stockField = Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Stok Awal (Porsi/Pcs) *',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                              color: isDark ? AppColors.darkText : AppColors.lightText,
                            ),
                          ),
                          const SizedBox(height: 8),
                          TextFormField(
                            controller: _stockController,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              hintText: '10',
                              suffixText: 'porsi',
                            ),
                            validator: (val) {
                              if (val == null || val.trim().isEmpty) {
                                return 'Stok wajib diisi';
                              }
                              final s = int.tryParse(val.trim());
                              if (s == null || s < 0) {
                                return 'Stok tidak valid';
                              }
                              return null;
                            },
                          ),
                        ],
                      );

                      if (isNarrow) {
                        return Column(
                          children: [
                            priceField,
                            const SizedBox(height: 16),
                            stockField,
                          ],
                        );
                      }

                      return Row(
                        children: [
                          Expanded(child: priceField),
                          const SizedBox(width: 16),
                          Expanded(child: stockField),
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: 20),

                  // Deskripsi Menu
                  Text(
                    'Deskripsi Makanan / Menu *',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      color: isDark ? AppColors.darkText : AppColors.lightText,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Deskripsi ini akan langsung ditampilkan pada website pemesanan pelanggan tepat di atas tombol pesan.',
                    style: TextStyle(
                      fontSize: 11.5,
                      color: isDark ? AppColors.darkMuted : AppColors.lightMuted,
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: _descriptionController,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      hintText:
                          'Contoh: Daging ayam empuk dimasak dengan rempah pilihan, disajikan dengan nasi hangat dan lalapan segar.',
                      prefixIcon: Padding(
                        padding: EdgeInsets.only(bottom: 40),
                        child: Icon(Icons.description_outlined),
                      ),
                    ),
                    validator: (val) {
                      if (val == null || val.trim().isEmpty) {
                        return 'Deskripsi makanan wajib diisi agar tampil di website';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 20),

                  // Ikon Cadangan
                  Text(
                    'Ikon Menu Cadangan',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      color: isDark ? AppColors.darkText : AppColors.lightText,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: _iconOptions.entries.map((entry) {
                      final isSelected = _selectedIcon == entry.key;
                      return InkWell(
                        onTap: () => setState(() => _selectedIcon = entry.key),
                        borderRadius: BorderRadius.circular(12),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? AppColors.primary.withAlpha(40)
                                : (isDark ? AppColors.darkSurface : AppColors.lightSurface),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: isSelected
                                  ? AppColors.primary
                                  : (isDark ? AppColors.darkBorder : AppColors.lightBorder),
                              width: isSelected ? 1.8 : 1.0,
                            ),
                          ),
                          child: Icon(
                            entry.value,
                            color: isSelected ? AppColors.primary : (isDark ? AppColors.darkMuted : AppColors.lightMuted),
                            size: 24,
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 32),

                  // Submit Button
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        elevation: 2,
                      ),
                      onPressed: _isLoading ? null : _submitProduct,
                      icon: _isLoading
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.check_circle_rounded),
                      label: Text(
                        _isLoading
                            ? 'Menyimpan Produk & Foto...'
                            : (_isEditing
                                ? 'Simpan Perubahan Produk'
                                : 'Simpan Produk ke Restoran'),
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPhotoUploaderBox(bool isDark) {
    if (_selectedImageBytes != null) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isDark ? AppColors.darkCard : AppColors.lightCard,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.primary.withAlpha(80)),
        ),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.memory(
                _selectedImageBytes!,
                width: 90,
                height: 90,
                fit: BoxFit.cover,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.check_circle_rounded, color: AppColors.statusCompleted, size: 18),
                      const SizedBox(width: 6),
                      Text(
                        'Foto Siap Diunggah',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                          color: isDark ? AppColors.darkText : AppColors.lightText,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _selectedImageName ?? 'Foto Terpilih',
                    style: TextStyle(fontSize: 12, color: isDark ? AppColors.darkMuted : AppColors.lightMuted),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          visualDensity: VisualDensity.compact,
                        ),
                        onPressed: _showImageSourcePicker,
                        icon: const Icon(Icons.edit_rounded, size: 14),
                        label: const Text('Ganti', style: TextStyle(fontSize: 11)),
                      ),
                      const SizedBox(width: 8),
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          visualDensity: VisualDensity.compact,
                          foregroundColor: Colors.redAccent,
                        ),
                        onPressed: () {
                          setState(() {
                            _selectedImageBytes = null;
                            _selectedImageName = null;
                          });
                        },
                        icon: const Icon(Icons.delete_outline_rounded, size: 14),
                        label: const Text('Hapus', style: TextStyle(fontSize: 11)),
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

    if (_imageUrlController.text.trim().isNotEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isDark ? AppColors.darkCard : AppColors.lightCard,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.primary.withAlpha(80)),
        ),
        child: Row(
          children: [
            Container(
              width: 80,
              height: 80,
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(borderRadius: BorderRadius.circular(12)),
              child: ProductImageView(
                imageUrl: _imageUrlController.text.trim(),
                fallbackIcon: _iconOptions[_selectedIcon] ?? Icons.fastfood_rounded,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Preview URL Gambar', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                  const SizedBox(height: 4),
                  Text(
                    _imageUrlController.text.trim(),
                    style: TextStyle(fontSize: 11, color: isDark ? AppColors.darkMuted : AppColors.lightMuted),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 8),
                  TextButton.icon(
                    onPressed: _showImageSourcePicker,
                    icon: const Icon(Icons.photo_camera_rounded, size: 16),
                    label: const Text('Ganti dengan Foto Asli HP'),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    // Default: Tombol & Area Masukkan Foto (Kamera / Galeri)
    return InkWell(
      onTap: _showImageSourcePicker,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        decoration: BoxDecoration(
          color: isDark ? AppColors.darkSurface : AppColors.lightBg,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isDark ? AppColors.darkBorder : AppColors.lightBorder,
            width: 1.5,
          ),
        ),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.primary.withAlpha(30),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.add_a_photo_rounded,
                size: 36,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Pilih Foto Produk dari Ponsel',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 15,
                color: isDark ? AppColors.darkText : AppColors.lightText,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Sentuh di sini untuk memotret dengan Kamera atau memilih dari Galeri',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                color: isDark ? AppColors.darkMuted : AppColors.lightMuted,
              ),
            ),
            const SizedBox(height: 14),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                OutlinedButton.icon(
                  onPressed: () => _pickImage(ImageSource.camera),
                  icon: const Icon(Icons.camera_alt_rounded, size: 16),
                  label: const Text('Kamera', style: TextStyle(fontSize: 12)),
                ),
                const SizedBox(width: 12),
                OutlinedButton.icon(
                  onPressed: () => _pickImage(ImageSource.gallery),
                  icon: const Icon(Icons.photo_library_rounded, size: 16),
                  label: const Text('Galeri', style: TextStyle(fontSize: 12)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
