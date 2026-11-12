/* ============================================================================
   RestoKasir Customer Self-Order Application
   Koneksi langsung ke Supabase REST API -> Aplikasi Kasir Flutter
   ============================================================================ */

const SUPABASE_URL = 'https://uinumtttwkwlurvqvidh.supabase.co';
const SUPABASE_ANON_KEY =
  'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InVpbnVtdHR0d2t3bHVydnF2aWRoIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODQ2OTUxNTcsImV4cCI6MjEwMDI3MTE1N30.eSfjbxge6LA8fIqP9Cnepld7s4PgQgh_Eqi3O58DI1M';
const PAY_PAGE_URL =
  'https://uinumtttwkwlurvqvidh.supabase.co/storage/v1/object/public/product-images/pay.html';

const THEME_STORAGE_KEY = 'restokasir_theme';
const LAST_ORDER_STORAGE_KEY = 'restokasir_last_order';

const state = {
  restoId: '',
  restoName: 'RestoKasir Nusantara',
  tableNumber: 1,
  products: [],
  cart: {},
  selectedCategory: 'Semua',
  searchQuery: '',
  selectedPayment: 'Bayar di Kasir',
  lastOrder: null,
  statusPollTimer: null,
};

function apiHeaders(extra = {}) {
  return {
    apikey: SUPABASE_ANON_KEY,
    Authorization: 'Bearer ' + SUPABASE_ANON_KEY,
    'Content-Type': 'application/json',
    ...extra,
  };
}

function escapeHtml(text) {
  return String(text == null ? '' : text)
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#39;');
}

function formatRupiah(num) {
  const n = Math.round(Number(num) || 0);
  return 'Rp ' + n.toString().replace(/\B(?=(\d{3})+(?!\d))/g, '.');
}

// ============================================================================
// Theme Toggle: Putih <-> Hitam (mengubah putih menjadi hitam, orange/kuning tetap)
// ============================================================================
function syncThemeButton() {
  const current =
    document.documentElement.dataset.theme === 'dark' ? 'dark' : 'light';
  const btn = document.getElementById('themeToggleBtn');
  const label = document.getElementById('themeToggleText');
  const isDark = current === 'dark';

  if (btn) {
    btn.setAttribute('aria-pressed', String(isDark));
    btn.setAttribute(
      'title',
      isDark ? 'Ubah ke tampilan putih' : 'Ubah ke tampilan hitam'
    );
  }
  if (label) {
    label.textContent = isDark ? 'Hitam' : 'Putih';
  }
}

function toggleTheme() {
  const next =
    document.documentElement.dataset.theme === 'dark' ? 'light' : 'dark';
  document.documentElement.dataset.theme = next;
  try {
    localStorage.setItem(THEME_STORAGE_KEY, next);
  } catch (e) {
    // Ignore storage restriction
  }
  syncThemeButton();
}

// ============================================================================
// Table Management
// ============================================================================
function setTableNumber(value, syncUrl = true) {
  const parsed = parseInt(value, 10);
  const valid = !Number.isNaN(parsed) && parsed >= 1 && parsed <= 99 ? parsed : 1;
  state.tableNumber = valid;

  const badge = document.getElementById('tableBadge');
  const noticeTitle = document.getElementById('noticeTableTitle');
  const cartBarTable = document.getElementById('cartBarTableInfo');
  const tableInput = document.getElementById('tableNumberInput');

  if (badge) badge.textContent = 'Meja ' + valid;
  if (noticeTitle) noticeTitle.textContent = 'Anda memesan untuk Meja ' + valid;
  if (cartBarTable) cartBarTable.textContent = 'Meja ' + valid;
  if (tableInput && document.activeElement !== tableInput) {
    tableInput.value = String(valid);
  }

  if (syncUrl && window.history && window.history.replaceState) {
    const url = new URL(window.location.href);
    url.searchParams.set('table', String(valid));
    window.history.replaceState({}, '', url.toString());
  }
}

function promptTableNumber() {
  const raw = window.prompt(
    'Masukkan nomor meja Anda saat ini (1 - 99):',
    String(state.tableNumber)
  );
  if (raw === null) return;
  const num = parseInt(raw.trim(), 10);
  if (Number.isNaN(num) || num < 1 || num > 99) {
    showToast('Nomor meja harus antara 1 sampai 99');
    return;
  }
  setTableNumber(num, true);
  showToast('Nomor meja diperbarui ke Meja ' + num);
}

// ============================================================================
// SVG Placeholder by Category (tanpa emoticon)
// ============================================================================
function getCategorySvg(cat) {
  const c = (cat || '').toLowerCase();
  if (c.includes('minuman')) {
    return (
      '<svg width="40" height="40" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round">' +
      '<path d="M6 8h12l-1.5 11a2 2 0 0 1-2 1.7H9.5a2 2 0 0 1-2-1.7L6 8z" />' +
      '<path d="M5 8h14" />' +
      '<path d="M12 8V4l3-1" />' +
      '</svg>'
    );
  }
  if (c.includes('dessert')) {
    return (
      '<svg width="40" height="40" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round">' +
      '<path d="M4 13h16v6a2 2 0 0 1-2 2H6a2 2 0 0 1-2-2v-6z" />' +
      '<path d="M4 13c0-3 3.5-5 8-5s8 2 8 5" />' +
      '<circle cx="12" cy="5.5" r="1.5" />' +
      '</svg>'
    );
  }
  return (
    '<svg width="40" height="40" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round">' +
    '<circle cx="12" cy="12" r="8" />' +
    '<circle cx="12" cy="12" r="4" />' +
    '<path d="M3 12h1M20 12h1" />' +
    '</svg>'
  );
}

// ============================================================================
// Initialization & Data Fetching
// ============================================================================
document.addEventListener('DOMContentLoaded', () => {
  syncThemeButton();
  parseUrlParams();
  bindEvents();
  restoreLastOrder();
  loadStoreAndMenu();
});

function parseUrlParams() {
  const params = new URLSearchParams(window.location.search);
  const rawTable = params.get('table');
  state.restoId = params.get('resto') || '';
  const nameFromParam = params.get('resto_name');
  if (nameFromParam) {
    state.restoName = nameFromParam;
  }
  setTableNumber(rawTable || 1, false);
}

function bindEvents() {
  const searchInput = document.getElementById('searchInput');
  if (searchInput) {
    searchInput.addEventListener('input', (e) => {
      state.searchQuery = e.target.value.toLowerCase().trim();
      renderMenuGrid();
    });
  }

  const tabs = document.getElementById('categoryTabs');
  if (tabs) {
    tabs.addEventListener('click', (e) => {
      const btn = e.target.closest('.cat-tab');
      if (!btn) return;
      document
        .querySelectorAll('.cat-tab')
        .forEach((b) => b.classList.remove('active'));
      btn.classList.add('active');
      state.selectedCategory = btn.dataset.cat || 'Semua';
      renderMenuGrid();
    });
  }

  const tableInput = document.getElementById('tableNumberInput');
  if (tableInput) {
    tableInput.addEventListener('change', (e) => {
      setTableNumber(e.target.value, true);
    });
  }

  // Fallback light-dismiss hanya bila browser belum mendukung closedby="any"
  ['cartModal', 'successModal'].forEach((id) => {
    const dlg = document.getElementById(id);
    if (!dlg) return;
    if (!('closedBy' in dlg)) {
      dlg.addEventListener('click', (ev) => {
        if (ev.target === dlg) dlg.close();
      });
    }
    dlg.addEventListener('close', () => {
      if (id === 'successModal') stopOrderStatusPolling();
    });
  });
}

async function loadStoreAndMenu() {
  const loadingGrid = document.getElementById('loadingGrid');
  const menuGrid = document.getElementById('menuGrid');
  const emptyState = document.getElementById('emptyState');

  loadingGrid.hidden = false;
  menuGrid.hidden = true;
  emptyState.hidden = true;

  try {
    const restoEndpoint = state.restoId
      ? SUPABASE_URL +
        '/rest/v1/restaurants?id=eq.' +
        encodeURIComponent(state.restoId) +
        '&select=id,name'
      : SUPABASE_URL + '/rest/v1/restaurants?select=id,name&limit=1';

    const restoRes = await fetch(restoEndpoint, { headers: apiHeaders() });
    if (restoRes.ok) {
      const restoList = await restoRes.json();
      if (Array.isArray(restoList) && restoList.length > 0) {
        state.restoId = restoList[0].id;
        state.restoName = restoList[0].name || state.restoName;
      }
    }

    document.getElementById('restoNameDisplay').textContent = state.restoName;
    document.title = 'Menu Meja ' + state.tableNumber + ' — ' + state.restoName;

    let prodUrl =
      SUPABASE_URL + '/rest/v1/products?select=*&order=name.asc';
    if (state.restoId) {
      prodUrl += '&resto_id=eq.' + encodeURIComponent(state.restoId);
    }

    const prodRes = await fetch(prodUrl, { headers: apiHeaders() });
    if (!prodRes.ok) {
      throw new Error('HTTP ' + prodRes.status);
    }
    const products = await prodRes.json();
    state.products = Array.isArray(products) ? products : [];

    loadingGrid.hidden = true;
    renderMenuGrid();
  } catch (err) {
    console.error('Gagal memuat menu:', err);
    loadingGrid.hidden = true;
    document.getElementById('emptyDesc').textContent =
      'Gagal memuat daftar menu dari server. Periksa koneksi internet Anda lalu coba lagi.';
    emptyState.hidden = false;
  }
}

function resetFiltersAndFetch() {
  state.selectedCategory = 'Semua';
  state.searchQuery = '';
  const searchInput = document.getElementById('searchInput');
  if (searchInput) searchInput.value = '';
  document.querySelectorAll('.cat-tab').forEach((b) => {
    b.classList.toggle('active', b.dataset.cat === 'Semua');
  });
  loadStoreAndMenu();
}

// ============================================================================
// Menu Rendering & Cart Actions
// ============================================================================
function renderMenuGrid() {
  const menuGrid = document.getElementById('menuGrid');
  const emptyState = document.getElementById('emptyState');

  const filtered = state.products.filter((p) => {
    if (p.is_available === false) return false;
    const matchCat =
      state.selectedCategory === 'Semua' ||
      p.category === state.selectedCategory;
    const matchSearch =
      !state.searchQuery ||
      (p.name || '').toLowerCase().includes(state.searchQuery);
    return matchCat && matchSearch;
  });

  if (filtered.length === 0) {
    menuGrid.hidden = true;
    document.getElementById('emptyDesc').textContent = state.searchQuery
      ? 'Tidak ada menu yang cocok dengan kata kunci "' + state.searchQuery + '".'
      : 'Belum ada menu tersedia pada kategori ini.';
    emptyState.hidden = false;
    return;
  }

  emptyState.hidden = true;
  menuGrid.hidden = false;

  menuGrid.innerHTML = filtered
    .map((p) => {
      const stock = Number(p.stock) || 0;
      const outOfStock = stock <= 0;
      const inCart = state.cart[p.id] ? state.cart[p.id].qty : 0;
      const imgSrc = p.image_url || p.imageUrl || '';

      let stockLabel = 'Tersedia';
      let stockClass = '';
      if (outOfStock) {
        stockLabel = 'Habis';
        stockClass = 'empty';
      } else if (stock <= 5) {
        stockLabel = 'Sisa ' + stock;
        stockClass = 'low';
      }

      const thumbHtml = imgSrc
        ? '<img src="' +
          escapeHtml(imgSrc) +
          '" alt="' +
          escapeHtml(p.name) +
          '" loading="lazy" onerror="this.remove()" />'
        : '<div class="menu-thumb-placeholder" aria-hidden="true">' +
          getCategorySvg(p.category) +
          '</div>';

      const actionHtml =
        inCart > 0
          ? '<div class="qty-stepper">' +
            '<button type="button" class="qty-btn" aria-label="Kurangi jumlah" onclick="updateCartQty(\'' +
            escapeHtml(p.id) +
            '\', -1)">-</button>' +
            '<span class="qty-count tabular">' +
            inCart +
            '</span>' +
            '<button type="button" class="qty-btn plus" aria-label="Tambah jumlah" onclick="updateCartQty(\'' +
            escapeHtml(p.id) +
            '\', 1)">+</button>' +
            '</div>'
          : '<button type="button" class="btn-add" ' +
            (outOfStock ? 'disabled' : '') +
            ' onclick="updateCartQty(\'' +
            escapeHtml(p.id) +
            '\', 1)">' +
            (outOfStock ? 'Habis' : '+ Tambah') +
            '</button>';

      return (
        '<article class="menu-card ' +
        (outOfStock ? 'out-of-stock' : '') +
        '">' +
        '<div class="menu-thumb">' +
        thumbHtml +
        '<span class="stock-badge ' +
        stockClass +
        '">' +
        stockLabel +
        '</span>' +
        '</div>' +
        '<div class="menu-body">' +
        '<div class="menu-cat-label">' +
        escapeHtml(p.category || 'Menu') +
        '</div>' +
        '<h3 class="menu-name">' +
        escapeHtml(p.name) +
        '</h3>' +
        '<div class="menu-footer">' +
        '<span class="menu-price tabular">' +
        formatRupiah(p.price) +
        '</span>' +
        actionHtml +
        '</div>' +
        '</div>' +
        '</article>'
      );
    })
    .join('');
}

function updateCartQty(productId, delta) {
  const product = state.products.find((p) => String(p.id) === String(productId));
  if (!product) return;

  const existing = state.cart[productId] || { product, qty: 0 };
  const nextQty = existing.qty + delta;
  const maxStock = Number(product.stock) || 0;

  if (nextQty > maxStock) {
    showToast('Stok tersisa ' + maxStock + ' porsi');
    return;
  }

  if (nextQty <= 0) {
    delete state.cart[productId];
  } else {
    state.cart[productId] = { product, qty: nextQty };
  }

  renderMenuGrid();
  updateFloatingCartBar();

  const cartModal = document.getElementById('cartModal');
  if (cartModal && cartModal.open) {
    renderCartModalContent();
  }
}

function getCartTotals() {
  const items = Object.values(state.cart);
  const count = items.reduce((acc, i) => acc + i.qty, 0);
  const subtotal = items.reduce(
    (acc, i) => acc + (Number(i.product.price) || 0) * i.qty,
    0
  );
  const serviceFee = Math.round(subtotal * 0.05);
  const grandTotal = subtotal + serviceFee;
  return { items, count, subtotal, serviceFee, grandTotal };
}

function updateFloatingCartBar() {
  const bar = document.getElementById('floatingCartBar');
  const { count, grandTotal } = getCartTotals();

  document.getElementById('cartCountPill').textContent = count + ' item';
  document.getElementById('cartBarTotal').textContent = formatRupiah(grandTotal);
  document.getElementById('cartBarTableInfo').textContent =
    'Meja ' + state.tableNumber;

  if (count > 0) {
    bar.classList.add('visible');
  } else {
    bar.classList.remove('visible');
  }
}

// ============================================================================
// Checkout Dialog (<dialog>)
// ============================================================================
function openCartModal() {
  const { count } = getCartTotals();
  if (count === 0) return;

  const tableInput = document.getElementById('tableNumberInput');
  if (tableInput) tableInput.value = String(state.tableNumber);

  renderCartModalContent();
  const dlg = document.getElementById('cartModal');
  if (dlg && !dlg.open) dlg.showModal();
}

function closeCartModal() {
  const dlg = document.getElementById('cartModal');
  if (dlg && dlg.open) dlg.close();
}

function renderCartModalContent() {
  const { items, count, subtotal, serviceFee, grandTotal } = getCartTotals();
  const container = document.getElementById('cartItemsContainer');

  if (count === 0) {
    closeCartModal();
    return;
  }

  container.innerHTML = items
    .map(({ product, qty }) => {
      const lineTotal = (Number(product.price) || 0) * qty;
      return (
        '<div class="cart-item-row">' +
        '<div class="cart-item-info">' +
        '<div class="cart-item-name">' +
        escapeHtml(product.name) +
        '</div>' +
        '<div class="cart-item-sub tabular">' +
        qty +
        ' x ' +
        formatRupiah(product.price) +
        ' = <strong>' +
        formatRupiah(lineTotal) +
        '</strong></div>' +
        '</div>' +
        '<div class="qty-stepper">' +
        '<button type="button" class="qty-btn" aria-label="Kurangi" onclick="updateCartQty(\'' +
        escapeHtml(product.id) +
        '\', -1)">-</button>' +
        '<span class="qty-count tabular">' +
        qty +
        '</span>' +
        '<button type="button" class="qty-btn plus" aria-label="Tambah" onclick="updateCartQty(\'' +
        escapeHtml(product.id) +
        '\', 1)">+</button>' +
        '</div>' +
        '</div>'
      );
    })
    .join('');

  document.getElementById('modalSubtotal').textContent = formatRupiah(subtotal);
  document.getElementById('modalService').textContent = formatRupiah(serviceFee);
  document.getElementById('modalTotal').textContent = formatRupiah(grandTotal);
}

function selectPayment(btn) {
  document
    .querySelectorAll('.pay-option')
    .forEach((b) => b.classList.remove('active'));
  btn.classList.add('active');
  state.selectedPayment = btn.dataset.method || 'Bayar di Kasir';
}

// ============================================================================
// Submit Order to Supabase -> Syncs Immediately to Cashier App
// ============================================================================
async function submitOrder() {
  const tableInput = document.getElementById('tableNumberInput');
  const rawTable = tableInput ? parseInt(tableInput.value, 10) : state.tableNumber;
  if (Number.isNaN(rawTable) || rawTable < 1 || rawTable > 99) {
    showToast('Masukkan nomor meja yang valid (1 - 99)');
    if (tableInput) tableInput.focus();
    return;
  }
  setTableNumber(rawTable, true);

  const nameInput = document.getElementById('customerNameInput');
  const customerName = nameInput ? nameInput.value.trim() : '';
  if (!customerName) {
    showToast('Mohon isi nama pemesan terlebih dahulu');
    if (nameInput) nameInput.focus();
    return;
  }

  const notesInput = document.getElementById('orderNotesInput');
  const notes = notesInput ? notesInput.value.trim() : '';

  const { items, subtotal, serviceFee, grandTotal } = getCartTotals();
  if (items.length === 0) return;

  const submitBtn = document.getElementById('btnSubmitOrder');
  submitBtn.disabled = true;
  submitBtn.textContent = 'Mengirim pesanan...';

  try {
    const now = new Date();
    const datePart =
      String(now.getFullYear()) +
      String(now.getMonth() + 1).padStart(2, '0') +
      String(now.getDate()).padStart(2, '0');
    const randPart = String(Math.floor(1000 + Math.random() * 9000));
    const invoiceNo = 'WEB-' + datePart + '-' + randPart;

    const paymentLabel =
      state.selectedPayment === 'QRIS'
        ? 'QRIS (Meja)'
        : 'Bayar di Kasir (Meja)';

    const baseCustomerTag = 'Meja ' + state.tableNumber + ' (' + customerName + ')';
    const cashierNameLabel = notes
      ? baseCustomerTag + ' - Catatan: ' + notes
      : baseCustomerTag;

    const orderPayload = {
      invoice_no: invoiceNo,
      resto_id: state.restoId,
      cashier_name: cashierNameLabel,
      table_number: state.tableNumber,
      subtotal: subtotal,
      service_fee: serviceFee,
      total: grandTotal,
      payment_method: paymentLabel,
      status: 'pesanan dibuat',
    };

    const orderRes = await fetch(SUPABASE_URL + '/rest/v1/orders', {
      method: 'POST',
      headers: apiHeaders({ Prefer: 'return=representation' }),
      body: JSON.stringify(orderPayload),
    });

    if (!orderRes.ok) {
      const errBody = await orderRes.text();
      throw new Error('Gagal menyimpan pesanan (' + orderRes.status + '): ' + errBody);
    }

    const createdRows = await orderRes.json();
    const createdOrder = Array.isArray(createdRows) ? createdRows[0] : createdRows;
    const orderId = createdOrder ? createdOrder.id : '';

    const itemsPayload = items.map(({ product, qty }) => ({
      order_id: orderId,
      product_id: product.id,
      product_name: product.name,
      price: Number(product.price) || 0,
      quantity: qty,
      subtotal: (Number(product.price) || 0) * qty,
    }));

    const itemsRes = await fetch(SUPABASE_URL + '/rest/v1/order_items', {
      method: 'POST',
      headers: apiHeaders(),
      body: JSON.stringify(itemsPayload),
    });
    if (!itemsRes.ok) {
      throw new Error('Gagal menyimpan detail item (' + itemsRes.status + ')');
    }

    // Kurangi stok secara paralel agar tetap akurat di kasir
    await Promise.all(
      items.map(({ product, qty }) => {
        const nextStock = Math.max(0, (Number(product.stock) || 0) - qty);
        return fetch(
          SUPABASE_URL + '/rest/v1/products?id=eq.' + encodeURIComponent(product.id),
          {
            method: 'PATCH',
            headers: apiHeaders(),
            body: JSON.stringify({
              stock: nextStock,
              is_available: nextStock > 0,
            }),
          }
        );
      })
    );

    const savedSummary = {
      id: orderId,
      invoiceNo,
      tableNumber: state.tableNumber,
      customerName,
      notes,
      total: grandTotal,
      paymentMethod: paymentLabel,
      isQris: state.selectedPayment === 'QRIS',
      status: 'pesanan dibuat',
      itemsSummary: items.map((i) => i.product.name + ' x' + i.qty),
    };

    saveLastOrder(savedSummary);
    state.cart = {};
    if (notesInput) notesInput.value = '';
    updateFloatingCartBar();
    closeCartModal();
    loadStoreAndMenu();
    openOrderStatusModal(savedSummary);
  } catch (err) {
    console.error('Submit order error:', err);
    showToast('Gagal mengirim pesanan. Silakan coba lagi.');
  } finally {
    submitBtn.disabled = false;
    submitBtn.textContent = 'Kirim Pesanan ke Kasir';
  }
}

// ============================================================================
// Last Order Persistence & Live Status Modal
// ============================================================================
function saveLastOrder(summary) {
  state.lastOrder = summary;
  try {
    localStorage.setItem(LAST_ORDER_STORAGE_KEY, JSON.stringify(summary));
  } catch (e) {
    // Ignore storage error
  }
  const checkBtn = document.getElementById('checkLastOrderBtn');
  if (checkBtn) checkBtn.hidden = false;
}

function restoreLastOrder() {
  try {
    const raw = localStorage.getItem(LAST_ORDER_STORAGE_KEY);
    if (!raw) return;
    const parsed = JSON.parse(raw);
    if (parsed && parsed.invoiceNo) {
      state.lastOrder = parsed;
      const checkBtn = document.getElementById('checkLastOrderBtn');
      if (checkBtn) checkBtn.hidden = false;
    }
  } catch (e) {
    // Ignore parse error
  }
}

function openLastOrderStatus() {
  if (!state.lastOrder) return;
  openOrderStatusModal(state.lastOrder);
}

function openOrderStatusModal(order) {
  renderOrderStatusModal(order);
  const dlg = document.getElementById('successModal');
  if (dlg && !dlg.open) dlg.showModal();
  startOrderStatusPolling(order);
}

function closeSuccessModal() {
  stopOrderStatusPolling();
  const dlg = document.getElementById('successModal');
  if (dlg && dlg.open) dlg.close();
}

function renderOrderStatusModal(order) {
  const statusLower = (order.status || '').toLowerCase();
  const isCompleted =
    statusLower === 'pesanan selesai' || statusLower === 'selesai';

  const banner = document.getElementById('orderStatusBanner');
  const titleEl = document.getElementById('orderStatusTitle');
  const subEl = document.getElementById('orderStatusSub');

  if (banner) {
    banner.classList.toggle('completed', isCompleted);
  }
  if (titleEl) {
    titleEl.textContent = isCompleted
      ? 'Pesanan Sudah Dicek / Lunas'
      : 'Pesanan Terkirim ke Kasir';
  }
  if (subEl) {
    subEl.textContent = isCompleted
      ? 'Status di aplikasi kasir: Selesai diproses'
      : 'Status di aplikasi kasir: Menunggu dicek oleh kasir';
  }

  document.getElementById('successTableNumber').textContent =
    'Meja ' + order.tableNumber;

  const itemsText = Array.isArray(order.itemsSummary)
    ? order.itemsSummary.join(', ')
    : '-';

  const notesLine = order.notes
    ? '<div class="receipt-line"><span>Catatan</span><strong>' +
      escapeHtml(order.notes) +
      '</strong></div>'
    : '';

  document.getElementById('successOrderDetails').innerHTML =
    '<div class="receipt-line"><span>Nomor Nota</span><strong>' +
    escapeHtml(order.invoiceNo) +
    '</strong></div>' +
    '<div class="receipt-line"><span>Pemesan</span><strong>' +
    escapeHtml(order.customerName) +
    '</strong></div>' +
    '<div class="receipt-line"><span>Metode Bayar</span><strong>' +
    escapeHtml(order.paymentMethod) +
    '</strong></div>' +
    '<div class="receipt-line"><span>Menu</span><strong>' +
    escapeHtml(itemsText) +
    '</strong></div>' +
    notesLine +
    '<div class="receipt-line" style="margin-top:0.5rem;padding-top:0.5rem;border-top:1px solid var(--border);">' +
    '<span>Total Tagihan</span><strong class="tabular">' +
    formatRupiah(order.total) +
    '</strong></div>';

  const qrisBox = document.getElementById('qrisInstantBox');
  const canvas = document.getElementById('webQrisCanvas');
  if (order.isQris && !isCompleted) {
    qrisBox.hidden = false;
    if (canvas) {
      canvas.innerHTML = '';
      if (typeof QRCode !== 'undefined') {
        const payLink =
          PAY_PAGE_URL +
          '?inv=' +
          encodeURIComponent(order.invoiceNo) +
          '&amt=' +
          encodeURIComponent(order.total) +
          '&resto=' +
          encodeURIComponent(state.restoName) +
          '&id=' +
          encodeURIComponent(order.id || '') +
          '&table=' +
          encodeURIComponent(order.tableNumber);
        new QRCode(canvas, {
          text: payLink,
          width: 156,
          height: 156,
          colorDark: '#171614',
          colorLight: '#ffffff',
          correctLevel: QRCode.CorrectLevel.M,
        });
      }
    }
  } else {
    qrisBox.hidden = true;
  }
}

async function confirmWebQrisPayment() {
  if (!state.lastOrder || !state.lastOrder.id) return;
  const btn = document.getElementById('btnConfirmWebQris');
  if (btn) {
    btn.disabled = true;
    btn.textContent = 'Memproses pembayaran...';
  }
  try {
    const res = await fetch(
      SUPABASE_URL +
        '/rest/v1/orders?id=eq.' +
        encodeURIComponent(state.lastOrder.id),
      {
        method: 'PATCH',
        headers: apiHeaders(),
        body: JSON.stringify({ status: 'pesanan selesai' }),
      }
    );
    if (!res.ok) throw new Error('HTTP ' + res.status);

    state.lastOrder.status = 'pesanan selesai';
    saveLastOrder(state.lastOrder);
    renderOrderStatusModal(state.lastOrder);
    showToast('Pembayaran QRIS berhasil. Sebutkan nomor meja Anda ke kasir.');
  } catch (err) {
    console.error('QRIS confirm error:', err);
    showToast('Gagal mengonfirmasi pembayaran QRIS');
  } finally {
    if (btn) {
      btn.disabled = false;
      btn.textContent = 'Konfirmasi Pembayaran QRIS';
    }
  }
}

function startOrderStatusPolling(order) {
  stopOrderStatusPolling();
  if (!order || !order.id) return;

  state.statusPollTimer = setInterval(async () => {
    try {
      const res = await fetch(
        SUPABASE_URL +
          '/rest/v1/orders?id=eq.' +
          encodeURIComponent(order.id) +
          '&select=status',
        { headers: apiHeaders() }
      );
      if (!res.ok) return;
      const rows = await res.json();
      if (Array.isArray(rows) && rows.length > 0) {
        const latestStatus = rows[0].status;
        if (latestStatus && latestStatus !== state.lastOrder.status) {
          state.lastOrder.status = latestStatus;
          saveLastOrder(state.lastOrder);
          renderOrderStatusModal(state.lastOrder);
        }
      }
    } catch (e) {
      // Silent retry
    }
  }, 4000);
}

function stopOrderStatusPolling() {
  if (state.statusPollTimer) {
    clearInterval(state.statusPollTimer);
    state.statusPollTimer = null;
  }
}

function showToast(msg) {
  const el = document.getElementById('toastEl');
  if (!el) return;
  el.textContent = msg;
  el.classList.add('show');
  setTimeout(() => el.classList.remove('show'), 3200);
}
