/* ============================================================================
   RestoKasir Customer Self-Order Application
   - Automatic Table Identification (?table=04) & Backend Validation
   - Locked Table Number (No Manual Table Switching)
   - Dual Payment Modes: QRIS (MODE DEMO) & Bayar Melalui Kasir (Realtime)
   ============================================================================ */

const SUPABASE_URL = 'https://uinumtttwkwlurvqvidh.supabase.co';
const SUPABASE_ANON_KEY =
  'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InVpbnVtdHR0d2t3bHVydnF2aWRoIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODQ2OTUxNTcsImV4cCI6MjEwMDI3MTE1N30.eSfjbxge6LA8fIqP9Cnepld7s4PgQgh_Eqi3O58DI1M';

const MAX_DEFAULT_TABLES = 20;
const PREVIEW_DEFAULT_TABLE = 4;
const PREVIEW_DEFAULT_RESTO = 'a36bf20d-4060-4f78-babe-6202d8f8705d';

// Identitas meja terkunci privat agar tidak bisa diubah dari UI atau konsol
let lockedTableNumber = null;
let tableValidated = false;
let supabaseClient = null;
let extendedSchemaSupported = null;

const state = {
  restoId: '',
  restoName: 'RestoKasir',
  products: [],
  cart: {},
  selectedCategory: 'Semua',
  searchQuery: '',
  lastOrder: null,
  statusPollTimer: null,
  realtimeChannel: null,
  activeDetailProductId: null,
};

Object.defineProperty(state, 'tableNumber', {
  enumerable: true,
  configurable: false,
  get() {
    return lockedTableNumber;
  },
});

function getSupabaseClient() {
  if (supabaseClient) return supabaseClient;
  if (window.supabase && typeof window.supabase.createClient === 'function') {
    supabaseClient = window.supabase.createClient(SUPABASE_URL, SUPABASE_ANON_KEY, {
      auth: { persistSession: false },
    });
  }
  return supabaseClient;
}

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

function formatTableLabel(tableNum) {
  const padded = String(tableNum).padStart(2, '0');
  return 'Meja ' + padded;
}

function formatOrderTime(isoStr) {
  try {
    const d = isoStr ? new Date(isoStr) : new Date();
    return d.toLocaleTimeString('id-ID', {
      hour: '2-digit',
      minute: '2-digit',
    });
  } catch (e) {
    return '-';
  }
}

// ============================================================================
// Parsing & Validasi Nomor Meja Otomatis dari Parameter URL QR Code
// ============================================================================
function parseStrictTableFromUrl() {
  const params = new URLSearchParams(window.location.search);
  let rawTable = (params.get('table') || '').trim();
  let restoParam = (params.get('resto') || '').trim();
  const nameParam = (params.get('resto_name') || '').trim();

  // Fallback otomatis ke Meja 04 bila dibuka di dalam iframe pratinjau tanpa query string
  const isEmbeddedPreview =
    !window.location.search &&
    (window.self !== window.top ||
      window.location.protocol === 'blob:' ||
      window.location.protocol === 'about:');

  if (isEmbeddedPreview && !rawTable) {
    rawTable = String(PREVIEW_DEFAULT_TABLE).padStart(2, '0');
    if (!restoParam) restoParam = PREVIEW_DEFAULT_RESTO;
  }

  if (!/^\d+$/.test(rawTable)) {
    return { valid: false, tableNumber: null, restoParam, nameParam };
  }

  const parsed = parseInt(rawTable, 10);
  if (Number.isNaN(parsed) || parsed < 1) {
    return { valid: false, tableNumber: null, restoParam, nameParam };
  }

  return { valid: true, tableNumber: parsed, restoParam, nameParam };
}

function applyLockedTableLabels(tableNum) {
  const label = formatTableLabel(tableNum);
  const badge = document.getElementById('tableBadge');
  const badgeText = document.getElementById('tableBadgeText');
  const noticeTitle = document.getElementById('noticeTableTitle');
  const cartBarTable = document.getElementById('cartBarTableInfo');
  const modalTable = document.getElementById('modalLockedTableText');

  if (badgeText) {
    badgeText.textContent = label;
  } else if (badge) {
    badge.textContent = label;
  }
  if (badge) {
    badge.hidden = false;
  }
  const btnCheck = document.getElementById('btnCheckOrder');
  if (btnCheck) {
    btnCheck.hidden = false;
  }
  if (noticeTitle) {
    noticeTitle.textContent = 'Pemesanan otomatis untuk ' + label;
  }
  if (cartBarTable) cartBarTable.textContent = label;
  if (modalTable) modalTable.textContent = label;
  document.title = 'Menu ' + label + ' — ' + state.restoName;
}

function showInvalidQrScreen(customMessage) {
  tableValidated = false;
  lockedTableNumber = null;

  const badge = document.getElementById('tableBadge');
  const orderingContent = document.getElementById('orderingContent');
  const invalidView = document.getElementById('invalidQrView');
  const invalidMsg = document.getElementById('invalidQrMessage');
  const cartBar = document.getElementById('floatingCartBar');

  const btnCheck = document.getElementById('btnCheckOrder');
  if (btnCheck) btnCheck.hidden = true;
  if (badge) badge.hidden = true;
  if (orderingContent) orderingContent.hidden = true;
  if (cartBar) cartBar.classList.remove('visible');

  if (invalidMsg) {
    invalidMsg.textContent =
      customMessage ||
      'QR Code meja tidak valid. Silakan pindai kembali QR Code yang tersedia di meja Anda.';
  }
  if (invalidView) invalidView.hidden = false;
  document.title = 'QR Code Meja Tidak Valid — RestoKasir';
}

async function verifyTableInSupabase(restoId, tableNum) {
  if (!tableNum || tableNum < 1) return false;
  if (!restoId) return tableNum >= 1 && tableNum <= MAX_DEFAULT_TABLES;

  try {
    const res = await fetch(
      SUPABASE_URL +
        '/rest/v1/restaurant_tables?resto_id=eq.' +
        encodeURIComponent(restoId) +
        '&select=id,table_number,is_active',
      { headers: apiHeaders() }
    );

    if (res.ok) {
      const rows = await res.json();
      if (Array.isArray(rows) && rows.length > 0) {
        const matched = rows.find((r) => Number(r.table_number) === Number(tableNum));
        if (!matched) return false;
        return matched.is_active !== false;
      }
      // Jika restaurant_tables belum diisi untuk resto ini, validasi nomor meja standar 1..20
      return tableNum >= 1 && tableNum <= MAX_DEFAULT_TABLES;
    }

    if (res.status === 404 || res.status === 401 || res.status === 403) {
      return tableNum >= 1 && tableNum <= MAX_DEFAULT_TABLES;
    }

    return tableNum >= 1 && tableNum <= MAX_DEFAULT_TABLES;
  } catch (e) {
    console.error('Gagal memverifikasi nomor meja di Supabase:', e);
    return tableNum >= 1 && tableNum <= MAX_DEFAULT_TABLES;
  }
}

async function detectExtendedOrderSchema() {
  if (extendedSchemaSupported !== null) return extendedSchemaSupported;
  try {
    const res = await fetch(
      SUPABASE_URL + '/rest/v1/orders?select=id,payment_status,order_source&limit=1',
      { headers: apiHeaders() }
    );
    extendedSchemaSupported = res.ok;
  } catch (e) {
    extendedSchemaSupported = false;
  }
  return extendedSchemaSupported;
}

// ============================================================================
// Placeholder SVG Berdasarkan Kategori
// ============================================================================
function getCategorySvg(cat) {
  const c = (cat || '').toLowerCase();
  if (c.includes('minuman')) {
    return (
      '<svg width="36" height="36" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round">' +
      '<path d="M6 8h12l-1.5 11a2 2 0 0 1-2 1.7H9.5a2 2 0 0 1-2-1.7L6 8z" />' +
      '<path d="M5 8h14" />' +
      '<path d="M12 8V4l3-1" />' +
      '</svg>'
    );
  }
  if (c.includes('dessert')) {
    return (
      '<svg width="36" height="36" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round">' +
      '<path d="M4 13h16v6a2 2 0 0 1-2 2H6a2 2 0 0 1-2-2v-6z" />' +
      '<path d="M4 13c0-3 3.5-5 8-5s8 2 8 5" />' +
      '<circle cx="12" cy="5.5" r="1.5" />' +
      '</svg>'
    );
  }
  return (
    '<svg width="36" height="36" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round">' +
    '<circle cx="12" cy="12" r="8" />' +
    '<circle cx="12" cy="12" r="4" />' +
    '<path d="M3 12h1M20 12h1" />' +
    '</svg>'
  );
}

// ============================================================================
// Accessible Form Validation (:user-invalid + ARIA live sync)
// ============================================================================
function linkInputError(el, shown) {
  const errId = el.dataset.error;
  if (!errId) return;
  const ids = (el.getAttribute('aria-describedby') || '')
    .split(/\s+/)
    .filter((id) => id && id !== errId);
  if (shown) ids.push(errId);
  if (ids.length) {
    el.setAttribute('aria-describedby', ids.join(' '));
  } else {
    el.removeAttribute('aria-describedby');
  }
}

function updateFieldValidationState(el, showErrorIfInvalid = false) {
  if (!el || !el.validity) return true;
  const val = (el.value || '').trim();
  if (el.id === 'customerNameInput') {
    el.setCustomValidity(val ? '' : 'Nama pemesan wajib diisi.');
  }
  const isValid = el.validity.valid;
  if (!isValid && showErrorIfInvalid) {
    el.classList.add('user-invalid-fallback');
    el.setAttribute('aria-invalid', 'true');
    linkInputError(el, true);
  } else if (isValid) {
    el.classList.remove('user-invalid-fallback');
    el.setAttribute('aria-invalid', 'false');
    linkInputError(el, false);
  }
  return isValid;
}

// ============================================================================
// Initialization & Data Fetching
// ============================================================================
document.addEventListener('DOMContentLoaded', () => {
  bindEvents();
  bootstrapOrderPage();
});

async function bootstrapOrderPage() {
  const parsed = parseStrictTableFromUrl();
  if (!parsed.valid) {
    showInvalidQrScreen(
      'QR Code meja tidak valid. Silakan pindai kembali QR Code yang tersedia di meja Anda.'
    );
    return;
  }

  state.restoId = parsed.restoParam;
  if (parsed.nameParam) {
    state.restoName = parsed.nameParam;
  }

  const invalidView = document.getElementById('invalidQrView');
  const orderingContent = document.getElementById('orderingContent');
  const loadingState = document.getElementById('loadingState');
  const menuGrid = document.getElementById('menuGrid');
  const emptyState = document.getElementById('emptyState');

  if (invalidView) invalidView.hidden = true;
  if (orderingContent) orderingContent.hidden = false;
  if (loadingState) loadingState.hidden = false;
  if (menuGrid) menuGrid.hidden = true;
  if (emptyState) emptyState.hidden = true;

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
        state.restoId = restoList[0].id || state.restoId;
        state.restoName = restoList[0].name || state.restoName;
      } else if (!state.restoId) {
        showInvalidQrScreen(
          'Data restoran pada QR Code tidak ditemukan. Silakan pindai ulang QR Code di meja Anda.'
        );
        return;
      }
    } else if (!state.restoId) {
      throw new Error('Gagal memuat data restoran (HTTP ' + restoRes.status + ')');
    }

    document.getElementById('restoNameDisplay').textContent = state.restoName;

    const isRegisteredTable = await verifyTableInSupabase(
      state.restoId,
      parsed.tableNumber
    );
    if (!isRegisteredTable) {
      showInvalidQrScreen(
        'QR Code meja tidak valid. Silakan pindai kembali QR Code yang tersedia di meja Anda.'
      );
      return;
    }

    lockedTableNumber = parsed.tableNumber;
    tableValidated = true;
    applyLockedTableLabels(lockedTableNumber);

    restoreLastOrderFromStorage();
    await Promise.all([
      fetchMenuProducts(),
      detectExtendedOrderSchema(),
      fetchLatestTableOrderFromServer(),
    ]);
  } catch (err) {
    console.error('Bootstrap error:', err);
    lockedTableNumber = parsed.tableNumber;
    tableValidated = true;
    applyLockedTableLabels(lockedTableNumber);
    if (loadingState) loadingState.hidden = true;
    document.getElementById('emptyDesc').textContent =
      'Gagal memuat data dari server. Periksa koneksi internet Anda lalu coba lagi.';
    if (emptyState) emptyState.hidden = false;
  }
}

function sortProductsNewestFirst(list) {
  return [...list].sort((a, b) => {
    const aTime = Date.parse(a && a.created_at ? a.created_at : '');
    const bTime = Date.parse(b && b.created_at ? b.created_at : '');
    const validA = Number.isFinite(aTime);
    const validB = Number.isFinite(bTime);
    if (validA && validB && bTime !== aTime) {
      return bTime - aTime;
    }
    if (validB && !validA) return 1;
    if (validA && !validB) return -1;

    const aId = Number(a && a.id);
    const bId = Number(b && b.id);
    if (Number.isFinite(aId) && Number.isFinite(bId) && bId !== aId) {
      return bId - aId;
    }
    return String((a && a.name) || '').localeCompare(String((b && b.name) || ''), 'id');
  });
}

async function fetchMenuProducts() {
  const loadingState = document.getElementById('loadingState');
  const menuGrid = document.getElementById('menuGrid');
  const emptyState = document.getElementById('emptyState');

  if (loadingState) loadingState.hidden = false;
  if (menuGrid) menuGrid.hidden = true;
  if (emptyState) emptyState.hidden = true;

  try {
    let prodUrl = SUPABASE_URL + '/rest/v1/products?select=*&order=created_at.desc,name.asc';
    if (state.restoId) {
      prodUrl += '&resto_id=eq.' + encodeURIComponent(state.restoId);
    }

    const prodRes = await fetch(prodUrl, { headers: apiHeaders() });
    if (!prodRes.ok) {
      throw new Error('HTTP ' + prodRes.status);
    }
    const products = await prodRes.json();
    const validProducts = (Array.isArray(products) ? products : []).filter(
      (p) => p && p.id && p.name && String(p.name).trim() && Number(p.price) >= 0
    );
    state.products = sortProductsNewestFirst(validProducts);

    if (loadingState) loadingState.hidden = true;
    renderMenuGrid();

    if (state.activeDetailProductId) {
      renderProductDetailDialog(state.activeDetailProductId);
    }
  } catch (err) {
    console.error('Gagal memuat menu:', err);
    if (loadingState) loadingState.hidden = true;
    document.getElementById('emptyDesc').textContent =
      'Gagal memuat daftar menu dari server. Silakan coba lagi.';
    if (emptyState) emptyState.hidden = false;
  }
}

function bindEvents() {
  const searchForm = document.getElementById('searchForm');
  if (searchForm) {
    searchForm.addEventListener('submit', (e) => e.preventDefault());
  }

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
      btn.scrollIntoView({ inline: 'center', block: 'nearest', behavior: 'smooth' });
      state.selectedCategory = btn.dataset.cat || 'Semua';
      renderMenuGrid();
    });
  }

  const menuGrid = document.getElementById('menuGrid');
  if (menuGrid) {
    menuGrid.addEventListener('click', (e) => {
      const stepBtn = e.target.closest('[data-cart-action]');
      if (stepBtn) {
        const pid = stepBtn.dataset.productId;
        const delta = stepBtn.dataset.cartAction === 'inc' ? 1 : -1;
        updateCartQty(pid, delta, true);
        return;
      }

      const detailBtn = e.target.closest('[data-detail-id]');
      if (detailBtn) {
        openProductDetailModal(detailBtn.dataset.detailId);
      }
    });
  }

  const cartContainer = document.getElementById('cartItemsContainer');
  if (cartContainer) {
    cartContainer.addEventListener('click', (e) => {
      const stepBtn = e.target.closest('[data-cart-action]');
      if (!stepBtn) return;
      const pid = stepBtn.dataset.productId;
      const delta = stepBtn.dataset.cartAction === 'inc' ? 1 : -1;
      updateCartQty(pid, delta, false);
    });
  }

  const detailFooter = document.getElementById('detailModalFooter');
  if (detailFooter) {
    detailFooter.addEventListener('click', (e) => {
      const stepBtn = e.target.closest('[data-cart-action]');
      if (!stepBtn) return;
      const pid = stepBtn.dataset.productId;
      const delta = stepBtn.dataset.cartAction === 'inc' ? 1 : -1;
      updateCartQty(pid, delta, true);
    });
  }

  const checkoutForm = document.getElementById('checkoutForm');
  const customerNameInput = document.getElementById('customerNameInput');
  if (customerNameInput) {
    customerNameInput.setAttribute('aria-invalid', 'false');
    customerNameInput.addEventListener('input', () => {
      if (customerNameInput.value.trim()) {
        updateFieldValidationState(customerNameInput, false);
      }
    });
    customerNameInput.addEventListener('blur', () => {
      updateFieldValidationState(customerNameInput, true);
    });
  }

  if (checkoutForm) {
    checkoutForm.addEventListener('submit', (e) => {
      e.preventDefault();
      if (customerNameInput) {
        const isValid = updateFieldValidationState(customerNameInput, true);
        if (!isValid) {
          customerNameInput.focus();
          return;
        }
      }
      submitOrder();
    });
  }

  document.getElementById('btnOpenCart')?.addEventListener('click', openCartModal);
  document.getElementById('btnCloseCart')?.addEventListener('click', closeCartModal);
  document.getElementById('btnCloseDetail')?.addEventListener('click', closeProductDetailModal);
  document.getElementById('btnCheckOrder')?.addEventListener('click', handleCheckOrderClick);
  document.getElementById('activeOrderBar')?.addEventListener('click', handleCheckOrderClick);
  document.getElementById('btnRefreshOrderStatus')?.addEventListener('click', manualRefreshOrderStatus);
  document.getElementById('btnCloseOrderFlow')?.addEventListener('click', closeOrderFlowModal);
  document.getElementById('btnBackToMenu')?.addEventListener('click', closeOrderFlowModal);
  document.getElementById('btnConfirmDemoQris')?.addEventListener('click', confirmDemoQrisSimulation);
  document.getElementById('btnRetryMenu')?.addEventListener('click', resetFiltersAndFetch);

  ['cartModal', 'productDetailModal', 'orderFlowModal'].forEach((id) => {
    const dlg = document.getElementById(id);
    if (!dlg) return;
    if (!('closedBy' in dlg)) {
      dlg.addEventListener('click', (ev) => {
        if (ev.target === dlg) dlg.close();
      });
    }
    dlg.addEventListener('close', () => {
      if (id === 'orderFlowModal') stopOrderListeners();
      if (id === 'productDetailModal') state.activeDetailProductId = null;
    });
  });
}

function resetFiltersAndFetch() {
  state.selectedCategory = 'Semua';
  state.searchQuery = '';
  const searchInput = document.getElementById('searchInput');
  if (searchInput) searchInput.value = '';
  document.querySelectorAll('.cat-tab').forEach((b) => {
    b.classList.toggle('active', b.dataset.cat === 'Semua');
  });
  fetchMenuProducts();
}

// ============================================================================
// Menu Grid, Product Detail Modal & Cart Actions
// ============================================================================
function buildStepperOrAddHtml(product, inCart) {
  const stock = Number(product.stock) || 0;
  const outOfStock = stock <= 0;
  const safeId = escapeHtml(product.id);

  if (inCart > 0) {
    return (
      '<div class="qty-stepper">' +
      '<button type="button" class="qty-btn" data-cart-action="dec" data-product-id="' +
      safeId +
      '" aria-label="Kurangi jumlah ' +
      escapeHtml(product.name) +
      '">-</button>' +
      '<span class="qty-count tabular">' +
      inCart +
      '</span>' +
      '<button type="button" class="qty-btn plus" data-cart-action="inc" data-product-id="' +
      safeId +
      '" aria-label="Tambah jumlah ' +
      escapeHtml(product.name) +
      '">+</button>' +
      '</div>'
    );
  }

  return (
    '<button type="button" class="btn-add" data-cart-action="inc" data-product-id="' +
    safeId +
    '" ' +
    (outOfStock ? 'disabled' : '') +
    '>' +
    (outOfStock ? 'Habis' : '+ Tambah') +
    '</button>'
  );
}

function renderMenuGrid() {
  if (!tableValidated) return;
  const menuGrid = document.getElementById('menuGrid');
  const emptyState = document.getElementById('emptyState');

  const filtered = sortProductsNewestFirst(
    state.products.filter((p) => {
      if (!p || !p.id || !p.name || !String(p.name).trim()) return false;
      if (p.is_available === false) return false;
      const matchCat =
        state.selectedCategory === 'Semua' ||
        p.category === state.selectedCategory;
      const matchSearch =
        !state.searchQuery ||
        (p.name || '').toLowerCase().includes(state.searchQuery);
      return matchCat && matchSearch;
    })
  );

  if (filtered.length === 0) {
    menuGrid.dataset.count = '0';
    menuGrid.hidden = true;
    document.getElementById('emptyDesc').textContent = state.searchQuery
      ? 'Tidak ada menu yang cocok dengan kata kunci "' + state.searchQuery + '".'
      : 'Belum ada menu tersedia saat ini.';
    emptyState.hidden = false;
    return;
  }

  emptyState.hidden = true;
  menuGrid.hidden = false;
  menuGrid.dataset.count = String(filtered.length);

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

      const placeholderHtml =
        '<div class="menu-thumb-placeholder" aria-hidden="true">' +
        getCategorySvg(p.category) +
        '</div>';

      const imgHtml = imgSrc
        ? '<img src="' +
          escapeHtml(imgSrc) +
          '" alt="' +
          escapeHtml(p.name) +
          '" loading="lazy" onerror="this.remove()" />'
        : '';

      return (
        '<article class="menu-card ' +
        (outOfStock ? 'out-of-stock' : '') +
        '">' +
        '<button type="button" class="menu-detail-trigger" data-detail-id="' +
        escapeHtml(p.id) +
        '" aria-label="Lihat detail ' +
        escapeHtml(p.name) +
        '">' +
        '<div class="menu-thumb">' +
        placeholderHtml +
        imgHtml +
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
        (p.description && String(p.description).trim()
          ? '<p class="menu-desc-snippet">' +
            escapeHtml(String(p.description).trim()) +
            '</p>'
          : '') +
        '</div>' +
        '</button>' +
        '<div class="menu-footer">' +
        '<span class="menu-price tabular">' +
        formatRupiah(p.price) +
        '</span>' +
        buildStepperOrAddHtml(p, inCart) +
        '</div>' +
        '</article>'
      );
    })
    .join('');
}

function openProductDetailModal(productId) {
  state.activeDetailProductId = productId;
  renderProductDetailDialog(productId);
  const dlg = document.getElementById('productDetailModal');
  if (dlg && !dlg.open) dlg.showModal();
}

function closeProductDetailModal() {
  state.activeDetailProductId = null;
  const dlg = document.getElementById('productDetailModal');
  if (dlg && dlg.open) dlg.close();
}

function renderProductDetailDialog(productId) {
  const product = state.products.find((p) => String(p.id) === String(productId));
  if (!product) {
    closeProductDetailModal();
    return;
  }

  const stock = Number(product.stock) || 0;
  const outOfStock = stock <= 0;
  const inCart = state.cart[product.id] ? state.cart[product.id].qty : 0;
  const imgSrc = product.image_url || product.imageUrl || '';

  const placeholderHtml =
    '<div class="menu-thumb-placeholder" aria-hidden="true">' +
    getCategorySvg(product.category) +
    '</div>';

  const imgHtml = imgSrc
    ? '<img src="' +
      escapeHtml(imgSrc) +
      '" alt="' +
      escapeHtml(product.name) +
      '" onerror="this.remove()" />'
    : '';

  const stockText = outOfStock ? 'Stok habis' : 'Tersedia: ' + stock + ' porsi';

  document.getElementById('detailModalBody').innerHTML =
    '<div class="detail-hero">' +
    placeholderHtml +
    imgHtml +
    '</div>' +
    '<div class="detail-meta-row">' +
    '<span class="menu-cat-label">' +
    escapeHtml(product.category || 'Menu') +
    '</span>' +
    '<span class="locked-table-tag">' +
    escapeHtml(stockText) +
    '</span>' +
    '</div>' +
    '<h3 class="detail-title">' +
    escapeHtml(product.name) +
    '</h3>' +
    '<div class="detail-price tabular">' +
    formatRupiah(product.price) +
    '</div>' +
    '<div class="detail-desc-box">' +
    '<div class="detail-desc-label">Deskripsi Makanan</div>' +
    '<p class="detail-desc' +
    (product.description && String(product.description).trim() ? '' : ' text-muted') +
    '">' +
    escapeHtml(
      product.description && String(product.description).trim()
        ? String(product.description).trim()
        : 'Belum ada deskripsi makanan yang dicantumkan pada aplikasi kasir.'
    ) +
    '</p>' +
    '</div>';

  const footer = document.getElementById('detailModalFooter');
  if (inCart > 0) {
    footer.innerHTML =
      '<div class="detail-qty-row">' +
      '<span class="detail-qty-label">Jumlah di keranjang</span>' +
      buildStepperOrAddHtml(product, inCart) +
      '</div>';
  } else {
    footer.innerHTML =
      '<button type="button" class="btn-primary-full" data-cart-action="inc" data-product-id="' +
      escapeHtml(product.id) +
      '" ' +
      (outOfStock ? 'disabled' : '') +
      '>' +
      (outOfStock ? 'Stok Habis' : 'Tambah ke Keranjang — ' + formatRupiah(product.price)) +
      '</button>';
  }
}

function updateCartQty(productId, delta, notifyAdd = false) {
  if (!tableValidated || !lockedTableNumber) return;

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
    showToast(product.name + ' dihapus dari keranjang');
  } else {
    state.cart[productId] = { product, qty: nextQty };
    if (notifyAdd && delta > 0 && existing.qty === 0) {
      showToast(product.name + ' ditambahkan ke keranjang');
    }
  }

  renderMenuGrid();
  updateFloatingCartBar();

  if (state.activeDetailProductId && String(state.activeDetailProductId) === String(productId)) {
    renderProductDetailDialog(productId);
  }

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
  document.getElementById('cartBarTableInfo').textContent = formatTableLabel(lockedTableNumber);

  const isCartVisible = count > 0 && tableValidated;
  if (isCartVisible) {
    bar.classList.add('visible');
  } else {
    bar.classList.remove('visible');
  }
  if (document.body) {
    document.body.classList.toggle('has-cart', isCartVisible);
  }
}

// ============================================================================
// Checkout Dialog (<dialog>)
// ============================================================================
function openCartModal() {
  if (!tableValidated || !lockedTableNumber) return;
  const { count } = getCartTotals();
  if (count === 0) return;

  applyLockedTableLabels(lockedTableNumber);
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
      const safeId = escapeHtml(product.id);
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
        '<button type="button" class="qty-btn" data-cart-action="dec" data-product-id="' +
        safeId +
        '" aria-label="Kurangi">-</button>' +
        '<span class="qty-count tabular">' +
        qty +
        '</span>' +
        '<button type="button" class="qty-btn plus" data-cart-action="inc" data-product-id="' +
        safeId +
        '" aria-label="Tambah">+</button>' +
        '</div>' +
        '</div>'
      );
    })
    .join('');

  document.getElementById('modalSubtotal').textContent = formatRupiah(subtotal);
  document.getElementById('modalService').textContent = formatRupiah(serviceFee);
  document.getElementById('modalTotal').textContent = formatRupiah(grandTotal);
}

// ============================================================================
// Submit Order to Supabase -> Menggunakan Harga Server & Tabel `orders`
// ============================================================================
async function submitOrder() {
  const urlCheck = parseStrictTableFromUrl();
  if (
    !tableValidated ||
    !lockedTableNumber ||
    !urlCheck.valid ||
    urlCheck.tableNumber !== lockedTableNumber
  ) {
    closeCartModal();
    showInvalidQrScreen(
      'QR Code meja tidak valid. Silakan pindai kembali QR Code yang tersedia di meja Anda.'
    );
    return;
  }

  const stillRegistered = await verifyTableInSupabase(state.restoId, lockedTableNumber);
  if (!stillRegistered) {
    closeCartModal();
    showInvalidQrScreen(
      'QR Code meja tidak valid atau meja tidak aktif. Silakan pindai kembali QR Code di meja Anda.'
    );
    return;
  }

  const nameInput = document.getElementById('customerNameInput');
  const customerName = nameInput ? nameInput.value.trim() : '';
  if (!customerName) {
    updateFieldValidationState(nameInput, true);
    nameInput?.focus();
    return;
  }

  const notesInput = document.getElementById('orderNotesInput');
  const notes = notesInput ? notesInput.value.trim() : '';
  const selectedPaymentEl = document.querySelector('input[name="paymentMethod"]:checked');
  const paymentChoice =
    selectedPaymentEl && selectedPaymentEl.value === 'QRIS_DEMO' ? 'QRIS_DEMO' : 'CASHIER';

  const cartItems = Object.values(state.cart);
  if (cartItems.length === 0) return;

  const submitBtn = document.getElementById('btnSubmitOrder');
  submitBtn.disabled = true;
  submitBtn.textContent = 'Membuat pesanan...';

  try {
    let savedSummary = null;

    const rpcRes = await fetch(SUPABASE_URL + '/rest/v1/rpc/submit_qr_order', {
      method: 'POST',
      headers: apiHeaders(),
      body: JSON.stringify({
        p_resto_id: state.restoId,
        p_table_number: lockedTableNumber,
        p_customer_name: customerName,
        p_notes: notes,
        p_payment_method: paymentChoice,
        p_items: cartItems.map((c) => ({
          product_id: c.product.id,
          quantity: c.qty,
        })),
      }),
    });

    if (rpcRes.ok) {
      const rpcData = await rpcRes.json();
      savedSummary = {
        id: rpcData.id,
        invoiceNo: rpcData.invoice_no,
        tableNumber: lockedTableNumber,
        customerName,
        notes,
        subtotal: rpcData.subtotal,
        serviceFee: rpcData.service_fee,
        total: rpcData.total,
        paymentChoice,
        paymentMethod: rpcData.payment_method,
        paymentStatus: rpcData.payment_status || 'unpaid',
        status: rpcData.status || 'pesanan dibuat',
        createdAt: rpcData.created_at || new Date().toISOString(),
        itemsSummary: Array.isArray(rpcData.items_summary)
          ? rpcData.items_summary
          : cartItems.map((i) => i.product.name + ' x' + i.qty),
      };
    } else if (rpcRes.status === 404) {
      savedSummary = await submitOrderWithVerifiedServerPrices({
        cartItems,
        customerName,
        notes,
        paymentChoice,
      });
    } else {
      const errText = await rpcRes.text();
      throw new Error('Gagal membuat pesanan (' + rpcRes.status + '): ' + errText);
    }

    saveLastOrder(savedSummary);
    state.cart = {};
    if (notesInput) notesInput.value = '';
    updateFloatingCartBar();
    closeCartModal();
    fetchMenuProducts();
    showToast('Pesanan berhasil dibuat (' + savedSummary.invoiceNo + ')');
    openOrderFlowModal(savedSummary);
  } catch (err) {
    console.error('Submit order error:', err);
    showToast('Gagal membuat pesanan. Silakan periksa stok atau koneksi Anda.');
  } finally {
    submitBtn.disabled = false;
    submitBtn.textContent = 'Buat Pesanan';
  }
}

async function submitOrderWithVerifiedServerPrices({
  cartItems,
  customerName,
  notes,
  paymentChoice,
}) {
  const prodRes = await fetch(
    SUPABASE_URL +
      '/rest/v1/products?resto_id=eq.' +
      encodeURIComponent(state.restoId) +
      '&select=id,name,price,stock,is_available',
    { headers: apiHeaders() }
  );
  if (!prodRes.ok) {
    throw new Error('Gagal memverifikasi harga produk (' + prodRes.status + ')');
  }
  const serverProducts = await prodRes.json();
  const productMap = new Map(
    (Array.isArray(serverProducts) ? serverProducts : []).map((p) => [String(p.id), p])
  );

  let verifiedSubtotal = 0;
  const verifiedLines = [];

  for (const item of cartItems) {
    const dbProd = productMap.get(String(item.product.id));
    if (!dbProd || dbProd.is_available === false) {
      throw new Error('Produk ' + item.product.name + ' tidak tersedia.');
    }
    const dbStock = Number(dbProd.stock) || 0;
    if (dbStock < item.qty) {
      throw new Error('Stok ' + dbProd.name + ' tersisa ' + dbStock);
    }
    const unitPrice = Number(dbProd.price) || 0;
    const lineTotal = unitPrice * item.qty;
    verifiedSubtotal += lineTotal;
    verifiedLines.push({
      product_id: dbProd.id,
      product_name: dbProd.name,
      price: unitPrice,
      quantity: item.qty,
      subtotal: lineTotal,
      next_stock: Math.max(0, dbStock - item.qty),
    });
  }

  const verifiedServiceFee = Math.round(verifiedSubtotal * 0.05);
  const verifiedTotal = verifiedSubtotal + verifiedServiceFee;

  const now = new Date();
  const datePart =
    String(now.getFullYear()) +
    String(now.getMonth() + 1).padStart(2, '0') +
    String(now.getDate()).padStart(2, '0');
  const randPart = String(Math.floor(1000 + Math.random() * 9000));
  const invoiceNo = 'WEB-' + datePart + '-' + randPart;

  const hasExtendedCols = await detectExtendedOrderSchema();
  const isDemoQris = paymentChoice === 'QRIS_DEMO';

  const baseCustomerTag =
    formatTableLabel(lockedTableNumber) + ' (' + customerName + ')';
  let cashierLabel = notes ? baseCustomerTag + ' - Catatan: ' + notes : baseCustomerTag;
  if (isDemoQris) {
    cashierLabel += ' [QRIS DEMO]';
  }

  const paymentMethodValue = hasExtendedCols
    ? isDemoQris
      ? 'QRIS_DEMO'
      : 'CASHIER'
    : isDemoQris
      ? 'QRIS DEMO (Simulasi)'
      : 'Bayar di Kasir (Meja)';

  const orderPayload = {
    invoice_no: invoiceNo,
    resto_id: state.restoId,
    cashier_name: cashierLabel,
    table_number: lockedTableNumber,
    subtotal: verifiedSubtotal,
    service_fee: verifiedServiceFee,
    total: verifiedTotal,
    payment_method: paymentMethodValue,
    status: 'pesanan dibuat',
  };

  if (hasExtendedCols) {
    orderPayload.payment_status = 'unpaid';
    orderPayload.order_source = 'qr';
  }

  const orderRes = await fetch(SUPABASE_URL + '/rest/v1/orders', {
    method: 'POST',
    headers: apiHeaders({ Prefer: 'return=representation' }),
    body: JSON.stringify(orderPayload),
  });

  if (!orderRes.ok) {
    const errBody = await orderRes.text();
    throw new Error('Gagal menyimpan order (' + orderRes.status + '): ' + errBody);
  }

  const createdRows = await orderRes.json();
  const createdOrder = Array.isArray(createdRows) ? createdRows[0] : createdRows;
  const orderId = createdOrder ? createdOrder.id : '';

  const itemsPayload = verifiedLines.map((line) => ({
    order_id: orderId,
    product_id: line.product_id,
    product_name: line.product_name,
    price: line.price,
    quantity: line.quantity,
    subtotal: line.subtotal,
  }));

  const itemsRes = await fetch(SUPABASE_URL + '/rest/v1/order_items', {
    method: 'POST',
    headers: apiHeaders(),
    body: JSON.stringify(itemsPayload),
  });
  if (!itemsRes.ok) {
    throw new Error('Gagal menyimpan detail item (' + itemsRes.status + ')');
  }

  await Promise.all(
    verifiedLines.map((line) =>
      fetch(
        SUPABASE_URL + '/rest/v1/products?id=eq.' + encodeURIComponent(line.product_id),
        {
          method: 'PATCH',
          headers: apiHeaders(),
          body: JSON.stringify({
            stock: line.next_stock,
            is_available: line.next_stock > 0,
          }),
        }
      )
    )
  );

  return {
    id: orderId,
    invoiceNo,
    tableNumber: lockedTableNumber,
    customerName,
    notes,
    subtotal: verifiedSubtotal,
    serviceFee: verifiedServiceFee,
    total: verifiedTotal,
    paymentChoice,
    paymentMethod: paymentMethodValue,
    paymentStatus: 'unpaid',
    status: 'pesanan dibuat',
    createdAt: (createdOrder && createdOrder.created_at) || now.toISOString(),
    itemsSummary: verifiedLines.map((i) => i.product_name + ' x' + i.quantity),
  };
}

// ============================================================================
// Cek Pesanan, Persistensi Status Meja & Dialog Pembayaran
// ============================================================================
function getLastOrderStorageKey() {
  return 'restokasir_last_order_' + (state.restoId || 'default') + '_' + String(lockedTableNumber || 0);
}

function saveLastOrder(summary) {
  state.lastOrder = summary;
  try {
    if (summary && lockedTableNumber) {
      localStorage.setItem(getLastOrderStorageKey(), JSON.stringify(summary));
    }
  } catch (e) {
    // Abaikan bila storage dibatasi pada iframe
  }
  updateActiveOrderIndicators();
}

function restoreLastOrderFromStorage() {
  try {
    if (!lockedTableNumber) return;
    const raw = localStorage.getItem(getLastOrderStorageKey());
    if (!raw) return;
    const parsed = JSON.parse(raw);
    if (parsed && parsed.invoiceNo && Number(parsed.tableNumber) === Number(lockedTableNumber)) {
      state.lastOrder = parsed;
      updateActiveOrderIndicators();
    }
  } catch (e) {
    // Abaikan bila storage dibatasi
  }
}

async function fetchLatestTableOrderFromServer() {
  if (!lockedTableNumber) return null;
  try {
    const hasExtendedCols = await detectExtendedOrderSchema();
    const selectCols = hasExtendedCols
      ? 'id,invoice_no,table_number,cashier_name,subtotal,service_fee,total,payment_method,payment_status,status,created_at,order_items(product_name,quantity)'
      : 'id,invoice_no,table_number,cashier_name,subtotal,service_fee,total,payment_method,status,created_at,order_items(product_name,quantity)';

    let url =
      SUPABASE_URL +
      '/rest/v1/orders?table_number=eq.' +
      encodeURIComponent(lockedTableNumber) +
      '&order=created_at.desc&limit=1&select=' +
      selectCols;

    if (state.restoId) {
      url += '&resto_id=eq.' + encodeURIComponent(state.restoId);
    }

    const res = await fetch(url, { headers: apiHeaders() });
    if (!res.ok) return state.lastOrder;
    const rows = await res.json();
    if (!Array.isArray(rows) || rows.length === 0) return state.lastOrder;

    const latest = rows[0];
    // Hanya tampilkan pesanan dari 12 jam terakhir agar pesanan hari sebelumnya tidak membingungkan
    const createdMs = Date.parse(latest.created_at || '');
    if (Number.isFinite(createdMs) && Date.now() - createdMs > 12 * 60 * 60 * 1000) {
      return state.lastOrder;
    }

    const rawCashier = String(latest.cashier_name || '');
    let customerName = '-';
    const nameMatch = rawCashier.match(/\(([^)]+)\)/);
    if (nameMatch && nameMatch[1]) {
      customerName = nameMatch[1];
    }

    let notes = '';
    const notesMatch = rawCashier.match(/Catatan:\s*(.+?)(?:\s*\[QRIS DEMO\]|$)/);
    if (notesMatch && notesMatch[1]) {
      notes = notesMatch[1].trim();
    }

    const pmUpper = String(latest.payment_method || '').toUpperCase();
    const paymentChoice = pmUpper.includes('QRIS') ? 'QRIS_DEMO' : 'CASHIER';
    const itemsArr = Array.isArray(latest.order_items)
      ? latest.order_items.map((it) => it.product_name + ' x' + it.quantity)
      : state.lastOrder && state.lastOrder.id === latest.id
        ? state.lastOrder.itemsSummary
        : [];

    const syncedOrder = {
      id: latest.id,
      invoiceNo: latest.invoice_no || '-',
      tableNumber: lockedTableNumber,
      customerName,
      notes,
      subtotal: Number(latest.subtotal) || 0,
      serviceFee: Number(latest.service_fee) || 0,
      total: Number(latest.total) || 0,
      paymentChoice,
      paymentMethod: latest.payment_method || 'CASHIER',
      paymentStatus:
        latest.payment_status ||
        (String(latest.status || '').toLowerCase().includes('selesai') ? 'paid' : 'unpaid'),
      status: latest.status || 'pesanan dibuat',
      createdAt: latest.created_at || new Date().toISOString(),
      itemsSummary: itemsArr,
    };

    saveLastOrder(syncedOrder);
    return syncedOrder;
  } catch (e) {
    return state.lastOrder;
  }
}

function updateActiveOrderIndicators() {
  const dot = document.getElementById('checkOrderDot');
  const bar = document.getElementById('activeOrderBar');
  const titleEl = document.getElementById('activeOrderTitle');
  const subEl = document.getElementById('activeOrderSub');
  const ctaEl = document.getElementById('activeOrderCta');

  if (!state.lastOrder || !tableValidated) {
    if (dot) dot.hidden = true;
    if (bar) bar.hidden = true;
    return;
  }

  const order = state.lastOrder;
  const paid = isOrderPaid(order);
  const demoDone = isDemoQrisDone(order);

  if (dot) {
    dot.hidden = false;
    dot.classList.toggle('paid', paid || demoDone);
  }

  if (bar) {
    bar.hidden = false;
    bar.classList.toggle('is-paid', paid);
  }

  if (titleEl) {
    if (paid) {
      titleEl.textContent = 'Pesanan Dikonfirmasi Kasir (PAID)';
    } else if (demoDone) {
      titleEl.textContent = 'Terkirim ke Kasir • Simulasi QRIS Selesai';
    } else {
      titleEl.textContent = 'Pesanan Terkirim ke Kasir • Menunggu Bayar';
    }
  }

  if (subEl) {
    subEl.textContent =
      order.invoiceNo + ' • ' + formatRupiah(order.total) + ' • Ketuk untuk cek detail';
  }

  if (ctaEl) {
    ctaEl.textContent = paid ? 'Lunas ✓' : 'Cek Status';
  }
}

async function handleCheckOrderClick() {
  if (!tableValidated || !lockedTableNumber) return;
  const dlg = document.getElementById('orderFlowModal');
  if (state.lastOrder) {
    openOrderFlowModal(state.lastOrder);
    await manualRefreshOrderStatus(true);
    return;
  }

  // Coba ambil pesanan terbaru meja ini dari Supabase terlebih dahulu
  const fetched = await fetchLatestTableOrderFromServer();
  if (fetched) {
    openOrderFlowModal(fetched);
    return;
  }

  // Jika belum ada pesanan sama sekali untuk meja ini, tampilkan dialog kosong yang informatif
  renderEmptyCheckOrderModal();
  if (dlg && !dlg.open) dlg.showModal();
}

function renderEmptyCheckOrderModal() {
  const emptyView = document.getElementById('emptyOrderCheckView');
  const activeWrap = document.getElementById('activeOrderFlowWrap');
  const refreshBtn = document.getElementById('btnRefreshOrderStatus');
  const emptyDesc = document.getElementById('emptyOrderCheckDesc');

  if (emptyView) emptyView.hidden = false;
  if (activeWrap) activeWrap.hidden = true;
  if (refreshBtn) refreshBtn.hidden = true;
  if (emptyDesc && lockedTableNumber) {
    emptyDesc.innerHTML =
      'Belum ada pesanan aktif dari <strong>' +
      escapeHtml(formatTableLabel(lockedTableNumber)) +
      '</strong> yang dikirim ke kasir. Pilih menu lalu tekan <strong>Buat Pesanan</strong> untuk mengirim pesanan ke kasir.';
  }
}

async function manualRefreshOrderStatus(silent = false) {
  const btn = document.getElementById('btnRefreshOrderStatus');
  if (btn && !silent) {
    btn.disabled = true;
    btn.textContent = 'Memeriksa...';
  }
  try {
    const updated = await fetchLatestTableOrderFromServer();
    if (updated) {
      renderOrderFlowModal(updated);
      if (!silent) {
        showToast(
          isOrderPaid(updated)
            ? 'Status terbaru: Pembayaran telah dikonfirmasi kasir (PAID)'
            : 'Status terbaru: Pesanan sudah terkirim ke kasir'
        );
      }
    }
  } finally {
    if (btn && !silent) {
      btn.disabled = false;
      btn.textContent = 'Perbarui Status';
    }
  }
}

function openOrderFlowModal(order) {
  renderOrderFlowModal(order);
  const dlg = document.getElementById('orderFlowModal');
  if (dlg && !dlg.open) dlg.showModal();
  startOrderListeners(order);
}

function closeOrderFlowModal() {
  stopOrderListeners();
  const dlg = document.getElementById('orderFlowModal');
  if (dlg && dlg.open) dlg.close();
}

function isOrderPaid(order) {
  const ps = (order.paymentStatus || '').toLowerCase();
  const st = (order.status || '').toLowerCase();
  return ps === 'paid' || st === 'pesanan selesai' || st === 'selesai';
}

function isDemoQrisDone(order) {
  const ps = (order.paymentStatus || '').toLowerCase();
  const pm = (order.paymentMethod || '').toLowerCase();
  return ps === 'demo_paid' || pm.includes('demo berhasil');
}

function renderOrderFlowModal(order) {
  const emptyView = document.getElementById('emptyOrderCheckView');
  const activeWrap = document.getElementById('activeOrderFlowWrap');
  const refreshBtn = document.getElementById('btnRefreshOrderStatus');
  if (emptyView) emptyView.hidden = true;
  if (activeWrap) activeWrap.hidden = false;
  if (refreshBtn) refreshBtn.hidden = false;

  const paid = isOrderPaid(order);
  const demoDone = isDemoQrisDone(order);
  const isDemoChoice =
    order.paymentChoice === 'QRIS_DEMO' ||
    (order.paymentMethod || '').toUpperCase().includes('QRIS_DEMO') ||
    (order.paymentMethod || '').toUpperCase().includes('QRIS DEMO');

  const stepSentDesc = document.getElementById('stepSentDesc');
  const stepConfirmBox = document.getElementById('stepCashierConfirm');
  const stepConfirmBadge = document.getElementById('stepConfirmBadge');
  const stepConfirmTitle = document.getElementById('stepConfirmTitle');
  const stepConfirmDesc = document.getElementById('stepConfirmDesc');

  if (stepSentDesc) {
    stepSentDesc.textContent = 'Masuk pukul ' + formatOrderTime(order.createdAt);
  }
  if (stepConfirmBox) {
    stepConfirmBox.classList.toggle('done', paid || demoDone);
    stepConfirmBox.classList.toggle('pending', !paid && !demoDone);
  }
  if (stepConfirmBadge) {
    stepConfirmBadge.innerHTML = paid || demoDone ? '&#10003;' : '2';
  }
  if (stepConfirmTitle) {
    stepConfirmTitle.textContent = paid
      ? '2. Dikonfirmasi Kasir'
      : demoDone
        ? '2. Simulasi Selesai'
        : '2. Konfirmasi Kasir';
  }
  if (stepConfirmDesc) {
    stepConfirmDesc.textContent = paid
      ? 'Pembayaran lunas (PAID)'
      : demoDone
        ? 'Simulasi QRIS berhasil'
        : 'Menunggu konfirmasi kasir';
  }

  const banner = document.getElementById('orderStatusBanner');
  const titleEl = document.getElementById('orderStatusTitle');
  const subEl = document.getElementById('orderStatusSub');
  const iconEl = document.getElementById('orderStatusIcon');
  const qrisView = document.getElementById('qrisDemoView');
  const qrStage = document.getElementById('qrisDemoQrStage');
  const qrLoadStage = document.getElementById('qrisDemoLoadingStage');
  const cashierBox = document.getElementById('cashierInstructionBox');

  banner.classList.remove('completed', 'demo-done');

  let pillHtml = '<span class="status-pill unpaid">UNPAID</span>';
  const checkSvg =
    '<svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.4" stroke-linecap="round" stroke-linejoin="round"><polyline points="20 6 9 17 4 12" /></svg>';
  const clockSvg =
    '<svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"><circle cx="12" cy="12" r="10" /><polyline points="12 6 12 12 16 14" /></svg>';

  if (paid) {
    banner.classList.add('completed');
    iconEl.innerHTML = checkSvg;
    titleEl.textContent = 'Pembayaran Dikonfirmasi (PAID)';
    subEl.textContent = 'Kasir telah mengonfirmasi pembayaran Anda.';
    pillHtml = '<span class="status-pill paid">PAID</span>';
  } else if (isDemoChoice && demoDone) {
    banner.classList.add('demo-done');
    iconEl.innerHTML = checkSvg;
    titleEl.textContent = 'Pembayaran Demo Berhasil';
    subEl.textContent = 'Status simulasi: DEMO BERHASIL (bukan transaksi merchant aktif)';
    pillHtml = '<span class="status-pill demo">DEMO BERHASIL</span>';
  } else if (isDemoChoice) {
    iconEl.innerHTML = clockSvg;
    titleEl.textContent = 'Pembayaran QRIS (MODE DEMO)';
    subEl.textContent = 'Scan QR dummy (teks BAYAR) lalu tekan tombol simulasi.';
    pillHtml = '<span class="status-pill unpaid">UNPAID (DEMO)</span>';
  } else {
    iconEl.innerHTML = clockSvg;
    titleEl.textContent = 'Menunggu Pembayaran di Kasir';
    subEl.textContent = 'Status pembayaran: UNPAID';
    pillHtml = '<span class="status-pill unpaid">UNPAID</span>';
  }

  document.getElementById('flowTableNumber').textContent =
    formatTableLabel(order.tableNumber);
  document.getElementById('flowInvoiceLine').textContent =
    'Nomor Pesanan: ' + order.invoiceNo;

  if (isDemoChoice && !paid && !demoDone) {
    qrisView.hidden = false;
    cashierBox.hidden = true;
    qrStage.hidden = false;
    qrLoadStage.hidden = true;
    document.getElementById('qrisDemoAmount').textContent = formatRupiah(order.total);

    const canvas = document.getElementById('webQrisCanvas');
    if (canvas) {
      canvas.innerHTML = '';
      if (typeof QRCode !== 'undefined') {
        new QRCode(canvas, {
          text: 'BAYAR',
          width: 164,
          height: 164,
          colorDark: '#171614',
          colorLight: '#ffffff',
          correctLevel: QRCode.CorrectLevel.M,
        });
      }
    }
  } else if (!isDemoChoice && !paid) {
    qrisView.hidden = true;
    cashierBox.hidden = false;
  } else {
    qrisView.hidden = true;
    cashierBox.hidden = true;
  }

  const itemsText = Array.isArray(order.itemsSummary)
    ? order.itemsSummary.join(', ')
    : '-';

  const notesLine = order.notes
    ? '<div class="receipt-line receipt-line--stack"><span>Catatan</span><strong>' +
      escapeHtml(order.notes) +
      '</strong></div>'
    : '';

  const methodDisplay = isDemoChoice ? 'QRIS (MODE DEMO)' : 'Bayar Melalui Kasir';

  document.getElementById('flowOrderDetails').innerHTML =
    '<div class="receipt-line"><span>Status Pembayaran</span><strong>' +
    pillHtml +
    '</strong></div>' +
    '<div class="receipt-line"><span>Nomor Pesanan</span><strong>' +
    escapeHtml(order.invoiceNo) +
    '</strong></div>' +
    '<div class="receipt-line"><span>Nomor Meja</span><strong>' +
    escapeHtml(formatTableLabel(order.tableNumber)) +
    '</strong></div>' +
    '<div class="receipt-line"><span>Waktu Pesan</span><strong>' +
    escapeHtml(formatOrderTime(order.createdAt)) +
    '</strong></div>' +
    '<div class="receipt-line"><span>Pemesan</span><strong>' +
    escapeHtml(order.customerName) +
    '</strong></div>' +
    '<div class="receipt-line"><span>Metode Bayar</span><strong>' +
    escapeHtml(methodDisplay) +
    '</strong></div>' +
    '<div class="receipt-line receipt-line--stack"><span>Detail Pesanan</span><strong>' +
    escapeHtml(itemsText) +
    '</strong></div>' +
    notesLine +
    '<div class="receipt-line receipt-line--total">' +
    '<span>Total Pembayaran</span><strong class="tabular">' +
    formatRupiah(order.total) +
    '</strong></div>';
}

async function confirmDemoQrisSimulation() {
  if (!state.lastOrder || !state.lastOrder.id) return;
  if (state.lastOrder.paymentChoice !== 'QRIS_DEMO') return;

  const qrStage = document.getElementById('qrisDemoQrStage');
  const qrLoadStage = document.getElementById('qrisDemoLoadingStage');
  const btn = document.getElementById('btnConfirmDemoQris');

  if (btn) btn.disabled = true;
  if (qrStage) qrStage.hidden = true;
  if (qrLoadStage) qrLoadStage.hidden = false;

  try {
    await new Promise((resolve) => setTimeout(resolve, 900));

    let confirmed = false;
    const rpcRes = await fetch(
      SUPABASE_URL + '/rest/v1/rpc/confirm_demo_qris_order',
      {
        method: 'POST',
        headers: apiHeaders(),
        body: JSON.stringify({ p_order_id: state.lastOrder.id }),
      }
    );

    if (rpcRes.ok) {
      confirmed = true;
    } else if (rpcRes.status === 404) {
      const hasExtendedCols = await detectExtendedOrderSchema();
      const patchBody = hasExtendedCols
        ? { payment_status: 'demo_paid' }
        : { payment_method: 'QRIS DEMO (DEMO BERHASIL)' };

      const patchRes = await fetch(
        SUPABASE_URL +
          '/rest/v1/orders?id=eq.' +
          encodeURIComponent(state.lastOrder.id),
        {
          method: 'PATCH',
          headers: apiHeaders(),
          body: JSON.stringify(patchBody),
        }
      );
      if (!patchRes.ok) {
        throw new Error('HTTP ' + patchRes.status);
      }
      confirmed = true;
    } else {
      throw new Error('HTTP ' + rpcRes.status);
    }

    if (confirmed) {
      state.lastOrder.paymentStatus = 'demo_paid';
      state.lastOrder.paymentMethod = 'QRIS DEMO (DEMO BERHASIL)';
      saveLastOrder(state.lastOrder);
      renderOrderFlowModal(state.lastOrder);
      showToast('Simulasi pembayaran QRIS DEMO berhasil');
    }
  } catch (err) {
    console.error('Demo QRIS confirm error:', err);
    if (qrStage) qrStage.hidden = false;
    if (qrLoadStage) qrLoadStage.hidden = true;
    showToast('Gagal menyelesaikan simulasi QRIS DEMO');
  } finally {
    if (btn) btn.disabled = false;
  }
}

function applyRealtimeOrderRowUpdate(row) {
  if (!row || !state.lastOrder || row.id !== state.lastOrder.id) return;

  const nextStatus = row.status || state.lastOrder.status;
  const nextPayStatus =
    row.payment_status ||
    (nextStatus.toLowerCase() === 'pesanan selesai' || nextStatus.toLowerCase() === 'selesai'
      ? 'paid'
      : state.lastOrder.paymentStatus);

  const changed =
    nextStatus !== state.lastOrder.status ||
    nextPayStatus !== state.lastOrder.paymentStatus;

  if (changed) {
    const wasPaid = isOrderPaid(state.lastOrder);
    state.lastOrder.status = nextStatus;
    state.lastOrder.paymentStatus = nextPayStatus;
    saveLastOrder(state.lastOrder);
    renderOrderFlowModal(state.lastOrder);

    if (!wasPaid && isOrderPaid(state.lastOrder)) {
      showToast('Pembayaran telah dikonfirmasi oleh kasir (PAID)');
    }
  }
}

function startOrderListeners(order) {
  stopOrderListeners();
  if (!order || !order.id) return;

  const sb = getSupabaseClient();
  if (sb) {
    try {
      state.realtimeChannel = sb
        .channel('qr-order-' + order.id)
        .on(
          'postgres_changes',
          {
            event: 'UPDATE',
            schema: 'public',
            table: 'orders',
            filter: 'id=eq.' + order.id,
          },
          (payload) => {
            if (payload && payload.new) {
              applyRealtimeOrderRowUpdate(payload.new);
            }
          }
        )
        .subscribe();
    } catch (e) {
      console.warn('Supabase Realtime fallback aktif:', e);
    }
  }

  state.statusPollTimer = setInterval(async () => {
    try {
      const hasExtendedCols = await detectExtendedOrderSchema();
      const selectCols = hasExtendedCols ? 'id,status,payment_status' : 'id,status';
      const res = await fetch(
        SUPABASE_URL +
          '/rest/v1/orders?id=eq.' +
          encodeURIComponent(order.id) +
          '&select=' +
          selectCols,
        { headers: apiHeaders() }
      );
      if (!res.ok) return;
      const rows = await res.json();
      if (Array.isArray(rows) && rows.length > 0) {
        applyRealtimeOrderRowUpdate(rows[0]);
      }
    } catch (e) {
      // Silent retry
    }
  }, 4000);
}

function stopOrderListeners() {
  if (state.statusPollTimer) {
    clearInterval(state.statusPollTimer);
    state.statusPollTimer = null;
  }
  if (state.realtimeChannel) {
    try {
      state.realtimeChannel.unsubscribe();
    } catch (e) {
      // Ignore cleanup error
    }
    state.realtimeChannel = null;
  }
}

function showToast(msg) {
  const el = document.getElementById('toastEl');
  if (!el) return;
  el.textContent = msg;
  el.classList.add('show');
  setTimeout(() => el.classList.remove('show'), 3200);
}
