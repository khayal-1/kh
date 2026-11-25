import { supabase, supabaseConfigured, getCurrentProfile } from './src/supabase.js';
import { esc, safeImageUrl } from './src/security.js';
import { applyQueryResults } from './src/purchasing-results.js';

/* =========================================================
   El Khayal Motors — app.js (Full SPA)
   Sections:
   1) State & Seed Data
   2) Auth & RBAC
   3) Storefront & Slider
   4) POS & Invoices
   5) Admin & Staff Monitoring
   6) UI & Sidebar (Router, Events, Init)
   ========================================================= */

/* =========================================================
   SECTION 1 — STATE & SEED DATA
   ========================================================= */

const DB = {
  USERS: 'ekm_users',
  BIKES: 'ekm_bikes',
  ORDERS: 'ekm_orders',
  INVOICES: 'ekm_invoices',
  FAVS: 'ekm_favs',
  CUSTOM_REQS: 'ekm_custom_requests',
  MESSAGES: 'ekm_messages',
  SESSION: 'ekm_session',
  SEEDED: 'ekm_seeded_v1'
};

const authRedirectUrl = new URL(import.meta.env.BASE_URL, window.location.origin).href;

const state = {
  user: null,
  pendingAuthAction: null,
  route: 'home',
  search: '',
  filterCat: 'all',
  filterPrice: 'all',
  sidebarOpen: false,
  bikes: [],
  sales: [],
  saleDeliveries: [],
  customerInvoices: [],
  registeredCustomers: [],
  saleReturns: [],
  saleReturnItems: [],
  customerCredits: [],
  suppliers: [],
  purchaseOrders: [],
  supplierBills: [],
  supplierBillItems: [],
  supplierPayments: [],
  supplierReturns: [],
  supplierReturnItems: [],
  purchasingLoadStatus: 'idle',
  purchasingLoadErrors: [],
  financeAccounts: [],
  financeAllAccounts: [],
  cashAccounts: [],
  salesCashAccounts: [],
  cashBalances: [],
  trialBalance: [],
  expenses: [],
  fiscalPeriods: [],
  costCenters: [],
  openingBatches: [],
  supplierAdvances: [],
  supplierAdvanceAllocations: [],
  fixedAssets: [],
  fixedAssetDepreciations: [],
  bankReconciliations: [],
  bankReconciliationLines: [],
  financeJournalLines: [],
  cheques: [],
  recurringJournalTemplates: [],
  recurringJournalRuns: [],
  taxRates: [],
  cashSessions: [],
  cashHandovers: [],
  pettyCashTransactions: [],
  financeSettings: null,
  journalReversals: [],
  financeBudgets: [],
  financeBudgetVsActual: [],
  accrualSchedules: [],
  accrualRuns: [],
  agingReport: [],
  cashBook: [],
  financeJournalEntries: [],
  unallocatedSalePayments: [],
  unallocatedCustomerRefunds: [],
  financialStatements: null,
  employees: [],
  attendanceRecords: [],
  employeeLeaveRequests: [],
  employeeCustody: [],
  employeeAdvances: [],
  salesCommissions: [],
  payrollRuns: [],
  payrollItems: [],
  payrollPayments: [],
  inventoryCosts: [],
  motorcycleUnits: [],
  inventoryReconciliation: [],
  storeUnits: [],
  stocktakeBatches: [],
  stocktakeLines: [],
  warranties: [],
  serviceOrders: [],
  reorderAlerts: [],
  crmClients: [],
  customerInteractions: [],
  customerComplaints: [],
  internalNotifications: [],
  customerStatementRows: [],
  salesQuotations: [],
  salesQuotationItems: [],
  saleInstallments: [],
  contactMessages: [],
  requestReplies: [],
  contactReplies: [],
  staffProvisionResult: null,
  language: localStorage.getItem('ekm_language') === 'en' ? 'en' : 'ar'
};

const STAFF_PERMISSION_OPTIONS = [
  { key: 'catalog_view', label: 'عرض الكتالوج والمخزون', description: 'رؤية بيانات الدراجات غير المنشورة أيضًا.' },
  { key: 'catalog_manage', label: 'المعرض / الكتالوج والصور', description: 'إضافة وتعديل الدراجات ورفع الصور؛ يشمل العرض.' },
  { key: 'requests_view', label: 'عرض طلبات العملاء', description: 'رؤية الطلبات وتفاصيلها التي أرسلها العميل.' },
  { key: 'requests_manage', label: 'تحديث حالة الطلبات', description: 'عرض الطلبات وتغيير حالتها؛ لا يسمح بالحذف.' },
  { key: 'customer_data_view', label: 'رؤية أسماء وهواتف العملاء', description: 'لعملاء الطلبات التي يحق للموظف عرضها.' },
  { key: 'sales_manage', label: 'إدارة المبيعات ونقاط البيع', description: 'تنفيذ المبيعات ومتابعة الفواتير والعمليات المسموح بها.' },
  { key: 'expenses_manage', label: 'إدارة المصروفات', description: 'تسجيل المصروفات وسدادها ومراجعة سجلها.' },
  { key: 'accounting_view', label: 'عرض الحسابات والتقارير المالية', description: 'عرض دليل الحسابات والقيود والأرصدة المالية.' },
  { key: 'finance_manage', label: 'إدارة النظام المحاسبي', description: 'الفترات والأرصدة الافتتاحية والأصول والسلف والتسويات والشيكات والقيود المتكررة.' },
];
const PERMISSION_LABELS = Object.fromEntries(STAFF_PERMISSION_OPTIONS.map((item) => [item.key, item.label]));

/* ---------- Helpers ---------- */
const $ = (sel, root = document) => root.querySelector(sel);
const $$ = (sel, root = document) => Array.from(root.querySelectorAll(sel));
const uid = () => Date.now().toString(36) + Math.random().toString(36).slice(2, 8);
const money = (n) => Number(n || 0).toLocaleString('en-US') + ' ج.م';
const nowISO = () => new Date().toISOString();
const safeName = (s) => String(s || '').trim();

async function optimizeCatalogImage(file) {
  const bitmap = await createImageBitmap(file);
  const maxSide = 1600;
  const scale = Math.min(1, maxSide / Math.max(bitmap.width, bitmap.height));
  const width = Math.max(1, Math.round(bitmap.width * scale));
  const height = Math.max(1, Math.round(bitmap.height * scale));
  const canvas = document.createElement('canvas');
  canvas.width = width;
  canvas.height = height;
  const context = canvas.getContext('2d', { alpha: false });
  if (!context) throw new Error('تعذر تجهيز الصورة للضغط');
  context.fillStyle = '#ffffff';
  context.fillRect(0, 0, width, height);
  context.drawImage(bitmap, 0, 0, width, height);
  bitmap.close?.();
  const blob = await new Promise((resolve, reject) => {
    canvas.toBlob((value) => value ? resolve(value) : reject(new Error('تعذر ضغط الصورة')), 'image/jpeg', 0.82);
  });
  const baseName = String(file.name || 'motorcycle-photo').replace(/\.[^.]+$/, '') || 'motorcycle-photo';
  return new File([blob], `${baseName}.jpg`, { type: 'image/jpeg', lastModified: Date.now() });
}

function whatsappNumber(value) {
  let digits = String(value || '').replace(/\D/g, '');
  if (digits.startsWith('00')) digits = digits.slice(2);
  if (digits.startsWith('0')) digits = '20' + digits.slice(1);
  return digits;
}
function contactActionLinks(person, message = '') {
  const phone = safeName(person.phone);
  const email = safeName(person.email);
  const wa = whatsappNumber(phone);
  const body = encodeURIComponent(message);
  const links = [];
  if (phone) {
    links.push(`<a class="btn btn-outline btn-sm" href="tel:${esc(phone)}"><i class="fa-solid fa-phone"></i> اتصال</a>`);
    links.push(`<a class="btn btn-outline btn-sm" href="sms:${esc(phone)}?body=${body}"><i class="fa-solid fa-comment-sms"></i> SMS</a>`);
  }
  if (wa) links.push(`<a class="btn btn-outline btn-sm" href="https://wa.me/${esc(wa)}?text=${body}" target="_blank" rel="noopener"><i class="fa-brands fa-whatsapp"></i> واتساب</a>`);
  if (email) links.push(`<a class="btn btn-outline btn-sm" href="mailto:${esc(email)}?subject=${encodeURIComponent('El Khayal Motors')}&body=${body}"><i class="fa-solid fa-envelope"></i> بريد</a>`);
  return links.join(' ');
}

const transientStore = new Map([
  [DB.USERS, []], [DB.BIKES, []], [DB.ORDERS, []], [DB.INVOICES, []],
  [DB.FAVS, {}], [DB.CUSTOM_REQS, []], [DB.MESSAGES, []]
]);
function get(key, fallback = []) { return transientStore.has(key) ? transientStore.get(key) : fallback; }
function set(key, val) { transientStore.set(key, val); }

/* ---------- Toast ---------- */
function toast(msg, type = 'info') {
  const el = $('#toast');
  if (!el) return;
  const icons = {
    success: 'fa-circle-check',
    error: 'fa-circle-exclamation',
    info: 'fa-circle-info'
  };
  el.className = `toast ${type}`;
  el.innerHTML = `<i class="fa-solid ${icons[type] || icons.info}"></i> <span>${esc(msg)}</span>`;
  void el.offsetWidth;
  el.classList.add('show');
  clearTimeout(el._t);
  el._t = setTimeout(() => el.classList.remove('show'), 2800);
}

/* =========================================================
   SECTION 2 — AUTH & RBAC
   ========================================================= */

function currentUser() { return state.user; }
function hasPermission(permission) {
  const user = currentUser();
  return !!user && (user.role === 'admin' || user.permissions?.includes(permission));
}
function hasAnyPermission(...permissions) { return permissions.some(hasPermission); }
function hasRequestAccess() { return hasAnyPermission('requests_view', 'requests_manage'); }
function pageNoPermission() {
  return '<div class="panel"><p>ليس لديك صلاحية لعرض هذا القسم. تواصل مع المدير إذا كنت تحتاجها.</p></div>';
}

async function login(email, password) {
  if (!supabaseConfigured) throw new Error('Supabase configuration is missing.');
  const { data, error } = await supabase.auth.signInWithPassword({ email, password });
  if (error) throw error;
  const profile = await getCurrentProfile(data.user.id);
  if (!profile) throw new Error('Supabase profile is missing for this account.');
  state.user = { ...profile, id: data.user.id, email: data.user.email };
  return state.user;
}

async function logout() {
  if (supabase) await supabase.auth.signOut();
  state.user = null;
  state.route = 'home';
  closeSidebar();
  render();
  toast('تم تسجيل الخروج', 'info');
}

async function signup({ name, email, phone, password }) {
  if (!supabaseConfigured) throw new Error('Supabase configuration is missing.');
  const { data, error } = await supabase.auth.signUp({
    email: String(email || '').trim(),
    password: String(password || ''),
    options: { data: { full_name: safeName(name), phone: safeName(phone) }, emailRedirectTo: authRedirectUrl }
  });
  if (error) throw error;
  if (data.session && data.user) {
    const profile = await getCurrentProfile(data.user.id);
    if (!profile) throw new Error('Supabase profile is missing for this account.');
    state.user = { ...profile, id: data.user.id, email: data.user.email };
  }
  return { ok: true, requiresEmailConfirmation: !data.session, user: state.user };
}

function hasRole(...roles) {
  const u = currentUser();
  return !!u && roles.includes(u.role);
}

/* ---------- Sidebar Items (Role-based) ---------- */
function sidebarItems() {
  const u = currentUser();
  const pendingTotal = get(DB.CUSTOM_REQS).filter((r) => ['pending', 'reviewing'].includes(r.status)).length;

  if (!u) {
    return [
      { section: 'التسوق' },
      { route: 'home', label: 'الرئيسية', icon: 'fa-house' },
      { route: 'request', label: 'اطلب موتسيكلك', icon: 'fa-motorcycle' },
      { route: 'contact', label: 'تواصل معنا', icon: 'fa-headset' },
      { section: 'الحساب' },
      { route: 'login', label: 'تسجيل الدخول', icon: 'fa-right-to-bracket' },
      { route: 'signup', label: 'حساب جديد', icon: 'fa-user-plus' }
    ];
  }

  if (u.role === 'customer') {
    return [
      { section: 'التسوق' },
      { route: 'home', label: 'الرئيسية', icon: 'fa-house' },
      { route: 'request', label: 'اطلب موتسيكلك', icon: 'fa-motorcycle' },
      { route: 'contact', label: 'تواصل معنا', icon: 'fa-headset' },
      { section: 'حسابي' },
      { route: 'account', label: 'ملفي الشخصي', icon: 'fa-user' },
      { route: 'favorites', label: 'المفضلة', icon: 'fa-heart' },
      { route: 'orders', label: 'طلباتي', icon: 'fa-clipboard-list' },
      { route: 'invoices', label: 'فواتيري', icon: 'fa-file-invoice' }
    ];
  }

  /* Staff / Manager / Admin — menu matches operations board layout */
  const isStaff = u.role === 'staff';
  const isAdminLike = u.role === 'admin' || u.systemRole === 'owner' || u.systemRole === 'manager';
  const items = [];

  items.push({ section: 'الحساب وإدارته' });
  items.push({ route: 'account', label: 'الحساب وإدارته', icon: 'fa-id-card' });
  if (isAdminLike) items.push({ route: 'dashboard', label: 'لوحة الإحصائيات', icon: 'fa-chart-line' });

  if (isAdminLike || hasPermission('sales_manage')) {
    items.push({ section: 'نظام البيع داخل المعرض' });
    items.push({ route: 'pos', label: 'نظام البيع داخل المعرض', icon: 'fa-cash-register' });
    items.push({ route: 'vin-scanner', label: 'الماسح الضوئي (شاسيه/باركود)', icon: 'fa-barcode' });
    if (isAdminLike) items.push({ route: 'suppliers', label: 'الموردون والتوريد', icon: 'fa-truck-ramp-box' });
  }

  if (isAdminLike || hasAnyPermission('catalog_view', 'catalog_manage', 'sales_manage')) {
    items.push({ section: 'الأسعار والكتالوج' });
    if (isAdminLike || hasAnyPermission('catalog_view', 'catalog_manage')) {
      items.push({ route: 'inventory', label: 'الأسعار', icon: 'fa-tags' });
    }
    if (isAdminLike || hasPermission('sales_manage')) {
      items.push({ route: 'sales-tools', label: 'عروض التقسيط والأسعار', icon: 'fa-file-invoice-dollar' });
    }
    if (isAdminLike || hasPermission('catalog_manage')) {
      items.push({ route: 'manage-bikes', label: 'المعرض / الكتالوج', icon: 'fa-motorcycle' });
    }
  }

  if (isAdminLike || hasPermission('expenses_manage') || hasPermission('accounting_view') || hasPermission('finance_manage')) {
    items.push({ section: 'المالية والمحاسبة' });
    if (isAdminLike || hasPermission('expenses_manage') || hasPermission('accounting_view')) {
      items.push({ route: 'expenses', label: 'النظام المالي', icon: 'fa-wallet' });
    }
    if (isAdminLike || hasPermission('finance_manage') || hasPermission('accounting_view')) {
      items.push({ route: 'finance-tools', label: 'النظام المحاسبي', icon: 'fa-building-columns' });
    }
  }

  if (isAdminLike || hasPermission('finance_manage')) {
    items.push({ section: 'الموارد البشرية' });
    if (isAdminLike) items.push({ route: 'staff', label: 'التعيين وحسابات الموظفين', icon: 'fa-user-plus' });
    if (isAdminLike || hasPermission('finance_manage')) items.push({ route: 'hr', label: 'الموارد البشرية والمرتبات', icon: 'fa-users-gear' });
  }

  if (isAdminLike || hasPermission('catalog_manage') || hasPermission('finance_manage')) {
    items.push({ section: 'المخزن والتشغيل' });
    items.push({ route: 'inventory-tools', label: 'الجرد والضمان والصيانة', icon: 'fa-warehouse' });
  }

  if (isAdminLike || hasPermission('customer_data_view') || hasPermission('customer_data_manage') || hasRequestAccess()) {
    items.push({ section: 'العملاء' });
    if (isAdminLike || hasPermission('customer_data_view') || hasPermission('customer_data_manage')) {
      items.push({ route: 'customer-relations', label: 'إدارة العملاء والعلاقات', icon: 'fa-address-book' });
    }
    if (isAdminLike || hasRequestAccess()) {
      items.push({ route: 'staff-orders', label: 'طلبات العملاء', icon: 'fa-clipboard-list', badge: pendingTotal || null });
    }
  }

  items.push({ section: 'المتجر' });
  items.push({ route: 'home', label: 'عرض المتجر', icon: 'fa-store' });

  if (u.systemRole === 'owner') {
    items.push({ section: 'صلاحيات المالك' });
    items.push({ route: 'owner-data', label: 'النسخ الاحتياطي وإعادة الضبط', icon: 'fa-shield-halved' });
  }
  return items;
}

function renderSidebar() {
  const nav = $('#sidebarNav');
  if (!nav) return;
  const active = state.route;
  const groups = [];
  for (const item of sidebarItems()) {
    if (item.section) groups.push({ title: item.section, items: [] });
    else if (groups.length) groups[groups.length - 1].items.push(item);
  }
  nav.innerHTML = groups.map((group) => {
    const isActive = group.items.some((item) => item.route === active);
    const links = group.items.map((item) => {
      const badge = item.badge ? '<span class="badge">'+esc(item.badge)+'</span>' : '';
      return '<a class="sidebar-link '+(active===item.route?'active':'')+'" data-nav="'+esc(item.route)+'" role="button" tabindex="0"><i class="fa-solid '+esc(item.icon)+'"></i><span>'+esc(item.label)+'</span>'+badge+'</a>';
    }).join('');
    return '<details class="sidebar-group" '+(isActive?'open':'')+'><summary>'+esc(group.title)+'<i class="fa-solid fa-chevron-down"></i></summary><div class="sidebar-group-links">'+links+'</div></details>';
  }).join('');
}

function renderAccountArea() {
  const area = $('#accountArea');
  if (!area) return;
  const u = currentUser();
  if (!u) {
    area.innerHTML = `
      <button class="btn btn-ghost-light btn-sm" data-nav="login">
        <i class="fa-solid fa-right-to-bracket"></i> دخول
      </button>
      <button class="btn btn-primary btn-sm" data-nav="signup">
        <i class="fa-solid fa-user-plus"></i> حساب جديد
      </button>`;
    return;
  }
  const roleLabel = u.systemRole === 'owner' ? 'المالك' : u.systemRole === 'manager' ? 'مدير مساعد' : u.role === 'admin' ? 'مدير' : u.role === 'staff' ? 'موظف' : 'عميل';
  const fullName = u.name || u.email || 'مستخدم';
  const initial = (fullName || '?').trim().charAt(0);
  const isOps = u.role === 'staff' || u.role === 'admin' || u.systemRole === 'owner' || u.systemRole === 'manager';
  area.innerHTML = `
    <button class="user-chip" data-nav="account" title="الحساب وإدارته" type="button">
      <div class="avatar" aria-hidden="true">${esc(initial)}</div>
      <span class="user-chip-meta">
        <span class="name">${esc(fullName)}</span>
        <span class="role-badge">${esc(roleLabel)}</span>
      </span>
    </button>
    ${isOps ? '' : '<button class="btn btn-ghost-light btn-sm" data-nav="account"><i class="fa-solid fa-user"></i> حسابي</button>'}
    <button class="btn btn-primary btn-sm" id="logoutBtn" title="تسجيل الخروج">
      <i class="fa-solid fa-right-from-bracket"></i>
    </button>`;
}

/* =========================================================
   SECTION 3 — STOREFRONT & SLIDER
   ========================================================= */

function filteredBikes() {
  const unitCounters = new Map();
  let bikes = (state.storeUnits || []).map((unit) => {
    const bike = (state.bikes || []).find((item) => item.id === unit.motorcycle_id);
    const unitNumber = (unitCounters.get(unit.motorcycle_id) || 0) + 1;
    unitCounters.set(unit.motorcycle_id, unitNumber);
    return bike ? { ...bike, unit_id: unit.unit_id, unit_condition: unit.unit_condition, unit_number: unitNumber, stock: 1 } : null;
  }).filter(Boolean);
  const q = state.search.trim().toLowerCase();
  if (q) {
    bikes = bikes.filter((b) =>
      String(b.name).toLowerCase().includes(q) ||
      String(b.model).toLowerCase().includes(q)
    );
  }
  if (state.filterCat !== 'all') {
    bikes = bikes.filter((b) => b.category === state.filterCat);
  }
  if (state.filterPrice !== 'all') {
    const [min, max] = state.filterPrice.split('-').map(Number);
    bikes = bikes.filter((b) => b.price >= min && (max ? b.price <= max : true));
  }
  return bikes;
}

function productCard(b) {
  const u = currentUser();
  const favMap = get(DB.FAVS, {});
  const favs = u ? (favMap[u.id] || []) : [];
  const isCustomer = u?.role === 'customer';
  const isGuest = !u;
  const isFav = isCustomer && favs.includes(b.id);
  const imgs = (b.images && b.images.length) ? b.images : [];
  const first = imgs[0];
  const dots = imgs.map((_, i) => `<span class="${i === 0 ? 'active' : ''}"></span>`).join('');

  const stockClass = 'in';
  const stockText = 'متاحة الآن';

  return `
    <article class="product-card" data-bike-id="${esc(b.id)}" data-unit-id="${esc(b.unit_id || '')}">
      <div class="slider-wrap" data-slider data-idx="0">
        ${first ? `<img src="${esc(safeImageUrl(first))}" alt="${esc(b.name)}" data-slide-img loading="lazy">` : `<div class="bike-image-placeholder" aria-hidden="true"><i class="fa-solid fa-motorcycle"></i></div>`}
        <span class="stock-tag ${stockClass}"><i class="fa-solid fa-circle"></i> ${stockText}</span>
        ${isCustomer || isGuest ? `<button class="fav-btn ${isFav ? 'active' : ''}" data-fav="${esc(b.id)}" aria-label="${isGuest ? 'سجل الدخول لإضافة للمفضلة' : 'إضافة للمفضلة'}"><i class="fa-${isFav ? 'solid' : 'regular'} fa-heart"></i></button>` : ''}
        <button class="slider-btn prev" data-slide="prev" aria-label="السابق"><i class="fa-solid fa-chevron-right"></i></button>
        <button class="slider-btn next" data-slide="next" aria-label="التالي"><i class="fa-solid fa-chevron-left"></i></button>
        <div class="slider-dots" data-dots>${dots}</div>
      </div>
      <div class="product-body">
        <span class="product-cat">${esc(b.category || 'عام')}</span>
        <h3 class="product-name">${esc(b.name)}</h3>
        <div class="product-model">موديل ${esc(b.model)} · الوحدة ${Number(b.unit_number || 1)}</div>
        <div class="unit-condition-tag">${b.unit_condition === 'used' ? 'مستعملة' : 'جديدة'}</div>
        <div class="product-price">${money(b.price)}</div>
        <div class="product-actions">
          ${isCustomer ? `<button class="btn btn-primary btn-sm" data-buy="${esc(b.id)}" data-unit-id="${esc(b.unit_id || '')}" ${b.stock <= 0 ? 'disabled' : ''}><i class="fa-solid fa-cart-shopping"></i> طلب شراء</button>` : isGuest ? `<button class="btn btn-primary btn-sm" data-login-action="buy" data-bike-id="${esc(b.id)}" data-unit-id="${esc(b.unit_id || '')}" ${b.stock <= 0 ? 'disabled' : ''}><i class="fa-solid fa-cart-shopping"></i> تسجيل الدخول للشراء</button>` : ''}
          <button class="btn btn-outline btn-sm" data-details="${esc(b.id)}" data-unit-id="${esc(b.unit_id || '')}">
            <i class="fa-solid fa-eye"></i> تفاصيل
          </button>
        </div>
      </div>
    </article>`;
}

function pageHome() {
  const bikes = filteredBikes();
  const cats = Array.from(new Set(state.bikes.map((b) => b.category).filter(Boolean)));
  return `
    <section class="hero">
      <h1>El  <span>khayal </span> motor's </h1>
      <p>أفضل الدراجات النارية الرياضية بأعلى جودة وأفضل الأسعار. اختر دراجتك الآن من El Khayal Motors.</p>
      <button class="btn btn-primary" data-nav="request">
        <i class="fa-solid fa-motorcycle"></i> اطلب موتسيكلك الخاص
      </button>
    </section>

    <h2 class="page-title"><i class="fa-solid fa-motorcycle"></i> معرض الدراجات</h2>
    <p class="page-sub">تصفح مجموعتنا المختارة من أفضل الدراجات النارية</p>

    <div class="filters">
      <div class="search-wrap">
        <i class="fa-solid fa-magnifying-glass"></i>
        <input type="text" id="searchInput" placeholder="ابحث بالاسم أو الموديل..." value="${esc(state.search)}">
      </div>
      <select id="filterCat">
        <option value="all">كل الفئات</option>
        ${cats.map((c) => `<option value="${esc(c)}" ${state.filterCat === c ? 'selected' : ''}>${esc(c)}</option>`).join('')}
      </select>
      <select id="filterPrice">
        <option value="all">كل الأسعار</option>
        <option value="0-500000" ${state.filterPrice === '0-500000' ? 'selected' : ''}>أقل من 500 ألف</option>
        <option value="500000-1000000" ${state.filterPrice === '500000-1000000' ? 'selected' : ''}>500 ألف - مليون</option>
        <option value="1000000-0" ${state.filterPrice === '1000000-0' ? 'selected' : ''}>أكثر من مليون</option>
      </select>
    </div>

    <div class="products-grid" id="productsGrid">
      ${bikes.length
        ? bikes.map(productCard).join('')
        : `<div class="empty" style="grid-column:1/-1"><i class="fa-solid fa-box-open"></i><p>لا توجد وحدات دراجات متاحة للبيع حالياً</p></div>`}
    </div>`;
}

function pageRequest() {
  const u = currentUser();
  if (!u) return pageLogin();
  if (u.role !== 'customer') return pageNoPermission();
  return `
    <h2 class="page-title"><i class="fa-solid fa-motorcycle"></i> اطلب موتسيكلك الخاص</h2>
    <p class="page-sub">سجل الدخول بحساب عميل لإرسال طلبك ومتابعة حالته</p>
    <div class="panel" style="max-width:680px">
      <form id="requestForm" class="form-grid">
        <div class="field"><label>اسمك</label><input name="requester_name" required maxlength="120" value="${esc(u?.name || '')}" placeholder="الاسم بالكامل"></div>
        <div class="form-row">
          <div class="field"><label>رقم الهاتف</label><input name="requester_phone" type="tel" maxlength="32" value="${esc(u?.phone || '')}" placeholder="01xxxxxxxxx"></div>
          <div class="field"><label>البريد الإلكتروني</label><input name="requester_email" type="email" maxlength="254" value="${esc(u?.email || '')}" placeholder="name@example.com"></div>
        </div>
        <div class="field"><label>تفضّل التواصل عبر</label><select name="preferred_contact"><option value="whatsapp">واتساب</option><option value="phone">مكالمة هاتفية</option><option value="sms">رسالة SMS</option><option value="email">البريد الإلكتروني</option></select></div>
        <div class="field"><label>اسم الدراجة المطلوبة</label><input name="bikeName" required maxlength="160" placeholder="مثال: BMW S1000RR"></div>
        <div class="form-row">
          <div class="field"><label>الموديل / السنة</label><input name="model" inputmode="numeric" placeholder="2024"></div>
          <div class="field"><label>الميزانية التقريبية (ج.م)</label><input type="number" name="budget" min="0" step="0.01"></div>
        </div>
        <div class="field"><label>ملاحظات إضافية</label><textarea name="notes" maxlength="3000" placeholder="اللون والمواصفات وأي تفاصيل أخرى..."></textarea></div>
        <button class="btn btn-primary" type="submit"><i class="fa-solid fa-paper-plane"></i> إرسال الطلب</button>
      </form>
    </div>`;
}

function pageContact() {
  const u = currentUser();
  const canSend = u?.role === 'customer';
  const contactContent = canSend ? `
        <div class="panel-title"><i class="fa-solid fa-paper-plane"></i> أرسل رسالة</div>
        <form id="contactForm" class="form-grid">
          <div class="field"><label>الاسم</label><input name="name" required maxlength="120" value="${esc(u?.name || '')}"></div>
          <div class="form-row">
            <div class="field"><label>رقم الهاتف</label><input name="phone" type="tel" maxlength="32" value="${esc(u?.phone || '')}"></div>
            <div class="field"><label>البريد الإلكتروني</label><input type="email" name="email" maxlength="254" value="${esc(u?.email || '')}"></div>
          </div>
          <div class="field"><label>طريقة الرد المفضلة</label><select name="preferred_contact"><option value="whatsapp">واتساب</option><option value="phone">مكالمة هاتفية</option><option value="sms">SMS</option><option value="email">البريد الإلكتروني</option></select></div>
          <div class="field"><label>رسالتك</label><textarea name="message" required maxlength="10000"></textarea></div>
          <button class="btn btn-primary" type="submit"><i class="fa-solid fa-paper-plane"></i> إرسال الرسالة</button>
        </form>` : `
        <div class="panel-title"><i class="fa-solid fa-paper-plane"></i> أرسل رسالة</div>
        <p>إرسال الرسائل متاح لحسابات العملاء المسجلة فقط.</p>
        <div class="contact-actions">
          <button class="btn btn-primary" type="button" data-contact-auth="signup"><i class="fa-solid fa-user-plus"></i> إنشاء حساب</button>
          <button class="btn btn-outline" type="button" data-contact-auth="login"><i class="fa-solid fa-right-to-bracket"></i> تسجيل الدخول</button>
        </div>`;
  return `
    <h2 class="page-title"><i class="fa-solid fa-headset"></i> تواصل معنا</h2>
    <p class="page-sub">معلومات التواصل متاحة للجميع؛ ولإرسال رسالة يلزم حساب عميل مسجل.</p>
    <div style="display:grid;grid-template-columns:repeat(auto-fit,minmax(280px,1fr));gap:20px">
      <div class="panel">
        <div class="panel-title"><i class="fa-solid fa-comments"></i> قنوات التواصل</div>
        <p>تواصل مباشرة مع معرض الخيال موتورز أو زرنا في موقعنا.</p>
        <div class="contact-details">
          <p><i class="fa-solid fa-phone"></i> <strong>الهاتف والواتساب:</strong> <a href="tel:01006315559" dir="ltr">01006315559</a></p>
          <p><i class="fa-brands fa-whatsapp"></i> <a class="btn btn-outline btn-sm" href="https://wa.me/201006315559" target="_blank" rel="noopener">راسلنا على واتساب</a></p>
          <p><i class="fa-solid fa-location-dot"></i> <strong>العنوان:</strong> الطريق الجديد – مدخل حلوان 3 الأوتوستراد</p>
          <p><a class="btn btn-outline btn-sm" href="https://www.google.com/maps/search/?api=1&query=%D8%A7%D9%84%D8%B7%D8%B1%D9%8A%D9%82%20%D8%A7%D9%84%D8%AC%D8%AF%D9%8A%D8%AF%20%E2%80%93%20%D9%85%D8%AF%D8%AE%D9%84%20%D8%AD%D9%84%D9%88%D8%A7%D9%86%203%20%D8%A7%D9%84%D8%A3%D9%88%D8%AA%D9%88%D8%B3%D8%AA%D8%B1%D8%A7%D8%AF" target="_blank" rel="noopener"><i class="fa-solid fa-map-location-dot"></i> افتح الموقع على الخريطة</a></p>
        </div>
        <button class="btn btn-outline" data-nav="request"><i class="fa-solid fa-motorcycle"></i> إرسال طلب شراء</button>
      </div>
      <div class="panel">${contactContent}</div>
    </div>`;
}

function pageLogin() {
  return `
    <div class="auth-card">
      <h2>تسجيل الدخول</h2>
      <p class="sub">أدخل بياناتك للوصول إلى حسابك</p>
      <form id="loginForm" class="form-grid">
        <div class="field">
          <label>البريد الإلكتروني</label>
          <input type="email" name="email" required placeholder="email@example.com" autocomplete="email">
        </div>
        <div class="field">
          <label>كلمة المرور</label>
          <input type="password" name="password" required placeholder="••••••••" autocomplete="current-password">
        </div>
        <button class="btn btn-primary btn-block" type="submit">
          <i class="fa-solid fa-right-to-bracket"></i> دخول
        </button>
      </form>
      <button class="text-link" type="button" id="resendConfirmationBtn">إعادة إرسال تأكيد البريد</button>
      <p class="hint">إذا أنشأ المدير حساب موظف لك، استخدم بريد الحساب هنا لطلب رسالة التأكيد أولاً.</p>
      <div class="auth-switch">ليس لديك حساب؟ <a data-nav="signup">أنشئ حساباً جديداً</a></div>

    </div>`;
}

function pageSignup() {
  return `
    <div class="auth-card">
      <h2>حساب جديد</h2>
      <p class="sub">سجل الآن لتتمكن من الشراء والمفضلة</p>
      <form id="signupForm" class="form-grid">
        <div class="field"><label>الاسم الكامل</label>
          <input type="text" name="name" required placeholder="اسمك" autocomplete="name"></div>
        <div class="field"><label>البريد الإلكتروني</label>
          <input type="email" name="email" required placeholder="email@example.com" autocomplete="email"></div>
        <div class="field"><label>رقم الهاتف</label>
          <input type="tel" name="phone" required placeholder="01xxxxxxxxx" autocomplete="tel"></div>
        <div class="field"><label>كلمة المرور</label>
          <input type="password" name="password" required minlength="6" placeholder="6 أحرف على الأقل" autocomplete="new-password"></div>
        <button class="btn btn-primary btn-block" type="submit">
          <i class="fa-solid fa-user-plus"></i> إنشاء الحساب
        </button>
      </form>
      <div class="auth-switch">لديك حساب بالفعل؟ <a data-nav="login">تسجيل الدخول</a></div>
    </div>`;
}

function pageAccount() {
  const u = currentUser();
  if (!u) return pageLogin();
  const allRequests = get(DB.CUSTOM_REQS);
  const orders = allRequests.filter((request) => request.motorcycleId);
  const reqs = allRequests.filter((request) => !request.motorcycleId);
  return `
    <h2 class="page-title"><i class="fa-solid fa-user"></i> ملفي الشخصي</h2>
    <p class="page-sub">بياناتك، طلباتك، وحالة طلباتك الخاصة</p>
    <div class="stats-grid">
      <div class="stat-card"><div class="stat-icon"><i class="fa-solid fa-receipt"></i></div><div class="stat-label">إجمالي الطلبات</div><div class="stat-value">${orders.length}</div></div>
      <div class="stat-card"><div class="stat-icon"><i class="fa-solid fa-motorcycle"></i></div><div class="stat-label">طلبات خاصة</div><div class="stat-value">${reqs.length}</div></div>
    </div>
    <div class="panel">
      <div class="panel-title"><i class="fa-solid fa-id-card"></i> بياناتي</div>
      <p style="margin-bottom:8px"><b>الاسم:</b> ${esc(u.name)}</p>
      <p style="margin-bottom:8px"><b>الإيميل:</b> ${esc(u.email)}</p>
      <p><b>الهاتف:</b> ${esc(u.phone || '—')}</p>
    </div>
    <div class="panel">
      <div class="panel-title"><i class="fa-solid fa-box"></i> طلباتي الخاصة</div>
      ${reqs.length ? `
        <div class="table-wrap"><table>
          <thead><tr><th>الدراجة</th><th>الموديل</th><th>الميزانية</th><th>الحالة</th><th>التاريخ</th></tr></thead>
          <tbody>${reqs.map((r) => `
            <tr>
              <td>${esc(r.bikeName)}</td>
              <td>${esc(r.model)}</td>
              <td>${money(r.budget)}</td>
              <td><span class="status-pill ${r.status}">${esc(requestStatusLabel(r.status))}</span></td>
              <td>${new Date(r.createdAt).toLocaleDateString('ar-EG')}</td>
            </tr>`).join('')}</tbody>
        </table></div>` : `<div class="empty"><i class="fa-solid fa-inbox"></i><p>لا توجد طلبات خاصة بعد</p></div>`}
    </div>`;
}

function pageFavorites() {
  const u = currentUser();
  if (!u) return pageLogin();
  if (u.role !== 'customer') return pageNoPermission();
  const favIds = get(DB.FAVS, {})[u.id] || [];
  const bikes = get(DB.BIKES).filter((b) => favIds.includes(b.id));
  return `
    <h2 class="page-title"><i class="fa-solid fa-heart"></i> المفضلة</h2>
    <p class="page-sub">الدراجات التي أعجبتك</p>
    <div class="products-grid">
      ${bikes.length ? bikes.map(productCard).join('') : `<div class="empty" style="grid-column:1/-1"><i class="fa-solid fa-heart-crack"></i><p>لا توجد دراجات في المفضلة</p></div>`}
    </div>`;
}

function pageOrders() {
  const u = currentUser();
  if (!u) return pageLogin();
  if (u.role !== 'customer') return pageNoPermission();
  const orders = get(DB.CUSTOM_REQS).filter((request) => request.motorcycleId);
  return `
    <h2 class="page-title"><i class="fa-solid fa-receipt"></i> طلباتي</h2>
    <p class="page-sub">طلباتك المسجلة في Supabase</p>
    <div class="panel">
      ${orders.length ? `
        <div class="table-wrap"><table>
          <thead><tr><th>الدراجة</th><th>الميزانية</th><th>الحالة</th><th>التاريخ</th></tr></thead>
          <tbody>${orders.map((o) => `
            <tr>
              <td>${esc(o.bikeName)}${o.unitCondition ? `<br><small>${o.unitCondition === 'used' ? 'مستعملة' : 'جديدة'}</small>` : ''}</td>
              <td style="color:var(--red);font-weight:700">${money(o.budget)}</td>
              <td><span class="status-pill ${o.status}">${esc(requestStatusLabel(o.status))}</span></td>
              <td>${new Date(o.createdAt).toLocaleDateString('ar-EG')}</td>
            </tr>`).join('')}</tbody>
        </table></div>` : `<div class="empty"><i class="fa-solid fa-inbox"></i><p>لا توجد طلبات</p></div>`}
    </div>`;
}

function pageCustomerInvoices() {
  const u = currentUser();
  if (!u) return pageLogin();
  if (u.role !== 'customer') return pageNoPermission();
  const invoices = state.customerInvoices || [];
  return `
    <h2 class="page-title"><i class="fa-solid fa-file-invoice"></i> فواتيري</h2>
    <p class="page-sub">فواتير المبيعات المرتبطة بحسابك لدى معرض الخيال موتورز</p>
    ${invoices.length ? invoices.map((invoice) => {
      const status = invoice.payment_status === 'paid' ? 'مدفوعة' : invoice.payment_status === 'partial' ? 'مدفوعة جزئيًا' : 'غير مدفوعة';
      return `<details class="panel customer-invoice">
        <summary><b>${esc(invoice.invoice_number)}</b> — ${new Date(invoice.created_at).toLocaleDateString('ar-EG')} — ${money(invoice.total)} <span class="status-pill ${esc(invoice.payment_status)}">${status}</span></summary>
        <div class="table-wrap mt-2"><table><thead><tr><th>الصنف</th><th>الموديل</th><th>رقم الشاسيه</th><th>رقم الموتور</th><th>الكمية</th><th>سعر الوحدة</th><th>الإجمالي</th></tr></thead>
        <tbody>${invoice.items.map(item => {
          const units=item.sale_item_units||[];
          const ids=units.length?units.map(unit=>`<tr><td>${esc(item.motorcycle_name)}</td><td>${esc(item.model_year||'—')}</td><td>${esc(unit.vin_snapshot||'—')}</td><td>${esc(unit.engine_number_snapshot||'—')}</td><td>1</td><td>${money(item.unit_price)}</td><td>${money(item.unit_price)}</td></tr>`).join(''):`<tr><td>${esc(item.motorcycle_name)}</td><td>${esc(item.model_year||'—')}</td><td>—</td><td>—</td><td>${Number(item.quantity)}</td><td>${money(item.unit_price)}</td><td>${money(item.line_total)}</td></tr>`;
          return ids;
        }).join('')}</tbody></table></div>
        <div class="invoice-totals"><p><b>إجمالي الفاتورة:</b> ${money(invoice.total)}</p><p><b>المدفوع:</b> ${money(invoice.amount_paid)}</p><p><b>الرصيد المستخدم:</b> ${money(invoice.credit_applied)}</p><p><b>المتبقي:</b> ${money(invoice.balance_due)}</p></div>
        <div class="contact-actions mt-2 no-print"><button class="btn btn-primary btn-sm" type="button" data-print-customer-invoice><i class="fa-solid fa-print"></i> طباعة هذه الفاتورة</button></div>
      </details>`;
    }).join('') : `<div class="panel empty"><i class="fa-solid fa-file-invoice"></i><p>لا توجد فواتير مرتبطة بحسابك حتى الآن.</p><small>إذا اشتريت من المعرض ولم تظهر فاتورتك، اطلب من الموظف ربط عملية البيع بحسابك عند إصدار الفاتورة.</small></div>`}
  `;
}


/* ---------- VIN / Engine-number camera scanner ---------- */
let vinScannerStream = null;
let vinScanTimer = null;
let vinOcrWorker = null;
let vinScanBusy = false;
let vinBarcodeDetector = null;
let lastScannedUnit = null;

function normalizeUnitCode(value) {
  return String(value || '').toUpperCase().replace(/[^A-Z0-9]/g, '');
}

function stopVinScanner() {
  if (vinScanTimer) clearInterval(vinScanTimer);
  vinScanTimer = null;
  if (vinScannerStream) vinScannerStream.getTracks().forEach(track => track.stop());
  vinScannerStream = null;
  const video = $('#vinScannerVideo');
  if (video) video.srcObject = null;
  const start = $('#startVinScanner'), stop = $('#stopVinScanner'), placeholder = $('#vinCameraPlaceholder');
  if (start) start.disabled = false;
  if (stop) stop.disabled = true;
  if (placeholder) placeholder.classList.remove('hidden');
}

async function loadTesseractLibrary() {
  if (window.Tesseract) return window.Tesseract;
  await new Promise((resolve, reject) => {
    const script = document.createElement('script');
    script.src = 'https://cdn.jsdelivr.net/npm/tesseract.js@5.0.5/dist/tesseract.min.js';
    script.onload = resolve;
    script.onerror = () => reject(new Error('تعذر تحميل محرك قراءة النصوص'));
    document.head.appendChild(script);
  });
  return window.Tesseract;
}

async function getVinOcrWorker() {
  if (vinOcrWorker) return vinOcrWorker;
  const tesseract = await loadTesseractLibrary();
  vinOcrWorker = await tesseract.createWorker('eng');
  return vinOcrWorker;
}

async function lookupUnitByCode(rawCode) {
  const code = normalizeUnitCode(rawCode);
  if (code.length < 5) throw new Error('الرقم قصير جدًا؛ تحقق من وضوح الصورة أو أدخل الرقم كاملًا');
  if (!supabase || !currentUser() || !canUseVinScanner()) throw new Error('يلزم تسجيل الدخول بصلاحية المبيعات للبحث');
  const columns = ['vin','engine_number','barcode'];
  for (const column of columns) {
    const { data, error } = await supabase.from('motorcycle_units')
      .select('id,motorcycle_id,vin,engine_number,barcode,unit_status,sale_item_id,warranty_start,warranty_end,notes,registered_at,odometer_reading,unit_condition,is_demo,motorcycles(id,name,model_year,category,price,stock,image_urls,description)')
      .ilike(column, code)
      .limit(2);
    if (error) throw error;
    if (data?.length > 1) throw new Error('الرقم يطابق أكثر من وحدة؛ راجع تسجيل أرقام الوحدات في المخزن');
    if (data?.length === 1) return data[0];
  }
  return null;
}

function showVinScanStatus(message, isError = false) {
  const el = $('#vinScanStatus');
  if (el) { el.textContent = message; el.classList.toggle('text-red', !!isError); }
}

function renderVinUnitMatch(unit) {
  lastScannedUnit = unit;
  const target = $('#vinScanResult');
  if (!target) return;
  if (!unit) {
    target.innerHTML = '<div class="empty"><i class="fa-solid fa-circle-question"></i><p>لم يتم العثور على وحدة مسجلة بهذا الرقم.</p><small>تأكد من إدخال رقم الهيكل أو الموتور كما هو مسجل في المخزن.</small></div>';
    return;
  }
  const bike = unit.motorcycles || {};
  const available = unit.unit_status === 'available' && Number(bike.stock || 0) > 0;
  const image = bike.image_urls?.[0] ? '<img class="vin-unit-image" src="'+esc(safeImageUrl(bike.image_urls[0]))+'" alt="'+esc(bike.name)+'">' : '<div class="vin-unit-image vin-unit-placeholder"><i class="fa-solid fa-motorcycle"></i></div>';
  target.innerHTML = '<div class="vin-unit-card">'+image+'<div class="vin-unit-details"><div class="contact-actions"><span class="status-badge '+(available?'success':'danger')+'">'+(available?'متاحة للبيع':'غير متاحة للبيع')+'</span><b>'+esc(bike.name||'طراز غير معروف')+'</b></div>'+
    '<div class="vin-unit-grid"><div><small>الموديل</small><b>'+esc(bike.model_year||'—')+'</b></div><div><small>الفئة</small><b>'+esc(bike.category||'—')+'</b></div><div><small>السعر</small><b>'+money(bike.price)+'</b></div><div><small>المخزون العام</small><b>'+Number(bike.stock||0)+'</b></div><div><small>رقم الشاسيه VIN</small><b>'+esc(unit.vin||'—')+'</b></div><div><small>رقم الموتور</small><b>'+esc(unit.engine_number||'—')+'</b></div><div><small>العداد</small><b>'+Number(unit.odometer_reading||0).toLocaleString('en-US')+' كم</b></div><div><small>حالة الدراجة</small><b>'+(unit.unit_condition==='used'?'مستعملة':'جديدة')+'</b></div><div><small>الباركود</small><b>'+esc(unit.barcode||'—')+'</b></div><div><small>حالة الوحدة</small><b>'+(unit.is_demo?'بيانات تجريبية — غير قابلة للبيع':esc(unit.unit_status))+'</b></div><div><small>الضمان</small><b>'+esc(unit.warranty_start||'—')+' – '+esc(unit.warranty_end||'—')+'</b></div></div>'+
    (bike.description?'<p>'+esc(bike.description)+'</p>':'')+'</div></div>'+
    (available?'<form id="vinScannerSaleForm" class="vin-sale-form form-grid" data-unit-id="'+esc(unit.id)+'"><h3><i class="fa-solid fa-cash-register"></i> بيع هذه الوحدة</h3>'+
      '<div class="form-row"><div class="field"><label>حساب العميل (اختياري)</label><select name="customer_user_id"><option value="">عميل نقدي / بدون ربط</option>'+((state.registeredCustomers||[]).map(c=>'<option value="'+esc(c.user_id)+'" data-name="'+esc(c.display_name)+'" data-phone="'+esc(c.phone||'')+'">'+esc(c.display_name)+' — '+esc(c.phone||'بدون هاتف')+'</option>').join(''))+'</select></div><div class="field"><label>اسم العميل</label><input name="customer_name" maxlength="120" placeholder="عميل نقدي"></div><div class="field"><label>هاتف العميل</label><input name="customer_phone" type="tel" maxlength="32"></div></div>'+
      '<div class="form-row"><div class="field"><label>المبلغ المدفوع الآن (ج.م)</label><input name="payment_amount" type="number" min="0" max="'+Number(bike.price||0)+'" step="0.01" value="'+Number(bike.price||0)+'" required></div><div class="field"><label>طريقة الدفع</label><select name="payment_method"><option value="cash">نقدي</option><option value="bank_transfer">تحويل بنكي</option><option value="card">بطاقة</option><option value="other">أخرى</option></select></div><div class="field"><label>استلمت الدفعة في</label><select name="cash_account_id"><option value="">اختر الخزينة / البنك</option>'+((state.salesCashAccounts||[]).map(a=>'<option value="'+esc(a.id)+'">'+esc(a.name)+' — '+esc(a.account_kind==='bank'?'بنك':'خزينة')+'</option>').join(''))+'</select></div></div>'+
      '<div class="field"><label>مرجع الدفع (اختياري)</label><input name="payment_reference" maxlength="120"></div><div class="field"><label>ملاحظات</label><textarea name="notes" rows="2" maxlength="500"></textarea></div>'+
      '<button class="btn btn-primary btn-block" type="submit"><i class="fa-solid fa-file-invoice"></i> تأكيد البيع وإصدار الفاتورة</button></form>':'<div class="hint">لا يمكن بيع الوحدة من هنا لأنها مباعة أو محجوزة أو غير متاحة أو أن مخزون الطراز غير كافٍ.</div>');
}

async function processVinScan(rawCode) {
  const input = $('#vinScanInput');
  if (input) input.value = rawCode;
  showVinScanStatus('تم التقاط الرقم؛ جارٍ البحث في قاعدة البيانات...');
  try {
    const unit = await lookupUnitByCode(rawCode);
    renderVinUnitMatch(unit);
    showVinScanStatus(unit ? 'تم العثور على الوحدة وربط الرقم ببياناتها.' : 'لم يتم العثور على وحدة مطابقة.', !unit);
    if (unit) stopVinScanner();
  } catch (error) {
    showVinScanStatus(error.message || 'تعذر البحث عن الوحدة', true);
  }
}

async function startVinScanner() {
  if (!navigator.mediaDevices?.getUserMedia) {
    toast('الكاميرا تحتاج متصفحًا يدعمها واتصال HTTPS', 'error'); return;
  }
  try {
    vinScannerStream = await navigator.mediaDevices.getUserMedia({ video: { facingMode: { ideal: 'environment' }, width: { ideal: 1920 }, height: { ideal: 1080 } }, audio: false });
    const video = $('#vinScannerVideo');
    if (!video) { stopVinScanner(); return; }
    video.srcObject = vinScannerStream;
    await video.play();
    $('#vinCameraPlaceholder')?.classList.add('hidden');
    $('#startVinScanner').disabled = true;
    $('#stopVinScanner').disabled = false;
    if ('BarcodeDetector' in window) {
      try {
        const supported = await window.BarcodeDetector.getSupportedFormats();
        const wanted = ['code_128','code_39','qr_code','ean_13','ean_8','upc_a','upc_e','itf','codabar','data_matrix','pdf417'];
        vinBarcodeDetector = new window.BarcodeDetector({ formats: wanted.filter(x => supported.includes(x)) });
      } catch { vinBarcodeDetector = null; }
    }
    let lastOcrAt = 0;
    vinScanTimer = setInterval(async () => {
      if (vinScanBusy || !vinScannerStream || video.readyState < 2) return;
      vinScanBusy = true;
      try {
        if (vinBarcodeDetector) {
          const codes = await vinBarcodeDetector.detect(video);
          const value = codes.find(x => normalizeUnitCode(x.rawValue).length >= 5)?.rawValue;
          if (value) { await processVinScan(value); return; }
        }
        if (Date.now() - lastOcrAt > 2600) {
          lastOcrAt = Date.now();
          const canvas = document.createElement('canvas');
          canvas.width = Math.min(video.videoWidth, 1500);
          canvas.height = Math.round(canvas.width * video.videoHeight / video.videoWidth);
          const ctx = canvas.getContext('2d');
          ctx.drawImage(video, 0, 0, canvas.width, canvas.height);
          const worker = await getVinOcrWorker();
          const result = await worker.recognize(canvas);
          const textValue = String(result?.data?.text || '').toUpperCase();
          const candidates = [...new Set([
            ...(textValue.match(/[A-HJ-NPR-Z0-9]{17}/g) || []),
            ...(textValue.match(/[A-Z0-9]{7,20}/g) || [])
          ])].sort((a,b)=>b.length-a.length);
          for (const candidate of candidates.slice(0,5)) {
            const unit = await lookupUnitByCode(candidate).catch(()=>null);
            if (unit) { await processVinScan(candidate); return; }
          }
        }
      } catch (error) {
        console.debug('Camera scan iteration:', error);
      } finally { vinScanBusy = false; }
    }, 650);
    toast('الكاميرا تعمل؛ ثبّت الرقم داخل الإطار', 'success');
  } catch (error) {
    stopVinScanner();
    toast(error.name === 'NotAllowedError' ? 'لم يتم السماح باستخدام الكاميرا' : 'تعذر تشغيل الكاميرا: '+(error.message||''), 'error');
  }
}

/* =========================================================
   SECTION 4 — POS & INVOICES
   ========================================================= */

function canUseVinScanner() {
  return !!currentUser() && (hasRole('admin','manager','owner') || hasPermission('sales_manage'));
}

function pageVinScanner() {
  if (!canUseVinScanner()) return pageNoPermission();
  return `
    <h2 class="page-title"><i class="fa-solid fa-barcode"></i> ماسح رقم الشاسيه والموتور</h2>
    <p class="page-sub">افتح الكاميرا لقراءة رقم الهيكل أو رقم الموتور تلقائيًا، أو أدخل الرقم يدويًا. سيبحث النظام في الوحدات المسجلة ويعرض بيانات الطراز والسعر والتوفر.</p>
    <div class="panel vin-scanner-panel">
      <div class="panel-title"><i class="fa-solid fa-camera"></i> مسح بالكاميرا</div>
      <div class="vin-camera-frame">
        <video id="vinScannerVideo" autoplay muted playsinline></video>
        <div class="vin-camera-guide"><span>وجّه الرقم داخل الإطار</span></div>
        <div class="vin-camera-placeholder" id="vinCameraPlaceholder"><i class="fa-solid fa-camera"></i><b>الكاميرا متوقفة</b><small>استخدم الكاميرا الخلفية مع إضاءة جيدة</small></div>
      </div>
      <div class="contact-actions vin-camera-actions">
        <button class="btn btn-primary" type="button" id="startVinScanner"><i class="fa-solid fa-camera"></i> تشغيل الكاميرا والمسح التلقائي</button>
        <button class="btn btn-outline" type="button" id="stopVinScanner" disabled><i class="fa-solid fa-camera-rotate"></i> إيقاف الكاميرا</button>
      </div>
      <small class="hint">يدعم قراءة الباركود تلقائيًا، والتعرف على النص المطبوع/المحفور باستخدام OCR عند توفر مكتبة التعرف. يتطلب السماح بالكاميرا واتصال HTTPS.</small>
    </div>
    <div class="panel">
      <div class="panel-title"><i class="fa-solid fa-magnifying-glass"></i> البحث المباشر</div>
      <form id="vinLookupForm" class="form-row vin-lookup-form">
        <div class="field"><label for="vinScanInput">رقم الشاسيه VIN أو رقم الموتور أو الباركود</label><input id="vinScanInput" name="code" maxlength="80" autocomplete="off" autocapitalize="characters" placeholder="اكتب الرقم أو امسحه بالكاميرا" required></div>
        <button class="btn btn-primary" type="submit"><i class="fa-solid fa-search"></i> بحث عن الوحدة</button>
      </form>
      <div id="vinScanStatus" class="hint" aria-live="polite">لم يتم إجراء بحث بعد.</div>
      <div id="vinScanResult" class="vin-scan-result"></div>
    </div>`;
}

function pagePOS() {
  const u = currentUser();
  if (!canUseVinScanner()) return pageNoPermission();
  const availableUnits = (state.motorcycleUnits || []).filter(unit => unit.unit_status === 'available' && !unit.is_demo);
  const available = state.bikes.filter(bike => bike.status === 'available' && availableUnits.some(unit => unit.motorcycle_id === bike.id));
  const sales = state.sales || [];
  return `
    <h2 class="page-title"><i class="fa-solid fa-cash-register"></i> نظام البيع داخل المعرض</h2>
    <p class="page-sub">بيع مباشر من المعرض — لا يحتاج العميل إلى حساب دخول</p>
    <div class="panel">
      <div class="panel-title"><i class="fa-solid fa-cart-plus"></i> فاتورة بيع جديدة</div>
      ${available.length ? `
      <form id="posSaleForm" class="form-grid">
        <div class="field"><label for="posCustomerAccount">ربط الفاتورة بحساب عميل مسجل (اختياري)</label><select id="posCustomerAccount" name="customer_user_id"><option value="">عميل نقدي / بدون ربط بحساب</option>${state.registeredCustomers.map(customer => `<option value="${esc(customer.user_id)}" data-name="${esc(customer.display_name)}" data-phone="${esc(customer.phone || '')}">${esc(customer.display_name)} — ${esc(customer.phone || 'بدون هاتف')}</option>`).join('')}</select><small class="hint">عند اختيار حساب عميل، ستظهر الفاتورة في قسم «فواتيري» بعد تسجيل دخوله.</small></div>
        <div class="form-row">
          <div class="field"><label for="posCustomerName">اسم العميل (اختياري)</label><input id="posCustomerName" name="customer_name" maxlength="120" placeholder="عميل نقدي"></div>
          <div class="field"><label for="posCustomerPhone">رقم الهاتف (اختياري)</label><input id="posCustomerPhone" name="customer_phone" maxlength="32" type="tel"></div>
        </div>
        <div class="field">
          <label>أصناف الفاتورة</label>
          <div id="posCartRows">
            <div class="form-row pos-cart-row">
              <div class="field"><label>طراز الدراجة</label><select name="motorcycle_id" required>
                <option value="">اختر الدراجة</option>
                ${available.map((bike) => `<option value="${esc(bike.id)}">${esc(bike.name)} — ${esc(bike.model)} — ${money(bike.price)}</option>`).join('')}
              </select></div>
              <div class="field"><label>الوحدات الفعلية — اختر أرقام الشاسيه</label><select name="unit_ids" multiple size="4" required>
                ${availableUnits.map(unit => {const bike=state.bikes.find(item=>item.id===unit.motorcycle_id);return `<option value="${esc(unit.id)}" data-motorcycle-id="${esc(unit.motorcycle_id)}">${esc(bike?.name||'دراجة')} — ${esc(unit.vin)}</option>`;}).join('')}
              </select><small class="hint">يجب اختيار رقم شاسيه لكل دراجة مباعة.</small></div>
              <div class="field"><label>إجراء</label><button class="btn btn-outline btn-sm" type="button" data-remove-pos-row disabled>حذف الصنف</button></div>
            </div>
          </div>
          <button class="btn btn-outline btn-sm" type="button" id="addPosItemBtn"><i class="fa-solid fa-plus"></i> إضافة صنف آخر</button>
          <small class="hint">اختر طراز الدراجة ثم أرقام الشاسيه الفعلية لكل وحدة. لا يعتمد البيع على كمية تقديرية.</small>
        </div>
        <div class="form-row">
          <div class="field"><label for="posPaymentAmount">المبلغ المدفوع الآن (ج.م)</label><input id="posPaymentAmount" name="payment_amount" type="number" min="0" step="0.01" value="0" required><small class="hint">يمكن تسجيل دفعة جزئية أو إصدار الفاتورة دون تحصيل.</small></div>
          <div class="field"><label for="posPaymentMethod">طريقة الدفع</label><select id="posPaymentMethod" name="payment_method"><option value="cash">نقدي</option><option value="bank_transfer">تحويل بنكي</option><option value="card">بطاقة</option><option value="other">أخرى</option></select></div>
          <div class="field"><label>الخزينة / البنك المستلم</label><select name="cash_account_id"><option value="">اختر الحساب عند تحصيل دفعة</option>${(state.salesCashAccounts||[]).map(a=>'<option value="'+esc(a.id)+'">'+esc(a.name)+' — '+esc(a.account_kind==='bank'?'بنك':'خزينة')+'</option>').join('')}</select></div>
        </div>
        <div class="field"><label for="posPaymentReference">مرجع الدفع (اختياري)</label><input id="posPaymentReference" name="payment_reference" maxlength="120"></div>
        <div class="field"><label for="posNotes">ملاحظات (اختياري)</label><textarea id="posNotes" name="notes" rows="2" maxlength="1000"></textarea></div>
        <button class="btn btn-primary btn-block" type="submit"><i class="fa-solid fa-file-invoice"></i> تسجيل البيع وإصدار الفاتورة</button>
      </form>` : `<div class="empty"><i class="fa-solid fa-box-open"></i><p>لا توجد دراجات متاحة للبيع حاليًا.</p></div>`}
    </div>
    <div class="panel">
      <div class="panel-title"><i class="fa-solid fa-receipt"></i> أحدث فواتير المعرض</div>
      ${sales.length ? `<div class="table-wrap"><table>
        <thead><tr><th>رقم الفاتورة</th><th>العميل</th><th>الإجمالي</th><th>المدفوع</th><th>رصيد مستخدم</th><th>المتبقي</th><th>الحالة</th><th>المرتجعات</th><th>التاريخ</th><th>إجراءات</th></tr></thead>
        <tbody>${sales.map((sale) => `<tr>
          <td><b>${esc(sale.invoice_number)}</b></td><td>${esc(sale.customer_name)}</td>
          <td>${money(sale.total)}</td><td>${money(sale.amount_paid)}</td><td>${money(sale.credit_applied || 0)}</td>
          <td>${money(Math.max(0, Number(sale.total) - Number(sale.amount_paid) - Number(sale.credit_applied || 0) - Number(sale.returnedAmount || 0)))}</td>
          <td><span class="status-pill ${esc(sale.payment_status)}">${sale.payment_status === 'paid' ? 'مدفوعة' : sale.payment_status === 'partial' ? 'مدفوعة جزئيًا' : 'غير مدفوعة'}</span></td>
          <td>${money(sale.returnedAmount || 0)}</td>
          <td>${new Date(sale.created_at).toLocaleDateString('ar-EG')}</td>
          <td><button class="btn btn-outline btn-sm" data-view-invoice="${esc(sale.id)}">عرض / طباعة</button> ${Number(sale.total) - Number(sale.amount_paid) - Number(sale.credit_applied || 0) - Number(sale.returnedAmount || 0) > 0 ? `<button class="btn btn-outline btn-sm" data-collect-payment="${esc(sale.id)}">تحصيل دفعة</button>` : ''} ${(state.customerCredits.find(c => c.customerId === sale.customer_id)?.balance || 0) > 0 && Number(sale.total) - Number(sale.amount_paid) - Number(sale.credit_applied || 0) - Number(sale.returnedAmount || 0) > 0 ? `<button class="btn btn-outline btn-sm" data-apply-credit="${esc(sale.id)}">استخدام رصيد</button>` : ''} <button class="btn btn-outline btn-sm" data-return-sale="${esc(sale.id)}">مرتجع</button></td>
        </tr>`).join('')}</tbody></table></div>` : `<div class="empty"><i class="fa-solid fa-inbox"></i><p>لا توجد فواتير مسجلة بعد.</p></div>`}
    </div>
    <div class="panel">
      <div class="panel-title"><i class="fa-solid fa-wallet"></i> أرصدة العملاء الدائنة</div>
      <p class="hint">الرصيد هنا ناتج عن مرتجعات البيع بعد خصم أي مبالغ تم ردّها بالفعل.</p>
      ${state.customerCredits.length ? `<div class="table-wrap"><table>
        <thead><tr><th>العميل</th><th>الهاتف</th><th>الرصيد المتاح</th><th>إجراء</th></tr></thead>
        <tbody>${state.customerCredits.map(c=>`<tr>
          <td>${esc(c.name)}</td><td>${esc(c.phone || '—')}</td><td><b>${money(c.balance)}</b></td>
          <td><button class="btn btn-outline btn-sm" data-refund-credit="${esc(c.customerId)}">رد مبلغ</button></td>
        </tr>`).join('')}</tbody></table></div>` : `<div class="empty"><i class="fa-solid fa-wallet"></i><p>لا توجد أرصدة دائنة مستحقة للعملاء حاليًا.</p></div>`}
    </div>`;
}

function pageSalesTools() {
 const u=currentUser(),canManage=hasRole('admin','manager','owner')||hasPermission('sales_manage');
 if(!u||!canManage)return pageNoPermission();
 const bikes=state.bikes||[],clients=state.crmClients||[],sales=state.sales||[];
 const clientOpts=clients.map(x=>'<option value="'+esc(x.id)+'">'+esc(x.display_name)+' — '+esc(x.phone||'')+'</option>').join('');
 const bikeLines=bikes.map(b=>'<div class="form-row" data-quote-line="'+esc(b.id)+'"><div class="field"><label>'+esc(b.name)+' — المتاح '+b.stock+'</label><input type="number" name="quantity" min="0" max="'+b.stock+'" step="1" value="0"></div><div class="field"><label>سعر الوحدة</label><input type="number" name="unit_price" min="0" step="0.01" value="'+Number(b.price||0)+'"></div></div>').join('');
 const quoteRows=(state.salesQuotations||[]).map(q=>{
  const items=(state.salesQuotationItems||[]).filter(i=>i.quotation_id===q.id);
  return '<tr><td>#'+esc(q.quotation_number)+'</td><td>'+esc(q.customer_name)+'</td><td>'+esc(q.customer_phone)+'</td><td>'+money(q.total_amount)+'</td><td>'+esc(q.valid_until)+'</td><td>'+esc(q.status)+'</td><td>'+(q.status==='draft'||q.status==='sent'?'<form id="quotationStatusForm" class="inline-form" data-quote-id="'+esc(q.id)+'"><select name="status"><option value="sent">إرسال</option><option value="accepted">اعتماد العميل</option><option value="cancelled">إلغاء</option></select><button class="btn btn-outline btn-sm" type="submit">تحديث</button></form>':q.status==='accepted'?'<form id="convertQuotationForm" class="form-grid" data-quote-id="'+esc(q.id)+'"><input type="number" name="payment_amount" min="0" step="0.01" value="0" placeholder="دفعة مقدمة إن وجدت"><select name="payment_method"><option value="cash">نقدي</option><option value="bank_transfer">تحويل بنكي</option><option value="card">بطاقة</option><option value="other">أخرى</option></select><button class="btn btn-primary btn-sm" type="submit">تحويل إلى فاتورة</button></form>':q.status==='converted'?'<a href="#" data-route="sales">فاتورة '+esc(q.sale_id||'')+'</a>':'—')+'</td></tr><tr><td colspan="7"><small>'+items.map(i=>esc(i.motorcycles?.name||'')+' × '+i.quantity+' = '+money(i.line_total)).join(' | ')+'</small></td></tr>';
 }).join('');
 const deliveredIds=new Set((state.saleDeliveries||[]).map(d=>d.sale_id));
 const deliverySales=sales.filter(s=>s.status==='posted'&&!deliveredIds.has(s.id));
 const deliverySaleOpts=deliverySales.map(s=>'<option value="'+esc(s.id)+'">'+esc(s.invoice_number)+' — '+esc(s.customer_name)+' — '+money(s.total)+'</option>').join('');
 const deliveryRows=(state.saleDeliveries||[]).map(d=>'<tr><td>#'+d.delivery_number+'</td><td>'+esc(d.sales?.invoice_number||'—')+'</td><td>'+esc(d.recipient_name)+'</td><td>'+esc(d.recipient_phone||'—')+'</td><td>'+new Date(d.delivered_at).toLocaleString('ar-EG')+'</td><td>'+esc(d.odometer_reading??'—')+'</td><td><button class="btn btn-outline btn-sm" type="button" data-print-delivery="'+esc(d.id)+'">طباعة محضر التسليم</button></td></tr>').join('');

 const dueSales=sales.filter(s=>s.status==='posted'&&Number(s.total)-Number(s.amount_paid||0)-Number(s.credit_applied||0)>0);
 const saleOpts=dueSales.map(s=>'<option value="'+esc(s.id)+'">فاتورة '+esc(s.invoice_number)+' — '+esc(s.customer_name)+' — متبقي '+money(Number(s.total)-Number(s.amount_paid||0)-Number(s.credit_applied||0))+'</option>').join('');
 const installmentRows=(state.saleInstallments||[]).map(x=>'<tr><td>'+esc(x.sales?.invoice_number||'—')+'</td><td>#'+x.installment_number+'</td><td>'+esc(x.due_date)+'</td><td>'+money(x.amount)+'</td><td>'+money(x.paid_amount)+'</td><td>'+money(Number(x.amount)-Number(x.paid_amount))+'</td><td>'+esc(x.status)+'</td><td>'+(x.status!=='paid'&&x.status!=='cancelled'?'<form id="installmentPaymentForm" class="inline-form" data-installment-id="'+esc(x.id)+'"><input type="number" name="amount" min="0.01" max="'+(Number(x.amount)-Number(x.paid_amount))+'" step="0.01" placeholder="المبلغ" required><select name="method"><option value="cash">نقدي</option><option value="bank_transfer">تحويل</option><option value="card">بطاقة</option><option value="other">أخرى</option></select><button class="btn btn-outline btn-sm" type="submit">تحصيل</button></form>':'—')+'</td></tr>').join('');
 return '<h2 class="page-title"><i class="fa-solid fa-file-invoice-dollar"></i> عروض الأسعار والتقسيط</h2><p class="page-sub">إعداد عروض أسعار للعميل، اعتمادها ثم تحويلها إلى فاتورة بيع، وإنشاء جداول أقساط مخصصة مرتبطة برصيد الفاتورة وتسجيل التحصيلات.</p>'+
 '<div class="panel"><div class="panel-title">إنشاء عرض سعر</div><form id="salesQuotationForm" class="form-grid"><div class="form-row"><div class="field"><label>عميل مسجل (اختياري)</label><select name="customer_id"><option value="">عميل غير مسجل</option>'+clientOpts+'</select></div><div class="field"><label>اسم العميل</label><input name="customer_name" required maxlength="120"></div><div class="field"><label>الهاتف</label><input name="customer_phone" required maxlength="30"></div></div><div class="form-row"><div class="field"><label>صالح حتى</label><input type="date" name="valid_until" required></div><div class="field"><label>ملاحظات</label><input name="notes" maxlength="180"></div></div><h4>الأصناف</h4>'+bikeLines+'<button class="btn btn-primary" type="submit" '+(!bikes.length?'disabled':'')+'>إنشاء عرض السعر</button></form><div class="table-wrap mt-2"><table><thead><tr><th>رقم</th><th>العميل</th><th>الهاتف</th><th>الإجمالي</th><th>الصلاحية</th><th>الحالة</th><th>الإجراء</th></tr></thead><tbody>'+(quoteRows||'<tr><td colspan="7">لا توجد عروض أسعار</td></tr>')+'</tbody></table></div></div>'+
 '<div class="panel"><div class="panel-title">جدولة أقساط فاتورة</div><p class="hint">أدخل جدول الأقساط بصيغة JSON، ويجب أن يساوي مجموع المبالغ الرصيد المستحق الحالي بالضبط. لا تُضاف فوائد أو رسوم تلقائيًا. مثال: [{"due_date":"2026-12-01","amount":5000},{"due_date":"2027-01-01","amount":5000}]</p><form id="installmentScheduleForm" class="form-grid"><div class="field"><label>الفاتورة</label><select name="sale_id" required><option value="">اختر الفاتورة</option>'+saleOpts+'</select></div><div class="field"><label>جدول الأقساط JSON</label><textarea name="schedule_json" rows="4" placeholder="[{&quot;due_date&quot;:&quot;2026-12-01&quot;,&quot;amount&quot;:5000}]" required></textarea></div><button class="btn btn-primary" type="submit">إنشاء جدول الأقساط</button></form><div class="table-wrap mt-2"><table><thead><tr><th>الفاتورة</th><th>القسط</th><th>الاستحقاق</th><th>المبلغ</th><th>المسدد</th><th>المتبقي</th><th>الحالة</th><th>التحصيل</th></tr></thead><tbody>'+(installmentRows||'<tr><td colspan="8">لا توجد أقساط مجدولة</td></tr>')+'</tbody></table></div></div>'+
 '<div class="panel"><div class="panel-title"><i class="fa-solid fa-motorcycle"></i> محاضر تسليم الدراجات</div><p class="hint">سجل استلام العميل للدراجة بعد ترحيل فاتورة البيع. يسجل النظام وقت التسليم تلقائيًا، ويمكن طباعة محضر استلام.</p><form id="saleDeliveryForm" class="form-grid"><div class="form-row"><div class="field"><label>فاتورة البيع</label><select name="sale_id" required><option value="">اختر فاتورة لم يتم تسليمها</option>'+deliverySaleOpts+'</select></div><div class="field"><label>اسم المستلم</label><input name="recipient_name" required maxlength="120"></div><div class="field"><label>هاتف المستلم</label><input name="recipient_phone" maxlength="32"></div></div><div class="form-row"><div class="field"><label>قراءة العداد كم (اختياري)</label><input name="odometer_reading" type="number" min="0" step="1"></div><div class="field"><label>الملحقات المسلمة</label><input name="accessories" maxlength="300" placeholder="المفاتيح، الكتيب، أدوات الصيانة..."></div></div><div class="field"><label>حالة الدراجة عند التسليم</label><textarea name="condition_notes" rows="2" maxlength="1000"></textarea></div><div class="field"><label>ملاحظات</label><input name="notes" maxlength="300"></div><button class="btn btn-primary" type="submit" '+(!deliverySales.length?'disabled':'')+'>حفظ محضر التسليم</button></form><div class="table-wrap mt-2"><table><thead><tr><th>المحضر</th><th>الفاتورة</th><th>المستلم</th><th>الهاتف</th><th>وقت التسليم</th><th>العداد</th><th>الطباعة</th></tr></thead><tbody>'+(deliveryRows||'<tr><td colspan="7">لا توجد محاضر تسليم بعد</td></tr>')+'</tbody></table></div></div>';
}

function pageCustomerRelations() {
 const u=currentUser(),manager=hasRole('admin','manager','owner'),canManage=manager||hasPermission('customer_data_manage');
 if(!u||!(manager||hasPermission('customer_data_view')||canManage))return pageNoPermission();
 const clients=state.crmClients||[],clientOpts=clients.map(x=>'<option value="'+esc(x.id)+'">'+esc(x.display_name)+' — '+esc(x.phone||'')+'</option>').join('');
 const userOpts=(get(DB.USERS)||[]).filter(x=>x.id).map(x=>'<option value="'+esc(x.id)+'">'+esc(x.name||x.email||x.id)+'</option>').join('');
 const interactionRows=(state.customerInteractions||[]).map(x=>'<tr><td>'+esc(x.clients?.display_name||'—')+'</td><td>'+esc(x.interaction_type)+'</td><td>'+esc(x.subject)+'</td><td>'+esc(x.interaction_at?.slice(0,16)||'')+'</td><td>'+esc(x.next_follow_up||'—')+'</td><td>'+esc(x.notes||'—')+'</td></tr>').join('');
 const complaintRows=(state.customerComplaints||[]).map(x=>'<tr><td>#'+x.complaint_number+'</td><td>'+esc(x.customer_name)+'</td><td>'+esc(x.customer_phone||'—')+'</td><td>'+esc(x.subject)+'</td><td>'+esc(x.priority)+'</td><td>'+esc(x.status)+'</td><td>'+(canManage&&x.status!=='closed'?'<form id="customerComplaintUpdateForm" class="inline-form" data-complaint-id="'+esc(x.id)+'"><select name="status"><option value="in_progress">قيد المعالجة</option><option value="resolved">تم الحل</option><option value="closed">مغلقة</option></select><input name="resolution" placeholder="الإجراء / الحل"><button class="btn btn-outline btn-sm" type="submit">تحديث</button></form>':'—')+'</td></tr>').join('');
 const notificationRows=(state.internalNotifications||[]).map(x=>'<tr><td>'+esc(x.title)+'</td><td>'+esc(x.body||'—')+'</td><td>'+esc(x.category)+'</td><td>'+esc(x.created_at?.slice(0,16)||'')+'</td><td>'+(x.read_at?'مقروء':'<form id="markNotificationReadForm" class="inline-form" data-notification-id="'+esc(x.id)+'"><button class="btn btn-outline btn-sm" type="submit">تحديد كمقروء</button></form>')+'</td></tr>').join('');
 const statementRows=(state.customerStatementRows||[]).map(x=>'<tr><td>'+esc(clients.find(c=>c.id===x.customer_id)?.display_name||x.customer_id)+'</td><td>'+esc(x.entry_date)+'</td><td>'+esc(x.entry_type)+'</td><td>'+esc(x.document_number||'—')+'</td><td>'+money(x.debit)+'</td><td>'+money(x.credit)+'</td></tr>').join('');
 const profileRows=clients.map(x=>'<tr><td>'+esc(x.display_name)+'</td><td>'+esc(x.phone||'—')+'</td><td>'+esc(x.email||'—')+'</td><td>'+esc(x.customer_segment||'standard')+'</td><td>'+money(x.credit_limit)+'</td><td>'+esc(x.lead_source||'—')+'</td><td>'+(canManage?'<form id="customerProfileMetaForm" class="form-grid" data-customer-id="'+esc(x.id)+'"><input name="credit_limit" type="number" min="0" step="0.01" value="'+(x.credit_limit??'')+'" placeholder="حد ائتماني فارغ = بلا حد"><select name="customer_segment"><option value="standard" '+(x.customer_segment==='standard'?'selected':'')+'>عادي</option><option value="vip" '+(x.customer_segment==='vip'?'selected':'')+'>VIP</option><option value="wholesale" '+(x.customer_segment==='wholesale'?'selected':'')+'>جملة</option><option value="restricted" '+(x.customer_segment==='restricted'?'selected':'')+'>مقيّد</option></select><input name="lead_source" value="'+esc(x.lead_source||'')+'" placeholder="مصدر العميل"><label><input type="checkbox" name="marketing_consent" '+(x.marketing_consent?'checked':'')+'> موافقة تسويق</label><button class="btn btn-outline btn-sm" type="submit">حفظ</button></form>':'—')+'</td></tr>').join('');
 return '<h2 class="page-title"><i class="fa-solid fa-address-book"></i> إدارة العملاء والعلاقات</h2><p class="page-sub">تصنيف العملاء، حدود الائتمان، مصادر العملاء وموافقات التواصل، سجل التفاعلات، الشكاوى، والإشعارات الداخلية.</p>'+
 '<div class="stats-grid"><div class="stat-card"><div class="stat-label">العملاء</div><div class="stat-value">'+clients.length+'</div></div><div class="stat-card"><div class="stat-label">تفاعلات مسجلة</div><div class="stat-value">'+(state.customerInteractions||[]).length+'</div></div><div class="stat-card"><div class="stat-label">شكاوى مفتوحة</div><div class="stat-value">'+(state.customerComplaints||[]).filter(x=>!['resolved','closed'].includes(x.status)).length+'</div></div><div class="stat-card"><div class="stat-label">إشعارات غير مقروءة</div><div class="stat-value">'+(state.internalNotifications||[]).filter(x=>!x.read_at).length+'</div></div></div>'+
 '<div class="panel"><div class="panel-title">ملفات العملاء والحد الائتماني</div><p class="hint">الحد الائتماني اختياري؛ تركه فارغًا يعني عدم فرض حد. عند تحديده، تمنع قاعدة البيانات إنشاء فاتورة جديدة إذا تجاوزت المديونية المتوقعة الحد.</p><div class="table-wrap"><table><thead><tr><th>العميل</th><th>الهاتف</th><th>البريد</th><th>التصنيف</th><th>الحد الحالي</th><th>المصدر</th><th>تحديث الملف</th></tr></thead><tbody>'+(profileRows||'<tr><td colspan="7">لا توجد ملفات عملاء</td></tr>')+'</tbody></table></div></div>'+
 '<div class="panel"><div class="panel-title">سجل تواصل العملاء</div><form id="customerInteractionForm" class="form-grid"><div class="form-row"><div class="field"><label>العميل</label><select name="customer_id" required><option value="">اختر العميل</option>'+clientOpts+'</select></div><div class="field"><label>نوع التفاعل</label><select name="interaction_type"><option value="call">اتصال</option><option value="whatsapp">واتساب</option><option value="visit">زيارة</option><option value="email">بريد</option><option value="complaint">شكوى</option><option value="follow_up">متابعة</option><option value="other">أخرى</option></select></div><div class="field"><label>متابعة في</label><input type="datetime-local" name="next_follow_up"></div></div><div class="field"><label>عنوان التفاعل</label><input name="subject" required maxlength="150"></div><div class="field"><label>ملاحظات</label><textarea name="notes" rows="2"></textarea></div><button class="btn btn-primary" type="submit">تسجيل التفاعل</button></form><div class="table-wrap mt-2"><table><thead><tr><th>العميل</th><th>النوع</th><th>العنوان</th><th>التاريخ</th><th>متابعة</th><th>ملاحظات</th></tr></thead><tbody>'+(interactionRows||'<tr><td colspan="6">لا توجد تفاعلات</td></tr>')+'</tbody></table></div></div>'+
 '<div class="panel"><div class="panel-title">الشكاوى وخدمة العملاء</div><form id="customerComplaintForm" class="form-grid"><div class="form-row"><div class="field"><label>ربط بعميل (اختياري)</label><select name="customer_id"><option value="">عميل غير مسجل</option>'+clientOpts+'</select></div><div class="field"><label>اسم العميل</label><input name="customer_name" required maxlength="120"></div><div class="field"><label>الهاتف</label><input name="customer_phone" maxlength="30"></div></div><div class="form-row"><div class="field"><label>عنوان الشكوى</label><input name="subject" required maxlength="150"></div><div class="field"><label>الأولوية</label><select name="priority"><option value="normal">عادية</option><option value="low">منخفضة</option><option value="high">عالية</option><option value="urgent">عاجلة</option></select></div></div><div class="field"><label>التفاصيل</label><textarea name="description" rows="2" required></textarea></div><button class="btn btn-primary" type="submit">تسجيل الشكوى</button></form><div class="table-wrap mt-2"><table><thead><tr><th>رقم</th><th>العميل</th><th>الهاتف</th><th>الموضوع</th><th>الأولوية</th><th>الحالة</th><th>المعالجة</th></tr></thead><tbody>'+(complaintRows||'<tr><td colspan="7">لا توجد شكاوى</td></tr>')+'</tbody></table></div></div>'+
 '<div class="panel"><div class="panel-title">الإشعارات الداخلية</div><form id="internalNotificationForm" class="form-grid"><div class="form-row"><div class="field"><label>الموظف المستلم</label><select name="user_id" required><option value="">اختر الموظف</option>'+userOpts+'</select></div><div class="field"><label>التصنيف</label><select name="category"><option value="general">عام</option><option value="sales">مبيعات</option><option value="finance">مالية</option><option value="inventory">مخزون</option><option value="customer">عميل</option></select></div></div><div class="field"><label>العنوان</label><input name="title" required maxlength="150"></div><div class="field"><label>الرسالة</label><textarea name="body" rows="2"></textarea></div><button class="btn btn-outline" type="submit">إرسال إشعار داخلي</button></form><div class="table-wrap mt-2"><table><thead><tr><th>العنوان</th><th>الرسالة</th><th>التصنيف</th><th>التاريخ</th><th>الحالة</th></tr></thead><tbody>'+(notificationRows||'<tr><td colspan="5">لا توجد إشعارات</td></tr>')+'</tbody></table></div></div>'+
 '<div class="panel printable-panel"><div class="panel-title">كشف حركة العملاء</div><div class="table-wrap"><table><thead><tr><th>العميل</th><th>التاريخ</th><th>النوع</th><th>المستند</th><th>مدين</th><th>دائن</th></tr></thead><tbody>'+(statementRows||'<tr><td colspan="6">لا توجد حركات أو لا تتوفر صلاحية عرض كشف العملاء</td></tr>')+'</tbody></table></div></div>';
}

function pageInventoryTools() {
 const u=currentUser(),canFinance=hasRole('admin','manager','owner')||hasPermission('finance_manage'),canCatalog=canFinance||hasPermission('catalog_manage');
 if(!u||!canCatalog)return pageNoPermission();
 const allBikes=state.bikes||[],bikes=allBikes.filter(b=>!b.is_demo),realModelIds=new Set(bikes.map(b=>b.id)),realUnits=(state.motorcycleUnits||[]).filter(x=>!x.is_demo&&realModelIds.has(x.motorcycle_id)),costMap=new Map((state.inventoryCosts||[]).map(x=>[x.motorcycle_id,x]));
 const bikeOpts=bikes.map(b=>'<option value="'+esc(b.id)+'">'+esc(b.name)+' — مخزون '+b.stock+'</option>').join('');
 const unitOpts=realUnits.filter(x=>x.unit_status!=='sold'&&x.unit_status!=='retired').map(x=>'<option value="'+esc(x.id)+'">'+esc(x.vin)+' — '+esc(x.motorcycles?.name||'')+'</option>').join('');
 const warrantyOpts=(state.warranties||[]).filter(x=>x.status==='active'&&x.end_date>=new Date().toISOString().slice(0,10)).map(x=>'<option value="'+esc(x.id)+'">ضمان #'+x.warranty_number+' — '+esc(x.customer_name)+'</option>').join('');
 const employeeOpts=(state.employees||[]).filter(x=>x.employment_status==='active').map(x=>'<option value="'+esc(x.id)+'">'+esc(x.full_name)+'</option>').join('');
 const saleOpts=(state.sales||[]).map(x=>'<option value="'+esc(x.id)+'">فاتورة '+esc(x.invoice_number)+' — '+esc(x.customer_name)+'</option>').join('');
 const costRows=bikes.map(b=>{const x=costMap.get(b.id)||{};return '<tr><td>'+esc(b.name)+'</td><td>'+b.stock+'</td><td>'+money(x.unit_cost)+'</td><td>'+Number(x.reorder_level||0)+'</td><td>'+(canFinance||hasPermission('catalog_manage')?'<form id="inventoryCostForm" class="inline-form" data-bike-id="'+esc(b.id)+'"><input type="number" name="unit_cost" min="0" step="0.01" value="'+(x.unit_cost??'')+'" placeholder="تكلفة الوحدة" required><input type="number" name="reorder_level" min="0" step="1" value="'+Number(x.reorder_level||0)+'" required><button class="btn btn-outline btn-sm" type="submit">حفظ</button></form>':'—')+'</td></tr>';}).join('');
 const batchRows=(state.stocktakeBatches||[]).map(x=>'<tr><td>#'+x.stocktake_number+'</td><td>'+esc(x.stocktake_date)+'</td><td>'+esc(x.notes||'—')+'</td><td>'+money(x.total_increase)+'</td><td>'+money(x.total_decrease)+'</td><td>'+esc(x.journal_entry_id||'بدون فرق مالي')+'</td></tr>').join('');
 const warrantyRows=(state.warranties||[]).map(x=>'<tr><td>#'+x.warranty_number+'</td><td>'+esc(x.motorcycles?.name||'—')+'</td><td>'+esc(x.customer_name)+'</td><td>'+esc(x.customer_phone)+'</td><td>'+esc(x.start_date)+' – '+esc(x.end_date)+'</td><td>'+esc(x.status)+'</td></tr>').join('');
 const serviceRows=(state.serviceOrders||[]).map(x=>'<tr><td>#'+x.service_number+'</td><td>'+esc(x.motorcycles?.name||'—')+'</td><td>'+esc(x.customer_name)+'</td><td>'+esc(x.customer_phone)+'</td><td>'+esc(x.issue_description)+'</td><td>'+money(x.estimated_cost)+'</td><td>'+esc(x.status)+'</td><td>'+(canCatalog&&!['completed','cancelled'].includes(x.status)?'<form id="serviceStatusForm" class="inline-form" data-order-id="'+esc(x.id)+'"><select name="status"><option value="in_progress">قيد العمل</option><option value="waiting_parts">بانتظار قطع غيار</option><option value="completed">مكتمل</option><option value="cancelled">ملغي</option></select><input name="actual_cost" type="number" min="0" step="0.01" placeholder="التكلفة الفعلية"><input name="diagnosis" placeholder="التشخيص"><button class="btn btn-outline btn-sm" type="submit">تحديث</button></form>':'—')+'</td></tr>').join('');
 const reorderRows=(state.reorderAlerts||[]).map(x=>'<tr><td>'+esc(x.name)+'</td><td>'+x.stock+'</td><td>'+x.reorder_level+'</td><td>'+money(x.unit_cost)+'</td><td>'+money(x.stock_value)+'</td></tr>').join('');
 const reconciliation=(state.inventoryReconciliation||[]).filter(x=>realModelIds.has(x.motorcycle_id)&&Number(x.difference)!==0);
 const reconciliationRows=reconciliation.map(x=>'<tr><td>'+esc(x.motorcycle_name)+'</td><td>'+x.model_stock+'</td><td>'+x.physical_units+'</td><td>'+x.difference+'</td><td>'+x.available_units+' متاح / '+x.reserved_units+' محجوز / '+x.service_units+' صيانة</td></tr>').join('');

 return '<h2 class="page-title"><i class="fa-solid fa-warehouse"></i> إدارة المخزون والجرد والضمان والصيانة</h2><p class="page-sub">تسجيل تكلفة المخزون الفعلية، حدود إعادة الطلب، أرقام الهياكل والباركود، الجرد الدوري مع قيد فروق المخزون، الضمان وأوامر الصيانة.</p>'+
 '<div class="stats-grid"><div class="stat-card"><div class="stat-label">طرازات المخزون</div><div class="stat-value">'+bikes.length+'</div></div><div class="stat-card"><div class="stat-label">أرقام هياكل فعلية</div><div class="stat-value">'+realUnits.length+'</div></div><div class="stat-card"><div class="stat-label">وحدات ببيانات تجريبية أو تابعة لطراز تجريبي</div><div class="stat-value">'+((state.motorcycleUnits||[]).length-realUnits.length)+'</div></div><div class="stat-card"><div class="stat-label">تنبيهات إعادة الطلب</div><div class="stat-value">'+(state.reorderAlerts||[]).length+'</div></div><div class="stat-card"><div class="stat-label">أوامر صيانة مفتوحة</div><div class="stat-value">'+(state.serviceOrders||[]).filter(x=>!['completed','cancelled'].includes(x.status)).length+'</div></div></div>'+
 '<div class="panel printable-panel"><div class="panel-title">مطابقة رصيد الطراز مع الوحدات الفعلية</div><p class="hint">يجب أن يساوي رصيد الطراز عدد الوحدات المتاحة والمحجوزة وتحت الصيانة. سجلات الفروق القديمة تحتاج تسجيل أرقام الشاسيه أو مراجعة حركة مخزون قبل اعتماد الجرد أو البيع.</p><div class="table-wrap"><table><thead><tr><th>الطراز</th><th>رصيد الطراز</th><th>الوحدات المسجلة</th><th>الفرق</th><th>تفصيل الحالات</th></tr></thead><tbody>'+(reconciliationRows||'<tr><td colspan="5">لا توجد فروق بين الرصيد والوحدات المسجلة</td></tr>')+'</tbody></table></div></div>'+
 '<div class="panel printable-panel"><div class="panel-title">تكلفة المخزون وحد إعادة الطلب</div><p class="hint">يُحدّث النظام متوسط تكلفة الوحدة المرجح تلقائيًا من استلامات الشراء بعد خصم مرتجعات المورد. يمكن للمحاسب تعديل التكلفة يدويًا عند وجود تسوية موثقة.</p><div class="table-wrap"><table><thead><tr><th>الدراجة</th><th>المخزون</th><th>متوسط التكلفة المرجح</th><th>حد الطلب</th><th>تحديث التكلفة / الحد</th></tr></thead><tbody>'+(costRows||'<tr><td colspan="5">لا توجد دراجات</td></tr>')+'</tbody></table></div></div>'+
 '<div class="panel"><div class="panel-title">إدارة وحدات الدراجات</div><p>أرقام الشاسيه والموتور وتفاصيل كل دراجة أصبحت داخل المعرض / الكتالوج. افتح مجلد النوع لإضافة الوحدات أو تعديل بياناتها وحالاتها.</p><button class="btn btn-outline" data-nav="manage-bikes">فتح المعرض / الكتالوج</button></div>'+
 '<div class="panel printable-panel"><div class="panel-title">الجرد الفعلي وتسوية فروق المخزون</div><p class="hint">أدخل العدد المعدود لكل طراز. تُسجل فروق الكمية في حركات المخزون، وتُرحّل القيمة إلى حساب المخزون وفروق الجرد باستخدام تكلفة الوحدة المسجلة. لا تُنشأ قيود إذا لم يوجد فرق.</p><form id="stocktakeForm" class="form-grid"><div class="form-row"><div class="field"><label>تاريخ الجرد</label><input name="stocktake_date" type="date" required></div><div class="field"><label>ملاحظات</label><input name="notes" maxlength="180"></div></div>'+bikes.map(b=>'<div class="form-row" data-stocktake-line="'+esc(b.id)+'"><div class="field"><label>'+esc(b.name)+' — الدفتري '+b.stock+'</label><input type="number" name="counted_quantity" min="0" step="1" value="'+b.stock+'" required></div><div class="field"><label>تكلفة الوحدة</label><input disabled value="'+(costMap.get(b.id)?.unit_cost??'غير محددة')+'"></div></div>').join('')+'<button class="btn btn-primary" type="submit" '+(!bikes.length?'disabled':'')+'>ترحيل الجرد الفعلي</button></form><div class="table-wrap mt-2"><table><thead><tr><th>الجرد</th><th>التاريخ</th><th>ملاحظات</th><th>زيادة</th><th>عجز</th><th>قيد اليومية</th></tr></thead><tbody>'+(batchRows||'<tr><td colspan="6">لا توجد عمليات جرد</td></tr>')+'</tbody></table></div></div>'+
 '<div class="panel printable-panel"><div class="panel-title">تنبيهات إعادة الطلب</div><div class="table-wrap"><table><thead><tr><th>الدراجة</th><th>المخزون الحالي</th><th>حد الطلب</th><th>تكلفة الوحدة</th><th>قيمة المخزون</th></tr></thead><tbody>'+(reorderRows||'<tr><td colspan="5">لا توجد تنبيهات. عيّن حد إعادة الطلب لكل طراز.</td></tr>')+'</tbody></table></div></div>'+
 '<div class="panel"><div class="panel-title">إدارة الضمان</div><form id="warrantyForm" class="form-grid"><div class="form-row"><div class="field"><label>الدراجة</label><select name="motorcycle_id" required><option value="">اختر الدراجة</option>'+bikeOpts+'</select></div><div class="field"><label>فاتورة البيع (اختياري)</label><select name="sale_id"><option value="">بدون ربط فاتورة</option>'+saleOpts+'</select></div></div><div class="form-row"><div class="field"><label>اسم العميل</label><input name="customer_name" required maxlength="120"></div><div class="field"><label>الهاتف</label><input name="customer_phone" required maxlength="30"></div></div><div class="form-row"><div class="field"><label>بداية الضمان</label><input name="start_date" type="date" required></div><div class="field"><label>نهاية الضمان</label><input name="end_date" type="date" required></div></div><div class="field"><label>الشروط</label><textarea name="terms" rows="2"></textarea></div><button class="btn btn-outline" type="submit">تسجيل ضمان</button></form><div class="table-wrap mt-2"><table><thead><tr><th>الضمان</th><th>الدراجة</th><th>العميل</th><th>الهاتف</th><th>الفترة</th><th>الحالة</th></tr></thead><tbody>'+(warrantyRows||'<tr><td colspan="6">لا توجد ضمانات</td></tr>')+'</tbody></table></div></div>'+
 '<div class="panel"><div class="panel-title">أوامر الصيانة</div><form id="serviceOrderForm" class="form-grid"><div class="form-row"><div class="field"><label>الدراجة</label><select name="motorcycle_id" required><option value="">اختر الدراجة</option>'+bikeOpts+'</select></div><div class="field"><label>رقم الهيكل (اختياري)</label><select name="unit_id"><option value="">غير محدد</option>'+unitOpts+'</select></div><div class="field"><label>ضمان (اختياري)</label><select name="warranty_id"><option value="">بدون ضمان</option>'+warrantyOpts+'</select></div></div><div class="form-row"><div class="field"><label>اسم العميل</label><input name="customer_name" required maxlength="120"></div><div class="field"><label>الهاتف</label><input name="customer_phone" required maxlength="30"></div><div class="field"><label>الفني المسؤول</label><select name="employee_id"><option value="">غير معين</option>'+employeeOpts+'</select></div></div><div class="field"><label>وصف العطل</label><textarea name="issue_description" rows="2" required></textarea></div><div class="form-row"><div class="field"><label>التكلفة التقديرية</label><input name="estimated_cost" type="number" min="0" step="0.01" value="0" required></div><div class="field"><label>ملاحظات</label><input name="notes" maxlength="180"></div></div><button class="btn btn-primary" type="submit">فتح أمر صيانة</button></form><div class="table-wrap mt-2"><table><thead><tr><th>الأمر</th><th>الدراجة</th><th>العميل</th><th>الهاتف</th><th>العطل</th><th>تقديري</th><th>الحالة</th><th>تحديث</th></tr></thead><tbody>'+(serviceRows||'<tr><td colspan="8">لا توجد أوامر صيانة</td></tr>')+'</tbody></table></div></div>';
}

function pageHR() {
  const u=currentUser(),canManage=hasRole('admin','manager','owner')||hasPermission('finance_manage');
  if(!u||!canManage)return pageNoPermission();
  const employees=state.employees||[],active=employees.filter(x=>x.employment_status==='active');
  const empOpts=active.map(x=>'<option value="'+esc(x.id)+'">'+esc(x.employee_code)+' — '+esc(x.full_name)+'</option>').join('');
  const cashOpts=(state.cashAccounts||[]).map(x=>'<option value="'+esc(x.id)+'">'+esc(x.name)+'</option>').join('');
  const periods=(state.fiscalPeriods||[]).filter(x=>x.status==='open').map(x=>'<option value="'+esc(x.id)+'">'+esc(x.period_name)+'</option>').join('');
  const salesOpts=(state.sales||[]).map(x=>'<option value="'+esc(x.id)+'">فاتورة '+esc(x.invoice_number)+' — '+esc(x.customer_name)+' — '+money(x.total)+'</option>').join('');
  const authUserOpts=(get(DB.USERS)||[]).map(x=>'<option value="'+esc(x.id)+'">'+esc(x.name||x.email||x.id)+' — '+esc(x.email||'')+'</option>').join('');
  const employeeRows=employees.map(x=>'<tr><td>'+esc(x.employee_code)+'</td><td>'+esc(x.full_name)+'</td><td>'+esc(x.job_title||'—')+'</td><td>'+esc(x.phone||'—')+'</td><td>'+money(x.base_salary)+'</td><td>'+esc(x.hire_date)+'</td><td><span class="status-pill '+(x.employment_status==='active'?'completed':'pending')+'">'+({active:'نشط',terminated:'منتهي',suspended:'موقوف'}[x.employment_status]||x.employment_status)+'</span></td><td>'+(canManage&&x.employment_status==='active'?'<form id="terminateEmployeeForm" class="inline-form" data-employee-id="'+esc(x.id)+'"><input type="date" name="termination_date" required><button class="btn btn-outline btn-sm" type="submit">إنهاء الملف</button></form>':'—')+'</td></tr>').join('');
  const attendanceRows=(state.attendanceRecords||[]).slice(0,60).map(x=>'<tr><td>'+esc(x.attendance_date)+'</td><td>'+esc(x.employees?.full_name||'—')+'</td><td>'+({present:'حاضر',absent:'غائب',late:'متأخر',leave:'إجازة',holiday:'عطلة'}[x.attendance_status]||x.attendance_status)+'</td><td>'+esc(x.check_in||'—')+'</td><td>'+esc(x.check_out||'—')+'</td></tr>').join('');
  const leaveRows=(state.employeeLeaveRequests||[]).map(x=>'<tr><td>'+esc(x.employees?.full_name||'—')+'</td><td>'+esc(x.leave_type)+'</td><td>'+esc(x.start_date)+' – '+esc(x.end_date)+'</td><td>'+x.days+'</td><td>'+esc(x.reason||'—')+'</td><td>'+esc(x.status)+'</td><td>'+(x.status==='pending'?'<form id="reviewLeaveForm" class="inline-form" data-leave-id="'+esc(x.id)+'"><button class="btn btn-outline btn-sm" name="status" value="approved" type="submit">موافقة</button><button class="btn btn-outline btn-sm" name="status" value="rejected" type="submit">رفض</button></form>':'—')+'</td></tr>').join('');
  const custodyRows=(state.employeeCustody||[]).map(x=>'<tr><td>#'+x.custody_number+'</td><td>'+esc(x.employees?.full_name||'—')+'</td><td>'+esc(x.item_name)+'</td><td>'+money(x.estimated_value)+'</td><td>'+esc(x.assigned_date)+'</td><td>'+esc(x.status)+'</td><td>'+(x.status==='assigned'?'<form id="returnCustodyForm" class="inline-form" data-custody-id="'+esc(x.id)+'"><button class="btn btn-outline btn-sm" type="submit">إثبات الرد</button></form>':'—')+'</td></tr>').join('');
  const advanceRows=(state.employeeAdvances||[]).map(x=>'<tr><td>#'+x.advance_number+'</td><td>'+esc(x.employees?.full_name||'—')+'</td><td>'+esc(x.advance_date)+'</td><td>'+money(x.amount)+'</td><td>'+money(x.repaid_amount)+'</td><td>'+money(Number(x.amount)-Number(x.repaid_amount))+'</td></tr>').join('');
  const commissionRows=(state.salesCommissions||[]).map(x=>'<tr><td>'+esc(x.employees?.full_name||'—')+'</td><td>'+esc(x.sales?.invoice_number||'—')+'</td><td>'+money(x.amount)+'</td><td>'+esc(x.status)+'</td></tr>').join('');
  const payrollRows=(state.payrollRuns||[]).map(x=>{
    const items=(state.payrollItems||[]).filter(i=>i.payroll_run_id===x.id);
    const paid=(state.payrollPayments||[]).filter(p=>p.payroll_run_id===x.id).reduce((n,p)=>n+Number(p.amount),0);
    return '<tr><td>#'+x.payroll_number+'</td><td>'+esc(x.payroll_name)+'</td><td>'+esc(x.payroll_date)+'</td><td>'+items.length+'</td><td>'+money(x.total_net)+'</td><td>'+money(paid)+'</td><td>'+esc(x.status)+'</td><td>'+(x.status==='draft'?'<form id="postPayrollForm" class="inline-form" data-run-id="'+esc(x.id)+'"><button class="btn btn-primary btn-sm" type="submit">ترحيل الرواتب</button></form><form id="cancelPayrollForm" class="inline-form" data-run-id="'+esc(x.id)+'"><button class="btn btn-outline btn-sm" type="submit">إلغاء المسودة</button></form>':x.status==='posted'?'<form id="payrollPaymentForm" class="form-grid" data-run-id="'+esc(x.id)+'"><input type="number" name="amount" min="0.01" max="'+Math.max(0,Number(x.total_net)-paid)+'" step="0.01" placeholder="المبلغ" required><select name="cash_account_id" required><option value="">الخزينة / البنك</option>'+cashOpts+'</select><input type="date" name="payment_date" required><button class="btn btn-outline btn-sm" type="submit">صرف</button></form>':'ملغى')+'</td></tr>';
  }).join('');
  const payrollEmployees=active.map(x=>'<div class="panel panel-subtle" data-payroll-employee="'+esc(x.id)+'"><strong>'+esc(x.full_name)+' — '+esc(x.employee_code)+'</strong><input type="hidden" name="employee_id" value="'+esc(x.id)+'"><div class="form-row"><div class="field"><label>الأساسي</label><input name="base_salary" type="number" min="0" step="0.01" value="'+Number(x.base_salary||0)+'"></div><div class="field"><label>بدلات</label><input name="allowances" type="number" min="0" step="0.01" value="0"></div><div class="field"><label>تأمين الموظف</label><input name="employee_insurance" type="number" min="0" step="0.01" value="0"></div></div><div class="form-row"><div class="field"><label>ضريبة</label><input name="tax_deduction" type="number" min="0" step="0.01" value="0"></div><div class="field"><label>استقطاعات أخرى</label><input name="other_deductions" type="number" min="0" step="0.01" value="0"></div><div class="field"><label>سداد سلفة</label><input name="advance_deduction" type="number" min="0" step="0.01" value="0"></div><div class="field"><label>تأمين الشركة</label><input name="employer_insurance" type="number" min="0" step="0.01" value="0"></div></div><small class="hint">العمولات المعلقة لهذا الموظف تُضاف تلقائيًا عند إنشاء كشف الرواتب.</small></div>').join('');
  return '<h2 class="page-title"><i class="fa-solid fa-users-gear"></i> الموارد البشرية والمرتبات</h2><p class="page-sub">إدارة ملفات الموظفين والحضور والإجازات والعهد والسلف والعمولات وكشوف الرواتب. نسب التأمين والضرائب لا تُفترض؛ تُدخل قيم الاستقطاع المعتمدة يدويًا.</p>'+
   '<div class="stats-grid"><div class="stat-card"><div class="stat-label">الموظفون النشطون</div><div class="stat-value">'+active.length+'</div></div><div class="stat-card"><div class="stat-label">طلبات إجازة معلقة</div><div class="stat-value">'+(state.employeeLeaveRequests||[]).filter(x=>x.status==='pending').length+'</div></div><div class="stat-card"><div class="stat-label">عهد لم تُرد</div><div class="stat-value">'+(state.employeeCustody||[]).filter(x=>x.status==='assigned').length+'</div></div><div class="stat-card"><div class="stat-label">سلف موظفين متبقية</div><div class="stat-value">'+money((state.employeeAdvances||[]).reduce((n,x)=>n+Number(x.amount)-Number(x.repaid_amount),0))+'</div></div></div>'+
   '<div class="panel"><div class="panel-title">ملفات الموظفين</div><form id="employeeForm" class="form-grid"><div class="form-row"><div class="field"><label>كود الموظف</label><input name="employee_code" required maxlength="30"></div><div class="field"><label>الاسم الكامل</label><input name="full_name" required maxlength="150"></div></div><div class="form-row"><div class="field"><label>الهاتف</label><input name="phone" maxlength="30"></div><div class="field"><label>البريد</label><input name="email" type="email" maxlength="150"></div></div><div class="form-row"><div class="field"><label>المسمى الوظيفي</label><input name="job_title" maxlength="100"></div><div class="field"><label>تاريخ التعيين</label><input name="hire_date" type="date" required></div><div class="field"><label>الراتب الأساسي</label><input name="base_salary" type="number" min="0" step="0.01" required></div></div><div class="field"><label>حساب دخول الموظف (اختياري)</label><select name="auth_user_id"><option value="">بدون ربط بحساب دخول</option>'+authUserOpts+'</select></div><div class="field"><label>ملاحظات</label><input name="notes" maxlength="200"></div><button class="btn btn-primary" type="submit">إضافة ملف موظف</button></form><div class="table-wrap mt-2"><table><thead><tr><th>الكود</th><th>الموظف</th><th>الوظيفة</th><th>الهاتف</th><th>الأساسي</th><th>التعيين</th><th>الحالة</th><th>الإجراء</th></tr></thead><tbody>'+(employeeRows||'<tr><td colspan="8">لا توجد ملفات موظفين</td></tr>')+'</tbody></table></div></div>'+
   '<div class="panel"><div class="panel-title">الحضور والانصراف</div><form id="attendanceForm" class="form-grid"><div class="form-row"><div class="field"><label>الموظف</label><select name="employee_id" required><option value="">اختر الموظف</option>'+empOpts+'</select></div><div class="field"><label>التاريخ</label><input type="date" name="attendance_date" required></div><div class="field"><label>الحالة</label><select name="attendance_status"><option value="present">حاضر</option><option value="late">متأخر</option><option value="absent">غائب</option><option value="leave">إجازة</option><option value="holiday">عطلة</option></select></div></div><div class="form-row"><div class="field"><label>الحضور</label><input type="datetime-local" name="check_in"></div><div class="field"><label>الانصراف</label><input type="datetime-local" name="check_out"></div></div><button class="btn btn-outline" type="submit">حفظ الحضور</button></form><div class="table-wrap mt-2"><table><thead><tr><th>التاريخ</th><th>الموظف</th><th>الحالة</th><th>الحضور</th><th>الانصراف</th></tr></thead><tbody>'+(attendanceRows||'<tr><td colspan="5">لا توجد سجلات حضور</td></tr>')+'</tbody></table></div></div>'+
   '<div class="panel"><div class="panel-title">الإجازات</div><form id="employeeLeaveForm" class="form-grid"><div class="form-row"><div class="field"><label>الموظف</label><select name="employee_id" required><option value="">اختر الموظف</option>'+empOpts+'</select></div><div class="field"><label>النوع</label><select name="leave_type"><option value="annual">سنوية</option><option value="sick">مرضية</option><option value="unpaid">بدون أجر</option><option value="emergency">طارئة</option><option value="other">أخرى</option></select></div><div class="field"><label>عدد الأيام</label><input name="days" type="number" min="0.5" step="0.5" required></div></div><div class="form-row"><div class="field"><label>من</label><input name="start_date" type="date" required></div><div class="field"><label>إلى</label><input name="end_date" type="date" required></div></div><div class="field"><label>السبب</label><input name="reason" maxlength="200"></div><button class="btn btn-outline" type="submit">تسجيل طلب إجازة</button></form><div class="table-wrap mt-2"><table><thead><tr><th>الموظف</th><th>النوع</th><th>الفترة</th><th>الأيام</th><th>السبب</th><th>الحالة</th><th>المراجعة</th></tr></thead><tbody>'+(leaveRows||'<tr><td colspan="7">لا توجد طلبات إجازة</td></tr>')+'</tbody></table></div></div>'+
   '<div class="panel"><div class="panel-title">العهد الوظيفية</div><form id="custodyForm" class="form-grid"><div class="form-row"><div class="field"><label>الموظف</label><select name="employee_id" required><option value="">اختر الموظف</option>'+empOpts+'</select></div><div class="field"><label>العهدة</label><input name="item_name" required maxlength="120"></div></div><div class="form-row"><div class="field"><label>تاريخ التسليم</label><input name="assigned_date" type="date" required></div><div class="field"><label>القيمة التقديرية</label><input name="estimated_value" type="number" min="0" step="0.01"></div></div><div class="field"><label>الوصف</label><input name="description" maxlength="200"></div><button class="btn btn-outline" type="submit">تسجيل عهدة</button></form><div class="table-wrap mt-2"><table><thead><tr><th>رقم</th><th>الموظف</th><th>العهدة</th><th>القيمة</th><th>التسليم</th><th>الحالة</th><th>الإجراء</th></tr></thead><tbody>'+(custodyRows||'<tr><td colspan="7">لا توجد عهد</td></tr>')+'</tbody></table></div></div>'+
   '<div class="panel"><div class="panel-title">سلف الموظفين وعمولات المبيعات</div><form id="employeeAdvanceForm" class="form-grid"><div class="form-row"><div class="field"><label>الموظف</label><select name="employee_id" required><option value="">اختر الموظف</option>'+empOpts+'</select></div><div class="field"><label>التاريخ</label><input type="date" name="advance_date" required></div></div><div class="form-row"><div class="field"><label>المبلغ</label><input type="number" name="amount" min="0.01" step="0.01" required></div><div class="field"><label>الخزينة / البنك</label><select name="cash_account_id" required><option value="">اختر الحساب</option>'+cashOpts+'</select></div></div><button class="btn btn-outline" type="submit">تسجيل سلفة وترحيلها</button></form><form id="salesCommissionForm" class="form-grid mt-2"><div class="form-row"><div class="field"><label>الموظف</label><select name="employee_id" required><option value="">اختر الموظف</option>'+empOpts+'</select></div><div class="field"><label>فاتورة البيع</label><select name="sale_id" required><option value="">اختر الفاتورة</option>'+salesOpts+'</select></div><div class="field"><label>العمولة</label><input type="number" name="amount" min="0.01" step="0.01" required></div></div><button class="btn btn-outline" type="submit">تسجيل عمولة</button></form><div class="table-wrap mt-2"><table><thead><tr><th>الموظف</th><th>الفاتورة</th><th>العمولة</th><th>الحالة</th></tr></thead><tbody>'+(commissionRows||'<tr><td colspan="4">لا توجد عمولات</td></tr>')+'</tbody></table></div><div class="table-wrap mt-2"><table><thead><tr><th>رقم السلفة</th><th>الموظف</th><th>التاريخ</th><th>القيمة</th><th>المسدد</th><th>المتبقي</th></tr></thead><tbody>'+(advanceRows||'<tr><td colspan="6">لا توجد سلف</td></tr>')+'</tbody></table></div></div>'+
   '<div class="panel"><div class="panel-title">كشوف الرواتب والتأمينات</div><p class="hint">أدخل المبالغ المعتمدة لكل موظف. العمولة تُجمع من العمولات المعلقة. لا توجد نسب تأمين أو ضرائب قانونية مضمّنة تلقائيًا. بعد ترحيل الكشف يُنشأ قيد استحقاق الرواتب، ثم تسجل دفعات الصرف منفصلة.</p><form id="payrollRunForm" class="form-grid"><div class="form-row"><div class="field"><label>الفترة المالية</label><select name="period_id" required><option value="">اختر الفترة</option>'+periods+'</select></div><div class="field"><label>اسم الكشف</label><input name="payroll_name" required maxlength="120"></div><div class="field"><label>تاريخ الترحيل</label><input type="date" name="payroll_date" required></div></div>'+(payrollEmployees||'<p class="empty">أضف موظفين نشطين أولًا.</p>')+'<button class="btn btn-primary" type="submit" '+(!active.length?'disabled':'')+'>إنشاء كشف الرواتب كمسودة</button></form><div class="table-wrap mt-2"><table><thead><tr><th>رقم</th><th>الكشف</th><th>التاريخ</th><th>الموظفون</th><th>صافي المستحق</th><th>المدفوع</th><th>الحالة</th><th>الترحيل/الصرف</th></tr></thead><tbody>'+(payrollRows||'<tr><td colspan="8">لا توجد كشوف رواتب</td></tr>')+'</tbody></table></div></div>';
}

function pageFinanceTools() {
  const u=currentUser();
  const managerAccess=hasRole('admin','manager','owner');
  const canManage=managerAccess||hasPermission('finance_manage');
  if(!u||!(managerAccess||hasPermission('accounting_view')||hasPermission('finance_manage')))return pageNoPermission();
  const accounts=state.financeAllAccounts||[],cash=state.cashAccounts||[],banks=cash.filter(x=>x.account_kind==='bank');
  const accountOpts=accounts.map(a=>'<option value="'+esc(a.id)+'">'+esc(a.code)+' — '+esc(a.name)+'</option>').join('');
  const assetOpts=accounts.filter(a=>a.account_type==='asset'&&!['1000','1010','1020','1100','1200','1300','1500','1510'].includes(a.code)).map(a=>'<option value="'+esc(a.id)+'">'+esc(a.code)+' — '+esc(a.name)+'</option>').join('');
  const assetAccountOpts=accounts.filter(a=>a.account_type==='asset').map(a=>'<option value="'+esc(a.id)+'">'+esc(a.code)+' — '+esc(a.name)+'</option>').join('');
  const expenseOpts=accounts.filter(a=>a.account_type==='expense').map(a=>'<option value="'+esc(a.id)+'">'+esc(a.code)+' — '+esc(a.name)+'</option>').join('');
  const liabilityOpts=accounts.filter(a=>a.account_type==='liability').map(a=>'<option value="'+esc(a.id)+'">'+esc(a.code)+' — '+esc(a.name)+'</option>').join('');
  const cashOpts=cash.map(a=>'<option value="'+esc(a.id)+'">'+esc(a.name)+' — '+(a.account_kind==='bank'?'بنك':'خزينة')+'</option>').join('');
  const bankOpts=banks.map(a=>'<option value="'+esc(a.id)+'">'+esc(a.name)+'</option>').join('');
  const supplierOpts=(state.suppliers||[]).filter(s=>s.is_active).map(s=>'<option value="'+esc(s.id)+'">'+esc(s.name)+'</option>').join('');
  const billOpts=(state.supplierBills||[]).filter(b=>b.balanceDue>0).map(b=>'<option value="'+esc(b.id)+'">'+esc(b.bill_number)+' — '+esc(b.supplierName)+' — متبقي '+money(b.balanceDue)+'</option>').join('');
  const periodRows=(state.fiscalPeriods||[]).map(p=>'<tr><td>'+esc(p.period_code)+'</td><td>'+esc(p.period_name)+'</td><td>'+esc(p.start_date)+' – '+esc(p.end_date)+'</td><td><span class="status-pill '+(p.status==='closed'?'completed':'pending')+'">'+(p.status==='closed'?'مقفلة':'مفتوحة')+'</span></td><td>'+(canManage&&p.status==='open'?'<form class="inline-form" id="closePeriodForm" data-period-id="'+esc(p.id)+'"><button class="btn btn-outline btn-sm" type="submit">إقفال الفترة</button></form>':'—')+'</td></tr>').join('');
  const centerRows=(state.costCenters||[]).map(x=>'<tr><td>'+esc(x.code)+'</td><td>'+esc(x.name)+'</td><td>'+esc(x.description||'—')+'</td><td>'+(x.is_active?'نشط':'متوقف')+'</td></tr>').join('');
  const openingRows=(state.openingBatches||[]).map(x=>'<tr><td>#'+x.batch_number+'</td><td>'+esc(x.effective_date)+'</td><td>'+esc(x.description)+'</td><td>'+esc(x.journal_entry_id||'—')+'</td></tr>').join('');
  const advanceRows=(state.supplierAdvances||[]).map(x=>'<tr><td>#'+x.advance_number+'</td><td>'+esc(x.suppliers?.name||'—')+'</td><td>'+esc(x.advance_date)+'</td><td>'+money(x.amount)+'</td><td>'+money(x.allocated_amount)+'</td><td>'+money(Number(x.amount)-Number(x.allocated_amount))+'</td></tr>').join('');
  const assetRows=(state.fixedAssets||[]).map(x=>'<tr><td>#'+x.asset_number+'</td><td>'+esc(x.asset_name)+'</td><td>'+money(x.cost)+'</td><td>'+money(x.accumulated_depreciation)+'</td><td>'+money(Number(x.cost)-Number(x.accumulated_depreciation))+'</td><td>'+esc(x.status==='active'?'نشط':'مستبعد')+'</td></tr>').join('');
  const chequeStatus={pending:'معلق',under_collection:'تحت التحصيل',cleared:'تم التحصيل/الصرف',bounced:'مرتد',cancelled:'ملغى'};
  const chequeRows=(state.cheques||[]).map(x=>'<tr><td>#'+x.cheque_number+'<br><small>'+esc(x.cheque_reference)+'</small></td><td>'+(x.cheque_type==='issued'?'صادر':'وارد')+'</td><td>'+esc(x.party_name)+'</td><td>'+money(x.amount)+'</td><td>'+esc(x.due_date)+'</td><td>'+esc(chequeStatus[x.status]||x.status)+'</td><td>'+(canManage&&!['cleared','bounced','cancelled'].includes(x.status)?'<form id="chequeStatusForm" class="inline-form" data-cheque-id="'+esc(x.id)+'"><select name="status"><option value="under_collection">تحت التحصيل</option><option value="cleared">تم التحصيل/الصرف</option><option value="bounced">مرتد</option><option value="cancelled">ملغى</option></select><button class="btn btn-outline btn-sm" type="submit">تحديث</button></form>':'—')+'</td></tr>').join('');
  const recRows=(state.bankReconciliations||[]).map(r=>{
    const ca=cash.find(x=>x.id===r.cash_account_id);
    const lines=(state.bankReconciliationLines||[]).filter(x=>x.reconciliation_id===r.id);
    const lineRows=lines.map(line=>{
      const matched=!!line.matched_journal_line_id;
      const options=(state.financeJournalLines||[]).filter(j=>{
        const je=Array.isArray(j.journal_entries)?j.journal_entries[0]:j.journal_entries;
        return ca&&j.account_id===ca.account_id&&je&&je.entry_date>=r.period_start&&je.entry_date<=r.period_end&&Math.abs((Number(j.debit)-Number(j.credit))-Number(line.amount))<0.006;
      }).map(j=>{const je=Array.isArray(j.journal_entries)?j.journal_entries[0]:j.journal_entries;return '<option value="'+esc(j.id)+'">'+esc(je.entry_date)+' — '+esc(je.description)+' — '+money(Number(j.debit)-Number(j.credit))+'</option>';}).join('');
      return '<tr><td>'+esc(line.statement_date)+'</td><td>'+esc(line.description)+'</td><td>'+money(line.amount)+'</td><td>'+(matched?'<span class="status-pill completed">مطابقة</span>':canManage?'<form id="bankMatchForm" class="inline-form" data-line-id="'+esc(line.id)+'"><select name="journal_line_id" required><option value="">اختر حركة الدفاتر</option>'+options+'</select><button class="btn btn-outline btn-sm" type="submit" '+(!options?'disabled':'')+'>مطابقة</button></form>':'غير مطابقة')+'</td></tr>';
    }).join('');
    return '<div class="panel"><div class="panel-title">تسوية #'+r.reconciliation_number+' — '+esc(ca?.name||'حساب بنكي')+' <span class="status-pill '+(r.status==='completed'?'completed':'pending')+'">'+(r.status==='completed'?'مكتملة':'مفتوحة')+'</span></div><p class="hint">'+esc(r.period_start)+' إلى '+esc(r.period_end)+' — رصيد كشف البنك: '+money(r.statement_ending_balance)+'</p>'+(lines.length?'<div class="table-wrap"><table><thead><tr><th>التاريخ</th><th>البيان</th><th>المبلغ</th><th>المطابقة</th></tr></thead><tbody>'+lineRows+'</tbody></table></div>':'<p class="empty">لم تُضف حركات كشف لهذا السجل.</p>')+(canManage&&r.status==='open'?'<form id="bankStatementLineForm" class="form-grid mt-2" data-reconciliation-id="'+esc(r.id)+'"><div class="form-row"><div class="field"><label>تاريخ الحركة</label><input type="date" name="statement_date" required></div><div class="field"><label>المبلغ (+ إيداع / − سحب)</label><input type="number" name="amount" step="0.01" required></div></div><div class="field"><label>البيان</label><input name="description" required maxlength="180"></div><div class="field"><label>المرجع</label><input name="reference_number" maxlength="100"></div><button class="btn btn-outline" type="submit">إضافة حركة كشف</button></form><form id="completeBankReconciliationForm" data-reconciliation-id="'+esc(r.id)+'" class="mt-2"><button class="btn btn-primary" type="submit">مطابقة وإقفال التسوية</button></form>':'')+'</div>';
  }).join('');
  const recurringRows=(state.recurringJournalTemplates||[]).map(t=>'<tr><td>'+esc(t.template_name)+'</td><td>'+({monthly:'شهري',quarterly:'ربع سنوي',yearly:'سنوي'}[t.frequency]||t.frequency)+'</td><td>'+esc(t.next_run_date)+'</td><td>'+(t.is_active?'نشط':'متوقف')+'</td><td>'+(canManage&&t.is_active?'<form id="recurringRunForm" class="inline-form" data-template-id="'+esc(t.id)+'"><input type="date" name="run_date" value="'+esc(t.next_run_date)+'" required><button class="btn btn-outline btn-sm" type="submit">ترحيل الموعد</button></form>':'—')+'</td></tr>').join('');
  const openCashSessions=(state.cashSessions||[]).filter(x=>x.status==='open');
  const cashSessionRows=(state.cashSessions||[]).map(x=>'<tr><td>#'+x.session_number+'</td><td>'+esc(x.cash_accounts?.name||'—')+'</td><td>'+esc(new Date(x.opened_at).toLocaleString('ar-EG'))+'</td><td>'+money(x.opening_balance)+'</td><td>'+money(x.expected_closing)+'</td><td>'+money(x.actual_closing)+'</td><td><span class="status-pill '+(x.status==='closed'?'completed':'pending')+'">'+(x.status==='closed'?'مقفلة':'مفتوحة')+'</span></td><td>'+(canManage&&x.status==='open'?'<form id="cashSessionCloseForm" class="inline-form" data-session-id="'+esc(x.id)+'"><input type="number" name="actual_closing" min="0" step="0.01" placeholder="الفعلي" required><button class="btn btn-outline btn-sm" type="submit">إقفال</button></form>':'—')+'</td></tr>').join('');
  const handoverRows=(state.cashHandovers||[]).map(x=>'<tr><td>#'+x.handover_number+'</td><td>'+esc(x.from_user_id)+'</td><td>'+esc(x.to_user_id)+'</td><td>'+money(x.amount)+'</td><td>'+esc(x.status)+'</td><td>'+(x.status==='pending'&&x.to_user_id===u.id?'<form id="handoverResponseForm" class="inline-form" data-handover-id="'+esc(x.id)+'"><button class="btn btn-outline btn-sm" name="accept" value="true" type="submit">استلام</button><button class="btn btn-outline btn-sm" name="accept" value="false" type="submit">رفض</button></form>':'—')+'</td></tr>').join('');
  const pettyRows=(state.pettyCashTransactions||[]).map(x=>'<tr><td>#'+x.transaction_number+'</td><td>'+esc(x.transaction_date)+'</td><td>'+esc(x.description)+'</td><td>'+money(x.amount)+'</td><td>'+esc(x.recipient||'—')+'</td><td>'+esc(x.accounting_accounts?.name||'—')+'</td></tr>').join('');
  const reversalRows=(state.journalReversals||[]).map(x=>'<tr><td>'+esc(x.original_journal_entry_id)+'</td><td>'+esc(x.reversal_journal_entry_id)+'</td><td>'+esc(x.reason)+'</td><td>'+esc(x.created_at?.slice(0,10)||'')+'</td></tr>').join('');
  const budgetRows=(state.financeBudgets||[]).map(x=>'<tr><td>#'+x.budget_number+'</td><td>'+esc(x.budget_name)+'</td><td>'+esc((state.fiscalPeriods||[]).find(p=>p.id===x.period_id)?.period_name||'—')+'</td><td>'+esc(x.status==='approved'?'معتمدة':'مسودة')+'</td><td>'+(canManage&&x.status==='draft'?'<form id="budgetApproveForm" class="inline-form" data-budget-id="'+esc(x.id)+'"><button class="btn btn-outline btn-sm" type="submit">اعتماد</button></form>':'—')+'</td></tr>').join('');
  const budgetActualRows=(state.financeBudgetVsActual||[]).map(x=>'<tr><td>'+esc(x.period_code)+'</td><td>'+esc(x.account_code)+' — '+esc(x.account_name)+'</td><td>'+money(x.budget_amount)+'</td><td>'+money(x.actual_amount)+'</td><td>'+money(x.variance)+'</td></tr>').join('');
  const accrualRows=(state.accrualSchedules||[]).map(x=>'<tr><td>#'+x.schedule_number+'</td><td>'+esc(x.schedule_name)+'</td><td>'+money(x.monthly_amount)+'</td><td>'+esc(x.next_run_date)+'</td><td>'+(x.is_active?'نشط':'متوقف')+'</td><td>'+(canManage&&x.is_active?'<form id="accrualRunForm" class="inline-form" data-schedule-id="'+esc(x.id)+'"><input type="date" name="run_date" value="'+esc(x.next_run_date)+'" required><button class="btn btn-outline btn-sm" type="submit">ترحيل</button></form>':'—')+'</td></tr>').join('');
  const agingRows=(state.agingReport||[]).map(x=>'<tr><td>'+(x.party_type==='customer'?'عميل':'مورد')+'</td><td>'+esc(x.party_name||'—')+'</td><td>'+esc(x.document_number)+'</td><td>'+esc(x.due_date||'غير محدد')+'</td><td>'+money(x.balance_due)+'</td><td>'+(x.days_overdue===null?'غير محسوب':x.days_overdue+' يوم')+'</td></tr>').join('');
  const cashBookRows=(state.cashBook||[]).map(x=>'<tr><td>'+esc(x.entry_date)+'</td><td>'+esc(x.cash_account_name)+'</td><td>#'+x.entry_number+'</td><td>'+esc(x.description)+'</td><td>'+money(x.debit)+'</td><td>'+money(x.credit)+'</td><td>'+money(x.running_balance)+'</td></tr>').join('');
  const openSessionOptions=openCashSessions.map(x=>'<option value="'+esc(x.id)+'">جلسة #'+x.session_number+' — '+esc(x.cash_accounts?.name||'')+'</option>').join('');
  const budgetPeriodOptions=(state.fiscalPeriods||[]).filter(x=>x.status==='open').map(x=>'<option value="'+esc(x.id)+'">'+esc(x.period_name)+'</option>').join('');
  const staffOptions=(get(DB.USERS)||[]).filter(x=>x.id&&x.id!==u.id).map(x=>'<option value="'+esc(x.id)+'">'+esc(x.name||x.email||x.id)+'</option>').join('');
  const pettyLimit=state.financeSettings?.petty_cash_limit||'';
  const taxRows=(state.taxRates||[]).map(t=>'<tr><td>'+esc(t.tax_code)+'</td><td>'+esc(t.tax_name)+'</td><td>'+Number(t.rate).toFixed(3)+'%</td><td>'+esc(t.effective_from)+(t.effective_to?' – '+esc(t.effective_to):'')+'</td><td>'+(t.is_active?'نشطة':'متوقفة')+'</td></tr>').join('');
  const unallocatedPaymentRows=(state.unallocatedSalePayments||[]).map(p=>'<tr><td>'+esc(p.sales?.invoice_number||'—')+'</td><td>'+esc(p.sales?.customer_name||'—')+'</td><td>'+esc(p.paid_at?.slice(0,10)||'')+'</td><td>'+money(p.amount)+'</td><td><form id="allocateSalePaymentForm" class="inline-form" data-payment-id="'+esc(p.id)+'"><select name="cash_account_id" required><option value="">اختر خزينة/بنك</option>'+cashOpts+'</select><button class="btn btn-outline btn-sm" type="submit">تسوية</button></form></td></tr>').join('');
  const unallocatedRefundRows=(state.unallocatedCustomerRefunds||[]).map(p=>'<tr><td>'+esc(p.clients?.display_name||'—')+'</td><td>'+esc(p.clients?.phone||'—')+'</td><td>'+esc(p.created_at?.slice(0,10)||'')+'</td><td>'+money(Math.abs(p.amount))+'</td><td><form id="allocateCustomerRefundForm" class="inline-form" data-transaction-id="'+esc(p.id)+'"><select name="cash_account_id" required><option value="">اختر خزينة/بنك</option>'+cashOpts+'</select><button class="btn btn-outline btn-sm" type="submit">تسوية</button></form></td></tr>').join('');
  const fs=state.financialStatements;
  const incomeRows=(fs?.income_statement?.accounts||[]).map(x=>'<tr><td>'+esc(x.code)+'</td><td>'+esc(x.name)+'</td><td>'+esc(x.account_type==='revenue'?'إيراد':'مصروف')+'</td><td>'+money(x.amount)+'</td></tr>').join('');
  const balanceRows=(fs?.balance_sheet?.accounts||[]).map(x=>'<tr><td>'+esc(x.code)+'</td><td>'+esc(x.name)+'</td><td>'+esc(x.account_type)+'</td><td>'+money(x.balance)+'</td></tr>').join('');
  const trialRows=(fs?.trial_balance||[]).map(x=>'<tr><td>'+esc(x.code)+'</td><td>'+esc(x.name)+'</td><td>'+money(x.debit)+'</td><td>'+money(x.credit)+'</td><td>'+money(x.net_debit)+'</td><td>'+money(x.net_credit)+'</td></tr>').join('');
  const financialReportsPanel='<div class="panel printable-panel"><div class="panel-title"><i class="fa-solid fa-chart-column"></i> القوائم المالية والتقارير المحاسبية</div><form id="financialStatementsForm" class="form-grid"><div class="form-row"><div class="field"><label>من تاريخ</label><input type="date" name="start_date" required></div><div class="field"><label>إلى تاريخ</label><input type="date" name="end_date" required></div><div class="field"><label>الميزانية حتى تاريخ</label><input type="date" name="as_of_date" required></div></div><button class="btn btn-primary" type="submit">إنشاء القوائم المالية</button></form>'+(fs?'<h4 class="mt-2">قائمة الدخل — '+esc(fs.period_start)+' إلى '+esc(fs.period_end)+'</h4><div class="stats-grid"><div class="stat-card"><div class="stat-label">الإيرادات</div><div class="stat-value">'+money(fs.income_statement.total_revenue)+'</div></div><div class="stat-card"><div class="stat-label">المصروفات</div><div class="stat-value">'+money(fs.income_statement.total_expenses)+'</div></div><div class="stat-card"><div class="stat-label">صافي الربح / الخسارة</div><div class="stat-value">'+money(fs.income_statement.net_income)+'</div></div></div><div class="table-wrap"><table><thead><tr><th>الحساب</th><th>الاسم</th><th>النوع</th><th>المبلغ</th></tr></thead><tbody>'+(incomeRows||'<tr><td colspan="4">لا توجد حركات دخل في الفترة</td></tr>')+'</tbody></table></div><h4 class="mt-2">الميزانية العمومية حتى '+esc(fs.as_of_date)+'</h4><div class="stats-grid"><div class="stat-card"><div class="stat-label">الأصول</div><div class="stat-value">'+money(fs.balance_sheet.assets)+'</div></div><div class="stat-card"><div class="stat-label">الالتزامات</div><div class="stat-value">'+money(fs.balance_sheet.liabilities)+'</div></div><div class="stat-card"><div class="stat-label">حقوق الملكية</div><div class="stat-value">'+money(fs.balance_sheet.total_equity_including_result)+'</div></div><div class="stat-card"><div class="stat-label">فرق الميزانية</div><div class="stat-value">'+money(fs.balance_sheet.difference)+'</div></div></div><div class="table-wrap"><table><thead><tr><th>الحساب</th><th>الاسم</th><th>النوع</th><th>الرصيد</th></tr></thead><tbody>'+(balanceRows||'<tr><td colspan="4">لا توجد أرصدة</td></tr>')+'</tbody></table></div><h4 class="mt-2">ميزان المراجعة حتى '+esc(fs.as_of_date)+'</h4><div class="table-wrap"><table><thead><tr><th>الحساب</th><th>الاسم</th><th>إجمالي مدين</th><th>إجمالي دائن</th><th>صافي مدين</th><th>صافي دائن</th></tr></thead><tbody>'+(trialRows||'<tr><td colspan="6">لا توجد حركات</td></tr>')+'</tbody></table></div>':'<p class="hint">حدد الفترة وتاريخ الميزانية لإظهار قائمة الدخل والميزانية العمومية وميزان المراجعة.</p>')+'</div>';
  const unallocatedPanel='<div class="panel"><div class="panel-title"><i class="fa-solid fa-money-bill-transfer"></i> تسوية المقبوضات وردود العملاء غير الموزعة</div><p class="hint">دفعات البيع وردود أرصدة العملاء القديمة أو المسجلة دون تحديد حساب نقدي تُرحّل مؤقتًا إلى حساب «متحصلات غير موزعة». اختر الخزينة أو البنك الفعلي لإنشاء قيد إعادة تصنيف دون تعديل القيد الأصلي.</p><h4>دفعات البيع</h4><div class="table-wrap"><table><thead><tr><th>الفاتورة</th><th>العميل</th><th>التاريخ</th><th>المبلغ</th><th>تحديد الحساب</th></tr></thead><tbody>'+(unallocatedPaymentRows||'<tr><td colspan="5">لا توجد دفعات غير موزعة</td></tr>')+'</tbody></table></div><h4 class="mt-2">رد أرصدة العملاء</h4><div class="table-wrap"><table><thead><tr><th>العميل</th><th>الهاتف</th><th>التاريخ</th><th>المبلغ</th><th>تحديد الحساب</th></tr></thead><tbody>'+(unallocatedRefundRows||'<tr><td colspan="5">لا توجد ردود غير موزعة</td></tr>')+'</tbody></table></div></div>';

  const openPeriods=(state.fiscalPeriods||[]).filter(x=>x.status==='open').map(x=>'<option value="'+esc(x.id)+'">'+esc(x.period_name)+' ('+esc(x.period_code)+')</option>').join('');
  const openRecs=(state.bankReconciliations||[]).filter(x=>x.status==='open').map(x=>'<option value="'+esc(x.id)+'">#'+x.reconciliation_number+' — '+esc(x.period_end)+'</option>').join('');
  const suppliersSummary=(state.supplierAdvances||[]).reduce((n,x)=>n+Number(x.amount)-Number(x.allocated_amount),0);
  const assetsSummary=(state.fixedAssets||[]).filter(x=>x.status==='active').reduce((n,x)=>n+Number(x.cost)-Number(x.accumulated_depreciation),0);
  return '<h2 class="page-title"><i class="fa-solid fa-building-columns"></i> مركز النظام المحاسبي</h2>'+
   '<p class="page-sub">إدارة الفترات والأرصدة الافتتاحية والسلف والأصول والتسويات والشيكات والقيود المتكررة والضرائب. كل الترحيلات تنشئ قيودًا مزدوجة متوازنة وتخضع لصلاحيات قاعدة البيانات.</p>'+
   '<div class="stats-grid"><div class="stat-card"><div class="stat-label">الفترات المفتوحة</div><div class="stat-value">'+(state.fiscalPeriods||[]).filter(x=>x.status==='open').length+'</div></div><div class="stat-card"><div class="stat-label">سلف الموردين غير المسواة</div><div class="stat-value">'+money(suppliersSummary)+'</div></div><div class="stat-card"><div class="stat-label">صافي قيمة الأصول النشطة</div><div class="stat-value">'+money(assetsSummary)+'</div></div><div class="stat-card"><div class="stat-label">الشيكات المعلقة</div><div class="stat-value">'+(state.cheques||[]).filter(x=>['pending','under_collection'].includes(x.status)).length+'</div></div></div>'+
   '<div class="panel"><div class="panel-title"><i class="fa-solid fa-calendar-check"></i> الفترات المحاسبية</div>'+(canManage?'<form id="fiscalPeriodForm" class="form-grid"><div class="form-row"><div class="field"><label>كود الفترة</label><input name="period_code" required placeholder="2026-12"></div><div class="field"><label>اسم الفترة</label><input name="period_name" required placeholder="ديسمبر 2026"></div></div><div class="form-row"><div class="field"><label>من</label><input type="date" name="start_date" required></div><div class="field"><label>إلى</label><input type="date" name="end_date" required></div></div><button class="btn btn-primary" type="submit">إنشاء فترة</button></form>':'')+'<div class="table-wrap mt-2"><table><thead><tr><th>الكود</th><th>الفترة</th><th>التواريخ</th><th>الحالة</th><th>الإجراء</th></tr></thead><tbody>'+(periodRows||'<tr><td colspan="5">لا توجد فترات بعد</td></tr>')+'</tbody></table></div></div>'+
   '<div class="panel"><div class="panel-title"><i class="fa-solid fa-scale-balanced"></i> الأرصدة الافتتاحية</div><p class="hint">أدخل الأرصدة الحقيقية المعتمدة فقط. يجب أن يتساوى إجمالي المدين مع إجمالي الدائن قبل الترحيل.</p>'+(canManage?'<form id="openingBalanceForm" class="form-grid"><div class="form-row"><div class="field"><label>تاريخ الأرصدة</label><input type="date" name="effective_date" required></div><div class="field"><label>وصف الدفعة</label><input name="description" required maxlength="180"></div></div>'+[1,2,3,4].map(n=>'<div class="form-row" data-opening-row><div class="field"><label>الحساب '+n+'</label><select name="account_id"><option value="">اختر الحساب</option>'+accountOpts+'</select></div><div class="field"><label>مدين</label><input type="number" name="debit" min="0" step="0.01" value="0"></div><div class="field"><label>دائن</label><input type="number" name="credit" min="0" step="0.01" value="0"></div></div>').join('')+'<button class="btn btn-primary" type="submit">ترحيل الأرصدة الافتتاحية</button></form>':'')+'<div class="table-wrap mt-2"><table><thead><tr><th>رقم</th><th>التاريخ</th><th>الوصف</th><th>القيد</th></tr></thead><tbody>'+(openingRows||'<tr><td colspan="4">لا توجد دفعات افتتاحية</td></tr>')+'</tbody></table></div></div>'+
   '<div class="panel"><div class="panel-title"><i class="fa-solid fa-bullseye"></i> مراكز التكلفة</div>'+(canManage?'<form id="costCenterForm" class="form-grid"><div class="form-row"><div class="field"><label>الكود</label><input name="code" required maxlength="30"></div><div class="field"><label>الاسم</label><input name="name" required maxlength="120"></div></div><div class="field"><label>الوصف</label><input name="description" maxlength="200"></div><button class="btn btn-outline" type="submit">إضافة مركز تكلفة</button></form>':'')+'<div class="table-wrap mt-2"><table><thead><tr><th>الكود</th><th>المركز</th><th>الوصف</th><th>الحالة</th></tr></thead><tbody>'+(centerRows||'<tr><td colspan="4">لا توجد مراكز تكلفة</td></tr>')+'</tbody></table></div></div>'+
   '<div class="panel"><div class="panel-title"><i class="fa-solid fa-hand-holding-dollar"></i> سلف الموردين وتسويتها</div>'+(canManage?'<form id="supplierAdvanceForm" class="form-grid"><div class="form-row"><div class="field"><label>المورد</label><select name="supplier_id" required><option value="">اختر المورد</option>'+supplierOpts+'</select></div><div class="field"><label>التاريخ</label><input type="date" name="advance_date" required></div></div><div class="form-row"><div class="field"><label>المبلغ</label><input type="number" name="amount" min="0.01" step="0.01" required></div><div class="field"><label>الخزينة / البنك</label><select name="cash_account_id" required><option value="">اختر الحساب</option>'+cashOpts+'</select></div></div><div class="form-row"><div class="field"><label>طريقة الدفع</label><select name="method"><option value="cash">نقدي</option><option value="bank_transfer">تحويل بنكي</option><option value="instapay">إنستاباي</option><option value="cheque">شيك</option><option value="other">أخرى</option></select></div><div class="field"><label>مرجع الدفع</label><input name="reference" maxlength="100"></div></div><button class="btn btn-primary" type="submit">تسجيل سلفة وترحيل قيدها</button></form><form id="supplierAdvanceAllocationForm" class="form-grid mt-2"><div class="form-row"><div class="field"><label>السلفة</label><select name="advance_id" required><option value="">اختر السلفة</option>'+(state.supplierAdvances||[]).filter(x=>Number(x.amount)>Number(x.allocated_amount)).map(x=>'<option value="'+esc(x.id)+'">#'+x.advance_number+' — '+esc(x.suppliers?.name||'')+' — متاح '+money(Number(x.amount)-Number(x.allocated_amount))+'</option>').join('')+'</select></div><div class="field"><label>فاتورة المورد</label><select name="bill_id" required><option value="">اختر الفاتورة</option>'+billOpts+'</select></div></div><div class="field"><label>قيمة التسوية</label><input name="amount" type="number" min="0.01" step="0.01" required></div><button class="btn btn-outline" type="submit">تسوية السلفة على الفاتورة</button></form>':'')+'<div class="table-wrap mt-2"><table><thead><tr><th>السلفة</th><th>المورد</th><th>التاريخ</th><th>القيمة</th><th>المسوى</th><th>المتبقي</th></tr></thead><tbody>'+(advanceRows||'<tr><td colspan="6">لا توجد سلف مسجلة</td></tr>')+'</tbody></table></div></div>'+
   '<div class="panel"><div class="panel-title"><i class="fa-solid fa-building"></i> الأصول الثابتة والإهلاك</div>'+(canManage?'<form id="fixedAssetForm" class="form-grid"><div class="form-row"><div class="field"><label>اسم الأصل</label><input name="asset_name" required maxlength="150"></div><div class="field"><label>التكلفة</label><input name="cost" type="number" min="0.01" step="0.01" required></div></div><div class="form-row"><div class="field"><label>حساب الأصل</label><select name="asset_account_id" required><option value="">اختر الحساب</option>'+assetAccountOpts+'</select></div><div class="field"><label>مجمع الإهلاك</label><select name="accum_account_id" required><option value="">اختر الحساب</option>'+assetAccountOpts+'</select></div></div><div class="form-row"><div class="field"><label>مصروف الإهلاك</label><select name="expense_account_id" required><option value="">اختر الحساب</option>'+expenseOpts+'</select></div><div class="field"><label>الخزينة / البنك</label><select name="cash_account_id" required><option value="">اختر الحساب</option>'+cashOpts+'</select></div></div><div class="form-row"><div class="field"><label>تاريخ الاقتناء</label><input type="date" name="acquisition_date" required></div><div class="field"><label>بداية الإهلاك</label><input type="date" name="depreciation_start_date" required></div></div><div class="form-row"><div class="field"><label>القيمة التخريدية</label><input name="salvage_value" type="number" min="0" step="0.01" value="0"></div><div class="field"><label>العمر الإنتاجي (شهر)</label><input name="useful_life_months" type="number" min="1" step="1" required></div></div><div class="field"><label>الوصف</label><input name="description" maxlength="200"></div><button class="btn btn-primary" type="submit">تسجيل الأصل وترحيل قيد الاقتناء</button></form><form id="depreciationForm" class="form-grid mt-2"><div class="field"><label>شهر الإهلاك</label><input type="date" name="period_date" required></div><button class="btn btn-outline" type="submit">احتساب وترحيل إهلاك الشهر</button></form>':'')+'<div class="table-wrap mt-2"><table><thead><tr><th>رقم</th><th>الأصل</th><th>التكلفة</th><th>مجمع الإهلاك</th><th>القيمة الدفترية</th><th>الحالة</th></tr></thead><tbody>'+(assetRows||'<tr><td colspan="6">لا توجد أصول ثابتة</td></tr>')+'</tbody></table></div></div>'+
   '<div class="panel"><div class="panel-title"><i class="fa-solid fa-building-columns"></i> تسوية الحسابات البنكية</div>'+(canManage?'<form id="bankReconciliationForm" class="form-grid"><div class="form-row"><div class="field"><label>الحساب البنكي</label><select name="cash_account_id" required><option value="">اختر البنك</option>'+bankOpts+'</select></div><div class="field"><label>رصيد كشف البنك الختامي</label><input name="statement_ending_balance" type="number" step="0.01" required></div></div><div class="form-row"><div class="field"><label>من</label><input name="period_start" type="date" required></div><div class="field"><label>إلى</label><input name="period_end" type="date" required></div></div><div class="field"><label>ملاحظات</label><input name="notes" maxlength="200"></div><button class="btn btn-primary" type="submit">بدء تسوية بنكية</button></form>':'')+(recRows||'<p class="empty">لا توجد تسويات بنكية.</p>')+'</div>'+
   '<div class="panel"><div class="panel-title"><i class="fa-solid fa-money-check-dollar"></i> سجل الشيكات</div>'+(canManage?'<form id="chequeForm" class="form-grid"><div class="form-row"><div class="field"><label>نوع الشيك</label><select name="cheque_type"><option value="received">وارد</option><option value="issued">صادر</option></select></div><div class="field"><label>رقم الشيك</label><input name="cheque_reference" required maxlength="80"></div></div><div class="form-row"><div class="field"><label>الطرف</label><input name="party_name" required maxlength="120"></div><div class="field"><label>البنك</label><input name="bank_name" maxlength="100"></div></div><div class="form-row"><div class="field"><label>الحساب المالي</label><select name="cash_account_id" required><option value="">اختر الحساب</option>'+cashOpts+'</select></div><div class="field"><label>المبلغ</label><input name="amount" type="number" min="0.01" step="0.01" required></div></div><div class="form-row"><div class="field"><label>تاريخ الإصدار</label><input name="issue_date" type="date" required></div><div class="field"><label>تاريخ الاستحقاق</label><input name="due_date" type="date" required></div></div><div class="field"><label>ملاحظات</label><input name="notes" maxlength="180"></div><button class="btn btn-primary" type="submit">إضافة الشيك</button></form>':'')+'<div class="table-wrap mt-2"><table><thead><tr><th>الرقم</th><th>النوع</th><th>الطرف</th><th>القيمة</th><th>الاستحقاق</th><th>الحالة</th><th>تحديث</th></tr></thead><tbody>'+(chequeRows||'<tr><td colspan="7">لا توجد شيكات مسجلة</td></tr>')+'</tbody></table></div></div>'+
   '<div class="panel"><div class="panel-title"><i class="fa-solid fa-repeat"></i> القيود المحاسبية المتكررة</div>'+(canManage?'<form id="recurringJournalForm" class="form-grid"><div class="form-row"><div class="field"><label>اسم القيد</label><input name="template_name" required maxlength="150"></div><div class="field"><label>التكرار</label><select name="frequency"><option value="monthly">شهري</option><option value="quarterly">ربع سنوي</option><option value="yearly">سنوي</option></select></div></div><div class="form-row"><div class="field"><label>بداية التكرار</label><input type="date" name="start_date" required></div><div class="field"><label>نهاية التكرار (اختياري)</label><input type="date" name="end_date"></div></div><div class="field"><label>الوصف</label><input name="description" maxlength="180"></div>'+[1,2,3,4].map(n=>'<div class="form-row" data-recurring-line><div class="field"><label>الحساب '+n+'</label><select name="account_id"><option value="">اختر الحساب</option>'+accountOpts+'</select></div><div class="field"><label>مدين</label><input type="number" name="debit" min="0" step="0.01" value="0"></div><div class="field"><label>دائن</label><input type="number" name="credit" min="0" step="0.01" value="0"></div></div>').join('')+'<button class="btn btn-primary" type="submit">حفظ القيد المتكرر</button></form>':'')+'<div class="table-wrap mt-2"><table><thead><tr><th>القيد</th><th>التكرار</th><th>الموعد التالي</th><th>الحالة</th><th>الترحيل</th></tr></thead><tbody>'+(recurringRows||'<tr><td colspan="5">لا توجد قوالب قيود متكررة</td></tr>')+'</tbody></table></div></div>'+
   '<div class="panel"><div class="panel-title"><i class="fa-solid fa-cash-register"></i> جلسات فتح وإقفال الخزينة اليومية</div>'+(canManage?'<form id="cashSessionOpenForm" class="form-grid"><div class="form-row"><div class="field"><label>الخزينة النقدية</label><select name="cash_account_id" required><option value="">اختر الخزينة</option>'+cash.filter(x=>x.account_kind==='cash').map(x=>'<option value="'+esc(x.id)+'">'+esc(x.name)+'</option>').join('')+'</select></div><div class="field"><label>الرصيد الفعلي الافتتاحي</label><input name="opening_balance" type="number" min="0" step="0.01" required></div></div><div class="field"><label>ملاحظات</label><input name="note" maxlength="180"></div><button class="btn btn-primary" type="submit">فتح جلسة خزينة</button></form>':'')+'<div class="table-wrap mt-2"><table><thead><tr><th>الجلسة</th><th>الخزينة</th><th>الفتح</th><th>افتتاحي</th><th>متوقع</th><th>فعلي</th><th>الحالة</th><th>الإقفال</th></tr></thead><tbody>'+(cashSessionRows||'<tr><td colspan="8">لا توجد جلسات خزينة</td></tr>')+'</tbody></table></div></div>'+
   '<div class="panel"><div class="panel-title"><i class="fa-solid fa-handshake"></i> تسليم النقدية بين الكاشير والمحاسب</div>'+(canManage?'<form id="cashHandoverForm" class="form-grid"><div class="form-row"><div class="field"><label>جلسة الخزينة المفتوحة</label><select name="session_id" required><option value="">اختر الجلسة</option>'+openSessionOptions+'</select></div><div class="field"><label>المستلم</label><select name="to_user_id" required><option value="">اختر الموظف</option>'+staffOptions+'</select></div></div><div class="field"><label>المبلغ المسلم</label><input type="number" name="amount" min="0.01" step="0.01" required></div><div class="field"><label>ملاحظات</label><input name="notes" maxlength="180"></div><button class="btn btn-outline" type="submit">تسجيل تسليم النقدية</button></form>':'')+'<div class="table-wrap mt-2"><table><thead><tr><th>التسليم</th><th>من (معرف)</th><th>إلى (معرف)</th><th>المبلغ</th><th>الحالة</th><th>الإجراء</th></tr></thead><tbody>'+(handoverRows||'<tr><td colspan="6">لا توجد عمليات تسليم</td></tr>')+'</tbody></table></div></div>'+
   '<div class="panel"><div class="panel-title"><i class="fa-solid fa-wallet"></i> المصروفات النثرية</div>'+(canManage?'<form id="pettyCashLimitForm" class="form-grid"><div class="field"><label>الحد الأقصى للحركة الواحدة</label><input type="number" name="limit" min="0.01" step="0.01" value="'+esc(pettyLimit)+'" required></div><button class="btn btn-outline" type="submit">حفظ حد المصروفات النثرية</button></form><form id="pettyCashForm" class="form-grid mt-2"><div class="form-row"><div class="field"><label>التاريخ</label><input type="date" name="transaction_date" required></div><div class="field"><label>المبلغ</label><input type="number" name="amount" min="0.01" step="0.01" required></div></div><div class="field"><label>البيان</label><input name="description" required maxlength="180"></div><div class="form-row"><div class="field"><label>حساب المصروف</label><select name="expense_account_id" required><option value="">اختر الحساب</option>'+expenseOpts+'</select></div><div class="field"><label>الخزينة النقدية</label><select name="cash_account_id" required><option value="">اختر الخزينة</option>'+cash.filter(x=>x.account_kind==='cash').map(x=>'<option value="'+esc(x.id)+'">'+esc(x.name)+'</option>').join('')+'</select></div></div><div class="form-row"><div class="field"><label>المستلم</label><input name="recipient" maxlength="120"></div><div class="field"><label>مرجع</label><input name="reference" maxlength="100"></div></div><button class="btn btn-primary" type="submit">تسجيل المصروف النثري وترحيله</button></form>':'')+'<div class="table-wrap mt-2"><table><thead><tr><th>رقم</th><th>التاريخ</th><th>البيان</th><th>المبلغ</th><th>المستلم</th><th>الحساب</th></tr></thead><tbody>'+(pettyRows||'<tr><td colspan="6">لا توجد مصروفات نثرية</td></tr>')+'</tbody></table></div></div>'+
   '<div class="panel"><div class="panel-title"><i class="fa-solid fa-rotate-left"></i> عكس القيود المحاسبية</div>'+(canManage?'<form id="reverseJournalForm" class="form-grid"><div class="field"><label>القيد الأصلي</label><select name="original_id" required><option value="">اختر القيد</option>'+(state.financeJournalEntries||[]).filter(x=>x.status==='posted'&&!(state.journalReversals||[]).some(r=>r.original_journal_entry_id===x.id)).map(x=>'<option value="'+esc(x.id)+'">#'+x.entry_number+' — '+esc(x.entry_date)+' — '+esc(x.description)+'</option>').join('')+'</select></div><div class="field"><label>سبب العكس</label><input name="reason" required maxlength="250"></div><button class="btn btn-outline" type="submit">إنشاء قيد عكسي</button></form>':'')+'<div class="table-wrap mt-2"><table><thead><tr><th>القيد الأصلي</th><th>القيد العكسي</th><th>السبب</th><th>التاريخ</th></tr></thead><tbody>'+(reversalRows||'<tr><td colspan="4">لا توجد قيود معكوسة</td></tr>')+'</tbody></table></div></div>'+
   '<div class="panel"><div class="panel-title"><i class="fa-solid fa-chart-column"></i> الموازنات التقديرية ومقارنة الفعلي</div>'+(canManage?'<form id="financeBudgetForm" class="form-grid"><div class="form-row"><div class="field"><label>الفترة المفتوحة</label><select name="period_id" required><option value="">اختر الفترة</option>'+budgetPeriodOptions+'</select></div><div class="field"><label>اسم الموازنة</label><input name="budget_name" required maxlength="120"></div></div>'+[1,2,3,4].map(n=>'<div class="form-row" data-budget-line><div class="field"><label>حساب إيراد/مصروف '+n+'</label><select name="account_id"><option value="">اختر الحساب</option>'+accounts.filter(a=>['expense','revenue'].includes(a.account_type)).map(a=>'<option value="'+esc(a.id)+'">'+esc(a.code)+' — '+esc(a.name)+'</option>').join('')+'</select></div><div class="field"><label>المبلغ المخطط</label><input type="number" name="budget_amount" min="0" step="0.01" value="0"></div></div>').join('')+'<button class="btn btn-primary" type="submit">حفظ الموازنة</button></form>':'')+'<div class="table-wrap mt-2"><table><thead><tr><th>رقم</th><th>الموازنة</th><th>الفترة</th><th>الحالة</th><th>الإجراء</th></tr></thead><tbody>'+(budgetRows||'<tr><td colspan="5">لا توجد موازنات</td></tr>')+'</tbody></table></div><div class="table-wrap mt-2"><table><thead><tr><th>الفترة</th><th>الحساب</th><th>المخطط</th><th>الفعلي</th><th>الانحراف</th></tr></thead><tbody>'+(budgetActualRows||'<tr><td colspan="5">لا توجد بيانات مقارنة</td></tr>')+'</tbody></table></div></div>'+
   '<div class="panel"><div class="panel-title"><i class="fa-solid fa-calendar-days"></i> المصروفات المستحقة والإيرادات المؤجلة (قيود دورية)</div>'+(canManage?'<form id="accrualForm" class="form-grid"><div class="form-row"><div class="field"><label>اسم الجدول</label><input name="schedule_name" required maxlength="150"></div><div class="field"><label>القيمة الشهرية</label><input name="monthly_amount" type="number" min="0.01" step="0.01" required></div></div><div class="form-row"><div class="field"><label>الحساب المدين</label><select name="debit_account_id" required><option value="">اختر الحساب</option>'+accountOpts+'</select></div><div class="field"><label>الحساب الدائن</label><select name="credit_account_id" required><option value="">اختر الحساب</option>'+accountOpts+'</select></div></div><div class="form-row"><div class="field"><label>بداية الاستحقاق</label><input type="date" name="start_date" required></div><div class="field"><label>النهاية (اختياري)</label><input type="date" name="end_date"></div></div><div class="field"><label>الوصف</label><input name="description" maxlength="180"></div><button class="btn btn-primary" type="submit">إنشاء جدول الاستحقاق</button></form>':'')+'<div class="table-wrap mt-2"><table><thead><tr><th>رقم</th><th>الجدول</th><th>شهريًا</th><th>الموعد التالي</th><th>الحالة</th><th>ترحيل</th></tr></thead><tbody>'+(accrualRows||'<tr><td colspan="6">لا توجد جداول استحقاق</td></tr>')+'</tbody></table></div></div>'+
   '<div class="panel printable-panel"><div class="panel-title"><i class="fa-solid fa-hourglass-half"></i> تقرير أعمار ديون العملاء والموردين</div><p class="hint">لا يُحسب التأخير لفواتير العملاء التي لم يُحدد لها تاريخ استحقاق. الفاتورة دون تاريخ استحقاق لا تُفترض مستحقة بعد 30 يومًا.</p><div class="table-wrap"><table><thead><tr><th>النوع</th><th>الطرف</th><th>المستند</th><th>الاستحقاق</th><th>الرصيد</th><th>التأخير</th></tr></thead><tbody>'+(agingRows||'<tr><td colspan="6">لا توجد ديون مفتوحة</td></tr>')+'</tbody></table></div></div>'+
   '<div class="panel"><div class="panel-title"><i class="fa-solid fa-book"></i> دفتر حركة الخزائن والبنوك</div><div class="table-wrap"><table><thead><tr><th>التاريخ</th><th>الحساب</th><th>القيد</th><th>البيان</th><th>مدين</th><th>دائن</th><th>الرصيد الجاري</th></tr></thead><tbody>'+(cashBookRows||'<tr><td colspan="7">لا توجد حركات مالية مرحّلة</td></tr>')+'</tbody></table></div></div>'+
   '<div class="panel"><div class="panel-title"><i class="fa-solid fa-percent"></i> إعدادات الضرائب والرقم الضريبي</div><p class="hint">لا تُضبط نسبة ضريبية افتراضية. أدخل النسبة وتاريخ سريانها بعد اعتمادها من محاسب المعرض، ثم تُستخدم في ربط الفواتير لاحقًا.</p>'+(canManage?'<form id="taxRateForm" class="form-grid"><div class="form-row"><div class="field"><label>كود الضريبة</label><input name="tax_code" required maxlength="30"></div><div class="field"><label>اسم الضريبة</label><input name="tax_name" required maxlength="100"></div></div><div class="form-row"><div class="field"><label>النسبة %</label><input type="number" name="rate" min="0" max="100" step="0.0001" required></div><div class="field"><label>حساب الضريبة المستحقة</label><select name="tax_account_id"><option value="">بدون ربط حاليًا</option>'+liabilityOpts+'</select></div></div><div class="form-row"><div class="field"><label>سارية من</label><input type="date" name="effective_from" required></div><div class="field"><label>سارية حتى</label><input type="date" name="effective_to"></div></div><button class="btn btn-outline" type="submit">حفظ إعداد الضريبة</button></form>':'')+'<div class="table-wrap mt-2"><table><thead><tr><th>الكود</th><th>الضريبة</th><th>النسبة</th><th>السريان</th><th>الحالة</th></tr></thead><tbody>'+(taxRows||'<tr><td colspan="5">لم تُسجل نسب ضريبية بعد</td></tr>')+'</tbody></table></div></div>' + financialReportsPanel + unallocatedPanel;
}

function pageExpenses() {
  const u = currentUser();
  const managerAccess = hasRole('admin','manager','owner');
  if (!u || !(managerAccess || hasPermission('expenses_manage') || hasPermission('accounting_view'))) return pageNoPermission();
  const canManage = managerAccess || hasPermission('expenses_manage');
  const accounts = state.financeAccounts || [], cash = state.cashAccounts || [], expenses = state.expenses || [];
  const trial = state.trialBalance || [], balances = state.cashBalances || [];
  const total = expenses.reduce((sum,row)=>sum+Number(row.amount||0),0);
  const paid = expenses.reduce((sum,row)=>sum+Number(row.paid_amount||0),0);
  const accountOptions = accounts.filter(a=>a.code!=='6000'&&a.code!=='5000').map(a=>'<option value="'+esc(a.id)+'">'+esc(a.code)+' — '+esc(a.name)+'</option>').join('');
  const cashOptions = cash.map(a=>'<option value="'+esc(a.id)+'">'+esc(a.name)+' — '+(a.account_kind==='bank'?'بنك':'نقدية')+'</option>').join('');
  const rows = expenses.map(row=>{
    const due=Math.max(0,Number(row.amount||0)-Number(row.paid_amount||0));
    const account=Array.isArray(row.accounting_accounts)?row.accounting_accounts[0]:row.accounting_accounts;
    return '<tr><td>#'+(row.expense_number||'—')+'<br><small>'+esc(row.expense_date||'')+'</small></td><td><b>'+esc(row.description)+'</b><br><small>'+esc(row.vendor_name||'')+'</small></td><td>'+esc(account?.name||'—')+'</td><td>'+money(row.amount)+'</td><td>'+money(row.paid_amount)+'</td><td>'+money(due)+'</td><td><span class="status-pill '+(due>0?'pending':'completed')+'">'+(due>0?'مستحق':'مدفوع')+'</span>'+(canManage&&due>0?'<br><button class="btn btn-outline btn-sm mt-1" data-pay-expense="'+esc(row.id)+'" data-due="'+due+'">تسجيل سداد</button>':'')+'</td></tr>';
  }).join('');
  const trialRows = trial.map(row=>'<tr><td>'+esc(row.account_code)+'</td><td>'+esc(row.account_name)+'</td><td>'+esc(({asset:'أصول',liability:'التزامات',equity:'حقوق ملكية',revenue:'إيرادات',expense:'مصروفات'})[row.account_type]||row.account_type)+'</td><td>'+money(row.debit_balance)+'</td><td>'+money(row.credit_balance)+'</td></tr>').join('');
  const cashRows = balances.map(row=>'<tr><td>'+esc(row.cash_account_name)+'</td><td>'+(row.account_kind==='bank'?'بنك':'نقدية')+'</td><td>'+money(row.balance)+'</td></tr>').join('');
  const trialDebit=trial.reduce((n,row)=>n+Number(row.debit_balance||0),0);
  const trialCredit=trial.reduce((n,row)=>n+Number(row.credit_balance||0),0);
  return '<h2 class="page-title"><i class="fa-solid fa-money-bill-transfer"></i> النظام المالي</h2>' +
    '<p class="page-sub">سجل المصروفات، أرصدة الخزائن والبنوك، وميزان المراجعة من القيود المرحلة.</p>' +
    '<div class="stats-grid"><div class="stat-card"><div class="stat-label">إجمالي المصروفات المعروضة</div><div class="stat-value">'+money(total)+'</div></div><div class="stat-card"><div class="stat-label">المدفوع</div><div class="stat-value">'+money(paid)+'</div></div><div class="stat-card"><div class="stat-label">المتبقي</div><div class="stat-value">'+money(total-paid)+'</div></div></div>' +
    (managerAccess ? '<div class="panel"><div class="panel-title"><i class="fa-solid fa-building-columns"></i> إضافة خزينة أو حساب بنكي</div><form id="cashAccountForm" class="form-grid"><div class="form-row"><div class="field"><label>اسم الحساب</label><input name="name" required maxlength="120" placeholder="مثال: خزينة الفرع أو البنك الأهلي"></div><div class="field"><label>نوع الحساب</label><select name="kind" required><option value="cash">خزينة نقدية</option><option value="bank">حساب بنكي</option></select></div></div><button class="btn btn-outline" type="submit"><i class="fa-solid fa-plus"></i> إضافة الحساب</button></form><p class="hint">يُنشأ الحساب برصيد صفر. أدخل الأرصدة الافتتاحية فقط بعد اعتمادها محاسبيًا.</p></div>' : '') +
    (canManage ? '<div class="panel"><div class="panel-title"><i class="fa-solid fa-file-circle-plus"></i> تسجيل مصروف جديد</div><form id="expenseForm" class="form-grid">' +
      '<div class="form-row"><div class="field"><label>تاريخ المصروف</label><input name="expense_date" type="date" value="'+new Date().toISOString().slice(0,10)+'" required></div><div class="field"><label>بند المصروف</label><select name="expense_account_id" required><option value="">اختر البند</option>'+accountOptions+'</select></div></div>' +
      '<div class="field"><label>وصف المصروف</label><input name="description" maxlength="240" required placeholder="مثال: إيجار المعرض لشهر نوفمبر"></div>' +
      '<div class="form-row"><div class="field"><label>القيمة الإجمالية (ج.م)</label><input name="amount" type="number" min="0.01" step="0.01" required></div><div class="field"><label>المدفوع الآن (ج.م)</label><input name="paid_amount" type="number" min="0" step="0.01" value="0" required></div></div>' +
      '<div class="form-row"><div class="field"><label>الخزينة / البنك عند الدفع</label><select name="cash_account_id"><option value="">غير مدفوع الآن</option>'+cashOptions+'</select></div><div class="field"><label>طريقة الدفع</label><select name="payment_method"><option value="cash">نقدي</option><option value="bank_transfer">تحويل بنكي</option><option value="instapay">إنستاباي</option><option value="card">بطاقة</option><option value="cheque">شيك</option><option value="other">أخرى</option></select></div></div>' +
      '<div class="form-row"><div class="field"><label>اسم الجهة / المستفيد</label><input name="vendor_name" maxlength="160"></div><div class="field"><label>رقم الفاتورة / المرجع</label><input name="reference_number" maxlength="100"></div></div>' +
      '<div class="form-row"><div class="field"><label>تاريخ الاستحقاق</label><input name="due_date" type="date"></div><div class="field"><label>ملاحظات</label><input name="notes" maxlength="1000"></div></div>' +
      '<button class="btn btn-primary" type="submit"><i class="fa-solid fa-floppy-disk"></i> حفظ المصروف وترحيله محاسبيًا</button></form></div>' : '') +
    '<div class="panel printable-panel"><div class="panel-title"><i class="fa-solid fa-scale-balanced"></i> ميزان المراجعة</div>' +
    (trial.length ? '<div class="table-wrap"><table><thead><tr><th>كود الحساب</th><th>الحساب</th><th>النوع</th><th>رصيد مدين</th><th>رصيد دائن</th></tr></thead><tbody>'+trialRows+'</tbody><tfoot><tr><th colspan="3">الإجمالي</th><th>'+money(trialDebit)+'</th><th>'+money(trialCredit)+'</th></tr></tfoot></table></div>' : '<div class="empty"><p>لا توجد أرصدة محاسبية بعد.</p></div>')+
    '<p class="hint">يعرض الميزان القيود المرحلة فقط. لم تُسجل أرصدة افتتاحية بعد.</p></div>' +
    '<div class="panel printable-panel"><div class="panel-title"><i class="fa-solid fa-vault"></i> أرصدة الخزائن والبنوك</div>' +
    (balances.length ? '<div class="table-wrap"><table><thead><tr><th>الحساب</th><th>النوع</th><th>الرصيد</th></tr></thead><tbody>'+cashRows+'</tbody></table></div>' : '<div class="empty"><p>لا توجد خزائن أو حسابات بنكية مضافة.</p></div>')+
    '<p class="hint">الأرصدة محسوبة من القيود المرحلة، ولا تشمل أي مبالغ لم تُسجل في النظام.</p></div>' +
    '<div class="panel printable-panel"><div class="panel-title"><i class="fa-solid fa-list"></i> سجل المصروفات ('+expenses.length+')</div>' +
    (expenses.length ? '<div class="table-wrap"><table><thead><tr><th>رقم / تاريخ</th><th>البيان</th><th>البند</th><th>القيمة</th><th>المدفوع</th><th>المتبقي</th><th>الحالة / إجراء</th></tr></thead><tbody>'+rows+'</tbody></table></div>' : '<div class="empty"><i class="fa-solid fa-receipt"></i><p>لا توجد مصروفات مسجلة حتى الآن</p></div>')+'</div>' +
    '<div class="panel"><b>ملاحظة محاسبية:</b> لا توجد أرصدة افتتاحية، ولم يتم بعد ربط قيود المبيعات والمشتريات آليًا بهذا الدفتر؛ لذلك لا تعتبر هذه التقارير قوائم مالية مكتملة قبل استكمال الربط.</div>';
}
function pageSuppliers() {
  if (!currentUser() || currentUser().role !== 'admin') return pageNoPermission();
  const bikes = state.bikes.filter(b=>b.status!=='archived');
  const activeSuppliers = state.suppliers.filter(s=>s.is_active);
  const statusLabel = {ordered:'قيد التوريد',partially_received:'استلام جزئي',received:'مستلم بالكامل',cancelled:'ملغى'};
  const loadStatus = state.purchasingLoadStatus || 'idle';
  const loadMessage = loadStatus === 'loading' ? 'جارٍ تحميل بيانات الموردين والفواتير…'
    : loadStatus === 'loaded' ? ''
    : loadStatus === 'forbidden' ? 'تعذر تحميل البيانات: الحساب الحالي لا يملك صلاحية المدير.'
    : loadStatus === 'unavailable' ? 'تعذر الاتصال بقاعدة البيانات؛ لم تُحمّل بيانات الموردين.'
    : loadStatus === 'partial' ? 'لم تكتمل قراءة بعض بيانات الشراء: '+(state.purchasingLoadErrors||[]).join('، ')
    : loadStatus === 'error' ? 'تعذر تحميل بيانات الشراء: '+(state.purchasingLoadErrors||[]).join('، ')
    : 'بيانات الموردين لم تُحمّل بعد.';
  const loadNotice = loadStatus === 'loaded' ? '' : `<div class="panel alert alert-warning" role="status" data-purchasing-load-status="${esc(loadStatus)}"><b>${esc(loadMessage)}</b> ${loadStatus === 'loading' ? '' : '<button class="btn btn-outline btn-sm" type="button" data-retry-purchasing>إعادة تحميل البيانات</button>'}</div>`;
  return `
    <h2 class="page-title"><i class="fa-solid fa-truck-ramp-box"></i> الموردون والتوريد</h2>
    <p class="page-sub">تسجيل الموردين وأوامر التوريد واستلام الكميات مع تحديث المخزون وسجل الحركة داخل معاملة واحدة.</p>
    ${loadNotice}
    <div class="panel">
      <div class="panel-title"><i class="fa-solid fa-user-plus"></i> إضافة مورد</div>
      <form id="supplierForm" class="form-grid">
        <div class="form-row">
          <div class="field"><label>اسم المورد</label><input name="name" maxlength="160" required></div>
          <div class="field"><label>الهاتف</label><input name="phone" maxlength="32" type="tel"></div>
        </div>
        <div class="form-row">
          <div class="field"><label>البريد الإلكتروني</label><input name="email" maxlength="254" type="email"></div>
          <div class="field"><label>العنوان</label><input name="address" maxlength="500"></div>
        </div>
        <div class="field"><label>ملاحظات</label><textarea name="notes" rows="2" maxlength="1000"></textarea></div>
        <button class="btn btn-primary" type="submit">حفظ المورد</button>
      </form>
    </div>
    <div class="panel">
      <div class="panel-title"><i class="fa-solid fa-file-circle-plus"></i> إنشاء أمر توريد</div>
      ${activeSuppliers.length && bikes.length ? `
      <form id="purchaseOrderForm" class="form-grid">
        <div class="field"><label>المورد</label><select name="supplier_id" required><option value="">اختر المورد</option>${activeSuppliers.map(s=>`<option value="${esc(s.id)}">${esc(s.name)}</option>`).join('')}</select></div>
        <div id="purchaseOrderRows" class="form-grid">
          <div class="purchase-order-row form-row">
            <div class="field"><label>الدراجة / الصنف</label><select name="motorcycle_id" required><option value="">اختر الصنف</option>${bikes.map(b=>`<option value="${esc(b.id)}">${esc(b.name)} — ${esc(b.model)}</option>`).join('')}</select></div>
            <div class="field"><label>الكمية المطلوبة</label><input name="quantity" type="number" min="1" max="10000" value="1" required></div>
            <div class="field"><label>تكلفة الوحدة (ج.م)</label><input name="unit_cost" type="number" min="0" step="0.01" required></div>
            <div class="field"><label>إجراء</label><button class="btn btn-outline btn-sm" type="button" data-remove-purchase-row disabled>حذف البند</button></div>
          </div>
        </div>
        <button class="btn btn-outline btn-sm" type="button" id="addPurchaseOrderRow"><i class="fa-solid fa-plus"></i> إضافة صنف آخر</button>
        <div class="field"><label>ملاحظات أمر التوريد</label><textarea name="notes" rows="2" maxlength="1000"></textarea></div>
        <small class="hint">يمكن إضافة حتى 20 صنفًا مختلفًا في الأمر. لا يزيد المخزون عند إنشاء الأمر؛ الزيادة تحدث فقط عند تسجيل الاستلام.</small>
        <button class="btn btn-primary" type="submit">إنشاء أمر التوريد</button>
      </form>` : '<div class="empty">أضف موردًا وصنفًا في الكتالوج أولًا لإنشاء أمر توريد.</div>'}
    </div>
    <div class="panel">
      <div class="panel-title"><i class="fa-solid fa-file-invoice-dollar"></i> تسجيل فاتورة مورد</div>
      ${activeSuppliers.length ? `<form id="supplierBillForm" class="form-grid">
        <div class="form-row">
          <div class="field"><label>المورد</label><select name="supplier_id" required><option value="">اختر المورد</option>${activeSuppliers.map(s=>'<option value="'+esc(s.id)+'">'+esc(s.name)+'</option>').join('')}</select></div>
          <div class="field"><label>رقم فاتورة المورد</label><input name="bill_number" maxlength="100" required></div>
        </div>
        <div class="form-row">
          <div class="field"><label>تاريخ الفاتورة</label><input name="bill_date" type="date" value="${new Date().toISOString().slice(0,10)}" required></div>
          <div class="field"><label>تاريخ الاستحقاق (اختياري)</label><input name="due_date" type="date"></div>
        </div>
        <div class="form-row">
          <div class="field"><label>أمر التوريد المرتبط</label><select id="supplierBillPurchaseOrder" name="purchase_order_id"><option value="">بدون أمر توريد — بند مباشر فقط</option>${state.purchaseOrders.filter(o=>o.status!=='cancelled').map(o=>'<option value="'+esc(o.id)+'">'+esc(o.order_number)+' — '+esc(o.supplierName)+'</option>').join('')}</select></div>
          <div class="field"><label>إجمالي الفاتورة (ج.م)</label><input name="total_amount" type="number" min="0.01" step="0.01" readonly required></div>
        </div>
        <div class="panel-subtitle">بنود الاستلام المرتبطة بأمر التوريد</div>
        <div id="supplierBillLines" class="form-grid"><small class="hint">اختر أمر التوريد لعرض بنود الاستلام والوحدات التي لم تُفوتر بعد.</small></div>
        <div class="supplier-bill-direct-line">
          <label><input type="checkbox" name="direct_line_enabled"> إضافة بند مباشر (رسوم أو فرق غير مرتبط بوحدة مستلمة)</label>
          <div class="form-row">
            <div class="field"><label>وصف البند المباشر</label><input name="direct_description" maxlength="500" disabled></div>
            <div class="field"><label>قيمة البند (ج.م)</label><input name="direct_amount" type="number" min="0.01" step="0.01" disabled></div>
          </div>
        </div>
        <div class="field"><label>ملاحظات</label><textarea name="notes" rows="2" maxlength="1000"></textarea></div>
        <small class="hint">يجب أن يساوي إجمالي الفاتورة مجموع البنود. كل كمية مخزون تُربط بوحدات فعلية من الاستلام، ولا يمكن فوترة الوحدة مرتين.</small>
        <button class="btn btn-primary" type="submit">حفظ فاتورة المورد</button>
      </form>` : '<div class="empty">أضف موردًا أولًا.</div>'}
    </div>
    <div class="panel">
      <div class="panel-title"><i class="fa-solid fa-scale-balanced"></i> أرصدة الموردين</div>
      ${state.suppliers.length ? `<div class="table-wrap"><table><thead><tr><th>المورد</th><th>إجمالي الفواتير</th><th>المدفوع</th><th>المتبقي بعد المرتجعات</th><th>رصيد دائن للمورد</th></tr></thead><tbody>${state.suppliers.map(s=>{const bills=state.supplierBills.filter(b=>b.supplier_id===s.id);const total=bills.reduce((n,b)=>n+Number(b.total_amount),0);const paid=bills.reduce((n,b)=>n+b.amountPaid,0);const credits=bills.reduce((n,b)=>n+b.creditAmount,0);return '<tr><td><b>'+esc(s.name)+'</b></td><td>'+money(total)+'</td><td>'+money(paid)+'</td><td><b>'+money(Math.max(0,total-paid-credits))+'</b></td><td>'+money(Math.max(0,paid+credits-total))+'</td></tr>';}).join('')}</tbody></table></div>` : '<div class="empty">لا يوجد موردون.</div>'}
    </div>
    <div class="panel">
      <div class="panel-title"><i class="fa-solid fa-receipt"></i> فواتير ومدفوعات الموردين (${state.supplierBills.length})</div>
      ${state.supplierBills.length ? `<div class="table-wrap"><table><thead><tr><th>رقم الفاتورة</th><th>المورد</th><th>التاريخ</th><th>الإجمالي</th><th>المدفوع</th><th>خصم المرتجعات</th><th>المتبقي</th><th>إجراء</th></tr></thead><tbody>${state.supplierBills.map(b=>'<tr><td><b>'+esc(b.bill_number)+'</b></td><td>'+esc(b.supplierName)+'</td><td>'+esc(b.bill_date)+'</td><td>'+money(b.total_amount)+'</td><td>'+money(b.amountPaid)+'</td><td>'+money(b.creditAmount)+'</td><td><b>'+money(b.balanceDue)+'</b></td><td>'+(b.balanceDue>0?'<button class="btn btn-outline btn-sm" data-pay-supplier-bill="'+esc(b.id)+'">تسجيل دفعة</button>':'<span class="status-pill">مسددة</span>')+'</td></tr>').join('')}</tbody></table></div>` : '<div class="empty">لا توجد فواتير موردين مسجلة بعد.</div>'}
    </div>
    <div class="panel">
      <div class="panel-title"><i class="fa-solid fa-money-bill-transfer"></i> سجل مدفوعات الموردين (${state.supplierPayments.length})</div>
      ${state.supplierPayments.length ? `<div class="table-wrap"><table><thead><tr><th>رقم الدفعة</th><th>المورد</th><th>الفاتورة</th><th>التاريخ</th><th>الطريقة</th><th>المرجع</th><th>القيمة</th></tr></thead><tbody>${state.supplierPayments.map(p=>{const bill=state.supplierBills.find(b=>b.id===p.supplier_bill_id);const method={cash:'نقدي',bank_transfer:'تحويل بنكي',instapay:'إنستاباي',cheque:'شيك',other:'أخرى'}[p.method]||p.method;return '<tr><td>#'+esc(p.payment_number)+'</td><td>'+esc(bill?.supplierName||'—')+'</td><td>'+esc(bill?.bill_number||'—')+'</td><td>'+esc(new Date(p.paid_at).toLocaleString('ar-EG'))+'</td><td>'+esc(method)+'</td><td>'+esc(p.reference||'—')+'</td><td><b>'+money(p.amount)+'</b></td></tr>';}).join('')}</tbody></table></div>` : '<div class="empty">لا توجد مدفوعات مسجلة.</div>'}
    </div>
    <div class="panel">
      <div class="panel-title"><i class="fa-solid fa-truck"></i> الموردون المسجلون (${state.suppliers.length})</div>
      ${state.suppliers.length ? `<div class="table-wrap"><table><thead><tr><th>المورد</th><th>الهاتف</th><th>البريد</th><th>العنوان</th><th>الحالة</th></tr></thead><tbody>${state.suppliers.map(s=>`<tr><td>${esc(s.name)}</td><td>${esc(s.phone||'—')}</td><td>${esc(s.email||'—')}</td><td>${esc(s.address||'—')}</td><td>${s.is_active?'نشط':'موقوف'}</td></tr>`).join('')}</tbody></table></div>` : '<div class="empty">لا يوجد موردون مسجلون.</div>'}
    </div>
    <div class="panel">
      <div class="panel-title"><i class="fa-solid fa-clipboard-list"></i> أوامر التوريد (${state.purchaseOrders.length})</div>
      ${state.purchaseOrders.length ? `<div class="table-wrap"><table><thead><tr><th>رقم الأمر</th><th>المورد</th><th>الصنف</th><th>مطلوب</th><th>مستلم</th><th>الحالة</th><th>الاستلام</th></tr></thead><tbody>
      ${state.purchaseOrders.map(o=>{const ordered=o.items.reduce((n,it)=>n+Number(it.quantity_ordered||0),0);const received=o.items.reduce((n,it)=>n+Number(it.quantity_received||0),0);const remaining=o.items.filter(it=>Number(it.quantity_ordered)>Number(it.quantity_received)).length;return `<tr><td><b>${esc(o.order_number)}</b></td><td>${esc(o.supplierName)}</td><td>${o.items.length} أصناف</td><td>${ordered}</td><td>${received}</td><td><span class="status-pill">${esc(statusLabel[o.status]||o.status)}</span></td><td>${remaining>0&&o.status!=='cancelled'?`<button class="btn btn-outline btn-sm" data-receive-order="${esc(o.id)}">تسجيل استلام (${remaining})</button>`:'—'}${o.receiptItems?.length?'<button class=btn data-return-order='+esc(o.id)+'>مرتجع</button>':''}</td></tr>`}).join('')}
      </tbody></table></div>` : '<div class="empty">لا توجد أوامر توريد حتى الآن.</div>'}
    </div>`;
}

function pageTarget() {
  const u = currentUser();
  if (!u) return pageLogin();
  return `<h2 class="page-title"><i class="fa-solid fa-bullseye"></i> تارجت الشهر</h2><div class="panel"><p>تقارير الأهداف والمبيعات غير مفعّلة حتى تُحفظ بيانات المبيعات في Supabase.</p></div>`;
}


function getMarketPrices() {
  try { return JSON.parse(localStorage.getItem('kh_market_prices') || '{}') || {}; } catch { return {}; }
}
function setMarketPrice(bikeId, price) {
  const map = getMarketPrices();
  if (price === '' || price == null || Number.isNaN(Number(price))) delete map[bikeId];
  else map[bikeId] = Number(price);
  localStorage.setItem('kh_market_prices', JSON.stringify(map));
}
function autoBarcodeFromVin(vin) {
  const v = String(vin || '').replace(/[^A-Za-z0-9]/g, '').toUpperCase();
  if (v.length >= 8) return 'BC-' + v.slice(-10);
  return 'BC-' + Date.now().toString(36).toUpperCase();
}

function pageInventory() {
  const u = currentUser();
  if (!u || !['staff', 'admin', 'manager', 'owner'].includes(u.role)) return pageLogin();
  if (u.role === 'staff' && !hasAnyPermission('catalog_view', 'catalog_manage')) return pageNoPermission();
  const bikes = (get(DB.BIKES) || []).filter((b) => !b.is_demo);
  const costMap = new Map((state.inventoryCosts || []).map((x) => [x.motorcycle_id, x]));
  const marketMap = getMarketPrices();
  const canEditPrice = hasRole('admin', 'manager', 'owner') || hasPermission('catalog_manage');
  const canSales = hasRole('admin', 'manager', 'owner') || hasPermission('sales_manage');
  const rows = bikes.map((b) => {
    const cost = costMap.get(b.id) || {};
    const unitCost = Number(cost.unit_cost || 0);
    const sell = Number(b.price || 0);
    const market = Number(marketMap[b.id] || 0);
    const margin = sell - unitCost;
    const vsMarket = market > 0 ? sell - market : null;
    const marginPct = sell > 0 ? ((margin / sell) * 100) : 0;
    const sc = b.stock <= 0 ? 'out' : b.stock <= 2 ? 'low' : 'available';
    const st = b.stock <= 0 ? 'نفذ' : b.stock <= 2 ? 'منخفض' : 'متوفر';
    const img = (b.images && b.images[0]) || '';
    const priceCell = canEditPrice
      ? `<form id="sellPriceForm" class="inline-form" data-bike-id="${esc(b.id)}">
           <input type="number" name="price" min="0" step="0.01" value="${sell}" required style="max-width:120px">
           <button class="btn btn-outline btn-sm" type="submit">حفظ</button>
         </form>`
      : `<span class="text-red" style="font-weight:900">${money(sell)}</span>`;
    return `<tr>
      <td><img class="mini-img" src="${esc(safeImageUrl(img))}" alt="" loading="lazy"></td>
      <td><b>${esc(b.name)}</b><br><small>${esc(b.model || '')} · ${esc(b.category || '')}</small></td>
      <td>${unitCost ? money(unitCost) : '<span class="hint">غير مسجّل</span>'}</td>
      <td>${priceCell}</td>
      <td>${canEditPrice
      ? `<form id="marketPriceForm" class="inline-form" data-bike-id="${esc(b.id)}">
           <input type="number" name="market_price" min="0" step="0.01" value="${market || ''}" placeholder="—" style="max-width:110px">
           <button class="btn btn-outline btn-sm" type="submit">حفظ</button>
         </form>`
      : (market ? money(market) : '<span class="hint">—</span>')}</td>
      <td>${vsMarket == null ? '—' : (vsMarket === 0 ? 'مساوٍ للسوق' : (vsMarket > 0 ? ('أعلى ' + money(vsMarket)) : ('أقل ' + money(Math.abs(vsMarket)))))}</td>
      <td>${unitCost ? money(margin) + '<br><small>' + marginPct.toFixed(1) + '%</small>' : '—'}</td>
      <td>${b.stock}</td>
      <td><span class="status-pill ${sc}">${st}</span></td>
      <td><span class="status-pill">${esc(b.status || '—')}</span></td>
    </tr>`;
  }).join('');

  return `
    <h2 class="page-title"><i class="fa-solid fa-tags"></i> الأسعار</h2>
    <p class="page-sub">التحكم الكامل بالأسعار: عرض سعر الشراء (التكلفة) وسعر البيع مع إمكانية تعديله، وربط عروض التقسيط والكتالوج.</p>

    <div class="stats-grid">
      <div class="stat-card"><div class="stat-icon"><i class="fa-solid fa-motorcycle"></i></div><div class="stat-label">طرازات مسجّلة</div><div class="stat-value">${bikes.length}</div></div>
      <div class="stat-card"><div class="stat-icon"><i class="fa-solid fa-boxes-stacked"></i></div><div class="stat-label">إجمالي المخزون</div><div class="stat-value">${bikes.reduce((s,b)=>s+Number(b.stock||0),0)}</div></div>
      <div class="stat-card"><div class="stat-icon"><i class="fa-solid fa-coins"></i></div><div class="stat-label">قيمة البيع المتوقعة</div><div class="stat-value" style="font-size:1.05rem">${money(bikes.reduce((s,b)=>s+Number(b.price||0)*Number(b.stock||0),0))}</div></div>
    </div>

    <div class="panel">
      <div class="panel-title"><i class="fa-solid fa-screwdriver-wrench"></i> أدوات الأسعار والكتالوج</div>
      <div class="invoice-actions">
        ${canEditPrice ? '<button class="btn btn-primary btn-sm" data-nav="manage-bikes"><i class="fa-solid fa-motorcycle"></i> المعرض / الكتالوج (إضافة وتعديل)</button>' : ''}
        ${canSales ? '<button class="btn btn-outline btn-sm" data-nav="sales-tools"><i class="fa-solid fa-file-invoice-dollar"></i> عروض التقسيط وتعديلها</button>' : ''}
        ${(hasRole('admin','manager','owner')||hasPermission('catalog_manage')||hasPermission('finance_manage')) ? '<button class="btn btn-outline btn-sm" data-nav="inventory-tools"><i class="fa-solid fa-warehouse"></i> تكلفة الوحدة والجرد</button>' : ''}
        <button class="btn btn-outline btn-sm" data-nav="pos"><i class="fa-solid fa-cash-register"></i> البيع من المعرض</button>
      </div>
      <p class="hint mt-2">سعر الشراء = تكلفة الوحدة من المورد/الجرد. سعر البيع قابل للتعديل مباشرة من الجدول إن كانت لديك صلاحية الكتالوج. عروض التقسيط تُدار من أداة عروض التقسيط.</p>
    </div>


    ${canEditPrice ? `<div class="panel">
      <div class="panel-title"><i class="fa-solid fa-layer-group"></i> تعديل جماعي لأسعار البيع</div>
      <form id="bulkPriceForm" class="form-grid">
        <div class="form-row">
          <div class="field">
            <label>الطرازات (فارغ = الكل)</label>
            <select name="bike_ids" multiple size="4" style="min-height:90px">${bikes.map((b)=>'<option value="'+esc(b.id)+'">'+esc(b.name)+' — '+money(b.price||0)+'</option>').join('')}</select>
          </div>
          <div class="field">
            <label>طريقة التعديل</label>
            <select name="mode" required>
              <option value="set">تعيين سعر ثابت</option>
              <option value="percent_up">زيادة %</option>
              <option value="percent_down">تخفيض %</option>
              <option value="amount_up">زيادة بمبلغ</option>
              <option value="amount_down">تخفيض بمبلغ</option>
            </select>
            <label class="mt-2">القيمة</label>
            <input type="number" name="value" min="0" step="0.01" required>
          </div>
        </div>
        <button class="btn btn-primary" type="submit"><i class="fa-solid fa-floppy-disk"></i> تطبيق التعديل الجماعي</button>
      </form>
      <p class="hint mt-2">سعر السوق يُحفظ على هذا الجهاز لمتابعة المنافسة. الباركود يُولَّد تلقائياً عند تسجيل وحدة بلا باركود.</p>
    </div>` : ''}

    <div class="panel printable-panel">

      <div class="panel-title"><i class="fa-solid fa-list"></i> جدول الأسعار (${bikes.length})</div>
      <div class="table-wrap"><table>
        <thead><tr>
          <th>الصورة</th><th>الصنف / الموديل</th>
          <th>سعر الشراء</th><th>سعر البيع</th><th>سعر السوق</th><th>مقارنة السوق</th><th>هامش الربح</th>
          <th>المخزون</th><th>التوفر</th><th>حالة العرض</th>
        </tr></thead>
        <tbody>
          ${rows || '<tr><td colspan="9">لا توجد أصناف في الكتالوج</td></tr>'}
        </tbody>
      </table></div>
    </div>`;
}

function pageDashboard() {
  const u = currentUser();
  if (!u || u.role !== 'admin') return pageLogin();
  const bikes = get(DB.BIKES), requests = get(DB.CUSTOM_REQS);
  const sales = state.sales || [], bills = state.supplierBills || [], expenses = state.expenses || [];
  const totalStock = bikes.reduce((sum, bike) => sum + Number(bike.stock || 0), 0);
  const pending = requests.filter((r) => ['pending', 'reviewing'].includes(r.status)).length;
  const salesTotal = sales.reduce((sum, sale) => sum + Number(sale.total || 0), 0);
  const receivables = sales.reduce((sum, sale) => sum + Math.max(0, Number(sale.total || 0) - Number(sale.amount_paid || 0) - Number(sale.credit_applied || 0) - Number(sale.returnedAmount || 0)), 0);
  const supplierDue = bills.reduce((sum, bill) => sum + Number(bill.balanceDue || 0), 0);
  const expenseTotal = expenses.reduce((sum, expense) => sum + Number(expense.amount || 0), 0);
  const cashTotal = (state.cashBalances || []).reduce((sum, account) => sum + Number(account.balance || 0), 0);
  const recentSales = sales.slice(0,5);
  return `<h2 class="page-title"><i class="fa-solid fa-chart-line"></i> لوحة الإحصائيات</h2>
    <p class="page-sub">ملخص مباشر من بيانات المخزون والمبيعات والموردين والحسابات. أرقام المبيعات والمصروفات تخص السجلات المحملة في هذه الصفحة.</p>
    <div class="stats-grid">
      <a class="stat-card stat-card-link" href="#manage-bikes" data-nav="manage-bikes" aria-label="فتح المعرض / الكتالوج"><div class="stat-icon"><i class="fa-solid fa-motorcycle"></i></div><div class="stat-label">الدراجات المسجلة</div><div class="stat-value">${bikes.length}</div><span class="stat-hint">فتح المعرض / الكتالوج <i class="fa-solid fa-arrow-left"></i></span></a>
      <a class="stat-card stat-card-link" href="#inventory-tools" data-nav="inventory-tools" aria-label="فتح إدارة المخزون"><div class="stat-icon"><i class="fa-solid fa-boxes-stacked"></i></div><div class="stat-label">وحدات المخزون</div><div class="stat-value">${totalStock}</div><span class="stat-hint">فتح المخزون والجرد <i class="fa-solid fa-arrow-left"></i></span></a>
      <a class="stat-card stat-card-link" href="#staff-orders" data-nav="staff-orders" aria-label="فتح طلبات العملاء"><div class="stat-icon"><i class="fa-solid fa-clipboard-list"></i></div><div class="stat-label">طلبات العملاء المفتوحة</div><div class="stat-value">${pending}</div><span class="stat-hint">فتح الطلبات <i class="fa-solid fa-arrow-left"></i></span></a>
      <a class="stat-card stat-card-link" href="#pos" data-nav="pos" aria-label="فتح فواتير المبيعات"><div class="stat-icon"><i class="fa-solid fa-file-invoice-dollar"></i></div><div class="stat-label">مبيعات آخر ${sales.length} فاتورة</div><div class="stat-value">${money(salesTotal)}</div><span class="stat-hint">فتح نقطة البيع والفواتير <i class="fa-solid fa-arrow-left"></i></span></a>
      <a class="stat-card stat-card-link" href="#sales-tools" data-nav="sales-tools" aria-label="فتح مستحقات العملاء"><div class="stat-icon"><i class="fa-solid fa-hand-holding-dollar"></i></div><div class="stat-label">مستحقات العملاء ضمن الفواتير المعروضة</div><div class="stat-value">${money(receivables)}</div><span class="stat-hint">فتح أدوات المبيعات والتحصيل <i class="fa-solid fa-arrow-left"></i></span></a>
      <a class="stat-card stat-card-link" href="#suppliers" data-nav="suppliers" aria-label="فتح مستحقات الموردين"><div class="stat-icon"><i class="fa-solid fa-truck"></i></div><div class="stat-label">مستحقات الموردين ضمن الفواتير المحملة</div><div class="stat-value">${money(supplierDue)}</div><span class="stat-hint">فتح الموردين والمشتريات <i class="fa-solid fa-arrow-left"></i></span></a>
      <a class="stat-card stat-card-link" href="#expenses" data-nav="expenses" aria-label="فتح المصروفات"><div class="stat-icon"><i class="fa-solid fa-money-bill-transfer"></i></div><div class="stat-label">مصروفات السجلات المحملة</div><div class="stat-value">${money(expenseTotal)}</div><span class="stat-hint">فتح النظام المالي <i class="fa-solid fa-arrow-left"></i></span></a>
      <a class="stat-card stat-card-link" href="#finance-tools" data-nav="finance-tools" aria-label="فتح الأرصدة المالية"><div class="stat-icon"><i class="fa-solid fa-vault"></i></div><div class="stat-label">أرصدة الخزائن والبنوك</div><div class="stat-value">${money(cashTotal)}</div><span class="stat-hint">فتح الأدوات المالية <i class="fa-solid fa-arrow-left"></i></span></a>
    </div>
    <div class="panel"><div class="panel-title"><i class="fa-solid fa-receipt"></i> أحدث الفواتير المحملة</div>
      ${recentSales.length ? `<div class="table-wrap"><table><thead><tr><th>الفاتورة</th><th>العميل</th><th>الإجمالي</th><th>المدفوع</th><th>التاريخ</th></tr></thead><tbody>
      ${recentSales.map(sale => `<tr><td><b>${esc(sale.invoice_number)}</b></td><td>${esc(sale.customer_name)}</td><td>${money(sale.total)}</td><td>${money(sale.amount_paid)}</td><td>${new Date(sale.created_at).toLocaleDateString('ar-EG')}</td></tr>`).join('')}
      </tbody></table></div>` : '<div class="empty"><p>لا توجد فواتير محملة بعد.</p></div>'}
      <div class="contact-actions mt-2"><button class="btn btn-primary" data-nav="pos">فتح نقطة البيع</button><button class="btn btn-outline" data-nav="suppliers">إدارة الموردين</button><button class="btn btn-outline" data-nav="expenses">الحسابات والمصروفات</button></div>
    </div>`;
}

function unitStatusLabel(status) {
  return ({available:'متاحة للبيع',reserved:'محجوزة',sold:'مباعة',service:'تحت الصيانة',retired:'مستبعدة من المخزون'})[status] || status || 'غير محددة';
}
function unitRegistrationFormHTML(motorcycleId) {
  const bike = (state.bikes || []).find((item) => item.id === motorcycleId);
  if (!bike) return '';
  return '<div class="modal-header"><h3><i class="fa-solid fa-barcode"></i> تسجيل دراجة فعلية — '+esc(bike.name)+'</h3><button class="modal-close" data-close-modal aria-label="إغلاق"><i class="fa-solid fa-xmark"></i></button></div>' +
    '<p class="hint">هذا الإجراء لإدخال رصيد افتتاحي موجود فعليًا بالمعرض فقط. إذا كانت الدراجة واردة من مورد جديد، استخدم أمر التوريد والاستلام وفاتورة المورد حتى لا تُسجل التكلفة مرتين.</p>' +
    '<form id="motorcycleUnitForm" class="form-grid"><input type="hidden" name="motorcycle_id" value="'+esc(bike.id)+'">' +
    '<div class="form-row"><div class="field"><label>رقم الشاسيه (VIN)</label><input name="vin" required maxlength="80"></div><div class="field"><label>رقم الموتور</label><input name="engine_number" maxlength="80"></div></div>' +
    '<div class="form-row"><div class="field"><label>الباركود (يُولَّد تلقائياً من الشاسيه إن تُرك فارغاً)</label><input name="barcode" maxlength="80" placeholder="اختياري — توليد تلقائي"></div><div class="field"><label>عداد الكيلومترات</label><input name="odometer_reading" type="number" min="0" step="1" value="0" required></div></div>' +
    '<div class="form-row"><div class="field"><label>حالة الدراجة</label><select name="unit_condition"><option value="new">جديدة</option><option value="used">مستعملة</option></select></div><div class="field"><label>تكلفة الوحدة الافتتاحية (ج.م)</label><input name="unit_cost" type="number" min="0.01" step="0.01" required></div></div>' +
    '<div class="form-row"><div class="field"><label>بداية الضمان</label><input name="warranty_start" type="date"></div><div class="field"><label>نهاية الضمان</label><input name="warranty_end" type="date"></div></div>' +
    '<div class="field"><label>ملاحظات</label><textarea name="notes" rows="2" maxlength="500"></textarea></div>' +
    '<p class="hint">تُحفظ تكلفة الوحدة، ويُحدّث متوسط تكلفة مخزون الطراز، ويُنشأ قيد افتتاحي: مدين المخزون ودائن رأس المال. بعد التسجيل تظهر الوحدة في المتجر إذا كانت متاحة.</p>' +
    '<button class="btn btn-primary btn-block" type="submit">حفظ الوحدة</button></form>';
}
function unitEditFormHTML(unit) {
  return '<div class="modal-header"><h3><i class="fa-solid fa-pen"></i> تعديل بيانات الوحدة</h3><button class="modal-close" data-close-modal aria-label="إغلاق"><i class="fa-solid fa-xmark"></i></button></div>' +
    '<form id="motorcycleUnitEditForm" class="form-grid" data-unit-id="'+esc(unit.id)+'">' +
    '<div class="form-row"><div class="field"><label>رقم الشاسيه (VIN)</label><input name="vin" required maxlength="80" value="'+esc(unit.vin)+'"></div><div class="field"><label>رقم الموتور</label><input name="engine_number" maxlength="80" value="'+esc(unit.engine_number||'')+'"></div></div>' +
    '<div class="form-row"><div class="field"><label>الباركود</label><input name="barcode" maxlength="80" value="'+esc(unit.barcode||'')+'"></div><div class="field"><label>عداد الكيلومترات</label><input name="odometer_reading" type="number" min="0" step="1" required value="'+Number(unit.odometer_reading||0)+'"></div></div>' +
    '<div class="form-row"><div class="field"><label>حالة الدراجة</label><select name="unit_condition"><option value="new" '+(unit.unit_condition==='new'?'selected':'')+'>جديدة</option><option value="used" '+(unit.unit_condition==='used'?'selected':'')+'>مستعملة</option></select></div><div class="field"><label>حالة المخزون</label><select name="unit_status">'+['available','reserved','service',...(unit.sale_item_id?['sold']:[]),'retired'].map((status)=>'<option value="'+status+'" '+(unit.unit_status===status?'selected':'')+'>'+unitStatusLabel(status)+'</option>').join('')+'</select></div></div>' +
    '<div class="form-row"><div class="field"><label>بداية الضمان</label><input name="warranty_start" type="date" value="'+esc(unit.warranty_start||'')+'"></div><div class="field"><label>نهاية الضمان</label><input name="warranty_end" type="date" value="'+esc(unit.warranty_end||'')+'"></div></div>' +
    '<div class="field"><label>ملاحظات</label><textarea name="notes" rows="2" maxlength="500">'+esc(unit.notes||'')+'</textarea></div>' +
    (unit.sale_item_id ? '<p class="hint">هذه الوحدة مرتبطة بفاتورة بيع؛ لا يمكن تغيير حالة بيعها من هنا.</p>' : '') +
    '<button class="btn btn-primary btn-block" type="submit">حفظ التعديلات</button></form>';
}
function pageManageBikes() {
  const u = currentUser();
  if (!u || !['staff','admin','manager','owner'].includes(u.role)) return pageLogin();
  if (u.role === 'staff' && !hasPermission('catalog_manage')) return pageNoPermission();
  const bikes = get(DB.BIKES) || [];
  const units = state.motorcycleUnits || [];
  const isRealUnit = (unit) => !unit.is_demo && !bikes.find((bike)=>bike.id===unit.motorcycle_id)?.is_demo;
  const realUnits = units.filter(isRealUnit);
  const totalUnits = realUnits.length;
  const demoUnits = units.length - realUnits.length;
  const availableUnits = realUnits.filter((x)=>x.unit_status==='available').length;
  const soldUnits = realUnits.filter((x)=>x.unit_status==='sold').length;
  const publishedUnitIds = new Set((state.storeUnits || []).map((x) => x.unit_id));
  const publishedUnits = realUnits.filter((x) => publishedUnitIds.has(x.id)).length;
  const groups = bikes.map((b) => {
    const list = units.filter((x)=>x.motorcycle_id===b.id);
    const available = list.filter((x)=>x.unit_status==='available' && !x.is_demo && !b.is_demo).length;
    const sold = list.filter((x)=>x.unit_status==='sold').length;
    const reserved = list.filter((x)=>x.unit_status==='reserved').length;
    const retired = list.filter((x)=>x.unit_status==='retired').length;
    const rows = list.map((x) => {
      const visibleInStore = !x.is_demo && !b.is_demo && x.unit_status === 'available';
      const canDelete = !x.sale_item_id && x.unit_status !== 'sold';
      return '<article class="unit-admin-card '+(x.is_demo||b.is_demo?'demo-unit-row':'')+'">' +
        '<div class="unit-admin-main"><div><b>شاسيه: <span dir="ltr">'+esc(x.vin)+'</span></b><small>موتور: <span dir="ltr">'+esc(x.engine_number||'غير مسجل')+'</span></small></div>' +
        '<span class="status-pill '+(x.unit_status==='available'?'available':x.unit_status==='sold'?'out':'pending')+'">'+unitStatusLabel(x.unit_status)+'</span>' +
        '<span class="status-pill '+(visibleInStore?'available':'pending')+'">'+(visibleInStore?'تظهر في المتجر تلقائيًا':'لا تظهر — ليست متاحة للبيع')+'</span>'+(x.is_demo||b.is_demo?'<small class="demo-data-label">تجريبية</small>':'')+'</div>' +
        '<div class="unit-admin-meta"><span>'+(x.unit_condition==='used'?'مستعملة':'جديدة')+'</span><span>العداد: '+Number(x.odometer_reading||0).toLocaleString('en-US')+' كم</span><span>باركود: '+esc(x.barcode||'—')+'</span></div>' +
        '<div class="unit-admin-meta"><span>الضمان: '+esc(x.warranty_start||'—')+' إلى '+esc(x.warranty_end||'—')+'</span><span>تسجيل: '+esc((x.registered_at||'').slice(0,10)||'—')+'</span></div>' +
        (x.notes?'<p class="hint">'+esc(x.notes)+'</p>':'') +
        '<div class="unit-admin-actions"><button class="btn btn-outline btn-sm" data-edit-unit="'+esc(x.id)+'"><i class="fa-solid fa-pen"></i> تعديل الوحدة</button>' +
        '' +
        (canDelete?'<button class="btn btn-danger btn-sm" data-delete-unit="'+esc(x.id)+'" data-unit-vin="'+esc(x.vin)+'"><i class="fa-solid fa-trash"></i> حذف السجل</button>':'') +
        '</div></article>';
    }).join('');
    return '<details class="bike-folder"><summary><span class="bike-folder-name"><i class="fa-solid fa-folder"></i> '+esc(b.name)+' <small>موديل '+esc(b.model)+'</small></span><span class="bike-folder-count">'+list.length+' وحدة · متاح '+available+'</span></summary>' +
      '<div class="bike-folder-body"><div class="bike-folder-summary"><span>الإجمالي: <b>'+list.length+'</b></span><span>متاح: <b>'+available+'</b></span><span>مباع: <b>'+sold+'</b></span><span>محجوز: <b>'+reserved+'</b></span><span>مستبعد: <b>'+retired+'</b></span></div>' +
      '<div class="bike-folder-actions"><button class="btn btn-outline btn-sm" data-edit-bike="'+esc(b.id)+'"><i class="fa-solid fa-pen"></i> تعديل بيانات النوع</button>'+(!b.is_demo?'<button class="btn btn-primary btn-sm" data-add-unit-for="'+esc(b.id)+'"><i class="fa-solid fa-plus"></i> تسجيل دراجة فعلية</button>':'<span class="demo-data-label">نوع تجريبي — لا يقبل مخزونًا فعليًا</span>')+''+(!b.is_demo?'<button class="btn btn-outline btn-sm" data-archive-bike="'+esc(b.id)+'" data-bike-name="'+esc(b.name)+'" '+(b.status==='unavailable'?'disabled':'')+'><i class="fa-solid fa-box-archive"></i> أرشفة وإخفاء</button>':'<button class="btn btn-danger btn-sm" data-delete-bike="'+esc(b.id)+'" data-bike-name="'+esc(b.name)+'"><i class="fa-solid fa-trash"></i> حذف النوع التجريبي</button>')+'</div>' +
      (rows || '<div class="empty">لا توجد وحدات مسجلة لهذا النوع بعد.</div>')+'</div></details>';
  }).join('');
  return '<h2 class="page-title"><i class="fa-solid fa-motorcycle"></i> المعرض / الكتالوج والمخزون</h2>' +
    '<p class="page-sub">كل مجلد يمثل نوعاً واحداً. افتح المجلد لرؤية كل دراجة فعلية وأرقامها وحالتها وتفاصيلها.</p>' +
    '<div class="stats-grid"><div class="stat-card"><div class="stat-label">أنواع الدراجات</div><div class="stat-value">'+bikes.length+'</div></div><div class="stat-card"><div class="stat-label">إجمالي الوحدات المسجلة</div><div class="stat-value">'+totalUnits+'</div></div><div class="stat-card"><div class="stat-label">وحدات متاحة للبيع</div><div class="stat-value">'+availableUnits+'</div></div><div class="stat-card"><div class="stat-label">معروضة على المتجر</div><div class="stat-value">'+publishedUnits+'</div></div><div class="stat-card"><div class="stat-label">وحدات مباعة</div><div class="stat-value">'+soldUnits+'</div></div><div class="stat-card"><div class="stat-label">سجلات تجريبية</div><div class="stat-value">'+demoUnits+'</div></div></div>' +
    '<div class="panel"><div class="bike-folder-toolbar"><button class="btn btn-primary" id="addBikeBtn"><i class="fa-solid fa-plus"></i> إضافة نوع دراجة</button><button class="btn btn-outline" id="syncTelegramPhotosBtn"><i class="fa-solid fa-rotate"></i> مزامنة الصور</button></div><p class="hint">المخزون الفعلي هو المتجر نفسه: كل وحدة حقيقية متاحة للبيع تظهر تلقائيًا، وتختفي تلقائيًا عند بيعها أو حجزها أو تحويلها للصيانة. حذف السجل متاح فقط للوحدات غير المرتبطة بمبيعات أو مستندات مخزون.</p>' +
    (groups || '<div class="empty">لا توجد أنواع دراجات مسجلة.</div>')+'</div>';
}

function bikeFormHTML(bike) {
  const isEdit = !!bike;
  const b = bike || { id: '', name: '', model: '', category: '', price: '', stock: 0, images: [], description: '', status: 'draft' };
  return `
    <div class="modal-header">
      <h3><i class="fa-solid fa-${isEdit ? 'pen' : 'plus'}"></i> ${isEdit ? 'تعديل' : 'إضافة'} دراجة</h3>
      <button class="modal-close" data-close-modal aria-label="إغلاق"><i class="fa-solid fa-xmark"></i></button>
    </div>
    <form id="bikeForm" class="form-grid" data-id="${esc(b.id)}">
      <div class="form-row">
        <div class="field"><label>الاسم</label><input name="name" required value="${esc(b.name)}"></div>
        <div class="field"><label>الموديل</label><input name="model" required value="${esc(b.model)}"></div>
      </div>
      <div class="form-row">
        <div class="field"><label>الفئة</label><input name="category" required value="${esc(b.category)}" placeholder="سبورت / naked ..."></div>
        <div class="field"><label>السعر</label><input type="number" name="price" required min="0" value="${esc(b.price)}"></div>
      </div>
      <div class="form-row">
        <div class="field"><label>الرصيد الفعلي (يُحسب من أرقام الشاسيه)</label><input type="number" name="stock" min="0" value="${esc(b.stock)}" readonly><small class="hint">يُحدّث الرصيد تلقائيًا من استلام الوحدات وحركات البيع والمرتجعات والجرد المعتمد.</small></div>
        <div class="field"><label>حالة العرض</label><select name="status">
          <option value="draft" ${b.status === 'draft' ? 'selected' : ''}>مسودة</option>
          <option value="available" ${b.status === 'available' ? 'selected' : ''}>متاحة</option>
          <option value="reserved" ${b.status === 'reserved' ? 'selected' : ''}>محجوزة</option>
          <option value="sold" ${b.status === 'sold' ? 'selected' : ''}>مباعة</option>
          <option value="unavailable" ${b.status === 'unavailable' ? 'selected' : ''}>غير متاحة</option>
        </select></div>
      </div>
      <div class="field"><label>وصف الدراجة ومواصفاتها</label><textarea name="description" rows="4" maxlength="10000">${esc(b.description || '')}</textarea><small class="hint">يظهر الوصف في تفاصيل الدراجة للعميل.</small></div>
      <div class="field">
        <label>روابط الصور العامة (كل رابط في سطر) — احذف الرابط لإزالة الصورة من الكتالوج</label>
        <textarea name="images" rows="4" placeholder="https://...">${esc((b.images || []).join('\n'))}</textarea>
      </div>
      <div class="field">
        <label>رفع الصور (ضغط تلقائي ومزامنة)</label>
        <input type="file" name="photos" accept="image/*" multiple>
        <span class="hint">تُصغّر إلى 1600 بكسل وتُضغط بصيغة JPEG، ثم تُحفظ في Telegram وSupabase Storage وتُربط بالكتالوج تلقائيًا.</span>
      </div>
      <button class="btn btn-primary btn-block" type="submit">
        <i class="fa-solid fa-floppy-disk"></i> حفظ
      </button>
    </form>`;
}

function pageStaff() {
  const u = currentUser();
  if (!u || u.role !== 'admin') return pageLogin();
  const staff = get(DB.USERS).filter((entry) => entry.role === 'staff');
  const result = state.staffProvisionResult;
  const canManageManagerRole = ['owner', 'admin'].includes(u.systemRole);
  return `<h2 class="page-title"><i class="fa-solid fa-users-gear"></i> حسابات الموظفين</h2>
    <p class="page-sub">إدارة بيانات الموظفين وصلاحياتهم، مع إمكانية ترقية الموظف إلى مدير مساعد.</p>
    ${result ? `<div class="panel staff-created"><h3>تم إنشاء الحساب</h3><p>البريد: <b>${esc(result.staff.email)}</b></p><p>تم حفظ كلمة المرور التي أدخلتها، والحساب جاهز لتسجيل الدخول.</p></div>` : ''}
    <div class="panel"><h3>إنشاء حساب موظف</h3>
      <p class="hint">تحقق من صحة البريد مع الموظف قبل الإنشاء. كلمة المرور تُحفظ لحساب الموظف؛ شاركها معه بأمان خارج الموقع.</p>
      <form id="staffCreateForm" class="form-grid">
        <div class="form-row"><div class="field"><label>اسم الموظف</label><input name="full_name" required maxlength="120" autocomplete="name"></div>
          <div class="field"><label>البريد الإلكتروني</label><input name="email" type="email" required maxlength="254" autocomplete="email"></div></div>
        <div class="field"><label>رقم الهاتف (اختياري)</label><input name="phone" type="tel" maxlength="32" autocomplete="tel"></div>
        <div class="form-row"><div class="field"><label>كلمة المرور</label><input name="password" type="password" required minlength="8" autocomplete="new-password"></div>
          <div class="field"><label>تأكيد كلمة المرور</label><input name="password_confirm" type="password" required minlength="8" autocomplete="new-password"></div></div>
        <fieldset class="permission-fieldset"><legend>الصلاحيات الممنوحة — لا شيء محدد افتراضيًا</legend><div class="permission-grid">
          ${STAFF_PERMISSION_OPTIONS.map((item) => `<label class="permission-option"><input type="checkbox" name="permissions" value="${esc(item.key)}"><span><b>${esc(item.label)}</b><small>${esc(item.description)}</small></span></label>`).join('')}
        </div></fieldset>
        <button class="btn btn-primary" type="submit"><i class="fa-solid fa-user-plus"></i> إنشاء حساب الموظف</button>
      </form>
    </div>
    <div class="panel"><h3>الموظفون الحاليون</h3><div class="table-wrap"><table>
      <thead><tr><th>الاسم</th><th>البريد</th><th>الهاتف</th><th>الصفة</th><th>الصلاحيات</th><th>الإدارة</th></tr></thead>
      <tbody>${staff.map((person) => {
        const isAssistant = person.accountRole === 'manager';
        const canEditPerson = canManageManagerRole || !isAssistant;
        const permissionChecks = STAFF_PERMISSION_OPTIONS.map((item) =>
          `<label class="permission-option"><input type="checkbox" name="permissions" value="${esc(item.key)}" ${person.permissions.includes(item.key) ? 'checked' : ''}><span><b>${esc(item.label)}</b><small>${esc(item.description)}</small></span></label>`
        ).join('');
        const roleField = canManageManagerRole
          ? `<div class="field"><label>صفة الحساب</label><select name="account_role"><option value="employee" ${!isAssistant ? 'selected' : ''}>موظف</option><option value="manager" ${isAssistant ? 'selected' : ''}>مدير مساعد — صلاحيات الإدارة</option></select><small class="hint">المدير المساعد يحصل على صلاحيات الإدارة الكاملة.</small></div>`
          : `<input type="hidden" name="account_role" value="employee"><p class="hint">يمكنك تعديل الموظفين العاديين فقط. ترقية المدير المساعد متاحة للمدير الأساسي.</p>`;
        return `<tr>
          <td><b>${esc(person.name || '—')}</b></td>
          <td><span dir="ltr">${esc(person.email || '—')}</span></td>
          <td>${esc(person.phone || '—')}</td>
          <td><span class="role-badge">${isAssistant ? 'مدير مساعد' : 'موظف'}</span></td>
          <td>${isAssistant ? 'صلاحيات الإدارة الكاملة' : (person.permissions.length ? person.permissions.map((key) => esc(PERMISSION_LABELS[key] || key)).join('، ') : 'لا توجد صلاحيات')}</td>
          <td>${canEditPerson ? `<details class="staff-edit"><summary class="btn btn-outline btn-sm"><i class="fa-solid fa-pen"></i> تعديل</summary>
            <form id="staffEditForm" class="staff-edit-form" data-user-id="${esc(person.id)}">
              <div class="field"><label>اسم الموظف</label><input name="full_name" required maxlength="120" value="${esc(person.name)}"></div>
              <div class="field"><label>البريد الإلكتروني (ثابت)</label><input type="email" value="${esc(person.email)}" disabled><small class="hint">تغيير البريد يحتاج إجراء تحقق منفصل لحماية تسجيل الدخول.</small></div>
              <div class="field"><label>رقم الهاتف</label><input name="phone" type="tel" maxlength="32" value="${esc(person.phone)}"></div>
              ${roleField}
              <fieldset class="permission-fieldset"><legend>الصلاحيات</legend><div class="permission-grid">${permissionChecks}</div></fieldset>
              <button class="btn btn-primary" type="submit"><i class="fa-solid fa-floppy-disk"></i> حفظ التعديلات</button>
            </form>
          </details>` : 'لا يمكن تعديل حساب مدير مساعد من هذا الحساب'}
          </td>
        </tr>`;
      }).join('') || `<tr><td colspan="6" class="text-center">لا توجد حسابات موظفين</td></tr>`}</tbody>
    </table></div></div>`;
}

function requestStatusLabel(status) {
  return ({ pending:'قيد المراجعة', reviewing:'جارٍ التواصل', approved:'مقبول', rejected:'مرفوض', completed:'مكتمل', expired:'منتهي' })[status] || status || '—';
}

function pageStaffOrders() {
  const u = currentUser();
  if (!u || !['staff', 'admin'].includes(u.role)) return pageLogin();
  if (u.role === 'staff' && !hasRequestAccess()) return pageNoPermission();
  const requests = get(DB.CUSTOM_REQS);
  const messages = state.contactMessages || [];
  const canManage = hasPermission('requests_manage');
  const canDeleteClosed = u.role === 'admin';
  const showContact = hasPermission('customer_data_view') || hasRequestAccess();
  const contactCells = (person) => showContact ? `<div class="contact-actions">${contactActionLinks(person, 'مرحبًا، معك فريق El Khayal Motors بخصوص طلبك.')}</div>` : 'بيانات التواصل تتطلب صلاحية بيانات العملاء';
  return `
    <h2 class="page-title"><i class="fa-solid fa-inbox"></i> صندوق طلبات العملاء والرسائل</h2>
    <p class="page-sub">بيانات المرسل وقنوات الاتصال وسجل الردود؛ لا يتم إرسال الرسائل آليًا من المتصفح.</p>
    <div class="panel"><div class="panel-title"><i class="fa-solid fa-motorcycle"></i> طلبات الشراء ${requests.length}</div>
      ${requests.length ? `<div class="table-wrap"><table><thead><tr><th>العميل ووسائل الاتصال</th><th>الطلب</th><th>الميزانية</th><th>الحالة</th><th>التاريخ</th><th>التواصل والرد</th></tr></thead><tbody>
      ${requests.map((r) => {
        const person = {phone:r.customerPhone,email:r.customerEmail};
        const replies = state.requestReplies.filter((x) => x.request_id === r.id);
        return `<tr><td><b>${esc(r.customerName || '—')}</b><br><small>${esc(r.customerPhone || r.customerEmail || '—')}</small><br><small>يفضل: ${esc(({phone:'اتصال',whatsapp:'واتساب',email:'بريد',sms:'SMS'})[r.preferredContact] || '—')}</small>${contactCells(person)}</td>
          <td>${esc(r.bikeName || '—')} ${esc(r.model || '')}${r.requestedUnitCondition ? `<br><small>الوحدة: ${r.requestedUnitCondition === 'used' ? 'مستعملة' : 'جديدة'}${r.requestedUnitVin ? ` — VIN: ${esc(r.requestedUnitVin)}` : ''}</small>` : ''}<br><small>${esc(r.notes || '')}</small></td>
          <td>${money(r.budget)}</td><td><span class="status-pill ${esc(r.status)}">${esc(requestStatusLabel(r.status))}</span></td>
          <td>${r.createdAt ? new Date(r.createdAt).toLocaleDateString('ar-EG') : '—'}</td>
          <td>${canManage ? `<button class="btn btn-primary btn-sm" data-open-reply="request" data-record-id="${esc(r.id)}">رد / سجل الرد (${replies.length})</button>${replies.slice(0,2).map((reply) => `<div class="hint">${esc(reply.channel)}: ${esc(reply.reply_body.slice(0,110))}${reply.sent_at ? ' — تم الإرسال' : ' — ملاحظة داخلية'}</div>`).join('')}` : 'عرض فقط'}
          ${canManage ? `<div class="contact-actions"><button class="btn btn-outline btn-sm" data-approve-req="${esc(r.id)}" ${r.status === 'approved' ? 'disabled' : ''}>قبول</button><button class="btn btn-outline btn-sm" data-reject-req="${esc(r.id)}" ${r.status === 'rejected' ? 'disabled' : ''}>رفض</button>${!['rejected','completed','expired'].includes(r.status) ? `<button class="btn btn-outline btn-sm" data-expire-req="${esc(r.id)}">اعتبار منتهي</button>` : ''}${canDeleteClosed && ['rejected','completed','expired'].includes(r.status) ? `<button class="btn btn-danger btn-sm" data-delete-request="${esc(r.id)}">حذف نهائي</button>` : ''} </div>` : ''}</td></tr>`;
      }).join('')}
      </tbody></table></div>` : `<div class="empty"><i class="fa-solid fa-inbox"></i><p>لا توجد طلبات شراء</p></div>`}
    </div>
    <div class="panel"><div class="panel-title"><i class="fa-solid fa-envelope"></i> رسائل التواصل ${messages.length}</div>
      ${messages.length ? `<div class="table-wrap"><table><thead><tr><th>المرسل ووسائل الاتصال</th><th>الرسالة</th><th>الحالة</th><th>التاريخ</th><th>إجراء</th></tr></thead><tbody>
      ${messages.map((m) => {
        const replies = state.contactReplies.filter((x) => x.message_id === m.id);
        return `<tr><td><b>${esc(m.name)}</b><br><small>${esc(m.phone || m.email || '—')}</small><br><small>يفضل: ${esc(({phone:'اتصال',whatsapp:'واتساب',email:'بريد',sms:'SMS'})[m.preferred_contact] || '—')}</small><div class="contact-actions">${contactCells({phone:m.phone,email:m.email})}</div></td>
          <td>${esc(m.message)}</td><td>${esc(({new:'جديدة',in_progress:'قيد المتابعة',replied:'تم الرد',closed:'مغلقة'})[m.status] || m.status)}</td>
          <td>${new Date(m.created_at).toLocaleDateString('ar-EG')}</td><td>${canManage ? `<button class="btn btn-primary btn-sm" data-open-reply="message" data-record-id="${esc(m.id)}">رد / سجل الرد (${replies.length})</button>${replies.slice(0,2).map((reply) => `<div class="hint">${esc(reply.channel)}: ${esc(reply.reply_body.slice(0,110))}${reply.sent_at ? ' — تم الإرسال' : ' — ملاحظة داخلية'}</div>`).join('')}` : 'عرض فقط'}</td></tr>`;
      }).join('')}
      </tbody></table></div>` : `<div class="empty"><i class="fa-solid fa-envelope-open"></i><p>لا توجد رسائل تواصل</p></div>`}
    </div>`;
}

/* =========================================================
   SECTION 6 — UI & SIDEBAR (Router, Events, Init)
   ========================================================= */

/* ---------- Modal helpers ---------- */
function openModal(html) {
  const ov = $('#modalOverlay');
  const box = $('#modalBox');
  if (!ov || !box) return;
  box.innerHTML = html;
  ov.classList.add('show');
  ov.setAttribute('aria-hidden', 'false');
  document.body.style.overflow = 'hidden';
}
function closeModal() {
  const ov = $('#modalOverlay');
  const box = $('#modalBox');
  if (!ov || !box) return;
  ov.classList.remove('show');
  ov.setAttribute('aria-hidden', 'true');
  box.innerHTML = '';
  document.body.style.overflow = '';
}

/* ---------- Sidebar helpers ---------- */
function openSidebar() {
  state.sidebarOpen = true;
  const s = $('#sidebar');
  const o = $('#sidebarOverlay');
  const t = $('#menuToggle');
  if (s) s.classList.add('open');
  if (o) o.classList.add('show');
  if (t) t.setAttribute('aria-expanded', 'true');
  document.body.style.overflow = 'hidden';
}
function closeSidebar() {
  state.sidebarOpen = false;
  const s = $('#sidebar');
  const o = $('#sidebarOverlay');
  const t = $('#menuToggle');
  if (s) s.classList.remove('open');
  if (o) o.classList.remove('show');
  if (t) t.setAttribute('aria-expanded', 'false');
  document.body.style.overflow = '';
}
function toggleSidebar() {
  state.sidebarOpen ? closeSidebar() : openSidebar();
}

/* ---------- Router ---------- */
function pageOwnerData() {
  if (!currentUser() || state.user?.systemRole !== 'owner') return pageNoPermission();
  return `
    <section class="panel">
      <h2 class="page-title"><i class="fa-solid fa-shield-halved"></i> أدوات المالك والنسخ الاحتياطي</h2>
      <p class="page-sub">النسخ والاستعادة وإعادة ضبط بيانات التشغيل. جميع العمليات تتطلب كلمة مرور حساب المالك.</p>
      <div class="alert alert-warning" role="alert"><strong>تنبيه مهم:</strong> النسخة تشمل بيانات جداول قاعدة البيانات الـ86، ولا تشمل الملفات الثنائية في Supabase Storage. الاستعادة تستبدل بيانات التشغيل الحالية مع الاحتفاظ بحساب المالك وصلاحياته والإعدادات المحاسبية الأساسية وسجل التدقيق.</div>
      <div class="form-grid"><div class="field"><label for="ownerDataPassword">كلمة مرور حساب المالك (تُطلب لكل عملية)</label><input id="ownerDataPassword" type="password" autocomplete="current-password" required placeholder="أدخل كلمة المرور"></div></div>
      <div class="grid grid-2">
        <article class="card"><h3><i class="fa-solid fa-cloud-arrow-down"></i> نسخة احتياطية</h3><p>تصدير بيانات قاعدة البيانات في ملف JSON مع بصمة تحقق SHA-256.</p><button class="btn btn-primary" type="button" data-owner-backup><i class="fa-solid fa-download"></i> إنشاء وتنزيل نسخة</button></article>
        <article class="card"><h3><i class="fa-solid fa-cloud-arrow-up"></i> استعادة / استيراد</h3><p>ترفع البيانات إلى Supabase وتصبح مشتركة مع الموقع ولوحة الإدارة. الاستعادة ذرّية؛ إذا فشل التحقق تُلغى بالكامل.</p><div class="field"><label for="ownerBackupFile">ملف النسخة الاحتياطية JSON</label><input id="ownerBackupFile" type="file" accept=".json,application/json"></div><div class="field"><label for="ownerRestoreConfirmation">اكتب RESTORE BACKUP للتأكيد</label><input id="ownerRestoreConfirmation" autocomplete="off"></div><button class="btn btn-outline" type="button" data-owner-restore><i class="fa-solid fa-rotate"></i> استيراد النسخة</button></article>
        <article class="card"><h3><i class="fa-solid fa-triangle-exclamation"></i> حذف بيانات التشغيل</h3><p>يحذف بيانات التشغيل والحسابات المسجلة غير حساب المالك، وملفات الصور التي نُقلت من Telegram إلى Supabase Storage (catalog-images)، مع الاحتفاظ بحساب المالك وصلاحياته وإعدادات النظام الأساسية وسجل التدقيق.</p><p class="text-danger"><strong>تنبيه:</strong> ملف النسخة الاحتياطية JSON لا يتضمن الصور الثنائية؛ حذفها هنا نهائي من Supabase Storage، ولا يحذف الرسائل أو الصور الأصلية من محادثة Telegram.</p><div class="field"><label for="ownerResetConfirmation">اكتب DELETE ALL DATA للتأكيد</label><input id="ownerResetConfirmation" autocomplete="off"></div><button class="btn btn-danger" type="button" data-owner-reset><i class="fa-solid fa-trash"></i> حذف كل بيانات التشغيل</button></article>
      </div>
    </section>`;
}

const ROUTES = {
  home: pageHome,
  login: pageLogin,
  signup: pageSignup,
  request: pageRequest,
  contact: pageContact,
  account: pageAccount,
  favorites: pageFavorites,
  orders: pageOrders,
  invoices: pageCustomerInvoices,
  pos: pagePOS,
  'vin-scanner': pageVinScanner,
  suppliers: pageSuppliers,
  target: pageTarget,
  inventory: pageInventory,
  dashboard: pageDashboard,
  'manage-bikes': pageManageBikes,
  staff: pageStaff,
  'staff-orders': pageStaffOrders,
  expenses: pageExpenses,
  'finance-tools': pageFinanceTools,
  hr: pageHR,
  'inventory-tools': pageInventoryTools,
  'customer-relations': pageCustomerRelations,
  'sales-tools': pageSalesTools,
  'owner-data': pageOwnerData
};

function render() {
  currentUser();
  renderAccountArea();
  renderSidebar();

  const main = $('#mainContent');
  if (!main) return;

  const fn = ROUTES[state.route] || pageHome;
  main.innerHTML = fn();
  // Add print actions only to report panels explicitly marked as printable.
  $$('.panel.printable-panel', main).forEach((panel) => {
    if (panel.querySelector(':scope > .section-print-action')) return;
    const action = document.createElement('div');
    action.className = 'section-print-action no-print';
    action.innerHTML = '<button class="btn btn-outline btn-sm" type="button" data-print-section><i class="fa-solid fa-print"></i> طباعة الكشف</button>';
    panel.insertBefore(action, panel.firstChild);
  });
  applyLanguage(document);


  window.scrollTo({ top: 0, behavior: 'smooth' });
}

function navigate(route) {
  if (!ROUTES[route]) route = 'home';
  if (state.route === 'vin-scanner' && route !== 'vin-scanner') stopVinScanner();
  if (state.route === 'staff' && route !== 'staff') state.staffProvisionResult = null;
  state.route = route;
  state.search = '';
  state.filterCat = 'all';
  state.filterPrice = 'all';
  closeModal();
  closeSidebar();
  render();
  if (route === 'dashboard' && state.user?.role === 'admin') Promise.all([loadSalesData(),loadPurchasingData(),loadFinanceData()]).then(render);
  if (route === 'manage-bikes' && state.user) Promise.all([loadMotorcycles(),loadMotorcycleUnits()]).then(render);
  if (route === 'inventory' && state.user) Promise.all([loadMotorcycles(),loadInventoryData()]).then(render);
  if (route === 'staff' && state.user?.role === 'admin') loadStaffDirectory().then(render);
  if (route === 'pos') Promise.all([loadSalesData(),loadMotorcycles(),loadMotorcycleUnits(),loadSalesCashAccounts()]).then(render);
  if (route === 'vin-scanner') Promise.all([loadMotorcycles(),loadSalesData(),loadSalesCashAccounts()]).then(render);
  if (route === 'home') Promise.all([loadMotorcycles(),loadStoreUnits()]).then(render);
  if (route === 'staff-orders' && state.user && ['staff','admin'].includes(state.user.role)) loadBusinessData().then(render);
  if (route === 'hr' && state.user && (hasRole('admin','manager','owner') || hasPermission('finance_manage'))) Promise.all([loadHRData(),loadFinanceData(),loadSalesData()]).then(render);
  if (route === 'inventory-tools' && state.user && (hasRole('admin','manager','owner') || hasPermission('catalog_manage') || hasPermission('finance_manage'))) Promise.all([loadMotorcycles(),loadInventoryData(),loadHRData(),loadSalesData()]).then(render);
  if (route === 'customer-relations' && state.user && (hasRole('admin','manager','owner') || hasPermission('customer_data_view') || hasPermission('customer_data_manage'))) Promise.all([loadCRMData(),loadSalesData()]).then(render);
  if (route === 'sales-tools' && state.user && (hasRole('admin','manager','owner') || hasPermission('sales_manage'))) Promise.all([loadSalesToolsData(),loadSalesData(),loadMotorcycles(),loadCRMData()]).then(render);
  if ((route === 'expenses' || route === 'finance-tools') && state.user && (hasRole('admin','manager','owner') || hasPermission('expenses_manage') || hasPermission('accounting_view') || hasPermission('finance_manage'))) {
    const load = route === 'finance-tools' && hasRole('admin') ? loadPurchasingData() : Promise.resolve();
    Promise.all([load,loadFinanceData()]).then(render);
  }
}

/* ---------- Buy Flow ---------- */
function requireCustomerLogin(action, bikeId = null, unitId = null) {
  const pending = { action, bikeId, unitId: action === 'buy' ? (unitId || null) : null };
  state.pendingAuthAction = pending;
  try { sessionStorage.setItem('ekm_pending_auth_action', JSON.stringify(pending)); } catch { /* Session storage may be unavailable. */ }
  toast('سجّل الدخول أو أنشئ حسابًا للمتابعة؛ سنعيدك إلى الإجراء الذي اخترته', 'info');
  navigate('login');
}

async function toggleFavorite(bikeId) {
  const u = currentUser();
  if (!u) { requireCustomerLogin('favorite', bikeId); return; }
  if (u.role !== 'customer') { toast('المفضلة متاحة لحسابات العملاء فقط', 'error'); return; }
  if (!supabase) { toast('الخدمة غير مهيأة حالياً', 'error'); return; }
  const { data: existing, error: readError } = await supabase.from('favorites')
    .select('motorcycle_id').eq('user_id', u.id).eq('motorcycle_id', bikeId).maybeSingle();
  if (readError) { toast(readError.message, 'error'); return; }
  const result = existing
    ? await supabase.from('favorites').delete().eq('user_id', u.id).eq('motorcycle_id', bikeId)
    : await supabase.from('favorites').insert({ user_id: u.id, motorcycle_id: bikeId });
  if (result.error) { toast(result.error.message, 'error'); return; }
  toast(existing ? 'أزيلت من المفضلة' : 'أضيفت للمفضلة', 'success');
  render();
}

async function resumePendingAuthAction() {
  let pending = state.pendingAuthAction;
  if (!pending) {
    try { pending = JSON.parse(sessionStorage.getItem('ekm_pending_auth_action') || 'null'); } catch { pending = null; }
  }
  state.pendingAuthAction = null;
  try { sessionStorage.removeItem('ekm_pending_auth_action'); } catch { /* Session storage may be unavailable. */ }
  if (!pending || currentUser()?.role !== 'customer') return;
  if (!['favorite', 'buy'].includes(pending.action) || typeof pending.bikeId !== 'string') return;
  if (pending.action === 'favorite') {
    if (!state.bikes.some((bike) => bike.id === pending.bikeId)) return;
    await toggleFavorite(pending.bikeId);
    return;
  }
  await Promise.all([loadMotorcycles(), loadStoreUnits()]);
  if (!state.bikes.some((bike) => bike.id === pending.bikeId)) return;
  const unitId = typeof pending.unitId === 'string' && pending.unitId ? pending.unitId : null;
  if (unitId && !(state.storeUnits || []).some((unit) => unit.unit_id === unitId && unit.motorcycle_id === pending.bikeId)) {
    toast('الوحدة التي اخترتها لم تعد متاحة؛ حدّث المتجر واختر وحدة أخرى', 'error');
    return;
  }
  handleBuy(pending.bikeId, unitId);
}

function handleBuy(bikeId, unitId = null) {
  const u = currentUser();
  if (!u) { requireCustomerLogin('buy', bikeId, unitId); return; }
  if (u.role !== 'customer') { toast('الشراء وطلبات العملاء متاحة لحسابات العملاء فقط', 'error'); return; }
  const bike = state.bikes.find((b) => b.id === bikeId);
  if (!bike) return toast('الدراجة غير موجودة', 'error');
  const selectedUnit = unitId
    ? (state.storeUnits || []).find((unit) => unit.unit_id === unitId && unit.motorcycle_id === bikeId)
    : (state.storeUnits || []).find((unit) => unit.motorcycle_id === bikeId);
  if (!selectedUnit || bike.status !== 'available') return toast('هذه الوحدة لم تعد متاحة حالياً؛ حدّث الصفحة لاختيار وحدة أخرى', 'error');
  const conditionLabel = selectedUnit.unit_condition === 'used' ? 'مستعملة' : 'جديدة';
  openModal(`
    <div class="modal-header"><h3><i class="fa-solid fa-cart-shopping"></i> طلب شراء ${esc(bike.name)} — ${conditionLabel}</h3>
      <button class="modal-close" data-close-modal aria-label="إغلاق"><i class="fa-solid fa-xmark"></i></button></div>
    <p class="text-red mb-2" style="font-size:20px;font-weight:900">${money(bike.price)}</p>
    <form id="quickBuyRequestForm" class="form-grid" data-bike-id="${esc(bike.id)}" data-unit-id="${esc(selectedUnit.unit_id)}">
      <div class="field"><label>اسمك</label><input name="requester_name" required maxlength="120" value="${esc(u?.name || '')}"></div>
      <div class="form-row">
        <div class="field"><label>رقم الهاتف</label><input name="requester_phone" type="tel" maxlength="32" value="${esc(u?.phone || '')}"></div>
        <div class="field"><label>البريد الإلكتروني</label><input name="requester_email" type="email" maxlength="254" value="${esc(u?.email || '')}"></div>
      </div>
      <div class="field"><label>طريقة التواصل المفضلة</label><select name="preferred_contact"><option value="whatsapp">واتساب</option><option value="phone">اتصال</option><option value="sms">SMS</option><option value="email">البريد الإلكتروني</option></select></div>
      <div class="field"><label>ملاحظات (اختياري)</label><textarea name="notes" maxlength="2000"></textarea></div>
      <button class="btn btn-primary btn-block" type="submit">إرسال طلب الشراء</button>
    </form>`);
}

async function confirmBuy(bikeId, unitId = null) {
  handleBuy(bikeId, unitId);
}

/* ---------- Event: Click Delegation ---------- */
document.addEventListener('click', async (e) => {
  const ownerAction = e.target.closest('[data-owner-backup], [data-owner-restore], [data-owner-reset]');
  if (ownerAction) {
    if (state.user?.systemRole !== 'owner') { toast('هذه الأدوات متاحة للمالك فقط', 'error'); return; }
    if (!supabase) { toast('الاتصال بقاعدة البيانات غير متاح', 'error'); return; }
    const password = $('#ownerDataPassword')?.value || '';
    if (!password) { toast('أدخل كلمة مرور المالك أولاً', 'error'); return; }
    ownerAction.disabled = true;
    try {
      if (ownerAction.matches('[data-owner-backup]')) {
        const { data, error } = await supabase.functions.invoke('owner-data-management', { body: { action: 'backup', password } });
        if (error) throw error;
        if (!data?.tables || data.format !== 'khayal-backup') throw new Error(data?.error || 'تعذر إنشاء النسخة الاحتياطية');
        const blob = new Blob([JSON.stringify(data, null, 2)], { type: 'application/json' });
        const url = URL.createObjectURL(blob), link = document.createElement('a');
        link.href = url; link.download = 'khayal-backup-' + new Date().toISOString().replace(/[:.]/g, '-') + '.json';
        document.body.appendChild(link); link.click(); link.remove(); URL.revokeObjectURL(url);
        toast('تم إنشاء النسخة الاحتياطية وتنزيلها (' + Number(data.rowCount || 0) + ' سجل)', 'success');
      } else if (ownerAction.matches('[data-owner-restore]')) {
        const file = $('#ownerBackupFile')?.files?.[0], confirmation = $('#ownerRestoreConfirmation')?.value || '';
        if (!file) throw new Error('اختر ملف النسخة الاحتياطية أولاً');
        if (confirmation !== 'RESTORE BACKUP') throw new Error('اكتب RESTORE BACKUP كما هو للتأكيد');
        if (file.size > 25 * 1024 * 1024) throw new Error('حجم النسخة يتجاوز الحد المسموح 25 ميجابايت');
        const backup = JSON.parse(await file.text());
        if (!window.confirm('ستُستبدل بيانات التشغيل الحالية بمحتويات النسخة. هل أنشأت نسخة حديثة من البيانات الحالية؟')) return;
        const { data, error } = await supabase.functions.invoke('owner-data-management', { body: { action: 'restore', password, confirmation, backup } });
        if (error) throw error;
        if (!data?.ok) throw new Error(data?.error || 'فشلت الاستعادة');
        toast('تم استيراد البيانات إلى قاعدة البيانات بنجاح. سيتم تحديث الموقع الآن.', 'success');
        window.location.reload();
      } else {
        const confirmation = $('#ownerResetConfirmation')?.value || '';
        if (confirmation !== 'DELETE ALL DATA') throw new Error('اكتب DELETE ALL DATA كما هو للتأكيد');
        if (!window.confirm('تحذير نهائي: سيتم حذف الحسابات غير حساب المالك وكل الصور المخزنة في Supabase Storage نهائيًا، بالإضافة إلى بيانات التشغيل. ملف JSON لا يحتفظ بالصور. هل تريد المتابعة؟')) return;
        const { data, error } = await supabase.functions.invoke('owner-data-management', { body: { action: 'reset', password, confirmation } });
        if (error) throw error;
        if (!data?.ok) {
          toast((data?.error || 'اكتمل جزء من الحذف فقط') + ' — حُذف حتى الآن ' + Number(data.authUsersDeleted || 0) + ' حسابات و' + Number(data.storageDeleted || 0) + ' صورة. أعد المحاولة لإكمال التنظيف.', 'error');
          return;
        }
        toast('اكتمل الحذف: ' + Number(data.authUsersDeleted || 0) + ' حسابات غير المالك و' + Number(data.storageDeleted || 0) + ' صورة. تم الاحتفاظ بحساب المالك.', 'success');
        window.location.reload();
      }
    } catch (error) {
      console.error('Owner data operation failed', error);
      toast(error?.message || 'حدث خطأ أثناء تنفيذ العملية', 'error');
    } finally { ownerAction.disabled = false; }
    return;
  }

  const payExpenseButton = e.target.closest('[data-pay-expense]');
  if (payExpenseButton) {
    if (!(hasRole('admin') || hasPermission('expenses_manage'))) { toast('ليس لديك صلاحية سداد المصروفات','error'); return; }
    const due = Number(payExpenseButton.dataset.due || 0);
    const options = (state.cashAccounts||[]).map(a=>'<option value="'+esc(a.id)+'">'+esc(a.name)+'</option>').join('');
    openModal('<div class="modal-header"><h3>تسجيل سداد مصروف</h3><button class="modal-close" data-close-modal aria-label="إغلاق"><i class="fa-solid fa-xmark"></i></button></div>' +
      '<p>الرصيد المستحق: <b>'+money(due)+'</b></p><form id="expensePaymentForm" class="form-grid" data-expense-id="'+esc(payExpenseButton.dataset.payExpense)+'">' +
      '<div class="field"><label>المبلغ المدفوع</label><input name="amount" type="number" min="0.01" max="'+due+'" step="0.01" required></div>' +
      '<div class="field"><label>الخزينة / البنك</label><select name="cash_account_id" required><option value="">اختر الحساب</option>'+options+'</select></div>' +
      '<div class="field"><label>طريقة الدفع</label><select name="payment_method"><option value="cash">نقدي</option><option value="bank_transfer">تحويل بنكي</option><option value="instapay">إنستاباي</option><option value="card">بطاقة</option><option value="cheque">شيك</option><option value="other">أخرى</option></select></div>' +
      '<div class="field"><label>رقم المرجع</label><input name="reference_number" maxlength="100"></div><button class="btn btn-primary" type="submit">حفظ السداد</button></form>');
    return;
  }
  if (e.target.closest('#resendConfirmationBtn')) {
    if (!supabase) { toast('الخدمة غير مهيأة حالياً', 'error'); return; }
    const email = safeName($('#loginForm input[name="email"]')?.value).toLowerCase();
    if (!email) { toast('اكتب البريد الإلكتروني أولاً', 'error'); return; }
    const { error } = await supabase.auth.resend({ type: 'signup', email, options: { emailRedirectTo: authRedirectUrl } });
    if (error) toast(error.message || 'تعذر طلب رسالة التأكيد', 'error');
    else toast('إذا كان الحساب بانتظار التأكيد، ستصل رسالة إلى البريد', 'info');
    return;
  }

  const retryPurchasing = e.target.closest('[data-retry-purchasing]');
  if (retryPurchasing) {
    if (state.route !== 'suppliers') return;
    retryPurchasing.disabled = true;
    const reload = Promise.all([loadPurchasingData(), loadMotorcycles()]);
    render();
    await reload;
    render();
    return;
  }

  /* Keep the contact page as the return destination through customer authentication. */
  const contactAuth = e.target.closest('[data-contact-auth]');
  if (contactAuth) {
    e.preventDefault();
    try { sessionStorage.setItem('ekm_auth_return_route', 'contact'); } catch { /* Session storage may be unavailable. */ }
    navigate(contactAuth.dataset.contactAuth);
    return;
  }

  /* Navigation */
  const nav = e.target.closest('[data-nav]');
  if (nav) {
    e.preventDefault();
    const route = nav.dataset.nav;
    navigate(route);
    if (route === 'suppliers' && state.user?.role === 'admin') {
      const load = Promise.all([loadPurchasingData(), loadMotorcycles()]);
      render();
      load.then(render).catch((error) => {
        state.purchasingLoadStatus = 'error';
        state.purchasingLoadErrors = ['تحميل بيانات الموردين'];
        console.error('Supplier page load failed', error);
        render();
      });
    }
    return;
  }

  /* Sidebar toggle / overlay / logout */
  if (e.target.closest('#startVinScanner')) { await startVinScanner(); return; }
  if (e.target.closest('#stopVinScanner')) { stopVinScanner(); return; }
  if (e.target.closest('#menuToggle')) { toggleSidebar(); return; }
  if (e.target.closest('#sidebarOverlay')) { closeSidebar(); return; }
  if (e.target.closest('#logoutBtn')) { logout(); return; }

  /* Modal close */
  if (e.target.closest('[data-close-modal]') || e.target.id === 'modalOverlay') {
    closeModal();
    return;
  }

  const printDeliveryButton=e.target.closest('[data-print-delivery]');
  if(printDeliveryButton){
    const d=(state.saleDeliveries||[]).find(x=>x.id===printDeliveryButton.dataset.printDelivery);
    if(!d){toast('محضر التسليم غير موجود','error');return;}
    const w=window.open('','_blank','width=900,height=700');
    if(!w){toast('اسمح بفتح النوافذ المنبثقة لطباعة المحضر','error');return;}
    w.onload=()=>{w.focus();w.print();};
    w.document.open();
    w.document.write('<!doctype html><html lang="ar" dir="rtl"><head><meta charset="utf-8"><title>محضر تسليم #'+esc(d.delivery_number)+'</title><style>body{font-family:Arial,sans-serif;margin:32px;color:#111}h1{text-align:center;font-size:24px}.meta{display:grid;grid-template-columns:1fr 1fr;gap:12px;margin:24px 0}.cell{border:1px solid #bbb;padding:12px;border-radius:6px}.wide{grid-column:1/-1}.sign{display:flex;justify-content:space-between;margin-top:70px}.muted{color:#555} @media print{button{display:none}}</style></head><body><h1>الخيال موتورز — محضر تسليم دراجة</h1><p class="muted">رقم المحضر: #'+esc(d.delivery_number)+' | فاتورة البيع: '+esc(d.sales?.invoice_number||'—')+'</p><div class="meta"><div class="cell"><b>اسم المستلم</b><br>'+esc(d.recipient_name)+'</div><div class="cell"><b>هاتف المستلم</b><br>'+esc(d.recipient_phone||'—')+'</div><div class="cell"><b>وقت التسليم</b><br>'+new Date(d.delivered_at).toLocaleString('ar-EG')+'</div><div class="cell"><b>قراءة العداد</b><br>'+esc(d.odometer_reading??'—')+' كم</div><div class="cell wide"><b>الملحقات المسلمة</b><br>'+esc(d.accessories||'—')+'</div><div class="cell wide"><b>حالة الدراجة عند التسليم</b><br>'+esc(d.condition_notes||'—')+'</div><div class="cell wide"><b>ملاحظات</b><br>'+esc(d.notes||'—')+'</div></div><div class="sign"><span>توقيع المستلم: __________________</span><span>توقيع مسؤول التسليم: __________________</span></div></body></html>');
    w.document.close();return;
  }

  /* Print invoice and printable customer invoice details */
  if (e.target.closest('#printInvoiceBtn') || e.target.closest('[data-print-customer-invoice]')) {
    document.body.classList.add('print-invoice');
    window.print();
    document.body.classList.remove('print-invoice');
    return;
  }
  const printSectionButton = e.target.closest('[data-print-section]');
  if (printSectionButton) {
    const section = printSectionButton.closest('.panel');
    if (!section) return;
    document.querySelectorAll('.print-target').forEach((node) => node.classList.remove('print-target'));
    section.classList.add('print-target');
    document.body.classList.add('print-section');
    const cleanup = () => {
      document.body.classList.remove('print-section');
      section.classList.remove('print-target');
      window.removeEventListener('afterprint', cleanup);
    };
    window.addEventListener('afterprint', cleanup, { once: true });
    window.print();
    setTimeout(cleanup, 1200);
    return;
  }
  const sendInvoiceButton = e.target.closest('#sendInvoiceWhatsAppBtn');
  if (sendInvoiceButton) {
    let phone = String(sendInvoiceButton.dataset.phone || '').replace(/[^0-9]/g, '');
    if (!phone) { toast('أضف رقم هاتف العميل في بيانات البيع لإرسال الفاتورة عبر واتساب', 'error'); return; }
    if (phone.startsWith('0')) phone = '20' + phone.slice(1);
    const message = [
      'الخيال موتورز — فاتورة بيع',
      'رقم الفاتورة: ' + sendInvoiceButton.dataset.invoice,
      'العميل: ' + sendInvoiceButton.dataset.customer,
      'الأصناف: ' + (sendInvoiceButton.dataset.items || '—'),
      'الإجمالي: ' + sendInvoiceButton.dataset.total + ' ج.م',
      'المدفوع: ' + sendInvoiceButton.dataset.paid + ' ج.م',
      'المتبقي: ' + sendInvoiceButton.dataset.due + ' ج.م',
      'شكراً لثقتكم في El Khayal Motors.'
    ].join('\\n');
    window.open('https://wa.me/' + phone + '?text=' + encodeURIComponent(message), '_blank', 'noopener');
    return;
  }
  if (e.target.closest('#shareInvoiceBtn')) {
    const invoiceText = document.querySelector('.modal .invoice')?.innerText || '';
    if (navigator.share) {
      try { await navigator.share({ title: 'فاتورة الخيال موتورز', text: invoiceText }); }
      catch (error) { if (error?.name !== 'AbortError') toast('تعذرت مشاركة الفاتورة', 'error'); }
    } else if (navigator.clipboard?.writeText) {
      try { await navigator.clipboard.writeText(invoiceText); toast('تم نسخ تفاصيل الفاتورة؛ يمكنك إرسالها للعميل', 'success'); }
      catch { toast('تعذر نسخ الفاتورة من هذا المتصفح', 'error'); }
    } else toast('المشاركة غير مدعومة في هذا المتصفح', 'error');
    return;
  }

  if (e.target.closest('#addPosItemBtn')) {
    const rows = $('#posCartRows');
    const first = rows?.querySelector('.pos-cart-row');
    if (!rows || !first) return;
    if (rows.querySelectorAll('.pos-cart-row').length >= 20) { toast('الحد الأقصى 20 صنفًا في الفاتورة', 'error'); return; }
    const clone = first.cloneNode(true);
    clone.querySelectorAll('select').forEach(select => {
      if (select.multiple) [...select.options].forEach(option => { option.selected = false; option.disabled = false; });
      else select.value = '';
    });
    const remove = clone.querySelector('[data-remove-pos-row]');
    if (remove) remove.disabled = false;
    rows.appendChild(clone);
    return;
  }
  const removePosRow = e.target.closest('[data-remove-pos-row]');
  if (removePosRow) {
    const rows = $('#posCartRows');
    if (rows?.querySelectorAll('.pos-cart-row').length > 1) removePosRow.closest('.pos-cart-row').remove();
    else toast('يجب أن تحتوي الفاتورة على سطر واحد على الأقل', 'info');
    return;
  }

  if (e.target.closest('#addPurchaseOrderRow')) {
    const rows = $('#purchaseOrderRows');
    const first = rows?.querySelector('.purchase-order-row');
    if (!rows || !first) return;
    if (rows.querySelectorAll('.purchase-order-row').length >= 20) { toast('الحد الأقصى 20 صنفًا في أمر التوريد', 'error'); return; }
    const clone = first.cloneNode(true);
    clone.querySelector('select').value = '';
    clone.querySelector('input[name="quantity"]').value = '1';
    clone.querySelector('input[name="unit_cost"]').value = '';
    clone.querySelector('[data-remove-purchase-row]').disabled = false;
    rows.appendChild(clone);
    return;
  }
  const removePurchaseRow = e.target.closest('[data-remove-purchase-row]');
  if (removePurchaseRow) {
    const rows = $('#purchaseOrderRows');
    if (rows?.querySelectorAll('.purchase-order-row').length > 1) removePurchaseRow.closest('.purchase-order-row').remove();
    else toast('يجب أن يحتوي الأمر على بند واحد على الأقل', 'info');
    return;
  }

  const paySupplierBill = e.target.closest('[data-pay-supplier-bill]');
  if(paySupplierBill){
    const bill=state.supplierBills.find(b=>b.id===paySupplierBill.dataset.paySupplierBill);
    if(!bill||bill.balanceDue<=0)return;
    openModal(`<div class="modal-header"><h3>دفعة للمورد — فاتورة ${esc(bill.bill_number)}</h3><button class="modal-close" data-close-modal>×</button></div>
      <p>المورد: <b>${esc(bill.supplierName)}</b></p><p class="mb-2">الرصيد المستحق: <b>${money(bill.balanceDue)}</b></p>
      <form id="supplierPaymentForm" class="form-grid" data-bill-id="${esc(bill.id)}">
        <div class="field"><label>قيمة الدفعة (ج.م)</label><input name="amount" type="number" min="0.01" max="${bill.balanceDue}" step="0.01" required></div>
        <div class="field"><label>طريقة الدفع</label><select name="method" required><option value="cash">نقدي</option><option value="bank_transfer">تحويل بنكي</option><option value="instapay">إنستاباي</option><option value="cheque">شيك</option><option value="other">أخرى</option></select></div>
        <div class="field"><label>الخزينة / البنك</label><select name="cash_account_id" required><option value="">اختر الحساب المالي</option>${(state.cashAccounts||[]).map(a=>'<option value="'+esc(a.id)+'">'+esc(a.name)+'</option>').join('')}</select></div>
        <div class="field"><label>رقم مرجعي (اختياري)</label><input name="reference" maxlength="120"></div>
        <div class="field"><label>ملاحظات</label><textarea name="notes" rows="2" maxlength="1000"></textarea></div>
        <button class="btn btn-primary" type="submit">تأكيد تسجيل الدفعة</button>
      </form>`);
    return;
  }

  const returnOrderButton = e.target.closest('[data-return-order]');
  if(returnOrderButton){
    const order=state.purchaseOrders.find(o=>o.id===returnOrderButton.dataset.returnOrder); if(!order)return;
    const available=(order.receiptItems||[]).map(ri=>({...ri,returned:state.supplierReturnItems.filter(x=>x.purchase_receipt_item_id===ri.id).reduce((n,x)=>n+Number(x.quantity),0)})).filter(ri=>Number(ri.quantity)>ri.returned);
    const bills=state.supplierBills.filter(b=>b.supplier_id===order.supplier_id&&(!b.purchase_order_id||b.purchase_order_id===order.id));
    if(!available.length){toast('لا توجد كميات مستلمة متبقية للإرجاع','info');return;}
    if(!bills.length){toast('سجّل فاتورة المورد واربطها بالمورد أو أمر التوريد قبل إنشاء إشعار الخصم','error');return;}
    const receiptUnitsResult=await supabase.from('purchase_receipt_units')
      .select('receipt_item_id,motorcycle_unit_id,motorcycle_units(vin,engine_number,unit_status)')
      .in('receipt_item_id',available.map(ri=>ri.id));
    if(receiptUnitsResult.error){toast('تعذر تحميل أرقام الوحدات المستلمة للمرتجع','error');return;}
    const rows=available.map(ri=>{
      const po=order.items.find(it=>it.id===ri.purchase_order_item_id);
      const unitOptions=(receiptUnitsResult.data||[]).filter(x=>x.receipt_item_id===ri.id&&x.motorcycle_units?.unit_status==='available');
      return '<div data-receipt-item-id="'+esc(ri.id)+'"><label>'+esc(po?.motorcycle_name||'الصنف')+' — وحدات متاحة للإرجاع '+unitOptions.length+' — تكلفة '+money(ri.unit_cost)+'</label><select name=unit_ids multiple size=4>'+unitOptions.map(x=>'<option value="'+esc(x.motorcycle_unit_id)+'">'+esc(x.motorcycle_units?.vin||'VIN غير متاح')+' — موتور '+esc(x.motorcycle_units?.engine_number||'—')+'</option>').join('')+'</select></div>';
    }).join('');
    const opts=bills.map(b=>'<option value="'+esc(b.id)+'">'+esc(b.bill_number)+' — الرصيد '+money(b.balanceDue)+'</option>').join('');
    openModal('<div class=modal-header><h3>مرتجع مشتريات '+esc(order.order_number)+'</h3><button class=modal-close data-close-modal>×</button></div><form id=supplierReturnForm data-order-id="'+esc(order.id)+'"><label>فاتورة المورد</label><select name=supplier_bill_id required><option value="">اختر الفاتورة</option>'+opts+'</select>'+rows+'<small class=hint>حدد أرقام الشاسيه الفعلية التي ستُعاد للمورد؛ ستُخرج هذه الوحدات من المخزون وتُربط بإشعار الخصم.</small><label>ملاحظات</label><textarea name=notes maxlength=1000></textarea><button class=btn btn-primary type=submit>تأكيد المرتجع</button></form>'); return;
  }
  const receiveOrderButton = e.target.closest('[data-receive-order]');
  if (receiveOrderButton) {
    const order = state.purchaseOrders.find(o=>o.id===receiveOrderButton.dataset.receiveOrder);
    const pendingItems = (order?.items || []).filter(item=>Number(item.quantity_ordered)>Number(item.quantity_received));
    if (!order || !pendingItems.length) { toast('لا توجد كمية متبقية للاستلام', 'error'); return; }
    openModal(`<div class="modal-header"><h3>استلام أمر ${esc(order.order_number)}</h3><button class="modal-close" data-close-modal>×</button></div>
      <form id="receivePurchaseForm" class="form-grid" data-order-id="${esc(order.id)}">
        <div class="form-grid">${pendingItems.map(item=>{const remaining=Number(item.quantity_ordered)-Number(item.quantity_received);return `<div class="purchase-order-row" data-item-id="${esc(item.id)}">
          <div class="field"><label>${esc(item.motorcycle_name)} — المتبقي ${remaining}</label><input name="quantity" type="number" min="0" max="${remaining}" value="${remaining}" required></div>
          <div class="form-grid">${Array.from({length:remaining},(_,index)=>`<div class="panel" data-unit-row>
            <b>بيانات الدراجة رقم ${index+1}</b>
            <div class="field"><label>رقم الشاسيه VIN</label><input name="vin" maxlength="80" autocomplete="off" placeholder="VIN إلزامي"></div>
            <div class="field"><label>رقم الموتور</label><input name="engine_number" maxlength="80"></div>
            <div class="form-row"><div class="field"><label>الباركود (يُولَّد تلقائياً من الشاسيه إن تُرك فارغاً)</label><input name="barcode" maxlength="80" placeholder="اختياري — توليد تلقائي"></div><div class="field"><label>عداد الكيلومترات</label><input name="odometer_reading" type="number" min="0" value="0"></div></div>
            <div class="field"><label>الحالة</label><select name="unit_condition"><option value="new">جديدة</option><option value="used">مستعملة</option></select></div>
            <div class="form-row"><div class="field"><label>بداية الضمان</label><input name="warranty_start" type="date"></div><div class="field"><label>نهاية الضمان</label><input name="warranty_end" type="date"></div></div>
          </div>`).join('')}</div>
        </div>`}).join('')}</div>
        <div class="field"><label>ملاحظات الاستلام</label><textarea name="notes" rows="2" maxlength="1000"></textarea></div>
        <small class="hint">أدخل رقم الشاسيه لكل دراجة مستلمة. تُنشأ سجلات الوحدات وتُحدّث الكمية وتكلفة الاستلام في معاملة واحدة. يمكن الاستلام على دفعات.</small>
        <button class="btn btn-primary" type="submit">تأكيد الاستلام وربط أرقام الشاسيه</button>
      </form>`);
    return;
  }

  const returnSaleButton = e.target.closest('[data-return-sale]');
  if (returnSaleButton) {
    if (!canUseVinScanner() || !supabase) { toast('ليس لديك صلاحية تسجيل مرتجعات المبيعات','error'); return; }
    const sale = state.sales.find(s => s.id === returnSaleButton.dataset.returnSale);
    if (!sale) return;
    const { data: saleItems, error } = await supabase.from('sale_items')
      .select('id,motorcycle_id,motorcycle_name,model_year,quantity,unit_price')
      .eq('sale_id', sale.id).order('created_at');
    if (error) { toast('تعذر تحميل بنود الفاتورة','error'); return; }
    const saleItemIds = (saleItems || []).map(item => item.id);
    const unitResult = saleItemIds.length
      ? await supabase.from('sale_item_units').select('sale_item_id,vin_snapshot,engine_number_snapshot').in('sale_item_id', saleItemIds)
      : {data:[],error:null};
    if (unitResult.error) { toast('تعذر تحميل أرقام الشاسيه المرتبطة بالفاتورة','error'); return; }
    const unitSnapshots = unitResult.data || [];
    const items = (saleItems || []).map(item => {
      const returned = state.saleReturnItems.filter(x => x.sale_item_id === item.id).reduce((n,x)=>n+Number(x.quantity),0);
      return {
        ...item,
        unitSnapshots: unitSnapshots.filter(unit => unit.sale_item_id === item.id),
        remaining: Number(item.quantity)-returned
      };
    }).filter(item => item.remaining > 0);
    if (!items.length) { toast('تم إرجاع كامل كميات هذه الفاتورة','info'); return; }
    const rows = items.map(item => {
      const unitLabel = item.unitSnapshots.length
        ? item.unitSnapshots.map(unit => `VIN: ${esc(unit.vin_snapshot)}${unit.engine_number_snapshot ? ` — موتور: ${esc(unit.engine_number_snapshot)}` : ''}`).join(' | ')
        : 'فاتورة قديمة غير مرتبطة بأرقام شاسيه';
      return `<div class="sale-return-row form-row" data-sale-item-id="${esc(item.id)}">
      <div class="field"><label>${esc(item.motorcycle_name)} — موديل ${esc(item.model_year || '—')} — المتبقي ${item.remaining}</label>
      <small class="hint">${unitLabel}</small>
      <input name="quantity" type="number" min="0" max="${item.remaining}" value="0" required></div>
      <div class="field"><label>حالة القطعة</label><select name="disposition"><option value="restock">صالحة لإعادة البيع (إضافة للمخزون)</option><option value="damaged">تالفة / لا تعاد للمخزون</option></select></div>
      <small class="hint">سعر الوحدة: ${money(item.unit_price)}</small></div>`;
    }).join('');
    openModal(`<div class="modal-header"><h3>مرتجع فاتورة ${esc(sale.invoice_number)}</h3><button class="modal-close" data-close-modal>×</button></div>
      <p>العميل: <b>${esc(sale.customer_name)}</b> — إجمالي الفاتورة: ${money(sale.total)}</p>
      <p class="hint">تُخصم قيمة المرتجع من مديونية الفاتورة أولًا؛ لا ينشأ رصيد قابل للرد إلا إذا تجاوز ما دفعه العميل إجمالي الفاتورة بعد المرتجعات.</p>
      <form id="saleReturnForm" class="form-grid" data-sale-id="${esc(sale.id)}">
        ${rows}<div class="field"><label>ملاحظات</label><textarea name="notes" maxlength="1000"></textarea></div>
        <button class="btn btn-primary" type="submit">تأكيد المرتجع</button></form>`);
    return;
  }

  const refundCredit = e.target.closest('[data-refund-credit]');
  if (refundCredit) {
    if (!hasRole('admin') || !supabase) { toast('ليس لديك صلاحية رد أموال العملاء','error'); return; }
    const customer = state.customerCredits.find(c=>c.customerId===refundCredit.dataset.refundCredit);
    if (!customer || customer.balance <= 0) return;
    openModal(`<div class="modal-header"><h3>رد رصيد العميل</h3><button class="modal-close" data-close-modal aria-label="إغلاق">×</button></div>
      <p>العميل: <b>${esc(customer.name)}</b> — الرصيد المتاح: <b>${money(customer.balance)}</b></p>
      <form id="customerCreditRefundForm" class="form-grid" data-customer-id="${esc(customer.customerId)}" data-balance="${customer.balance}">
        <div class="field"><label>مبلغ الرد (ج.م)</label><input name="amount" type="number" min="0.01" max="${customer.balance}" step="0.01" required></div>
        <div class="field"><label>طريقة الصرف</label><select name="method"><option value="cash">نقدي</option><option value="bank_transfer">تحويل بنكي</option><option value="card">بطاقة</option><option value="other">أخرى</option></select></div>
        <div class="field"><label>مرجع الصرف (اختياري)</label><input name="reference" maxlength="120"></div>
        <div class="field"><label>ملاحظات</label><textarea name="notes" maxlength="1000"></textarea></div>
        <small class="hint">سجّل العملية بعد تنفيذ الصرف الفعلي. هذا الإجراء لا يحوّل الأموال تلقائيًا.</small>
        <button class="btn btn-primary" type="submit">تأكيد تسجيل الصرف</button>
      </form>`);
    return;
  }

  const applyCredit = e.target.closest('[data-apply-credit]');
  if (applyCredit) {
    if (!canUseVinScanner() || !supabase) { toast('ليس لديك صلاحية استخدام أرصدة العملاء','error'); return; }
    const sale = state.sales.find(x=>x.id===applyCredit.dataset.applyCredit);
    const credit = sale && state.customerCredits.find(x=>x.customerId===sale.customer_id);
    if (!sale || !credit || credit.balance<=0) return;
    const due = Math.max(0,Number(sale.total)-Number(sale.amount_paid)-Number(sale.credit_applied||0)-Number(sale.returnedAmount||0));
    const max = Math.min(due,credit.balance);
    if (max<=0) { toast('لا يوجد رصيد مستحق على الفاتورة أو رصيد دائن متاح','info'); return; }
    openModal(`<div class="modal-header"><h3>استخدام رصيد العميل</h3><button class="modal-close" data-close-modal aria-label="إغلاق">×</button></div>
      <p>الفاتورة: <b>${esc(sale.invoice_number)}</b> — العميل: <b>${esc(sale.customer_name)}</b></p>
      <p>الرصيد الدائن المتاح: <b>${money(credit.balance)}</b> — المتبقي على الفاتورة: <b>${money(due)}</b></p>
      <form id="applyCustomerCreditForm" class="form-grid" data-sale-id="${esc(sale.id)}" data-max="${max}">
        <div class="field"><label>قيمة الرصيد المستخدم (ج.م)</label><input name="amount" type="number" min="0.01" max="${max}" step="0.01" required></div>
        <div class="field"><label>مرجع أو ملاحظة (اختياري)</label><input name="reference" maxlength="120"></div>
        <small class="hint">سيُخصم المبلغ من رصيد العميل ويُسجل كجزء من تسوية هذه الفاتورة، دون إنشاء دفعة نقدية.</small>
        <button class="btn btn-primary" type="submit">تأكيد استخدام الرصيد</button>
      </form>`);
    return;
  }

  const viewInvoiceButton = e.target.closest('[data-view-invoice]');
  if (viewInvoiceButton) {
    if (!supabase) return;
    viewInvoiceButton.disabled = true;
    const {data,error}=await supabase.rpc('get_sale_invoice',{p_sale_id:viewInvoiceButton.dataset.viewInvoice});
    viewInvoiceButton.disabled = false;
    if(error){toast(error.message||'تعذر استرجاع الفاتورة المحفوظة','error');return;}
    const invoiceRows=(data.items||[]).flatMap(item=>{
      const units=item.units||[];
      if(!units.length)return [`<tr><td>${esc(item.motorcycle_name)}</td><td>—</td><td>—</td><td>${item.quantity}</td><td>${money(item.unit_price)}</td><td>${money(item.line_total)}</td></tr>`];
      return units.map(unit=>`<tr><td>${esc(item.motorcycle_name)}</td><td>${esc(unit.vin||'—')}</td><td>${esc(unit.engine_number||'—')}</td><td>1</td><td>${money(item.unit_price)}</td><td>${money(item.unit_price)}</td></tr>`);
    }).join('');
    const paymentRows=(data.payments||[]).map(payment=>`<tr><td>${new Date(payment.paid_at).toLocaleString('ar-EG')}</td><td>${esc(payment.method)}</td><td>${esc(payment.reference||'—')}</td><td>${money(payment.amount)}</td></tr>`).join('');
    const returned=(data.returns||[]).reduce((sum,item)=>sum+Number(item.total_amount||0),0);
    const due=Math.max(0,Number(data.total||0)-Number(data.amount_paid||0)-Number(data.credit_applied||0)-returned);
    const invoice=`<div class="invoice">
      <div class="invoice-header"><div><h2>El Khayal Motors</h2><p>نسخة محفوظة من فاتورة البيع</p></div><div class="invoice-meta"><b>${esc(data.invoice_number)}</b><br><span>${new Date(data.created_at).toLocaleString('ar-EG')}</span></div></div>
      <hr><p><b>العميل:</b> ${esc(data.customer_name||'عميل نقدي')}</p><p><b>الهاتف:</b> ${esc(data.customer_phone||'—')}</p>
      <div class="table-wrap"><table><thead><tr><th>الصنف</th><th>رقم الشاسيه</th><th>رقم الموتور</th><th>الكمية</th><th>سعر الوحدة</th><th>الإجمالي</th></tr></thead><tbody>${invoiceRows}</tbody></table></div>
      <p><b>الإجمالي:</b> ${money(data.total)}</p><p><b>المدفوع:</b> ${money(data.amount_paid)}</p><p><b>رصيد مستخدم:</b> ${money(data.credit_applied)}</p><p><b>قيمة المرتجعات:</b> ${money(returned)}</p><p><b>المتبقي:</b> ${money(due)}</p>
      <h4>المدفوعات</h4><div class="table-wrap"><table><thead><tr><th>التاريخ</th><th>الطريقة</th><th>المرجع</th><th>المبلغ</th></tr></thead><tbody>${paymentRows||'<tr><td colspan="4">لا توجد دفعات</td></tr>'}</tbody></table></div>
      <p class="text-center">هذه نسخة مسترجعة من السجل المحفوظ في النظام</p>
    </div><div class="contact-actions no-print"><button class="btn btn-primary" id="printInvoiceBtn" type="button">طباعة الفاتورة</button><button class="btn btn-outline" data-close-modal>إغلاق</button></div>`;
    openModal(invoice);
    return;
  }

  const collectPayment = e.target.closest('[data-collect-payment]');
  if (collectPayment) {
    const sale = state.sales.find((item) => item.id === collectPayment.dataset.collectPayment);
    if (!sale) return;
    const balance = Math.max(0, Number(sale.total) - Number(sale.amount_paid) - Number(sale.credit_applied || 0) - Number(sale.returnedAmount || 0));
    openModal(`<div class="modal-header"><h3>تحصيل دفعة — ${esc(sale.invoice_number)}</h3><button class="modal-close" data-close-modal aria-label="إغلاق"><i class="fa-solid fa-xmark"></i></button></div>
      <p class="mb-2">الرصيد المستحق: <b>${money(balance)}</b></p>
      <form id="collectPaymentForm" class="form-grid" data-sale-id="${esc(sale.id)}">
        <div class="field"><label for="collectAmount">قيمة الدفعة</label><input id="collectAmount" name="amount" type="number" min="0.01" max="${balance}" step="0.01" required></div>
        <div class="field"><label for="collectMethod">طريقة الدفع</label><select id="collectMethod" name="method"><option value="cash">نقدي</option><option value="bank_transfer">تحويل بنكي</option><option value="card">بطاقة</option><option value="other">أخرى</option></select></div>
        <div class="field"><label>استلمت الدفعة في</label><select name="cash_account_id" required><option value="">اختر الخزينة / البنك</option>${(state.salesCashAccounts||[]).map(a=>'<option value="'+esc(a.id)+'">'+esc(a.name)+' — '+esc(a.account_kind==='bank'?'بنك':'خزينة')+'</option>').join('')}</select></div>
        <div class="field"><label for="collectReference">مرجع الدفع (اختياري)</label><input id="collectReference" name="reference" maxlength="120"></div>
        <button class="btn btn-primary" type="submit">حفظ الدفعة</button>
      </form>`);
    return;
  }

  /* Slider prev/next */
  const slideBtn = e.target.closest('[data-slide]');
  if (slideBtn) {
    const card = slideBtn.closest('[data-bike-id]');
    if (!card) return;
    const bikeId = card.dataset.bikeId;
    const bike = get(DB.BIKES).find((b) => b.id === bikeId);
    if (!bike || !bike.images || !bike.images.length) return;
    const wrap = slideBtn.closest('[data-slider]');
    let idx = Number(wrap.dataset.idx || 0);
    const total = bike.images.length;
    idx = slideBtn.dataset.slide === 'next'
      ? (idx + 1) % total
      : (idx - 1 + total) % total;
    wrap.dataset.idx = String(idx);
    const img = wrap.querySelector('[data-slide-img]');
    if (img) img.src = bike.images[idx];
    wrap.querySelectorAll('[data-dots] span').forEach((d, i) => d.classList.toggle('active', i === idx));
    return;
  }

  /* Favorites: guests are redirected to sign-in and returned to the selected bike action. */
  const favBtn = e.target.closest('[data-fav]');
  if (favBtn) { await toggleFavorite(favBtn.dataset.fav); return; }

  /* Buy */
  const buyBtn = e.target.closest('[data-buy]');
  if (buyBtn) { handleBuy(buyBtn.dataset.buy, buyBtn.dataset.unitId || null); return; }
  const confirmBtn = e.target.closest('[data-confirm-buy]');
  if (confirmBtn) { confirmBuy(confirmBtn.dataset.confirmBuy); return; }
  const loginAction = e.target.closest('[data-login-action]');
  if (loginAction) { requireCustomerLogin(loginAction.dataset.loginAction, loginAction.dataset.bikeId || null, loginAction.dataset.unitId || null); return; }

  /* Details */
  const detailsBtn = e.target.closest('[data-details]');
  if (detailsBtn) {
    const bike = get(DB.BIKES).find((b) => b.id === detailsBtn.dataset.details);
    if (!bike) return;
    const storeUnit = (state.storeUnits || []).find((unit)=>unit.unit_id===detailsBtn.dataset.unitId);
    const img = (bike.images && bike.images[0]) || '';
    openModal(`
      <div class="modal-header">
        <h3><i class="fa-solid fa-motorcycle"></i> ${esc(bike.name)}</h3>
        <button class="modal-close" data-close-modal aria-label="إغلاق"><i class="fa-solid fa-xmark"></i></button>
      </div>
      ${img ? `<img src="${esc(safeImageUrl(img))}" alt="${esc(bike.name)}" style="width:100%;height:220px;object-fit:cover;border-radius:12px;margin-bottom:14px">` : ''}
      <p class="mb-1"><b>الموديل:</b> ${esc(bike.model)}</p>
      <p class="mb-1"><b>الفئة:</b> ${esc(bike.category)}</p>
      <p class="mb-1"><b>السعر:</b> <span class="text-red" style="font-weight:900">${money(bike.price)}</span></p>
      ${bike.description ? `<div class="bike-description"><b>التفاصيل والمواصفات:</b><p>${esc(bike.description).replace(/\n/g, '<br>')}</p></div>` : ''}
      <p><b>الوحدة:</b> دراجة واحدة متاحة حالياً</p>
      <p><b>الحالة:</b> ${storeUnit?.unit_condition === 'used' ? 'مستعملة' : 'جديدة'}</p>
    `);
    return;
  }

  /* Manager or explicitly authorized staff — catalog */
  if (e.target.closest('#addBikeBtn')) {
    if (!hasRole('admin','manager','owner') && !hasPermission('catalog_manage')) { toast('ليس لديك صلاحية المعرض / الكتالوج', 'error'); return; }
    openModal(bikeFormHTML(null)); return;
  }
  const addUnitButton = e.target.closest('[data-add-unit-for]');
  if (addUnitButton) {
    if (!hasRole('admin','manager','owner') && !hasPermission('catalog_manage')) { toast('ليس لديك صلاحية إضافة وحدات', 'error'); return; }
    openModal(unitRegistrationFormHTML(addUnitButton.dataset.addUnitFor)); return;
  }
  const editUnitButton = e.target.closest('[data-edit-unit]');
  if (editUnitButton) {
    if (!hasRole('admin','manager','owner') && !hasPermission('catalog_manage') && !hasPermission('finance_manage')) { toast('ليس لديك صلاحية تعديل الوحدة', 'error'); return; }
    const unit = (state.motorcycleUnits || []).find((item)=>item.id===editUnitButton.dataset.editUnit);
    if (unit) openModal(unitEditFormHTML(unit));
    return;
  }
  const deleteUnitButton = e.target.closest('[data-delete-unit]');
  if (deleteUnitButton) {
    if ((!hasRole('admin','manager','owner') && !hasPermission('catalog_manage')) || !supabase) { toast('ليس لديك صلاحية حذف سجل الوحدة','error'); return; }
    const vin = deleteUnitButton.dataset.unitVin || 'هذه الوحدة';
    if (!confirm('هل تريد حذف سجل الشاسيه '+vin+' نهائيًا؟ لن يسمح النظام بالحذف إذا كانت الوحدة مرتبطة بفاتورة بيع أو استلام أو فاتورة مورد أو مرتجع أو أمر صيانة.')) return;
    deleteUnitButton.disabled = true;
    const {error} = await supabase.rpc('delete_motorcycle_unit',{p_unit_id:deleteUnitButton.dataset.deleteUnit});
    if(error){deleteUnitButton.disabled=false;toast(error.message||'تعذر حذف سجل الوحدة','error');return;}
    await Promise.all([loadMotorcycleUnits(),loadStoreUnits(),loadMotorcycles()]);
    render();
    toast('تم حذف سجل الوحدة وتحديث رصيد المخزون','success');
    return;
  }
  const archiveBike = e.target.closest('[data-archive-bike]');
  if (archiveBike) {
    if ((!hasRole('admin','manager','owner') && !hasPermission('catalog_manage')) || !supabase) { toast('ليس لديك صلاحية أرشفة الدراجات', 'error'); return; }
    const bikeId = archiveBike.dataset.archiveBike;
    const bikeName = archiveBike.dataset.bikeName || 'هذه الدراجة';
    if (!confirm('سيتم إخفاء «' + bikeName + '» من المتجر مع الاحتفاظ بكل الوحدات والفواتير وحركات المخزون. يمكنك إعادة نشرها بتعديل حالتها إلى متاحة. هل تريد المتابعة؟')) return;
    archiveBike.disabled = true;
    const { error } = await supabase.from('motorcycles').update({ status: 'unavailable' }).eq('id', bikeId);
    if (error) { archiveBike.disabled = false; toast(error.message || 'تعذرت أرشفة الدراجة', 'error'); return; }
    await Promise.all([loadMotorcycles(), loadStoreUnits()]);
    render();
    toast('تمت أرشفة الدراجة وإخفاؤها من المتجر مع الاحتفاظ بسجلها', 'success');
    return;
  }

  const deleteBike = e.target.closest('[data-delete-bike]');
  if (deleteBike) {
    if ((!hasRole('admin','manager','owner') && !hasPermission('catalog_manage')) || !supabase) { toast('ليس لديك صلاحية حذف الدراجات', 'error'); return; }
    const bikeName = deleteBike.dataset.bikeName || 'هذه الدراجة';
    if (!confirm('هل تريد حذف الدراجة التجريبية «' + bikeName + '»؟ سيتم حذف وحداتها التجريبية فقط. إذا كانت مرتبطة بمشتريات أو حركات مخزون فلن يسمح النظام بحذفها حفاظًا على السجلات.')) return;
    deleteBike.disabled = true;
    const { error } = await supabase.rpc('delete_demo_motorcycle', { p_motorcycle_id: deleteBike.dataset.deleteBike });
    if (error) { deleteBike.disabled = false; toast(error.message || 'تعذر حذف الدراجة', 'error'); return; }
    await Promise.all([loadMotorcycles(), loadInventoryData()]);
    render();
    toast('تم حذف الدراجة التجريبية ووحداتها', 'success');
    return;
  }
  const editBike = e.target.closest('[data-edit-bike]');
  if (editBike) {
    if (!hasRole('admin','manager','owner') && !hasPermission('catalog_manage')) { toast('ليس لديك صلاحية المعرض / الكتالوج', 'error'); return; }
    const bike = get(DB.BIKES).find((b) => b.id === editBike.dataset.editBike);
    if (bike) openModal(bikeFormHTML(bike));
    return;
  }


  const replyButton = e.target.closest('[data-open-reply]');
  if (replyButton) {
    if (!hasPermission('requests_manage')) { toast('ليس لديك صلاحية الرد على العملاء', 'error'); return; }
    const kind = replyButton.dataset.openReply;
    const id = replyButton.dataset.recordId;
    const item = kind === 'request' ? get(DB.CUSTOM_REQS).find((x) => x.id === id) : state.contactMessages.find((x) => x.id === id);
    if (!item) return;
    const person = kind === 'request'
      ? {name:item.customerName,phone:item.customerPhone,email:item.customerEmail}
      : {name:item.name,phone:item.phone,email:item.email};
    const message = kind === 'request' ? `بخصوص طلب ${item.bikeName || ''}` : item.message;
    openModal(`<div class="modal-header"><h3>التواصل مع ${esc(person.name || 'العميل')}</h3><button class="modal-close" data-close-modal aria-label="إغلاق"><i class="fa-solid fa-xmark"></i></button></div>
      <p class="mb-2">${esc(message)}</p><div class="contact-actions">${contactActionLinks(person, 'مرحبًا ' + (person.name || '') + '، معك فريق El Khayal Motors. ' + message)}</div>
      <p class="hint">افتح قناة الاتصال وأرسل الرد بنفسك، ثم سجّل الرد أدناه لحفظه في سجل العميل.</p>
      <form id="customerReplyForm" class="form-grid" data-kind="${esc(kind)}" data-record-id="${esc(id)}">
        <div class="field"><label>نص الرد أو ملخص المكالمة</label><textarea name="reply_body" required maxlength="10000"></textarea></div>
        <div class="field"><label>القناة المستخدمة</label><select name="channel"><option value="whatsapp">واتساب</option><option value="phone">مكالمة هاتفية</option><option value="email">بريد إلكتروني</option><option value="sms">SMS</option><option value="internal">ملاحظة داخلية فقط</option></select></div>
        <label class="field"><span><input type="checkbox" name="sent" value="yes"> أؤكد أنني أرسلت الرد أو أجريت المكالمة بالفعل</span></label>
        <button class="btn btn-primary" type="submit">حفظ سجل الرد</button>
      </form>`);
    return;
  }

  const syncPhotosButton = e.target.closest('#syncTelegramPhotosBtn');
  if (syncPhotosButton) {
    if (!hasPermission('catalog_manage') || !supabase) { toast('ليس لديك صلاحية مزامنة صور الكتالوج', 'error'); return; }
    syncPhotosButton.disabled = true;
    const originalText = syncPhotosButton.innerHTML;
    syncPhotosButton.textContent = 'جارٍ مزامنة الصور القديمة...';
    let synced = 0, failed = 0, pending = null, failureMessage = '';
    try {
      for (let batch = 0; batch < 10; batch++) {
        const { data, error } = await supabase.functions.invoke('telegram-photo-sync', { body: {} });
        if (error || data?.error) { failureMessage = data?.error || error?.message || 'تعذرت مزامنة الصور'; break; }
        synced += Number(data?.synced_count || 0);
        failed += Number(data?.failed_count || 0);
        pending = data?.pending_remaining;
        if (!pending || (Number(data?.synced_count || 0) === 0 && Number(data?.failed_count || 0) === 0)) break;
      }
      await loadMotorcycles();
      render();
      if (failureMessage) toast(failureMessage, 'error');
      else toast(`تمت مزامنة ${synced} صورة، وتعذر ${failed} صورة، والمتبقي ${pending ?? 'غير معروف'}`, failed ? 'error' : 'success');
    } finally {
      const current = $('#syncTelegramPhotosBtn');
      if (current) { current.disabled = false; current.innerHTML = originalText; }
    }
    return;
  }

  /* Delete only closed customer requests; management permission is enforced again in SQL. */
  const deleteRequestButton = e.target.closest('[data-delete-request]');
  if (deleteRequestButton) {
    if (!hasRole('admin')) { toast('الحذف النهائي متاح للإدارة فقط', 'error'); return; }
    const request = state.user && get(DB.CUSTOM_REQS).find((item) => item.id === deleteRequestButton.dataset.deleteRequest);
    if (!request || !['rejected','completed','expired'].includes(request.status)) {
      toast('لا يمكن حذف طلب مفتوح أو غير موجود', 'error');
      return;
    }
    if (!window.confirm('سيتم حذف الطلب المغلق وسجل الردود المرتبط به نهائيًا. هل تريد المتابعة؟')) return;
    const { error } = await supabase.rpc('delete_closed_customer_request', { p_request_id: request.id });
    if (error) { toast(error.message || 'تعذر حذف الطلب', 'error'); return; }
    await loadBusinessData();
    render();
    toast('تم حذف الطلب المغلق وسجل ردوده', 'success');
    return;
  }

  /* Update customer request status in Supabase under RLS. */
  const statusButton = e.target.closest('[data-approve-req], [data-reject-req], [data-expire-req]');
  if (statusButton) {
    if (!hasPermission('requests_manage')) { toast('ليس لديك صلاحية تحديث الطلبات', 'error'); return; }
    const id = statusButton.dataset.approveReq || statusButton.dataset.rejectReq || statusButton.dataset.expireReq;
    const status = statusButton.dataset.approveReq ? 'approved' : statusButton.dataset.rejectReq ? 'rejected' : 'expired';
    const { error } = await supabase.from('customer_requests').update({ status }).eq('id', id);
    if (error) { toast(error.message, 'error'); return; }
    await loadBusinessData();
    toast(status === 'approved' ? 'تم قبول الطلب' : status === 'rejected' ? 'تم رفض الطلب' : 'تم اعتبار الطلب منتهيًا', 'success');
    render();
    return;
  }

});

/* ---------- Event: Submit Delegation ---------- */
document.addEventListener('submit', async (e) => {
  e.preventDefault();
  const form = e.target;
  if (form.id === 'cashAccountForm') {
    if (!hasRole('admin','manager','owner') || !supabase) { toast('إدارة الخزائن والبنوك متاحة للإدارة فقط','error'); return; }
    const fd = new FormData(form), name = safeName(fd.get('name')), kind = String(fd.get('kind') || '');
    if (!name || !['cash','bank'].includes(kind)) { toast('أدخل اسم الحساب ونوعه بصورة صحيحة','error'); return; }
    const btn = form.querySelector('[type=submit]'); if (btn) btn.disabled = true;
    const {data,error} = await supabase.rpc('create_cash_account',{p_name:name,p_kind:kind});
    if (btn) btn.disabled = false;
    if (error) { toast(error.message || 'تعذرت إضافة الحساب','error'); return; }
    await loadFinanceData(); render();
    toast('تمت إضافة '+(kind==='bank'?'الحساب البنكي':'الخزينة')+' برقم حساب '+(data?.account_code || ''),'success');
    return;
  }

  if (form.id === 'saleDeliveryForm') {
    if (!hasRole('admin','manager','owner') && !hasPermission('sales_manage')) { toast('ليس لديك صلاحية تسجيل محضر التسليم','error'); return; }
    const fd=new FormData(form);
    const {error}=await supabase.rpc('create_sale_delivery',{p_sale_id:fd.get('sale_id'),p_delivered_at:null,p_recipient_name:safeName(fd.get('recipient_name')),p_recipient_phone:safeName(fd.get('recipient_phone'))||null,p_odometer_reading:fd.get('odometer_reading')?Number(fd.get('odometer_reading')):null,p_accessories:safeName(fd.get('accessories'))||null,p_condition_notes:safeName(fd.get('condition_notes'))||null,p_notes:safeName(fd.get('notes'))||null});
    if(error){toast(error.message||'تعذر حفظ محضر التسليم','error');return;}
    await loadSalesData();render();toast('تم حفظ محضر التسليم ويمكن طباعته من الجدول','success');return;
  }

  if (form.id === 'salesQuotationForm') {
    if (!hasRole('admin','manager','owner') && !hasPermission('sales_manage')) { toast('ليس لديك صلاحية إنشاء عرض سعر','error'); return; }
    const fd=new FormData(form),items=[];
    for(const row of form.querySelectorAll('[data-quote-line]')){
      const quantity=Number(row.querySelector('[name="quantity"]').value||0);
      if(quantity>0)items.push({motorcycle_id:row.dataset.quoteLine,quantity,unit_price:Number(row.querySelector('[name="unit_price"]').value||0)});
    }
    if(!items.length){toast('اختر دراجة واحدة على الأقل في عرض السعر','error');return;}
    const {error}=await supabase.rpc('create_sales_quotation',{p_customer_id:fd.get('customer_id')||null,p_name:safeName(fd.get('customer_name')),p_phone:safeName(fd.get('customer_phone')),p_valid_until:fd.get('valid_until'),p_notes:safeName(fd.get('notes'))||null,p_items:items});
    if(error){toast(error.message||'تعذر إنشاء عرض السعر','error');return;}await loadSalesToolsData();render();toast('تم إنشاء عرض السعر دون حجز المخزون','success');return;
  }
  if (form.id === 'quotationStatusForm') {
    const fd=new FormData(form);const {error}=await supabase.rpc('update_sales_quotation_status',{p_quote_id:form.dataset.quoteId,p_status:fd.get('status')});
    if(error){toast(error.message||'تعذر تحديث عرض السعر','error');return;}await loadSalesToolsData();render();toast('تم تحديث حالة عرض السعر','success');return;
  }
  if (form.id === 'convertQuotationForm') {
    const fd=new FormData(form);const {data,error}=await supabase.rpc('convert_sales_quotation',{p_quote_id:form.dataset.quoteId,p_payment_amount:Number(fd.get('payment_amount')||0),p_payment_method:fd.get('payment_method'),p_reference:null});
    if(error){toast(error.message||'تعذر تحويل عرض السعر إلى فاتورة','error');return;}await Promise.all([loadSalesToolsData(),loadSalesData(),loadMotorcycles(),loadFinanceData()]);render();toast('تم تحويل عرض السعر إلى فاتورة رقم '+(data?.sale_result?.invoice_number||data?.sale_id||''),'success');return;
  }
  if (form.id === 'installmentScheduleForm') {
    const fd=new FormData(form);let schedule;
    try{schedule=JSON.parse(fd.get('schedule_json'));}catch{toast('صيغة جدول الأقساط JSON غير صحيحة','error');return;}
    if(!Array.isArray(schedule)){toast('جدول الأقساط يجب أن يكون قائمة','error');return;}
    const {error}=await supabase.rpc('create_sale_installment_schedule',{p_sale_id:fd.get('sale_id'),p_schedule:schedule});
    if(error){toast(error.message||'تعذر إنشاء جدول الأقساط','error');return;}await loadSalesToolsData();render();toast('تم إنشاء جدول الأقساط وربطه بالفاتورة','success');return;
  }
  if (form.id === 'installmentPaymentForm') {
    const fd=new FormData(form);const {error}=await supabase.rpc('record_sale_installment_payment',{p_installment_id:form.dataset.installmentId,p_amount:Number(fd.get('amount')),p_method:fd.get('method'),p_reference:null});
    if(error){toast(error.message||'تعذر تحصيل القسط','error');return;}await Promise.all([loadSalesToolsData(),loadSalesData(),loadFinanceData()]);render();toast('تم تحصيل القسط وتحديث رصيد الفاتورة','success');return;
  }

  if (form.id === 'customerProfileMetaForm') {
    if (!hasRole('admin','manager','owner') && !hasPermission('customer_data_manage')) { toast('ليس لديك صلاحية تعديل ملف العميل','error'); return; }
    const fd=new FormData(form);const {error}=await supabase.rpc('set_customer_profile_meta',{p_customer_id:form.dataset.customerId,p_credit_limit:fd.get('credit_limit')?Number(fd.get('credit_limit')):null,p_segment:fd.get('customer_segment'),p_lead_source:safeName(fd.get('lead_source'))||null,p_marketing_consent:fd.get('marketing_consent')==='on'});
    if(error){toast(error.message||'تعذر تحديث ملف العميل','error');return;}await loadCRMData();render();toast('تم تحديث ملف العميل والحد الائتماني','success');return;
  }
  if (form.id === 'customerInteractionForm') {
    if (!hasRole('admin','manager','owner') && !hasPermission('customer_data_manage')) { toast('ليس لديك صلاحية تسجيل التفاعل','error'); return; }
    const fd=new FormData(form);const {error}=await supabase.rpc('create_customer_interaction',{p_customer_id:fd.get('customer_id'),p_type:fd.get('interaction_type'),p_subject:safeName(fd.get('subject')),p_notes:safeName(fd.get('notes'))||null,p_follow_up:fd.get('next_follow_up')?new Date(fd.get('next_follow_up')).toISOString():null});
    if(error){toast(error.message||'تعذر تسجيل التفاعل','error');return;}await loadCRMData();render();toast('تم تسجيل تفاعل العميل','success');return;
  }
  if (form.id === 'customerComplaintForm') {
    if (!hasRole('admin','manager','owner') && !hasPermission('customer_data_manage')) { toast('ليس لديك صلاحية تسجيل الشكوى','error'); return; }
    const fd=new FormData(form);const {error}=await supabase.rpc('create_customer_complaint',{p_customer_id:fd.get('customer_id')||null,p_name:safeName(fd.get('customer_name')),p_phone:safeName(fd.get('customer_phone'))||null,p_subject:safeName(fd.get('subject')),p_description:safeName(fd.get('description')),p_priority:fd.get('priority'),p_assigned_to:null});
    if(error){toast(error.message||'تعذر تسجيل الشكوى','error');return;}await loadCRMData();render();toast('تم تسجيل الشكوى','success');return;
  }
  if (form.id === 'customerComplaintUpdateForm') {
    if (!hasRole('admin','manager','owner') && !hasPermission('customer_data_manage')) { toast('ليس لديك صلاحية تحديث الشكوى','error'); return; }
    const fd=new FormData(form);const {error}=await supabase.rpc('update_customer_complaint',{p_id:form.dataset.complaintId,p_status:fd.get('status'),p_resolution:safeName(fd.get('resolution'))||null,p_assigned_to:null});
    if(error){toast(error.message||'تعذر تحديث الشكوى','error');return;}await loadCRMData();render();toast('تم تحديث حالة الشكوى','success');return;
  }
  if (form.id === 'internalNotificationForm') {
    const fd=new FormData(form);const {error}=await supabase.rpc('create_internal_notification',{p_user_id:fd.get('user_id'),p_title:safeName(fd.get('title')),p_body:safeName(fd.get('body'))||null,p_category:fd.get('category')});
    if(error){toast(error.message||'تعذر إرسال الإشعار','error');return;}await loadCRMData();render();toast('تم إرسال الإشعار الداخلي','success');return;
  }
  if (form.id === 'markNotificationReadForm') {
    const {error}=await supabase.rpc('mark_internal_notification_read',{p_id:form.dataset.notificationId});
    if(error){toast(error.message||'تعذر تحديث الإشعار','error');return;}await loadCRMData();render();toast('تم تحديد الإشعار كمقروء','success');return;
  }

  if (form.id === 'sellPriceForm') {
    if (!hasRole('admin','manager','owner') && !hasPermission('catalog_manage')) { toast('ليس لديك صلاحية تعديل سعر البيع','error'); return; }
    if (!supabase) { toast('الاتصال غير متاح','error'); return; }
    const fd = new FormData(form);
    const bikeId = form.dataset.bikeId;
    const price = Number(fd.get('price'));
    if (!bikeId || !(price >= 0)) { toast('أدخل سعراً صحيحاً','error'); return; }
    const btn = form.querySelector('[type=submit]'); if (btn) btn.disabled = true;
    const { error } = await supabase.from('motorcycles').update({ price }).eq('id', bikeId);
    if (btn) btn.disabled = false;
    if (error) { toast(error.message || 'تعذر حفظ سعر البيع','error'); return; }
    await Promise.all([loadMotorcycles(), loadInventoryData()]);
    render();
    toast('تم تحديث سعر البيع','success');
    return;
  }

  if (form.id === 'marketPriceForm') {
    if (!hasRole('admin','manager','owner') && !hasPermission('catalog_manage')) { toast('ليس لديك صلاحية تعديل سعر السوق','error'); return; }
    const fd = new FormData(form);
    const bikeId = form.dataset.bikeId;
    setMarketPrice(bikeId, fd.get('market_price') === '' ? null : Number(fd.get('market_price')));
    render();
    toast('تم حفظ سعر السوق','success');
    return;
  }
  if (form.id === 'bulkPriceForm') {
    if (!hasRole('admin','manager','owner') && !hasPermission('catalog_manage')) { toast('ليس لديك صلاحية التعديل الجماعي','error'); return; }
    if (!supabase) { toast('الاتصال غير متاح','error'); return; }
    const fd = new FormData(form);
    const mode = fd.get('mode');
    const value = Number(fd.get('value'));
    if (!(value >= 0)) { toast('أدخل قيمة صحيحة','error'); return; }
    const selected = Array.from(form.querySelectorAll('select[name="bike_ids"] option:checked')).map((o) => o.value);
    let bikes = (get(DB.BIKES) || []).filter((b) => !b.is_demo);
    if (selected.length) bikes = bikes.filter((b) => selected.includes(b.id));
    if (!bikes.length) { toast('لا توجد طرازات للتعديل','error'); return; }
    const btn = form.querySelector('[type=submit]'); if (btn) btn.disabled = true;
    let ok = 0, fail = 0;
    for (const b of bikes) {
      let price = Number(b.price || 0);
      if (mode === 'set') price = value;
      else if (mode === 'percent_up') price = price * (1 + value / 100);
      else if (mode === 'percent_down') price = price * (1 - value / 100);
      else if (mode === 'amount_up') price = price + value;
      else if (mode === 'amount_down') price = Math.max(0, price - value);
      price = Math.round(price * 100) / 100;
      const { error } = await supabase.from('motorcycles').update({ price }).eq('id', b.id);
      if (error) fail += 1; else ok += 1;
    }
    if (btn) btn.disabled = false;
    await Promise.all([loadMotorcycles(), loadInventoryData()]);
    render();
    toast('تم تحديث ' + ok + ' طرازاً' + (fail ? (' — فشل ' + fail) : ''), fail ? 'error' : 'success');
    return;
  }
  if (form.id === 'inventoryCostForm') {
    if (!hasRole('admin','manager','owner') && !hasPermission('finance_manage') && !hasPermission('catalog_manage')) { toast('ليس لديك صلاحية تعديل تكلفة المخزون','error'); return; }
    const fd=new FormData(form); const {error}=await supabase.rpc('set_motorcycle_inventory_controls',{p_motorcycle_id:form.dataset.bikeId,p_unit_cost:Number(fd.get('unit_cost')),p_reorder_level:Number(fd.get('reorder_level'))});
    if(error){toast(error.message||'تعذر حفظ تكلفة المخزون','error');return;} await loadInventoryData();render();toast('تم حفظ تكلفة الوحدة وحد إعادة الطلب','success');return;
  }
  if (form.id === 'motorcycleUnitForm') {
    if (!hasRole('admin','manager','owner') && !hasPermission('finance_manage') && !hasPermission('catalog_manage')) { toast('ليس لديك صلاحية تسجيل أرقام الهياكل','error'); return; }
    const fd=new FormData(form);
    const {data:unitId,error}=await supabase.rpc('register_motorcycle_unit_with_engine_number',{
      p_motorcycle_id:fd.get('motorcycle_id'),
      p_vin:safeName(fd.get('vin')),
      p_engine_number:safeName(fd.get('engine_number'))||null,
      p_barcode:safeName(fd.get('barcode'))||autoBarcodeFromVin(fd.get('vin')),
      p_warranty_start:fd.get('warranty_start')||null,
      p_warranty_end:fd.get('warranty_end')||null,
      p_notes:safeName(fd.get('notes'))||null,
      p_odometer_reading:Number(fd.get('odometer_reading')||0),
      p_unit_condition:String(fd.get('unit_condition')||'new'),
      p_unit_cost:Number(fd.get('unit_cost'))
    });
    if(error){toast(error.message||'تعذر تسجيل الوحدة؛ لم يتم حفظ أي جزء من العملية','error');return;}
    await Promise.all([loadMotorcycleUnits(),loadStoreUnits(),loadMotorcycles()]);
    closeModal();render();
    toast('تم تسجيل الدراجة في المعرض والمخزون، وأصبحت تظهر تلقائيًا في المتجر','success');
    return;
  }
  if (form.id === 'motorcycleUnitEditForm') {
    if (!hasRole('admin','manager','owner') && !hasPermission('catalog_manage') && !hasPermission('finance_manage')) { toast('ليس لديك صلاحية تعديل الوحدة','error'); return; }
    const fd=new FormData(form);
    const {error}=await supabase.rpc('update_motorcycle_unit_details',{
      p_unit_id:form.dataset.unitId,
      p_vin:safeName(fd.get('vin')),
      p_engine_number:safeName(fd.get('engine_number')),
      p_barcode:safeName(fd.get('barcode')),
      p_unit_status:String(fd.get('unit_status')),
      p_odometer_reading:Number(fd.get('odometer_reading')||0),
      p_unit_condition:String(fd.get('unit_condition')),
      p_warranty_start:fd.get('warranty_start')||null,
      p_warranty_end:fd.get('warranty_end')||null,
      p_notes:safeName(fd.get('notes'))||null
    });
    if(error){toast(error.message||'تعذر تحديث الوحدة','error');return;}
    await Promise.all([loadMotorcycleUnits(),loadStoreUnits(),loadMotorcycles()]);
    closeModal();render();toast('تم تحديث بيانات الوحدة وحالتها','success');return;
  }
  if (form.id === 'stocktakeForm') {
    if (!hasRole('admin','manager','owner') && !hasPermission('finance_manage')) { toast('الجرد المالي يحتاج صلاحية الإدارة المالية','error'); return; }
    const fd=new FormData(form),lines=[];
    for(const row of form.querySelectorAll('[data-stocktake-line]'))lines.push({motorcycle_id:row.dataset.stocktakeLine,counted_quantity:Number(row.querySelector('[name="counted_quantity"]').value)});
    const {data,error}=await supabase.rpc('create_stocktake',{p_date:fd.get('stocktake_date'),p_notes:safeName(fd.get('notes'))||null,p_lines:lines});
    if(error){toast(error.message||'تعذر ترحيل الجرد','error');return;} await Promise.all([loadInventoryData(),loadMotorcycles(),loadFinanceData()]);render();toast('تم ترحيل الجرد. الزيادة '+money(data?.increase_value||0)+' والعجز '+money(data?.decrease_value||0),'success');return;
  }
  if (form.id === 'warrantyForm') {
    if (!hasRole('admin','manager','owner') && !hasPermission('catalog_manage') && !hasPermission('finance_manage')) { toast('ليس لديك صلاحية إدارة الضمان','error'); return; }
    const fd=new FormData(form); const {error}=await supabase.rpc('create_warranty',{p_motorcycle_id:fd.get('motorcycle_id'),p_sale_id:fd.get('sale_id')||null,p_customer_id:null,p_customer_name:safeName(fd.get('customer_name')),p_phone:safeName(fd.get('customer_phone')),p_start:fd.get('start_date'),p_end:fd.get('end_date'),p_terms:safeName(fd.get('terms'))||null});
    if(error){toast(error.message||'تعذر تسجيل الضمان','error');return;} await loadInventoryData();render();toast('تم تسجيل الضمان','success');return;
  }
  if (form.id === 'serviceOrderForm') {
    if (!hasRole('admin','manager','owner') && !hasPermission('catalog_manage') && !hasPermission('finance_manage')) { toast('ليس لديك صلاحية فتح أوامر الصيانة','error'); return; }
    const fd=new FormData(form); const {error}=await supabase.rpc('create_service_order',{p_motorcycle_id:fd.get('motorcycle_id'),p_unit_id:fd.get('unit_id')||null,p_warranty_id:fd.get('warranty_id')||null,p_customer_id:null,p_customer_name:safeName(fd.get('customer_name')),p_phone:safeName(fd.get('customer_phone')),p_employee_id:fd.get('employee_id')||null,p_issue:safeName(fd.get('issue_description')),p_estimated:Number(fd.get('estimated_cost')),p_notes:safeName(fd.get('notes'))||null});
    if(error){toast(error.message||'تعذر فتح أمر الصيانة','error');return;} await loadInventoryData();render();toast('تم فتح أمر الصيانة','success');return;
  }
  if (form.id === 'serviceStatusForm') {
    if (!hasRole('admin','manager','owner') && !hasPermission('catalog_manage') && !hasPermission('finance_manage')) { toast('ليس لديك صلاحية تحديث أمر الصيانة','error'); return; }
    const fd=new FormData(form); const {error}=await supabase.rpc('update_service_order',{p_order_id:form.dataset.orderId,p_status:fd.get('status'),p_diagnosis:safeName(fd.get('diagnosis'))||null,p_actual_cost:fd.get('actual_cost')?Number(fd.get('actual_cost')):null});
    if(error){toast(error.message||'تعذر تحديث أمر الصيانة','error');return;} await loadInventoryData();render();toast('تم تحديث أمر الصيانة','success');return;
  }

  if (form.id === 'employeeForm') {
    if (!hasRole('admin','manager','owner') && !hasPermission('finance_manage')) { toast('ليس لديك صلاحية إدارة الموظفين','error'); return; }
    const fd=new FormData(form); const {error}=await supabase.rpc('create_employee',{p_code:safeName(fd.get('employee_code')),p_user_id:fd.get('auth_user_id')||null,p_name:safeName(fd.get('full_name')),p_phone:safeName(fd.get('phone'))||null,p_email:safeName(fd.get('email'))||null,p_job:safeName(fd.get('job_title'))||null,p_hire_date:fd.get('hire_date'),p_salary:Number(fd.get('base_salary')),p_notes:safeName(fd.get('notes'))||null});
    if(error){toast(error.message||'تعذر إنشاء ملف الموظف','error');return;} await loadHRData();render();toast('تم إنشاء ملف الموظف','success');return;
  }
  if (form.id === 'attendanceForm') {
    if (!hasRole('admin','manager','owner') && !hasPermission('finance_manage')) { toast('ليس لديك صلاحية تسجيل الحضور','error'); return; }
    const fd=new FormData(form); const {error}=await supabase.rpc('record_attendance',{p_employee_id:fd.get('employee_id'),p_date:fd.get('attendance_date'),p_status:fd.get('attendance_status'),p_check_in:fd.get('check_in')?new Date(fd.get('check_in')).toISOString():null,p_check_out:fd.get('check_out')?new Date(fd.get('check_out')).toISOString():null,p_notes:null});
    if(error){toast(error.message||'تعذر تسجيل الحضور','error');return;} await loadHRData();render();toast('تم حفظ سجل الحضور','success');return;
  }
  if (form.id === 'employeeLeaveForm') {
    if (!hasRole('admin','manager','owner') && !hasPermission('finance_manage')) { toast('ليس لديك صلاحية تسجيل الإجازات','error'); return; }
    const fd=new FormData(form); const {error}=await supabase.rpc('create_employee_leave',{p_employee_id:fd.get('employee_id'),p_type:fd.get('leave_type'),p_start:fd.get('start_date'),p_end:fd.get('end_date'),p_days:Number(fd.get('days')),p_reason:safeName(fd.get('reason'))||null});
    if(error){toast(error.message||'تعذر تسجيل الإجازة','error');return;} await loadHRData();render();toast('تم تسجيل طلب الإجازة','success');return;
  }
  if (form.id === 'reviewLeaveForm') {
    const status=String(e.submitter?.value||'');
    const {error}=await supabase.rpc('review_employee_leave',{p_leave_id:form.dataset.leaveId,p_status:status});
    if(error){toast(error.message||'تعذر مراجعة طلب الإجازة','error');return;} await loadHRData();render();toast('تم تحديث حالة طلب الإجازة','success');return;
  }
  if (form.id === 'custodyForm') {
    if (!hasRole('admin','manager','owner') && !hasPermission('finance_manage')) { toast('ليس لديك صلاحية إدارة العهد','error'); return; }
    const fd=new FormData(form); const {error}=await supabase.rpc('create_employee_custody',{p_employee_id:fd.get('employee_id'),p_item:safeName(fd.get('item_name')),p_description:safeName(fd.get('description'))||null,p_date:fd.get('assigned_date'),p_value:fd.get('estimated_value')?Number(fd.get('estimated_value')):null});
    if(error){toast(error.message||'تعذر تسجيل العهدة','error');return;} await loadHRData();render();toast('تم تسجيل العهدة','success');return;
  }
  if (form.id === 'returnCustodyForm') {
    const {error}=await supabase.rpc('return_employee_custody',{p_custody_id:form.dataset.custodyId,p_notes:null});
    if(error){toast(error.message||'تعذر إثبات رد العهدة','error');return;} await loadHRData();render();toast('تم إثبات رد العهدة','success');return;
  }
  if (form.id === 'terminateEmployeeForm') {
    if (!hasRole('admin','manager','owner') && !hasPermission('finance_manage')) { toast('ليس لديك صلاحية إنهاء ملف الموظف','error'); return; }
    const fd=new FormData(form); const {error}=await supabase.rpc('terminate_employee',{p_employee_id:form.dataset.employeeId,p_date:fd.get('termination_date')});
    if(error){toast(error.message||'تعذر إنهاء ملف الموظف','error');return;} await loadHRData();render();toast('تم إنهاء ملف الموظف بعد التحقق من العهد والسلف','success');return;
  }
  if (form.id === 'employeeAdvanceForm') {
    if (!hasRole('admin','manager','owner') && !hasPermission('finance_manage')) { toast('ليس لديك صلاحية تسجيل سلف الموظفين','error'); return; }
    const fd=new FormData(form); const {error}=await supabase.rpc('record_employee_advance',{p_employee_id:fd.get('employee_id'),p_date:fd.get('advance_date'),p_amount:Number(fd.get('amount')),p_cash_account_id:fd.get('cash_account_id'),p_notes:null});
    if(error){toast(error.message||'تعذر تسجيل سلفة الموظف','error');return;} await Promise.all([loadHRData(),loadFinanceData()]);render();toast('تم تسجيل سلفة الموظف وترحيل القيد','success');return;
  }
  if (form.id === 'salesCommissionForm') {
    if (!hasRole('admin','manager','owner') && !hasPermission('finance_manage')) { toast('ليس لديك صلاحية تسجيل العمولات','error'); return; }
    const fd=new FormData(form); const {error}=await supabase.rpc('create_sales_commission',{p_employee_id:fd.get('employee_id'),p_sale_id:fd.get('sale_id'),p_amount:Number(fd.get('amount')),p_notes:null});
    if(error){toast(error.message||'تعذر تسجيل العمولة','error');return;} await loadHRData();render();toast('تم تسجيل العمولة وستظهر في كشف الرواتب التالي','success');return;
  }
  if (form.id === 'payrollRunForm') {
    if (!hasRole('admin','manager','owner') && !hasPermission('finance_manage')) { toast('ليس لديك صلاحية إعداد الرواتب','error'); return; }
    const fd=new FormData(form),items=[];
    for(const row of form.querySelectorAll('[data-payroll-employee]')){
      const item={employee_id:row.dataset.payrollEmployee};
      for(const key of ['base_salary','allowances','employee_insurance','tax_deduction','other_deductions','advance_deduction','employer_insurance']) item[key]=Number(row.querySelector('[name="'+key+'"]').value||0);
      items.push(item);
    }
    if(!items.length){toast('لا يوجد موظفون نشطون لإعداد الرواتب','error');return;}
    const {error}=await supabase.rpc('create_payroll_run',{p_period_id:fd.get('period_id'),p_name:safeName(fd.get('payroll_name')),p_date:fd.get('payroll_date'),p_items:items});
    if(error){toast(error.message||'تعذر إنشاء كشف الرواتب','error');return;} await loadHRData();render();toast('تم إنشاء كشف الرواتب كمسودة؛ راجعه قبل الترحيل','success');return;
  }
  if (form.id === 'cancelPayrollForm') {
    if (!hasRole('admin','manager','owner') && !hasPermission('finance_manage')) { toast('ليس لديك صلاحية إلغاء كشف الرواتب','error'); return; }
    const {error}=await supabase.rpc('cancel_payroll_run',{p_run_id:form.dataset.runId});
    if(error){toast(error.message||'تعذر إلغاء كشف الرواتب','error');return;} await loadHRData();render();toast('تم إلغاء المسودة دون إنشاء قيد مالي','success');return;
  }
  if (form.id === 'postPayrollForm') {
    if (!hasRole('admin','manager','owner') && !hasPermission('finance_manage')) { toast('ليس لديك صلاحية ترحيل الرواتب','error'); return; }
    const {error}=await supabase.rpc('post_payroll_run',{p_run_id:form.dataset.runId});
    if(error){toast(error.message||'تعذر ترحيل كشف الرواتب','error');return;} await Promise.all([loadHRData(),loadFinanceData()]);render();toast('تم ترحيل كشف الرواتب إلى دفتر الأستاذ','success');return;
  }
  if (form.id === 'payrollPaymentForm') {
    if (!hasRole('admin','manager','owner') && !hasPermission('finance_manage')) { toast('ليس لديك صلاحية صرف الرواتب','error'); return; }
    const fd=new FormData(form); const {error}=await supabase.rpc('record_payroll_payment',{p_run_id:form.dataset.runId,p_amount:Number(fd.get('amount')),p_cash_account_id:fd.get('cash_account_id'),p_date:fd.get('payment_date'),p_reference:null});
    if(error){toast(error.message||'تعذر صرف الرواتب','error');return;} await Promise.all([loadHRData(),loadFinanceData()]);render();toast('تم تسجيل صرف الرواتب وترحيل القيد','success');return;
  }

  if (form.id === 'financialStatementsForm') {
    if (!hasRole('admin','manager','owner') && !hasPermission('finance_manage') && !hasPermission('accounting_view')) { toast('ليس لديك صلاحية عرض القوائم المالية','error'); return; }
    const fd=new FormData(form);const {data,error}=await supabase.rpc('get_financial_statements',{p_start_date:fd.get('start_date'),p_end_date:fd.get('end_date'),p_as_of_date:fd.get('as_of_date')});
    if(error){toast(error.message||'تعذر إنشاء القوائم المالية','error');return;}state.financialStatements=data;render();toast('تم إنشاء القوائم المالية','success');return;
  }
  if (form.id === 'allocateSalePaymentForm') {
    if (!hasRole('admin','manager','owner') && !hasPermission('finance_manage')) { toast('ليس لديك صلاحية تسوية المقبوضات','error'); return; }
    const fd=new FormData(form);const {error}=await supabase.rpc('allocate_sale_payment_to_cash_account',{p_payment_id:form.dataset.paymentId,p_cash_account_id:fd.get('cash_account_id')});
    if(error){toast(error.message||'تعذر تسوية الدفعة','error');return;}await loadFinanceData();render();toast('تمت تسوية الدفعة إلى الحساب المختار','success');return;
  }
  if (form.id === 'allocateCustomerRefundForm') {
    if (!hasRole('admin','manager','owner') && !hasPermission('finance_manage')) { toast('ليس لديك صلاحية تسوية ردود العملاء','error'); return; }
    const fd=new FormData(form);const {error}=await supabase.rpc('allocate_customer_refund_to_cash_account',{p_transaction_id:form.dataset.transactionId,p_cash_account_id:fd.get('cash_account_id')});
    if(error){toast(error.message||'تعذر تسوية رد العميل','error');return;}await loadFinanceData();render();toast('تمت تسوية رد العميل إلى الحساب المختار','success');return;
  }
  if (form.id === 'cashSessionOpenForm') {
    if (!hasRole('admin','manager','owner') && !hasPermission('finance_manage')) { toast('ليس لديك صلاحية فتح جلسة الخزينة','error'); return; }
    const fd=new FormData(form); const {error}=await supabase.rpc('open_cash_session',{p_cash_account_id:fd.get('cash_account_id'),p_opening_balance:Number(fd.get('opening_balance')),p_note:safeName(fd.get('note'))||null});
    if(error){toast(error.message||'تعذر فتح جلسة الخزينة','error');return;} await loadFinanceData();render();toast('تم فتح جلسة الخزينة','success');return;
  }
  if (form.id === 'cashSessionCloseForm') {
    if (!hasRole('admin','manager','owner') && !hasPermission('finance_manage')) { toast('ليس لديك صلاحية إقفال جلسة الخزينة','error'); return; }
    const fd=new FormData(form); const {data,error}=await supabase.rpc('close_cash_session',{p_session_id:form.dataset.sessionId,p_actual_closing:Number(fd.get('actual_closing')),p_note:null});
    if(error){toast(error.message||'تعذر إقفال جلسة الخزينة','error');return;} await loadFinanceData();render();toast('تم إقفال الخزينة. الفرق: '+money(data?.difference||0),'success');return;
  }
  if (form.id === 'cashHandoverForm') {
    if (!hasRole('admin','manager','owner') && !hasPermission('finance_manage')) { toast('ليس لديك صلاحية تسليم النقدية','error'); return; }
    const fd=new FormData(form); const {error}=await supabase.rpc('create_cash_handover',{p_session_id:fd.get('session_id'),p_to_user_id:fd.get('to_user_id'),p_amount:Number(fd.get('amount')),p_notes:safeName(fd.get('notes'))||null});
    if(error){toast(error.message||'تعذر تسجيل التسليم','error');return;} await loadFinanceData();render();toast('تم تسجيل التسليم بانتظار تأكيد المستلم','success');return;
  }
  if (form.id === 'handoverResponseForm') {
    const accept=String(e.submitter?.value||'true')==='true';
    const {error}=await supabase.rpc('respond_cash_handover',{p_handover_id:form.dataset.handoverId,p_accept:accept});
    if(error){toast(error.message||'تعذر الرد على التسليم','error');return;} await loadFinanceData();render();toast(accept?'تم تأكيد استلام النقدية':'تم رفض استلام النقدية',accept?'success':'info');return;
  }
  if (form.id === 'pettyCashLimitForm') {
    if (!hasRole('admin','manager','owner') && !hasPermission('finance_manage')) { toast('ليس لديك صلاحية ضبط حد المصروفات النثرية','error'); return; }
    const fd=new FormData(form); const {error}=await supabase.rpc('set_petty_cash_limit',{p_limit:Number(fd.get('limit'))});
    if(error){toast(error.message||'تعذر حفظ الحد','error');return;} await loadFinanceData();render();toast('تم حفظ حد المصروفات النثرية','success');return;
  }
  if (form.id === 'pettyCashForm') {
    if (!hasRole('admin','manager','owner') && !hasPermission('finance_manage')) { toast('ليس لديك صلاحية تسجيل المصروفات النثرية','error'); return; }
    const fd=new FormData(form); const {error}=await supabase.rpc('create_petty_cash',{p_date:fd.get('transaction_date'),p_description:safeName(fd.get('description')),p_expense_account_id:fd.get('expense_account_id'),p_cash_account_id:fd.get('cash_account_id'),p_amount:Number(fd.get('amount')),p_recipient:safeName(fd.get('recipient'))||null,p_reference:safeName(fd.get('reference'))||null});
    if(error){toast(error.message||'تعذر تسجيل المصروف النثري','error');return;} await loadFinanceData();render();toast('تم تسجيل المصروف النثري وترحيل قيده','success');return;
  }
  if (form.id === 'reverseJournalForm') {
    if (!hasRole('admin','manager','owner') && !hasPermission('finance_manage')) { toast('ليس لديك صلاحية عكس القيود','error'); return; }
    const fd=new FormData(form); const {error}=await supabase.rpc('reverse_journal_entry',{p_original_id:fd.get('original_id'),p_reason:safeName(fd.get('reason'))});
    if(error){toast(error.message||'تعذر عكس القيد','error');return;} await loadFinanceData();render();toast('تم إنشاء القيد العكسي مع الحفاظ على القيد الأصلي','success');return;
  }
  if (form.id === 'financeBudgetForm') {
    if (!hasRole('admin','manager','owner') && !hasPermission('finance_manage')) { toast('ليس لديك صلاحية إنشاء الموازنات','error'); return; }
    const fd=new FormData(form),lines=[];
    for(const row of form.querySelectorAll('[data-budget-line]')){const account_id=row.querySelector('[name="account_id"]').value;const budget_amount=Number(row.querySelector('[name="budget_amount"]').value||0);if(account_id)lines.push({account_id,budget_amount});else if(budget_amount>0){toast('اختر الحساب لكل مبلغ مخطط','error');return;}}
    if(!lines.length){toast('أدخل بند موازنة واحدًا على الأقل','error');return;}
    const {error}=await supabase.rpc('create_finance_budget',{p_period_id:fd.get('period_id'),p_name:safeName(fd.get('budget_name')),p_lines:lines});
    if(error){toast(error.message||'تعذر حفظ الموازنة','error');return;} await loadFinanceData();render();toast('تم حفظ الموازنة كمسودة؛ اعتمدها بعد المراجعة','success');return;
  }
  if (form.id === 'budgetApproveForm') {
    if (!hasRole('admin','manager','owner') && !hasPermission('finance_manage')) { toast('ليس لديك صلاحية اعتماد الموازنة','error'); return; }
    const {error}=await supabase.rpc('approve_finance_budget',{p_budget_id:form.dataset.budgetId});
    if(error){toast(error.message||'تعذر اعتماد الموازنة','error');return;} await loadFinanceData();render();toast('تم اعتماد الموازنة','success');return;
  }
  if (form.id === 'accrualForm') {
    if (!hasRole('admin','manager','owner') && !hasPermission('finance_manage')) { toast('ليس لديك صلاحية إنشاء جدول الاستحقاق','error'); return; }
    const fd=new FormData(form); const {error}=await supabase.rpc('create_accrual_schedule',{p_name:safeName(fd.get('schedule_name')),p_description:safeName(fd.get('description'))||null,p_debit_account_id:fd.get('debit_account_id'),p_credit_account_id:fd.get('credit_account_id'),p_monthly_amount:Number(fd.get('monthly_amount')),p_start:fd.get('start_date'),p_end:fd.get('end_date')||null});
    if(error){toast(error.message||'تعذر إنشاء جدول الاستحقاق','error');return;} await loadFinanceData();render();toast('تم إنشاء جدول الاستحقاق','success');return;
  }
  if (form.id === 'accrualRunForm') {
    if (!hasRole('admin','manager','owner') && !hasPermission('finance_manage')) { toast('ليس لديك صلاحية ترحيل الاستحقاق','error'); return; }
    const fd=new FormData(form); const {error}=await supabase.rpc('run_accrual_schedule',{p_schedule_id:form.dataset.scheduleId,p_run_date:fd.get('run_date')});
    if(error){toast(error.message||'تعذر ترحيل الاستحقاق','error');return;} await loadFinanceData();render();toast('تم ترحيل قيد الاستحقاق','success');return;
  }

  if (form.id === 'fiscalPeriodForm') {
    if (!hasRole('admin','manager','owner') && !hasPermission('finance_manage')) { toast('ليس لديك صلاحية إدارة الفترات','error'); return; }
    const fd=new FormData(form); const {error}=await supabase.rpc('create_fiscal_period',{p_period_code:safeName(fd.get('period_code')),p_period_name:safeName(fd.get('period_name')),p_start_date:fd.get('start_date'),p_end_date:fd.get('end_date')});
    if(error){toast(error.message||'تعذر إنشاء الفترة','error');return;} await loadFinanceData();render();toast('تم إنشاء الفترة المحاسبية','success');return;
  }
  if (form.id === 'closePeriodForm') {
    if (!hasRole('admin','manager','owner') && !hasPermission('finance_manage')) { toast('ليس لديك صلاحية إقفال الفترة','error'); return; }
    const {error}=await supabase.rpc('close_fiscal_period',{p_period_id:form.dataset.periodId});
    if(error){toast(error.message||'تعذر إقفال الفترة','error');return;} await loadFinanceData();render();toast('تم إقفال الفترة ومنع القيود الجديدة داخلها','success');return;
  }
  if (form.id === 'openingBalanceForm') {
    if (!hasRole('admin','manager','owner') && !hasPermission('finance_manage')) { toast('ليس لديك صلاحية ترحيل الأرصدة الافتتاحية','error'); return; }
    const fd=new FormData(form),lines=[];
    for(const row of form.querySelectorAll('[data-opening-row]')){const account_id=row.querySelector('[name="account_id"]').value;const debit=Number(row.querySelector('[name="debit"]').value||0);const credit=Number(row.querySelector('[name="credit"]').value||0);if(account_id&&(debit>0||credit>0))lines.push({account_id,debit,credit});else if(account_id||debit>0||credit>0){toast('أكمل الحساب وقيمة المدين أو الدائن لكل سطر','error');return;}}
    if(lines.length<2){toast('أدخل سطرين على الأقل للأرصدة الافتتاحية','error');return;} const debit=lines.reduce((n,x)=>n+x.debit,0),credit=lines.reduce((n,x)=>n+x.credit,0);
    if(Math.abs(debit-credit)>0.005){toast('الأرصدة غير متوازنة؛ يجب تساوي المدين والدائن','error');return;}
    const {data,error}=await supabase.rpc('post_opening_balance',{p_date:fd.get('effective_date'),p_description:safeName(fd.get('description')),p_lines:lines});
    if(error){toast(error.message||'تعذر ترحيل الأرصدة','error');return;} await loadFinanceData();render();toast('تم ترحيل الأرصدة الافتتاحية بنجاح','success');return;
  }
  if (form.id === 'costCenterForm') {
    if (!hasRole('admin','manager','owner') && !hasPermission('finance_manage')) { toast('ليس لديك صلاحية إدارة مراكز التكلفة','error'); return; }
    const fd=new FormData(form); const {error}=await supabase.rpc('create_cost_center',{p_code:safeName(fd.get('code')),p_name:safeName(fd.get('name')),p_description:safeName(fd.get('description'))||null});
    if(error){toast(error.message||'تعذر إنشاء مركز التكلفة','error');return;} await loadFinanceData();render();toast('تمت إضافة مركز التكلفة','success');return;
  }
  if (form.id === 'supplierAdvanceForm') {
    if (!hasRole('admin','manager','owner') && !hasPermission('finance_manage')) { toast('ليس لديك صلاحية تسجيل سلف الموردين','error'); return; }
    const fd=new FormData(form); const {error}=await supabase.rpc('record_supplier_advance',{p_supplier_id:fd.get('supplier_id'),p_date:fd.get('advance_date'),p_amount:Number(fd.get('amount')),p_cash_account_id:fd.get('cash_account_id'),p_method:fd.get('method'),p_reference:safeName(fd.get('reference'))||null,p_notes:null});
    if(error){toast(error.message||'تعذر تسجيل سلفة المورد','error');return;} await Promise.all([loadFinanceData(),loadPurchasingData()]);render();toast('تم تسجيل سلفة المورد وترحيل القيد المحاسبي','success');return;
  }
  if (form.id === 'supplierAdvanceAllocationForm') {
    if (!hasRole('admin','manager','owner') && !hasPermission('finance_manage')) { toast('ليس لديك صلاحية تسوية سلف الموردين','error'); return; }
    const fd=new FormData(form); const {error}=await supabase.rpc('allocate_supplier_advance',{p_advance_id:fd.get('advance_id'),p_bill_id:fd.get('bill_id'),p_amount:Number(fd.get('amount'))});
    if(error){toast(error.message||'تعذر تسوية السلفة','error');return;} await Promise.all([loadFinanceData(),loadPurchasingData()]);render();toast('تمت تسوية السلفة على فاتورة المورد','success');return;
  }
  if (form.id === 'fixedAssetForm') {
    if (!hasRole('admin','manager','owner') && !hasPermission('finance_manage')) { toast('ليس لديك صلاحية إدارة الأصول','error'); return; }
    const fd=new FormData(form); const {error}=await supabase.rpc('create_fixed_asset',{p_name:safeName(fd.get('asset_name')),p_description:safeName(fd.get('description'))||null,p_asset_account_id:fd.get('asset_account_id'),p_accum_account_id:fd.get('accum_account_id'),p_expense_account_id:fd.get('expense_account_id'),p_acquisition_date:fd.get('acquisition_date'),p_depreciation_start:fd.get('depreciation_start_date'),p_cost:Number(fd.get('cost')),p_salvage:Number(fd.get('salvage_value')||0),p_life_months:Number(fd.get('useful_life_months')),p_cash_account_id:fd.get('cash_account_id')});
    if(error){toast(error.message||'تعذر تسجيل الأصل الثابت','error');return;} await loadFinanceData();render();toast('تم تسجيل الأصل وترحيل قيد الاقتناء','success');return;
  }
  if (form.id === 'depreciationForm') {
    if (!hasRole('admin','manager','owner') && !hasPermission('finance_manage')) { toast('ليس لديك صلاحية ترحيل الإهلاك','error'); return; }
    const fd=new FormData(form); const {data,error}=await supabase.rpc('run_fixed_asset_depreciation',{p_period_date:fd.get('period_date')});
    if(error){toast(error.message||'تعذر ترحيل الإهلاك','error');return;} await loadFinanceData();render();toast('تم ترحيل إهلاك '+(data?.assets_count||0)+' أصل بإجمالي '+money(data?.total_depreciation||0),'success');return;
  }
  if (form.id === 'bankReconciliationForm') {
    if (!hasRole('admin','manager','owner') && !hasPermission('finance_manage')) { toast('ليس لديك صلاحية تسوية البنك','error'); return; }
    const fd=new FormData(form); const {error}=await supabase.rpc('create_bank_reconciliation',{p_cash_account_id:fd.get('cash_account_id'),p_start:fd.get('period_start'),p_end:fd.get('period_end'),p_statement_balance:Number(fd.get('statement_ending_balance')),p_notes:safeName(fd.get('notes'))||null});
    if(error){toast(error.message||'تعذر إنشاء التسوية البنكية','error');return;} await loadFinanceData();render();toast('تم إنشاء التسوية البنكية؛ أضف حركات كشف البنك ثم طابقها','success');return;
  }
  if (form.id === 'bankStatementLineForm') {
    if (!hasRole('admin','manager','owner') && !hasPermission('finance_manage')) { toast('ليس لديك صلاحية إضافة حركات كشف البنك','error'); return; }
    const fd=new FormData(form); const {error}=await supabase.rpc('add_bank_statement_line',{p_reconciliation_id:form.dataset.reconciliationId,p_date:fd.get('statement_date'),p_description:safeName(fd.get('description')),p_amount:Number(fd.get('amount')),p_reference:safeName(fd.get('reference_number'))||null});
    if(error){toast(error.message||'تعذر إضافة حركة كشف البنك','error');return;} await loadFinanceData();render();toast('تمت إضافة حركة كشف البنك','success');return;
  }
  if (form.id === 'bankMatchForm') {
    if (!hasRole('admin','manager','owner') && !hasPermission('finance_manage')) { toast('ليس لديك صلاحية مطابقة الحركات','error'); return; }
    const fd=new FormData(form); const {error}=await supabase.rpc('match_bank_statement_line',{p_line_id:form.dataset.lineId,p_journal_line_id:fd.get('journal_line_id')});
    if(error){toast(error.message||'تعذرت مطابقة الحركة','error');return;} await loadFinanceData();render();toast('تمت مطابقة حركة كشف البنك','success');return;
  }
  if (form.id === 'completeBankReconciliationForm') {
    if (!hasRole('admin','manager','owner') && !hasPermission('finance_manage')) { toast('ليس لديك صلاحية إقفال التسوية','error'); return; }
    const {error}=await supabase.rpc('complete_bank_reconciliation',{p_reconciliation_id:form.dataset.reconciliationId});
    if(error){toast(error.message||'لم تكتمل التسوية البنكية','error');return;} await loadFinanceData();render();toast('اكتملت التسوية البنكية','success');return;
  }
  if (form.id === 'chequeForm') {
    if (!hasRole('admin','manager','owner') && !hasPermission('finance_manage')) { toast('ليس لديك صلاحية إدارة الشيكات','error'); return; }
    const fd=new FormData(form); const {error}=await supabase.rpc('create_cheque',{p_type:fd.get('cheque_type'),p_reference:safeName(fd.get('cheque_reference')),p_party:safeName(fd.get('party_name')),p_cash_account_id:fd.get('cash_account_id'),p_amount:Number(fd.get('amount')),p_issue:fd.get('issue_date'),p_due:fd.get('due_date'),p_bank:safeName(fd.get('bank_name'))||null,p_notes:safeName(fd.get('notes'))||null});
    if(error){toast(error.message||'تعذر تسجيل الشيك','error');return;} await loadFinanceData();render();toast('تم تسجيل الشيك','success');return;
  }
  if (form.id === 'chequeStatusForm') {
    if (!hasRole('admin','manager','owner') && !hasPermission('finance_manage')) { toast('ليس لديك صلاحية تحديث حالة الشيك','error'); return; }
    const fd=new FormData(form); const {error}=await supabase.rpc('update_cheque_status',{p_cheque_id:form.dataset.chequeId,p_status:fd.get('status')});
    if(error){toast(error.message||'تعذر تحديث حالة الشيك','error');return;} await loadFinanceData();render();toast('تم تحديث حالة الشيك','success');return;
  }
  if (form.id === 'recurringJournalForm') {
    if (!hasRole('admin','manager','owner') && !hasPermission('finance_manage')) { toast('ليس لديك صلاحية إدارة القيود المتكررة','error'); return; }
    const fd=new FormData(form),lines=[];
    for(const row of form.querySelectorAll('[data-recurring-line]')){const account_id=row.querySelector('[name="account_id"]').value;const debit=Number(row.querySelector('[name="debit"]').value||0),credit=Number(row.querySelector('[name="credit"]').value||0);if(account_id&&(debit>0||credit>0))lines.push({account_id,debit,credit});else if(account_id||debit>0||credit>0){toast('أكمل الحساب والمدين أو الدائن لكل سطر','error');return;}}
    const debit=lines.reduce((n,x)=>n+x.debit,0),credit=lines.reduce((n,x)=>n+x.credit,0);if(lines.length<2||Math.abs(debit-credit)>0.005){toast('القيد المتكرر يحتاج سطرين متوازنين على الأقل','error');return;}
    const {error}=await supabase.rpc('save_recurring_journal_template',{p_name:safeName(fd.get('template_name')),p_description:safeName(fd.get('description'))||null,p_frequency:fd.get('frequency'),p_start:fd.get('start_date'),p_end:fd.get('end_date')||null,p_lines:lines});
    if(error){toast(error.message||'تعذر حفظ القيد المتكرر','error');return;} await loadFinanceData();render();toast('تم حفظ قالب القيد المتكرر','success');return;
  }
  if (form.id === 'recurringRunForm') {
    if (!hasRole('admin','manager','owner') && !hasPermission('finance_manage')) { toast('ليس لديك صلاحية ترحيل القيد المتكرر','error'); return; }
    const fd=new FormData(form); const {error}=await supabase.rpc('generate_recurring_journal',{p_template_id:form.dataset.templateId,p_run_date:fd.get('run_date')});
    if(error){toast(error.message||'تعذر ترحيل القيد المتكرر','error');return;} await loadFinanceData();render();toast('تم ترحيل القيد المتكرر بنجاح','success');return;
  }
  if (form.id === 'taxRateForm') {
    if (!hasRole('admin','manager','owner') && !hasPermission('finance_manage')) { toast('ليس لديك صلاحية إعداد الضرائب','error'); return; }
    const fd=new FormData(form); const {error}=await supabase.rpc('create_tax_rate',{p_code:safeName(fd.get('tax_code')),p_name:safeName(fd.get('tax_name')),p_rate:Number(fd.get('rate')),p_account_id:fd.get('tax_account_id')||null,p_from:fd.get('effective_from'),p_to:fd.get('effective_to')||null});
    if(error){toast(error.message||'تعذر حفظ إعداد الضريبة','error');return;} await loadFinanceData();render();toast('تم حفظ إعداد الضريبة؛ لم تُطبق النسبة تلقائيًا على الفواتير بعد','success');return;
  }

  if (form.id === 'expenseForm') {
    if (!(hasRole('admin','manager','owner') || hasPermission('expenses_manage')) || !supabase) { toast('ليس لديك صلاحية تسجيل المصروفات','error'); return; }
    const fd = new FormData(form), amount = Number(fd.get('amount') || 0), paid = Number(fd.get('paid_amount') || 0);
    if (paid > amount || paid < 0) { toast('المبلغ المدفوع يجب ألا يتجاوز قيمة المصروف','error'); return; }
    if (paid > 0 && !fd.get('cash_account_id')) { toast('اختر الخزينة أو البنك للمبلغ المدفوع','error'); return; }
    const btn=form.querySelector('[type=submit]'); if(btn)btn.disabled=true;
    const {data,error}=await supabase.rpc('create_expense',{
      p_expense_date:fd.get('expense_date'), p_description:safeName(fd.get('description')),
      p_expense_account_id:fd.get('expense_account_id'), p_amount:amount, p_paid_amount:paid,
      p_cash_account_id:fd.get('cash_account_id')||null, p_payment_method:fd.get('payment_method')||'cash',
      p_vendor_name:safeName(fd.get('vendor_name'))||null, p_reference_number:safeName(fd.get('reference_number'))||null,
      p_due_date:fd.get('due_date')||null, p_notes:safeName(fd.get('notes'))||null
    });
    if(btn)btn.disabled=false;
    if(error){toast(error.message||'تعذر تسجيل المصروف','error');return;}
    await loadFinanceData(); render();
    toast('تم حفظ المصروف وترحيل القيد المحاسبي بنجاح','success'); return;
  }

  if (form.id === 'expensePaymentForm') {
    if (!(hasRole('admin','manager','owner') || hasPermission('expenses_manage')) || !supabase) { toast('ليس لديك صلاحية سداد المصروفات','error'); return; }
    const fd=new FormData(form), amount=Number(fd.get('amount')||0);
    const btn=form.querySelector('[type=submit]'); if(btn)btn.disabled=true;
    const {data,error}=await supabase.rpc('record_expense_payment',{
      p_expense_id:form.dataset.expenseId, p_cash_account_id:fd.get('cash_account_id'), p_amount:amount,
      p_payment_method:fd.get('payment_method')||'cash', p_reference_number:safeName(fd.get('reference_number'))||null
    });
    if(btn)btn.disabled=false;
    if(error){toast(error.message||'تعذر تسجيل السداد','error');return;}
    closeModal(); await loadFinanceData(); render();
    toast('تم تسجيل السداد، والمتبقي '+money(data?.balance_due||0),'success'); return;
  }

  if (form.id === 'saleReturnForm') {
    if (!canUseVinScanner() || !supabase) { toast('ليس لديك صلاحية تسجيل مرتجعات المبيعات','error'); return; }
    const fd = new FormData(form), items = [];
    for (const row of form.querySelectorAll('[data-sale-item-id]')) {
      const quantity = Number(row.querySelector('[name=quantity]').value || 0);
      if (!Number.isInteger(quantity) || quantity < 0) { toast('أدخل كمية مرتجع صحيحة','error'); return; }
      if (quantity > 0) items.push({sale_item_id:row.dataset.saleItemId,quantity,disposition:row.querySelector('[name=disposition]').value});
    }
    if (!items.length) { toast('حدد كمية واحدة على الأقل للإرجاع','error'); return; }
    const btn = form.querySelector('[type=submit]'); if (btn) btn.disabled = true;
    const {data,error} = await supabase.rpc('create_sale_return',{
      p_sale_id:form.dataset.saleId,p_items:items,p_notes:safeName(fd.get('notes'))||null
    });
    if (btn) btn.disabled = false;
    if (error) { toast(error.message || 'تعذر تسجيل مرتجع البيع','error'); return; }
    closeModal();
    await Promise.all([loadSalesData(),loadMotorcycles()]);
    render();
    toast('تم تسجيل المرتجع رقم '+data.return_number+' بقيمة '+money(data.total_amount)+'؛ الرصيد الدائن الفعلي '+money(data.customer_credit || 0),'success');
    return;
  }

  if(form.id==='supplierReturnForm'){
    if(!hasRole('admin')||!supabase){toast('ليس لديك صلاحية تسجيل مرتجعات الموردين','error');return;}
    const fd=new FormData(form),items=[];
    for(const row of form.querySelectorAll('[data-receipt-item-id]')){
      const unitIds=[...(row.querySelector('[name=unit_ids]')?.selectedOptions||[])].map(option=>option.value);
      if(unitIds.length)items.push({purchase_receipt_item_id:row.dataset.receiptItemId,unit_ids:unitIds});
    }
    if(!items.length){toast('حدد رقم شاسيه واحدًا على الأقل لإرجاعه','error');return;}
    const btn=form.querySelector('[type=submit]');if(btn)btn.disabled=true;
    const {data,error}=await supabase.rpc('create_supplier_return_for_units',{
      p_purchase_order_id:form.dataset.orderId,p_supplier_bill_id:String(fd.get('supplier_bill_id')),
      p_items:items,p_notes:safeName(fd.get('notes'))||null
    });
    if(btn)btn.disabled=false;
    if(error){toast(error.message||'تعذر تسجيل المرتجع؛ لم يتم إخراج أي وحدة','error');return;}
    closeModal();await Promise.all([loadPurchasingData(),loadMotorcycles()]);
    render();toast('تم تسجيل المرتجع رقم '+data.return_number+' وربط '+items.reduce((n,x)=>n+x.unit_ids.length,0)+' وحدة فعلية بالمورد','success');return;
  }
  if(form.id==='supplierBillForm'){
    if(!hasRole('admin')||!supabase){toast('ليس لديك صلاحية إدارة فواتير الموردين','error');return;}
    const fd=new FormData(form),items=[];
    for(const row of form.querySelectorAll('.supplier-bill-line')){
      if(!row.querySelector('[name="selected"]')?.checked)continue;
      const quantity=Number(row.querySelector('[name="quantity"]')?.value);
      const unitCost=Number(row.querySelector('[name="unit_cost"]')?.value);
      const max=Number(row.querySelector('[name="quantity"]')?.max||0);
      if(!Number.isInteger(quantity)||quantity<1||quantity>max||!Number.isFinite(unitCost)||unitCost<0){
        toast('تحقق من الكمية وسعر الوحدة في بنود الفاتورة المحددة','error');return;
      }
      items.push({line_type:'inventory',purchase_receipt_item_id:row.dataset.receiptItemId,quantity,unit_cost:unitCost});
    }
    if(fd.get('direct_line_enabled')==='on'){
      const directAmount=Number(fd.get('direct_amount'));
      const description=safeName(fd.get('direct_description'));
      if(!description||!Number.isFinite(directAmount)||directAmount<=0){toast('أدخل وصفًا وقيمة صحيحة للبند المباشر','error');return;}
      items.push({line_type:'direct',description,quantity:1,unit_cost:Number(directAmount.toFixed(2))});
    }
    if(!items.length){toast('اختر بند استلام واحدًا على الأقل أو أضف بندًا مباشرًا','error');return;}
    const amount=Math.round(items.reduce((n,item)=>n+Math.round(Number(item.quantity)*Number(item.unit_cost)*100)/100,0)*100)/100;
    const submit=form.querySelector('button[type="submit"]');if(submit)submit.disabled=true;
    const {error}=await supabase.rpc('create_supplier_bill',{
      p_supplier_id:String(fd.get('supplier_id')),p_bill_number:safeName(fd.get('bill_number')),
      p_total_amount:amount,p_bill_date:String(fd.get('bill_date')),p_due_date:fd.get('due_date')||null,
      p_purchase_order_id:fd.get('purchase_order_id')||null,p_notes:safeName(fd.get('notes'))||null,p_items:items
    });
    if(submit)submit.disabled=false;
    if(error){toast(error.message||'تعذر حفظ فاتورة المورد؛ لم يتم تسجيل أي بند أو قيد جزئي','error');return;}
    await loadPurchasingData();render();toast('تم حفظ الفاتورة وبنودها وربط الوحدات المستلمة دون تكرار','success');return;
  }
  if(form.id==='supplierPaymentForm'){
    if(!hasRole('admin')||!supabase){toast('ليس لديك صلاحية تسجيل مدفوعات الموردين','error');return;}
    const fd=new FormData(form),amount=Number(fd.get('amount'));
    if(!Number.isFinite(amount)||amount<=0){toast('أدخل قيمة دفعة صحيحة','error');return;}
    const submit=form.querySelector('button[type="submit"]');if(submit)submit.disabled=true;
    const {data,error}=await supabase.rpc('record_supplier_payment',{p_supplier_bill_id:form.dataset.billId,p_amount:amount,p_method:String(fd.get('method')),p_reference:safeName(fd.get('reference'))||null,p_notes:safeName(fd.get('notes'))||null,p_cash_account_id:fd.get('cash_account_id')});
    if(submit)submit.disabled=false;
    if(error){toast(error.message||'تعذر تسجيل دفعة المورد','error');return;}
    closeModal();await loadPurchasingData();render();toast('تم تسجيل دفعة المورد رقم '+data.payment_number+' والمتبقي '+money(data.balance_due),'success');return;
  }

  if (form.id === 'supplierForm') {
    if (!hasRole('admin') || !supabase) { toast('ليس لديك صلاحية إدارة الموردين', 'error'); return; }
    const fd=new FormData(form);
    const payload={name:safeName(fd.get('name')),phone:safeName(fd.get('phone'))||null,email:safeName(fd.get('email')).toLowerCase()||null,address:safeName(fd.get('address'))||null,notes:safeName(fd.get('notes'))||null,created_by:state.user.id};
    const {error}=await supabase.from('suppliers').insert(payload);
    if(error){toast(error.message||'تعذر حفظ المورد','error');return;}
    await loadPurchasingData();render();toast('تم حفظ المورد','success');return;
  }
  if (form.id === 'purchaseOrderForm') {
    if (!hasRole('admin') || !supabase) { toast('ليس لديك صلاحية إنشاء أوامر التوريد', 'error'); return; }
    const fd=new FormData(form), rows=[...form.querySelectorAll('.purchase-order-row')], items=[], seen=new Set();
    for (const row of rows) {
      const motorcycleId=row.querySelector('[name="motorcycle_id"]')?.value;
      const quantity=Number(row.querySelector('[name="quantity"]')?.value);
      const unitCost=Number(row.querySelector('[name="unit_cost"]')?.value);
      if(!motorcycleId||!Number.isInteger(quantity)||quantity<1||quantity>10000||!Number.isFinite(unitCost)||unitCost<0){toast('تحقق من الصنف والكمية وتكلفة الوحدة في كل بند','error');return;}
      if(seen.has(motorcycleId)){toast('لا تكرر الدراجة في أكثر من بند؛ اجمع الكمية في سطر واحد','error');return;}
      seen.add(motorcycleId);items.push({motorcycle_id:motorcycleId,quantity,unit_cost:unitCost});
    }
    const submit=form.querySelector('button[type="submit"]');if(submit)submit.disabled=true;
    const {data,error}=await supabase.rpc('create_supplier_purchase_order',{p_supplier_id:String(fd.get('supplier_id')),p_items:items,p_notes:safeName(fd.get('notes'))||null});
    if(submit)submit.disabled=false;
    if(error){toast(error.message||'تعذر إنشاء أمر التوريد','error');return;}
    await loadPurchasingData();render();toast(`تم إنشاء أمر التوريد ${data.order_number} بعدد ${items.length} أصناف؛ لم يتغير المخزون بعد`,'success');return;
  }
  if (form.id === 'receivePurchaseForm') {
    if (!hasRole('admin') || !supabase) { toast('ليس لديك صلاحية استلام التوريد', 'error'); return; }
    const fd=new FormData(form), rows=[...form.querySelectorAll('[data-item-id]')], items=[];
    for (const row of rows) {
      const quantity=Number(row.querySelector('[name="quantity"]')?.value);
      if(!Number.isInteger(quantity)||quantity<0){toast('تحقق من كميات الاستلام؛ استخدم صفرًا للصنف غير المستلم','error');return;}
      if(quantity>0){
        const unitRows=[...row.querySelectorAll('[data-unit-row]')].slice(0,quantity);
        if(unitRows.length!==quantity){toast('عدد نماذج الوحدات لا يطابق كمية الاستلام','error');return;}
        const units=[];
        for(const unitRow of unitRows){
          const value=name=>unitRow.querySelector(`[name="${name}"]`)?.value;
          const vin=safeName(value('vin'));
          const odometer=Number(value('odometer_reading')||0);
          if(!vin||!Number.isInteger(odometer)||odometer<0){toast('أدخل رقم شاسيه صحيحًا وعداد كيلومترات غير سالب لكل وحدة','error');return;}
          units.push({
            vin,engine_number:safeName(value('engine_number'))||null,
            barcode:safeName(value('barcode'))||null,
            odometer_reading:odometer,unit_condition:String(value('unit_condition')||'new'),
            warranty_start:value('warranty_start')||null,warranty_end:value('warranty_end')||null
          });
        }
        items.push({purchase_order_item_id:row.dataset.itemId,units});
      }
    }
    if(!items.length){toast('أدخل كمية مستلمة واحدة على الأقل','error');return;}
    const submit=form.querySelector('button[type="submit"]');if(submit)submit.disabled=true;
    const {data,error}=await supabase.rpc('receive_supplier_purchase_order_units',{p_order_id:form.dataset.orderId,p_items:items,p_notes:safeName(fd.get('notes'))||null});
    if(submit)submit.disabled=false;
    if(error){toast(error.message||'تعذر تسجيل الاستلام؛ لم يتم اعتماد أي جزء منه','error');return;}
    closeModal();await Promise.all([loadPurchasingData(),loadMotorcycles()]);render();toast(`تم تسجيل الاستلام ${data.receipt_number} وربط ${data.quantity_received} وحدة بأرقام شاسيهها`,'success');return;
  }

  if (form.id === 'customerReplyForm') {
    if (!hasPermission('requests_manage') || !supabase) { toast('ليس لديك صلاحية تسجيل الردود', 'error'); return; }
    const fd = new FormData(form);
    const kind = form.dataset.kind;
    const sent = fd.get('sent') === 'yes';
    const channel = String(fd.get('channel'));
    if (channel !== 'internal' && !sent) {
      toast('أكد إرسال الرسالة أو اختر ملاحظة داخلية فقط', 'error'); return;
    }
    const payload = {reply_body:safeName(fd.get('reply_body')),channel,sent_by:state.user.id,sent_at:sent ? new Date().toISOString() : null};
    const table = kind === 'request' ? 'customer_request_replies' : 'contact_message_replies';
    const foreignKey = kind === 'request' ? 'request_id' : 'message_id';
    const {error} = await supabase.from(table).insert({...payload,[foreignKey]:form.dataset.recordId});
    if (error) { toast(error.message || 'تعذر حفظ سجل الرد', 'error'); return; }
    if (kind === 'message' && sent) {
      const statusResult = await supabase.from('contact_messages').update({status:'replied'}).eq('id',form.dataset.recordId);
      if (statusResult.error) console.error('Contact status update failed',statusResult.error);
    }
    closeModal();
    await loadBusinessData();
    render();
    toast('تم حفظ سجل التواصل', 'success');
    return;
  }

  if (form.id === 'customerCreditRefundForm') {
    if (!hasRole('admin') || !supabase) { toast('ليس لديك صلاحية رد أموال العملاء','error'); return; }
    const fd = new FormData(form), amount = Number(fd.get('amount'));
    const balance = Number(form.dataset.balance);
    if (!Number.isFinite(amount) || amount <= 0 || amount > balance) { toast('مبلغ الرد غير صحيح أو يتجاوز الرصيد','error'); return; }
    const submit = form.querySelector('button[type="submit"]'); if (submit) submit.disabled = true;
    const { data, error } = await supabase.rpc('record_customer_credit_refund', {
      p_customer_id:form.dataset.customerId,p_amount:amount,p_method:String(fd.get('method')),
      p_reference:safeName(fd.get('reference'))||null,p_notes:safeName(fd.get('notes'))||null
    });
    if (submit) submit.disabled = false;
    if (error) { toast(error.message || 'تعذر تسجيل رد المبلغ','error'); return; }
    closeModal();
    await loadSalesData();
    render();
    toast('تم تسجيل رد '+money(data.refunded_amount)+'؛ الرصيد المتبقي '+money(data.remaining_credit),'success');
    return;
  }

  if (form.id === 'applyCustomerCreditForm') {
    if (!canUseVinScanner() || !supabase) { toast('ليس لديك صلاحية استخدام أرصدة العملاء','error'); return; }
    const fd = new FormData(form), amount = Number(fd.get('amount')), max = Number(form.dataset.max);
    if (!Number.isFinite(amount) || amount<=0 || amount>max) { toast('قيمة استخدام الرصيد غير صحيحة','error'); return; }
    const submit = form.querySelector('button[type="submit"]'); if (submit) submit.disabled = true;
    const {data,error}=await supabase.rpc('apply_customer_credit_to_sale',{
      p_sale_id:form.dataset.saleId,p_amount:amount,p_reference:safeName(fd.get('reference'))||null
    });
    if(submit)submit.disabled=false;
    if(error){toast(error.message||'تعذر استخدام رصيد العميل','error');return;}
    closeModal(); await loadSalesData(); render();
    toast('تم استخدام '+money(data.applied_amount)+' من رصيد العميل؛ المتبقي على الفاتورة '+money(data.remaining_due),'success');
    return;
  }

  if (form.id === 'collectPaymentForm') {
    if (!canUseVinScanner() || !supabase) { toast('ليس لديك صلاحية تحصيل المدفوعات', 'error'); return; }
    const fd = new FormData(form);
    const amount = Number(fd.get('amount'));
    const submit = form.querySelector('button[type="submit"]');
    if (submit) submit.disabled = true;
    // Keep the same key while this modal remains open: a lost response can be retried safely.
    form.dataset.paymentIdempotencyKey ||= crypto.randomUUID();
    const { error } = await supabase.rpc('record_sale_payment', {
      p_sale_id: form.dataset.saleId, p_amount: amount, p_method: String(fd.get('method')),
      p_reference: safeName(fd.get('reference')) || null,
      p_idempotency_key: form.dataset.paymentIdempotencyKey,
      p_cash_account_id: String(fd.get('cash_account_id'))
    });
    if (submit) submit.disabled = false;
    if (error) { toast(error.message || 'تعذر تسجيل الدفعة', 'error'); return; }
    closeModal();
    await loadSalesData();
    render();
    toast('تم تسجيل الدفعة وتحديث رصيد الفاتورة', 'success');
    return;
  }

  /* Showroom POS: one atomic database RPC creates a multi-item invoice, payment and stock movements. */
  if (form.id === 'vinLookupForm') {
    const code = safeName(new FormData(form).get('code'));
    if (!code) return;
    showVinScanStatus('جارٍ البحث عن الرقم...');
    try {
      const unit = await lookupUnitByCode(code);
      renderVinUnitMatch(unit);
      showVinScanStatus(unit ? 'تم العثور على الوحدة.' : 'لا توجد وحدة مسجلة بهذا الرقم.', !unit);
    } catch (error) { showVinScanStatus(error.message || 'تعذر البحث', true); }
    return;
  }

  if (form.id === 'vinScannerSaleForm') {
    if (!canUseVinScanner() || !supabase) { toast('ليس لديك صلاحية تسجيل المبيعات', 'error'); return; }
    const fd = new FormData(form);
    const selectedAccount = form.querySelector('select[name="customer_user_id"] option:checked');
    const customerName = safeName(fd.get('customer_name')) || selectedAccount?.dataset.name || 'عميل نقدي';
    const customerPhone = safeName(fd.get('customer_phone')) || selectedAccount?.dataset.phone || '';
    const amount = Number(fd.get('payment_amount'));
    const bike = lastScannedUnit?.motorcycles;
    const cashAccountId=String(fd.get('cash_account_id')||'');
    if (!lastScannedUnit || lastScannedUnit.id !== form.dataset.unitId || !bike || !Number.isFinite(amount) || amount < 0 || amount > Number(bike.price)) {
      toast('بيانات الوحدة أو الدفعة غير صحيحة؛ أعد البحث عن الوحدة', 'error'); return;
    }
    if(amount>0&&!cashAccountId){toast('حدد الخزينة أو البنك الذي استلم الدفعة','error');return;}
    const submit = form.querySelector('[type="submit"]');
    if (submit) submit.disabled = true;
    const { data, error } = await supabase.rpc('create_showroom_sale_for_unit', {
      p_unit_id: lastScannedUnit.id,
      p_customer_user_id: String(fd.get('customer_user_id') || '') || null,
      p_customer_name: customerName,
      p_customer_phone: customerPhone,
      p_payment_amount: amount,
      p_payment_method: amount > 0 ? String(fd.get('payment_method')) : null,
      p_payment_reference: safeName(fd.get('payment_reference')) || null,
      p_notes: safeName(fd.get('notes')) || null,
      p_cash_account_id: cashAccountId || null
    });
    if (submit) submit.disabled = false;
    if (error) { toast(error.message || 'تعذر تسجيل البيع؛ لم يتم اعتماد العملية', 'error'); return; }
    const due = Number(data.balance_due || 0);
    const invoice = '<div class="invoice"><div class="invoice-header"><div><h2>El Khayal Motors</h2><p>فاتورة بيع وحدة محددة</p></div><div class="invoice-meta"><b>'+esc(data.invoice_number)+'</b><br><span>'+new Date(data.created_at).toLocaleString('ar-EG')+'</span></div></div><hr>'+
      '<p><b>العميل:</b> '+esc(customerName)+'</p><p><b>الهاتف:</b> '+esc(customerPhone || '—')+'</p>'+
      '<div class="table-wrap"><table><thead><tr><th>الصنف</th><th>الموديل</th><th>VIN</th><th>رقم الموتور</th><th>السعر</th></tr></thead><tbody><tr><td>'+esc(data.motorcycle_name)+'</td><td>'+esc(data.model_year||'—')+'</td><td>'+esc(data.vin||'—')+'</td><td>'+esc(data.engine_number||'—')+'</td><td>'+money(data.unit_price)+'</td></tr></tbody></table></div>'+
      '<p><b>الإجمالي:</b> '+money(data.total)+'</p><p><b>المدفوع:</b> '+money(data.amount_paid)+'</p><p><b>المتبقي:</b> '+money(due)+'</p><p><b>حالة الدفع:</b> '+(data.payment_status==='paid'?'مدفوعة':data.payment_status==='partial'?'مدفوعة جزئيًا':'غير مدفوعة')+'</p>'+
      '<p>رقم الشاسيه ورقم الموتور مرتبطان بهذه الفاتورة في سجل الوحدة.</p><p class="text-center">شكرًا لثقتكم في El Khayal Motors</p></div>'+
      '<div class="contact-actions no-print"><button class="btn btn-primary" id="printInvoiceBtn"><i class="fa-solid fa-print"></i> طباعة الفاتورة</button><button class="btn btn-outline" id="sendInvoiceWhatsAppBtn" data-phone="'+esc(customerPhone)+'" data-invoice="'+esc(data.invoice_number)+'" data-customer="'+esc(customerName)+'" data-items="'+esc(data.motorcycle_name+' — VIN '+data.vin+' — موتور '+(data.engine_number||'—'))+'" data-total="'+Number(data.total||0)+'" data-paid="'+Number(data.amount_paid||0)+'" data-due="'+due+'"><i class="fa-brands fa-whatsapp"></i> إرسال عبر واتساب</button><button class="btn btn-outline" id="shareInvoiceBtn"><i class="fa-solid fa-share-nodes"></i> مشاركة الفاتورة</button></div>';
    await Promise.all([loadMotorcycles(),loadSalesData()]);
    render();
    openModal(invoice);
    lastScannedUnit = null;
    toast('تم البيع وربط رقم الوحدة بالفاتورة وتحديث المخزون', 'success');
    return;
  }

  if (form.id === 'posSaleForm') {
    if (!canUseVinScanner() || !supabase) { toast('نقطة البيع غير متاحة لهذا الحساب', 'error'); return; }
    const fd = new FormData(form);
    const rows = [...form.querySelectorAll('.pos-cart-row')];
    const items = [];
    const seen = new Set();
    const seenUnits = new Set();
    for (const row of rows) {
      const motorcycleId = row.querySelector('[name="motorcycle_id"]')?.value;
      const bike = state.bikes.find((item) => item.id === motorcycleId);
      const unitSelect = row.querySelector('[name="unit_ids"]');
      const unitIds = [...(unitSelect?.selectedOptions || [])].map(option => option.value);
      if (!bike || !unitIds.length || unitIds.length > bike.stock) {
        toast('اختر طرازًا ووحدة فعلية واحدة على الأقل لكل سطر', 'error'); return;
      }
      if (seen.has(bike.id)) { toast('لا تكرر الطراز في أكثر من سطر؛ اجمع وحداته في سطر واحد', 'error'); return; }
      seen.add(bike.id);
      for (const option of [...(unitSelect?.selectedOptions || [])]) {
        if (option.dataset.motorcycleId !== bike.id || seenUnits.has(option.value)) {
          toast('تأكد أن كل رقم شاسيه يتبع الطراز المختار ولم يُستخدم في سطر آخر', 'error'); return;
        }
        seenUnits.add(option.value);
      }
      items.push({ motorcycle_id: bike.id, unit_ids: unitIds, bike });
    }
    if (!items.length) { toast('أضف صنفًا واحدًا على الأقل وحدد أرقام شاسيهه', 'error'); return; }
    const subtotal = items.reduce((sum, item) => sum + item.bike.price * item.unit_ids.length, 0);
    const paymentAmount = Number(fd.get('payment_amount'));
    const cashAccountId=String(fd.get('cash_account_id')||'');
    if (!Number.isFinite(paymentAmount) || paymentAmount < 0 || paymentAmount > subtotal) {
      toast('قيمة الدفعة غير صحيحة أو أكبر من إجمالي الفاتورة', 'error'); return;
    }
    if(paymentAmount>0&&!cashAccountId){toast('حدد الخزينة أو البنك الذي استلم الدفعة','error');return;}
    const selectedAccount = form.querySelector('select[name="customer_user_id"] option:checked');
    const customerName = safeName(fd.get('customer_name')) || selectedAccount?.dataset.name || 'عميل نقدي';
    const customerPhone = safeName(fd.get('customer_phone')) || selectedAccount?.dataset.phone || '';
    const submit = form.querySelector('button[type="submit"]');
    if (submit) submit.disabled = true;
    const { data, error } = await supabase.rpc('create_showroom_sale_with_units', {
      p_customer_user_id: String(fd.get('customer_user_id') || '') || null,
      p_customer_name: customerName,
      p_customer_phone: customerPhone,
      p_items: items.map(({ motorcycle_id, unit_ids }) => ({ motorcycle_id, unit_ids })),
      p_payment_amount: paymentAmount,
      p_payment_method: paymentAmount > 0 ? String(fd.get('payment_method')) : null,
      p_payment_reference: safeName(fd.get('payment_reference')) || null,
      p_notes: safeName(fd.get('notes')) || null,
      p_cash_account_id: paymentAmount > 0 ? cashAccountId : null
    });
    if (submit) submit.disabled = false;
    if (error) { toast(error.message || 'تعذر تسجيل البيع؛ لم يتم اعتماد أي وحدة', 'error'); return; }
    await Promise.all([loadMotorcycles(), loadMotorcycleUnits(), loadSalesData()]);
    const invoiceRows = (data.units || []).map(unit =>
      `<tr><td>${esc(unit.motorcycle_name)} — ${esc(unit.model_year || '—')}</td><td>${esc(unit.vin || '—')}</td><td>${esc(unit.engine_number || '—')}</td><td>${money(unit.unit_price)}</td></tr>`
    ).join('');
    const invoice = `
      <div class="invoice">
        <div class="invoice-header"><div><h2>El Khayal Motors</h2><p>فاتورة بيع معرض</p></div><div class="invoice-meta"><b>${esc(data.invoice_number)}</b><br><span>${new Date(data.created_at).toLocaleString('ar-EG')}</span></div></div>
        <hr><p><b>العميل:</b> ${esc(customerName)}</p><p><b>الهاتف:</b> ${esc(customerPhone || '—')}</p>
        <div class="table-wrap"><table><thead><tr><th>الصنف</th><th>رقم الشاسيه</th><th>رقم الموتور</th><th>السعر</th></tr></thead><tbody>${invoiceRows}</tbody></table></div>
        <p><b>الإجمالي:</b> ${money(data.total)}</p><p><b>المدفوع:</b> ${money(data.amount_paid)}</p>
        <p><b>المتبقي:</b> ${money(data.balance_due)}</p><p><b>حالة الدفع:</b> ${data.payment_status === 'paid' ? 'مدفوعة' : data.payment_status === 'partial' ? 'مدفوعة جزئيًا' : 'غير مدفوعة'}</p>
        <p class="text-center">شكرًا لثقتكم في El Khayal Motors</p>
      </div>
      <div class="contact-actions no-print invoice-actions"><button class="btn btn-primary" id="printInvoiceBtn" type="button"><i class="fa-solid fa-print"></i> طباعة الفاتورة</button><button class="btn btn-outline" id="sendInvoiceWhatsAppBtn" type="button" data-phone="${esc(customerPhone || '')}" data-invoice="${esc(data.invoice_number)}" data-customer="${esc(customerName)}" data-total="${esc(data.total)}" data-paid="${esc(data.amount_paid)}" data-due="${esc(data.balance_due)}" data-items="${esc((data.units || []).map(unit => unit.motorcycle_name + ' — VIN ' + unit.vin + ' — موتور ' + (unit.engine_number || '—')).join(' | '))}"><i class="fa-brands fa-whatsapp"></i> إرسال الفاتورة عبر واتساب</button><button class="btn btn-outline" id="shareInvoiceBtn" type="button"><i class="fa-solid fa-share-nodes"></i> مشاركة الفاتورة</button><button class="btn btn-outline" data-close-modal>إغلاق</button></div>`;
    openModal(invoice);
    render();
    toast('تم تسجيل البيع وتحديث المخزون وإصدار الفاتورة', 'success');
    return;
  }

  /* Login */
  if (form.id === 'loginForm') {
    const fd = new FormData(form);
    try {
      const u = await login(fd.get('email'), fd.get('password'));
      if (u.role === 'customer') await loadCustomerData();
      else { await loadBusinessData(); await loadStaffDirectory(); }
      await loadMotorcycles();
      toast(`أهلاً ${u.name}`, 'success');
      let returnRoute = null;
      try { returnRoute = sessionStorage.getItem('ekm_auth_return_route'); } catch { /* Session storage may be unavailable. */ }
      const route = u.role === 'admin' ? 'dashboard' : u.role === 'staff'
        ? (hasRequestAccess() ? 'staff-orders' : hasAnyPermission('catalog_view', 'catalog_manage') ? 'inventory' : 'home')
        : (returnRoute === 'contact' ? 'contact' : 'home');
      if (u.role === 'customer' && returnRoute === 'contact') {
        try { sessionStorage.removeItem('ekm_auth_return_route'); } catch { /* Session storage may be unavailable. */ }
      }
      navigate(route);
      await resumePendingAuthAction();
    } catch (error) { toast(error.message || 'تعذر تسجيل الدخول', 'error'); }
    return;
  }

  /* Signup */
  if (form.id === 'signupForm') {
    const fd = new FormData(form);
    try {
      const res = await signup({ name: fd.get('name'), email: fd.get('email'), phone: fd.get('phone'), password: fd.get('password') });
      if (res.requiresEmailConfirmation) {
        toast('افتح رسالة التأكيد في بريدك لإكمال إنشاء الحساب', 'info');
        navigate('login');
      } else {
        await loadCustomerData();
        await loadMotorcycles();
        toast('تم إنشاء الحساب بنجاح', 'success');
        let returnRoute = null;
        try { returnRoute = sessionStorage.getItem('ekm_auth_return_route'); } catch { /* Session storage may be unavailable. */ }
        if (returnRoute === 'contact') {
          try { sessionStorage.removeItem('ekm_auth_return_route'); } catch { /* Session storage may be unavailable. */ }
        }
        navigate(returnRoute === 'contact' ? 'contact' : 'home');
        await resumePendingAuthAction();
      }
    } catch (error) { toast(error.message || 'تعذر إنشاء الحساب', 'error'); }
    return;
  }

  /* Customer request: durable data is written only to Supabase under RLS. */
  if (form.id === 'requestForm' || form.id === 'quickBuyRequestForm') {
    if (!hasRole('customer')) { toast('يجب تسجيل الدخول بحساب عميل لإرسال طلب شراء', 'error'); navigate('login'); return; }
    if (!supabase) { toast('الخدمة غير مهيأة حالياً', 'error'); return; }
    const fd = new FormData(form);
    const u = currentUser();
    const name = safeName(fd.get('requester_name'));
    const phone = safeName(fd.get('requester_phone'));
    const email = safeName(fd.get('requester_email')).toLowerCase();
    const preferred = String(fd.get('preferred_contact') || 'phone');
    if (name.length < 2 || (!phone && !email)) { toast('اكتب اسمك ورقم هاتف أو بريدًا إلكترونيًا واحدًا على الأقل', 'error'); return; }
    if ((preferred === 'email' && !email) || (preferred !== 'email' && !phone)) { toast('أدخل بيانات وسيلة التواصل التي اخترتها', 'error'); return; }
    const bike = form.id === 'quickBuyRequestForm' ? state.bikes.find((b) => b.id === form.dataset.bikeId) : null;
    const requestedUnit = form.id === 'quickBuyRequestForm'
      ? (state.storeUnits || []).find((unit) => unit.unit_id === form.dataset.unitId && unit.motorcycle_id === bike?.id)
      : null;
    if (form.id === 'quickBuyRequestForm' && (!bike || !requestedUnit || bike.status !== 'available')) {
      toast('الوحدة التي اخترتها لم تعد متاحة؛ حدّث المتجر وحاول مرة أخرى', 'error'); return;
    }
    const { error } = await supabase.from('customer_requests').insert({
      client_user_id: u?.id || null,
      requester_name: name,
      requester_phone: phone || null,
      requester_email: email || null,
      preferred_contact: preferred,
      motorcycle_id: bike?.id || null,
      motorcycle_unit_id: requestedUnit?.unit_id || null,
      requested_name: bike?.name || safeName(fd.get('bikeName')),
      requested_model_year: bike ? (Number(bike.model) || null) : (Number(fd.get('model')) || null),
      budget: bike ? bike.price : (Number(fd.get('budget')) || null),
      notes: safeName(fd.get('notes')) || (bike ? 'طلب شراء من صفحة الدراجة' : null)
    });
    if (error) { toast(error.message || 'تعذر حفظ الطلب', 'error'); return; }
    if (u) await loadCustomerData();
    else if (state.user && ['staff','admin'].includes(state.user.role)) await loadBusinessData();
    closeModal();
    form.reset();
    toast('تم استلام طلبك بنجاح؛ سيتواصل معك فريق المعرض', 'success');
    if (u) navigate('orders');
    else if (hasRole('admin')) { await loadBusinessData(); render(); }
    else if (state.route === 'request') render();
    return;
  }

  /* Contact messages are sent to the protected Supabase table. */
  if (form.id === 'contactForm') {
    const sender = currentUser();
    if (!sender?.id || sender.role !== 'customer') {
      try { sessionStorage.setItem('ekm_auth_return_route', 'contact'); } catch { /* Session storage may be unavailable. */ }
      toast('يجب إنشاء حساب عميل أو تسجيل الدخول لإرسال رسالة', 'error');
      navigate('login');
      return;
    }
    const fd = new FormData(form);
    if (!supabase) { toast('الخدمة غير مهيأة حالياً', 'error'); return; }
    const phone = safeName(fd.get('phone'));
    const email = safeName(fd.get('email')).toLowerCase();
    const preferred = String(fd.get('preferred_contact') || 'email');
    if (!safeName(fd.get('name')) || !safeName(fd.get('message')) || (!phone && !email)) {
      toast('اكتب اسمك ورسالتك ورقم هاتف أو بريدًا إلكترونيًا واحدًا على الأقل', 'error'); return;
    }
    if ((preferred === 'email' && !email) || (preferred !== 'email' && !phone)) {
      toast('أدخل بيانات وسيلة التواصل التي اخترتها', 'error'); return;
    }
    const { error } = await supabase.from('contact_messages').insert({
      sender_user_id: sender.id,
      name: safeName(fd.get('name')),
      phone: phone || null,
      email: email || '',
      preferred_contact: preferred,
      message: safeName(fd.get('message'))
    });
    if (error) { toast(error.message || 'تعذر إرسال الرسالة', 'error'); return; }
    toast('وصلتنا رسالتك؛ سنعود إليك عبر وسيلة التواصل المفضلة', 'success');
    form.reset();
    return;
  }

  /* Create staff through a manager-authorized Edge Function; never from browser credentials. */
  if (form.id === 'staffCreateForm') {
    if (!hasRole('admin')) { toast('هذه العملية للمدير فقط', 'error'); return; }
    const fd = new FormData(form);
    const password = String(fd.get('password') || '');
    const passwordConfirm = String(fd.get('password_confirm') || '');
    if (password !== passwordConfirm) { toast('كلمتا المرور غير متطابقتين', 'error'); return; }
    const button = form.querySelector('button[type="submit"]');
    if (button) button.disabled = true;
    const { data, error } = await supabase.functions.invoke('manage-staff', { body: {
      action: 'create',
      full_name: fd.get('full_name'),
      email: fd.get('email'),
      phone: fd.get('phone'),
      password,
      permissions: fd.getAll('permissions')
    }});
    if (button) button.disabled = false;
    if (error || !data?.staff) {
      let serverMessage = data?.error;
      if (!serverMessage && error?.context && typeof error.context.clone === 'function') {
        try {
          const errorBody = await error.context.clone().json();
          serverMessage = typeof errorBody?.error === 'string' ? errorBody.error : '';
        } catch { /* Keep the SDK message if the response has no readable JSON body. */ }
      }
      if (serverMessage === 'An account already uses this email.') {
        serverMessage = 'البريد الإلكتروني مستخدم بالفعل؛ استخدم بريدًا آخر للموظف.';
      }
      toast(serverMessage || error?.message || 'تعذر إنشاء حساب الموظف', 'error');
      return;
    }
    state.staffProvisionResult = data;
    await loadStaffDirectory();
    render();
    toast('تم إنشاء الحساب؛ كلمة المرور المؤقتة ظاهرة للمدير فقط', 'success');
    return;
  }

  if (form.id === 'staffEditForm') {
    if (!hasRole('admin') || !supabase) { toast('ليس لديك صلاحية إدارة الموظفين', 'error'); return; }
    const fd = new FormData(form);
    const accountRole = String(fd.get('account_role') || 'employee');
    const button = form.querySelector('button[type="submit"]');
    if (button) button.disabled = true;
    const { data, error } = await supabase.functions.invoke('manage-staff', { body: {
      action: 'update', user_id: form.dataset.userId, full_name: fd.get('full_name'),
      phone: fd.get('phone'), permissions: fd.getAll('permissions'), account_role: accountRole
    }});
    if (button) button.disabled = false;
    if (error || !data?.success) { toast(data?.error || error?.message || 'تعذر حفظ تعديلات الموظف', 'error'); return; }
    await loadStaffDirectory();
    render();
    toast(accountRole === 'manager' ? 'تم حفظ البيانات وترقية الحساب إلى مدير مساعد' : 'تم حفظ بيانات الموظف وصلاحياته', 'success');
    return;
  }

  /* Motorcycle catalogue data and Telegram-backed images are stored through Supabase. */
  if (form.id === 'bikeForm') {
    if (!hasRole('admin','manager','owner') && !hasPermission('catalog_manage')) { toast('ليس لديك صلاحية المعرض / الكتالوج', 'error'); return; }
    const fd = new FormData(form);
    const id = form.dataset.id;
    const images = String(fd.get('images') || '').split('\n').map((s) => s.trim()).filter(Boolean);
    const values = {
      name: safeName(fd.get('name')),
      model_year: Number(fd.get('model')) || null,
      category: safeName(fd.get('category')),
      price: Number(fd.get('price')) || 0,
      description: String(fd.get('description') || '').trim(),
      status: String(fd.get('status') || 'draft'),
      image_urls: images
    };
    const result = id
      ? await supabase.from('motorcycles').update(values).eq('id', id).select('id').single()
      : await supabase.from('motorcycles').insert({ ...values, stock: 0 }).select('id').single();
    if (result.error) { toast(result.error.message, 'error'); return; }

    const savedId = result.data.id;
    const photos = fd.getAll('photos').filter((file) => file instanceof File && file.size > 0);
    let uploadFailure = null;
    for (const originalPhoto of photos) {
      let photo;
      try {
        photo = await optimizeCatalogImage(originalPhoto);
      } catch (error) {
        uploadFailure = error?.message || 'تعذر ضغط الصورة قبل الرفع';
        break;
      }
      const body = new FormData();
      body.append('photo', photo, photo.name);
      body.append('motorcycle_id', savedId);
      const { data, error } = await supabase.functions.invoke('telegram-photo-upload', { body });
      if (error || !data?.photo_asset?.id || !data?.public_url) {
        uploadFailure = data?.error || error?.message || 'تعذر حفظ الصورة وربطها بالكتالوج';
        break;
      }
    }
    await loadMotorcycles();
    closeModal();
    render();
    if (uploadFailure) toast(`تم حفظ بيانات الدراجة، لكن رفع الصور توقف: ${uploadFailure}`, 'error');
    else toast(photos.length ? 'تم ضغط الصور ومزامنتها وربطها بالكتالوج' : 'تم حفظ الدراجة في Supabase', 'success');
    return;
  }


});

/* ---------- Event: Input / Change ---------- */
document.addEventListener('input', (e) => {
  if(e.target.closest('#supplierBillForm')) updateSupplierBillTotal(e.target.closest('#supplierBillForm'));
  if (e.target.id === 'searchInput') {
    state.search = e.target.value;
    const grid = $('#productsGrid');
    if (grid) {
      const bikes = filteredBikes();
      grid.innerHTML = bikes.length
        ? bikes.map(productCard).join('')
        : `<div class="empty" style="grid-column:1/-1"><i class="fa-solid fa-box-open"></i><p>لا توجد نتائج</p></div>`;
    }
  }
});

document.addEventListener('change', (e) => {
  if(e.target.id==='supplierBillPurchaseOrder') renderSupplierBillLines(e.target.value);
  if(e.target.closest('#supplierBillForm')) updateSupplierBillTotal(e.target.closest('#supplierBillForm'));
  if (e.target.id === 'filterCat') { state.filterCat = e.target.value; render(); }
  if (e.target.id === 'filterPrice') { state.filterPrice = e.target.value; render(); }
  if (e.target.matches('.pos-cart-row select[name="motorcycle_id"]')) {
    const row=e.target.closest('.pos-cart-row');
    const unitSelect=row?.querySelector('select[name="unit_ids"]');
    if(unitSelect){
      [...unitSelect.options].forEach(option=>{
        option.selected=false;
        option.disabled=!!e.target.value && option.dataset.motorcycleId!==e.target.value;
      });
    }
  }
  if (e.target.id === 'posCustomerAccount') {
    const option = e.target.selectedOptions?.[0];
    const name = document.getElementById('posCustomerName');
    const phone = document.getElementById('posCustomerPhone');
    if (e.target.value && option) {
      if (name) name.value = option.dataset.name || '';
      if (phone) phone.value = option.dataset.phone || '';
    }
  }
});

/* ---------- Keyboard A11y ---------- */
document.addEventListener('keydown', (e) => {
  if (e.key === 'Escape') {
    if ($('#modalOverlay').classList.contains('show')) closeModal();
    else if (state.sidebarOpen) closeSidebar();
  }
});

/* ---------- Init ---------- */
async function loadStoreUnits() {
  if (!supabase) { state.storeUnits = []; return; }
  const { data, error } = await supabase.rpc('get_store_motorcycle_units');
  if (error) { console.error('Store units load failed', error); state.storeUnits = []; return; }
  state.storeUnits = (data || []).map((row) => ({ unit_id: row.unit_id, motorcycle_id: row.motorcycle_id, unit_condition: row.unit_condition }));
}

async function loadMotorcycleUnits() {
  if (!supabase || !state.user || !(hasRole('admin','manager','owner') || hasPermission('catalog_manage') || hasPermission('finance_manage') || hasPermission('sales_manage'))) return;
  const allUnits=[];
  for(let from=0; ; from+=500){
    const {data,error}=await supabase.from('motorcycle_units')
      .select('*,motorcycles(id,name,category,model_year,price,stock,image_urls,description)')
      .order('registered_at',{ascending:false}).range(from,from+499);
    if(error){console.error('Motorcycle units load failed',error);toast('تعذر تحميل وحدات الدراجات','error');return;}
    allUnits.push(...(data||[]));
    if(!data||data.length<500)break;
  }
  state.motorcycleUnits=allUnits;
}

async function loadMotorcycles() {
  if (!supabase) return;
  let query = supabase.from('motorcycles')
    .select('id,name,model_year,category,price,stock,image_urls,description,status,is_demo')
    .order('created_at', { ascending: false });
  // The physical units in the showroom are the source of truth. RLS exposes only
  // models that have at least one real, available unit (plus authorized staff data).
  const { data, error } = await query;
  if (error) { console.error('Catalogue load failed', error); return; }
  state.bikes = (data || []).map((row) => ({
    id: row.id, name: row.name, model: String(row.model_year || ''), category: row.category,
    price: Number(row.price), stock: row.stock, images: row.image_urls || [], description: row.description || '', status: row.status, is_demo: !!row.is_demo
  }));
  set(DB.BIKES, state.bikes);
}

async function loadSalesData() {
  if (!state.user || !(hasRole('admin','manager','owner') || hasPermission('sales_manage') || hasPermission('finance_manage')) || !supabase) {
    state.sales = [];
    state.saleDeliveries = [];
    return;
  }
  const { data, error } = await supabase.from('sales')
    .select('id,invoice_number,customer_id,customer_name,customer_phone,total,amount_paid,credit_applied,payment_status,status,created_at')
    .eq('channel', 'showroom')
    .order('created_at', { ascending: false })
    .limit(100);
  if (error) {
    console.error('Sales load failed', error);
    toast('تعذر تحميل سجل الفواتير', 'error');
    return;
  }
  state.sales = data || [];
  const deliveryResult = state.sales.length
    ? await supabase.from('sale_deliveries').select('id,delivery_number,sale_id,delivered_at,recipient_name,recipient_phone,odometer_reading,accessories,condition_notes,notes,sales(invoice_number,customer_name)').in('sale_id',state.sales.map(s=>s.id)).order('delivered_at',{ascending:false})
    : {data:[],error:null};
  if(deliveryResult.error){console.error('Sale delivery load failed',deliveryResult.error);toast('تعذر تحميل محاضر التسليم','error');state.saleDeliveries=[];}
  else state.saleDeliveries=deliveryResult.data||[];
  const customersResult = await supabase.from('clients')
    .select('user_id,display_name,phone').not('user_id','is',null).order('display_name');
  if (customersResult.error) {
    console.error('Registered customer list failed', customersResult.error);
    state.registeredCustomers = [];
  } else {
    state.registeredCustomers = customersResult.data || [];
  }
  const saleIds = state.sales.map(s => s.id);
  const returnsResult = saleIds.length
    ? await supabase.from('sale_returns').select('id,return_number,sale_id,total_amount,customer_name,created_at,notes').in('sale_id', saleIds).order('created_at', { ascending: false })
    : { data: [], error: null };
  if (returnsResult.error) { console.error('Sale returns load failed', returnsResult.error); toast('تعذر تحميل مرتجعات المبيعات', 'error'); return; }
  state.saleReturns = returnsResult.data || [];
  const returnIds = state.saleReturns.map(r => r.id);
  const itemsResult = returnIds.length
    ? await supabase.from('sale_return_items').select('id,sale_return_id,sale_item_id,motorcycle_id,quantity,disposition,unit_price,line_total').in('sale_return_id', returnIds)
    : { data: [], error: null };
  if (itemsResult.error) { console.error('Sale return items load failed', itemsResult.error); toast('تعذر تحميل تفاصيل المرتجعات', 'error'); return; }
  state.saleReturnItems = itemsResult.data || [];
  const creditResult = await supabase.from('customer_credit_balances')
    .select('customer_id,customer_name,customer_phone,balance')
    .order('balance', { ascending: false });
  if (creditResult.error) { console.error('Customer credit balances load failed', creditResult.error); toast('تعذر تحميل أرصدة العملاء', 'error'); return; }
  state.customerCredits = (creditResult.data || []).map(c => ({
    customerId:c.customer_id,name:c.customer_name || 'عميل',phone:c.customer_phone || '',balance:Number(c.balance || 0)
  }));
  state.sales = state.sales.map(s => ({...s,
    returnedAmount: state.saleReturns.filter(r => r.sale_id === s.id).reduce((n,r)=>n+Number(r.total_amount||0),0),
    returnItems: state.saleReturnItems.filter(i => state.saleReturns.some(r => r.id===i.sale_return_id && r.sale_id===s.id))
  }));
}

async function loadCustomerData() {
  const user = state.user;
  if (!user || !supabase) return;
  const [requestsResult, favoritesResult, salesResult] = await Promise.all([
    supabase.from('customer_requests').select('id,motorcycle_id,motorcycle_unit_id,requested_unit_condition,requested_name,requested_model_year,budget,notes,status,created_at').eq('client_user_id', user.id).order('created_at', { ascending: false }),
    supabase.from('favorites').select('motorcycle_id').eq('user_id', user.id),
    supabase.from('sales').select('id,invoice_number,total,amount_paid,credit_applied,payment_status,created_at').eq('channel','showroom').eq('status','posted').order('created_at',{ascending:false}).limit(100)
  ]);
  if (requestsResult.error) console.error('Customer request load failed', requestsResult.error);
  if (favoritesResult.error) console.error('Favorites load failed', favoritesResult.error);
  if (salesResult.error) console.error('Customer invoice history load failed', salesResult.error);
  const sales = salesResult.data || [];
  const saleIds = sales.map((sale) => sale.id);
  const [itemsResult,returnsResult] = await Promise.all([
    saleIds.length
      ? supabase.from('sale_items').select('sale_id,motorcycle_name,model_year,quantity,unit_price,line_total,sale_item_units(vin_snapshot,engine_number_snapshot)').in('sale_id', saleIds).order('created_at',{ascending:true})
      : Promise.resolve({data:[],error:null}),
    saleIds.length
      ? supabase.from('sale_returns').select('sale_id,total_amount').in('sale_id',saleIds)
      : Promise.resolve({data:[],error:null})
  ]);
  if (itemsResult.error) console.error('Customer invoice items load failed', itemsResult.error);
  if (returnsResult.error) console.error('Customer invoice returns load failed', returnsResult.error);
  const invoiceItems = itemsResult.data || [];
  const returnedBySale = new Map();
  for(const returned of returnsResult.data||[]) returnedBySale.set(returned.sale_id,(returnedBySale.get(returned.sale_id)||0)+Number(returned.total_amount||0));
  state.customerInvoices = sales.map((sale) => ({
    ...sale,
    total: Number(sale.total || 0),
    amount_paid: Number(sale.amount_paid || 0),
    credit_applied: Number(sale.credit_applied || 0),
    returned_amount: returnedBySale.get(sale.id)||0,
    balance_due: Math.max(0, Number(sale.total || 0) - Number(sale.amount_paid || 0) - Number(sale.credit_applied || 0) - (returnedBySale.get(sale.id)||0)),
    items: invoiceItems.filter((item) => item.sale_id === sale.id)
  }));
  set(DB.CUSTOM_REQS, (requestsResult.data || []).map((r) => ({id:r.id,motorcycleId:r.motorcycle_id,bikeName:r.requested_name,model:r.requested_model_year || '',unitCondition:r.requested_unit_condition || '',budget:Number(r.budget || 0),status:r.status,createdAt:r.created_at,customerEmail:user.email,notes:r.notes || ''})));
  set(DB.ORDERS, []);
  set(DB.FAVS, { [user.id]: (favoritesResult.data || []).map((f) => f.motorcycle_id) });
}

async function loadSalesToolsData() {
 const u=currentUser();if(!u||!supabase||!(hasRole('admin','manager','owner')||hasPermission('sales_manage')))return;
 const [quotes,items,installments]=await Promise.all([
  supabase.from('sales_quotations').select('*,clients(display_name,phone)').order('created_at',{ascending:false}).limit(300),
  supabase.from('sales_quotation_items').select('*,motorcycles(name)').limit(1000),
  supabase.from('sale_installments').select('*,sales(invoice_number,customer_name)').order('due_date').limit(1000)
 ]);
 const failed=[quotes,items,installments].find(x=>x.error);
 if(failed){console.error('Sales tools load failed',failed.error);toast('تعذر تحميل عروض الأسعار والتقسيط: '+failed.error.message,'error');return;}
 state.salesQuotations=quotes.data||[];state.salesQuotationItems=items.data||[];state.saleInstallments=installments.data||[];
}

async function loadCRMData() {
 const u=currentUser();if(!u||!supabase||!(hasRole('admin','manager','owner')||hasPermission('customer_data_view')||hasPermission('customer_data_manage')))return;
 const [clients,interactions,complaints,notifications]=await Promise.all([
  supabase.from('clients').select('id,display_name,phone,email,user_id,credit_limit,customer_segment,lead_source,marketing_consent').order('display_name').limit(1000),
  supabase.from('customer_interactions').select('*,clients(display_name,phone)').order('interaction_at',{ascending:false}).limit(500),
  supabase.from('customer_complaints').select('*').order('created_at',{ascending:false}).limit(300),
  supabase.from('internal_notifications').select('*').order('created_at',{ascending:false}).limit(100)
 ]);
 const failed=[clients,interactions,complaints,notifications].find(x=>x.error);
 if(failed){console.error('CRM load failed',failed.error);toast('تعذر تحميل بيانات إدارة العملاء: '+failed.error.message,'error');return;}
 state.crmClients=clients.data||[];state.customerInteractions=interactions.data||[];state.customerComplaints=complaints.data||[];state.internalNotifications=notifications.data||[];
 if(hasRole('admin','manager','owner')||hasPermission('sales_manage')){
  const stmt=await supabase.from('customer_statement').select('*').order('entry_date',{ascending:false}).limit(1000);
  if(!stmt.error)state.customerStatementRows=stmt.data||[];
 }
}

async function loadInventoryData() {
 const u=currentUser();if(!u||!supabase||!(hasRole('admin','manager','owner')||hasPermission('catalog_manage')||hasPermission('finance_manage')))return;
 const [costs,batches,lines,warranties,orders,alerts,reconciliation]=await Promise.all([
  supabase.from('motorcycle_inventory_costs').select('*'),
  supabase.from('stocktake_batches').select('*').order('stocktake_date',{ascending:false}).limit(100),
  supabase.from('stocktake_lines').select('*,motorcycles(name)').limit(1000),
  supabase.from('warranties').select('*,motorcycles(name)').order('created_at',{ascending:false}).limit(300),
  supabase.from('service_orders').select('*,motorcycles(name),employees(full_name,employee_code)').order('opened_at',{ascending:false}).limit(300),
  supabase.from('inventory_reorder_alerts').select('*').order('stock'),
  supabase.from('inventory_unit_reconciliation').select('*').order('difference',{ascending:false})
 ]);
 const results=[costs,batches,lines,warranties,orders,alerts,reconciliation],failed=results.find(x=>x.error);
 if(failed){console.error('Inventory data load failed',failed.error);toast('تعذر تحميل بيانات الجرد والصيانة: '+failed.error.message,'error');return;}
 const allUnits=[];
 for(let from=0;;from+=500){
  const {data,error}=await supabase.from('motorcycle_units').select('*,motorcycles(id,name,category,model_year,price,stock,image_urls,description)').order('registered_at',{ascending:false}).range(from,from+499);
  if(error){console.error('Inventory units page failed',error);toast('تعذر تحميل جميع وحدات المخزون','error');return;}
  allUnits.push(...(data||[]));if(!data||data.length<500)break;
 }
 state.inventoryCosts=costs.data||[];state.motorcycleUnits=allUnits;state.stocktakeBatches=batches.data||[];state.stocktakeLines=lines.data||[];
 state.warranties=warranties.data||[];state.serviceOrders=orders.data||[];state.reorderAlerts=alerts.data||[];state.inventoryReconciliation=reconciliation.data||[];
}

async function loadHRData() {
  const u=currentUser();
  if(!u||!supabase||!(hasRole('admin','manager','owner')||hasPermission('finance_manage')))return;
  const [employees,attendance,leaves,custody,advances,commissions,runs,items,payments]=await Promise.all([
    supabase.from('employees').select('*').order('full_name'),
    supabase.from('attendance_records').select('*,employees(full_name,employee_code)').order('attendance_date',{ascending:false}).limit(300),
    supabase.from('employee_leave_requests').select('*,employees(full_name,employee_code)').order('created_at',{ascending:false}).limit(200),
    supabase.from('employee_custody').select('*,employees(full_name,employee_code)').order('created_at',{ascending:false}).limit(200),
    supabase.from('employee_advances').select('*,employees(full_name,employee_code)').order('advance_date',{ascending:false}).limit(200),
    supabase.from('sales_commissions').select('*,employees(full_name,employee_code),sales(invoice_number)').order('created_at',{ascending:false}).limit(300),
    supabase.from('payroll_runs').select('*').order('payroll_date',{ascending:false}).limit(100),
    supabase.from('payroll_items').select('*,employees(full_name,employee_code)').limit(1000),
    supabase.from('payroll_payments').select('*').order('payment_date',{ascending:false}).limit(300)
  ]);
  const results=[employees,attendance,leaves,custody,advances,commissions,runs,items,payments];
  const failed=results.find(x=>x.error);
  if(failed){console.error('HR load failed',failed.error);toast('تعذر تحميل بيانات الموارد البشرية: '+failed.error.message,'error');return;}
  state.employees=employees.data||[];state.attendanceRecords=attendance.data||[];state.employeeLeaveRequests=leaves.data||[];
  state.employeeCustody=custody.data||[];state.employeeAdvances=advances.data||[];state.salesCommissions=commissions.data||[];
  state.payrollRuns=runs.data||[];state.payrollItems=items.data||[];state.payrollPayments=payments.data||[];
}

async function loadSalesCashAccounts() {
  if (!currentUser() || !supabase || !(hasRole('admin','manager','owner') || hasPermission('sales_manage'))) return;
  const {data,error}=await supabase.rpc('get_sales_cash_accounts');
  if(error){console.error('Sales cash accounts load failed',error);toast('تعذر تحميل حسابات التحصيل','error');return;}
  state.salesCashAccounts=data||[];
}

async function loadFinanceData() {
  const u = currentUser();
  if (!u || !supabase || !(hasRole('admin','manager','owner') || hasPermission('expenses_manage') || hasPermission('accounting_view') || hasPermission('finance_manage'))) return;
  const [
    accountsResult, allAccountsResult, cashResult, expensesResult, trialResult, balancesResult,
    periodsResult, centersResult, openingResult, advancesResult, advanceAllocationsResult,
    assetsResult, depreciationResult, reconciliationsResult, reconciliationLinesResult,
    journalLinesResult, chequesResult, recurringResult, recurringRunsResult, taxRatesResult,
    sessionsResult, handoversResult, pettyCashResult, settingsResult, reversalsResult,
    budgetsResult, budgetActualResult, accrualSchedulesResult, accrualRunsResult,
    agingResult, cashBookResult, journalEntriesResult, unallocatedPaymentsResult, unallocatedRefundsResult
  ] = await Promise.all([
    supabase.from('accounting_accounts').select('id,code,name,account_type').eq('is_active', true).eq('account_type', 'expense').order('code'),
    supabase.from('accounting_accounts').select('id,code,name,account_type,parent_code').eq('is_active', true).order('code'),
    supabase.from('cash_accounts').select('id,name,account_id,account_kind,currency').eq('is_active', true).order('name'),
    supabase.from('expenses').select('id,expense_number,expense_date,description,vendor_name,reference_number,amount,paid_amount,due_date,notes,accounting_accounts(name,code)').order('expense_date', {ascending:false}).limit(250),
    supabase.from('accounting_trial_balance').select('account_id,account_code,account_name,account_type,total_debit,total_credit,debit_balance,credit_balance').order('account_code'),
    supabase.from('accounting_cash_balances').select('cash_account_id,cash_account_name,account_kind,currency,balance').order('cash_account_name'),
    supabase.from('fiscal_periods').select('*').order('start_date',{ascending:false}).limit(60),
    supabase.from('cost_centers').select('*').order('code'),
    supabase.from('opening_balance_batches').select('*').order('effective_date',{ascending:false}).limit(100),
    supabase.from('supplier_advances').select('*,suppliers(name)').order('advance_date',{ascending:false}).limit(200),
    supabase.from('supplier_advance_allocations').select('*').order('created_at',{ascending:false}).limit(500),
    supabase.from('fixed_assets').select('*').order('asset_number',{ascending:false}).limit(200),
    supabase.from('fixed_asset_depreciations').select('*').order('period_date',{ascending:false}).limit(500),
    supabase.from('bank_reconciliations').select('*,cash_accounts(name,account_id,account_kind)').order('period_end',{ascending:false}).limit(100),
    supabase.from('bank_reconciliation_lines').select('*').order('statement_date',{ascending:false}).limit(500),
    supabase.from('journal_entry_lines').select('id,journal_entry_id,account_id,debit,credit,memo,journal_entries(entry_date,description,entry_number)').order('created_at',{ascending:false}).limit(500),
    supabase.from('cheques').select('*,cash_accounts(name)').order('due_date',{ascending:true}).limit(250),
    supabase.from('recurring_journal_templates').select('*,recurring_journal_template_lines(id,account_id,debit,credit,memo)').order('created_at',{ascending:false}).limit(100),
    supabase.from('recurring_journal_runs').select('*').order('run_date',{ascending:false}).limit(250),
    supabase.from('tax_rates').select('*,accounting_accounts(name,code)').order('effective_from',{ascending:false}).limit(100),
    supabase.from('cash_sessions').select('*,cash_accounts(name,account_kind)').order('opened_at',{ascending:false}).limit(100),
    supabase.from('cash_handovers').select('*').order('created_at',{ascending:false}).limit(200),
    supabase.from('petty_cash_transactions').select('*,accounting_accounts(name,code),cash_accounts(name)').order('transaction_date',{ascending:false}).limit(250),
    supabase.from('finance_settings').select('petty_cash_limit,updated_at').limit(1),
    supabase.from('journal_entry_reversals').select('*').order('created_at',{ascending:false}).limit(250),
    supabase.from('finance_budgets').select('*,finance_budget_lines(id,account_id,cost_center_id,budget_amount)').order('created_at',{ascending:false}).limit(100),
    supabase.from('finance_budget_vs_actual').select('*').limit(500),
    supabase.from('accrual_schedules').select('*').order('next_run_date').limit(100),
    supabase.from('accrual_runs').select('*').order('run_date',{ascending:false}).limit(250),
    supabase.from('accounting_aging_report').select('*').order('days_overdue',{ascending:false,nullsFirst:false}).limit(500),
    supabase.from('accounting_cash_book').select('*').order('entry_date',{ascending:false}).limit(500),
    supabase.from('journal_entries').select('id,entry_number,entry_date,description,status').order('entry_date',{ascending:false}).limit(250),
    supabase.from('payments').select('id,sale_id,amount,method,reference,paid_at,journal_entry_id,sales(invoice_number,customer_name)').is('cash_account_id',null).not('journal_entry_id','is',null).order('paid_at',{ascending:false}).limit(300),
    supabase.from('customer_credit_transactions').select('id,customer_id,amount,method,reference,created_at,clients(display_name,phone)').eq('transaction_type','cash_refund').is('cash_account_id',null).limit(300)
  ]);
  const results=[accountsResult,allAccountsResult,cashResult,expensesResult,trialResult,balancesResult,periodsResult,centersResult,openingResult,advancesResult,advanceAllocationsResult,assetsResult,depreciationResult,reconciliationsResult,reconciliationLinesResult,journalLinesResult,chequesResult,recurringResult,recurringRunsResult,taxRatesResult,sessionsResult,handoversResult,pettyCashResult,settingsResult,reversalsResult,budgetsResult,budgetActualResult,accrualSchedulesResult,accrualRunsResult,agingResult,cashBookResult,journalEntriesResult,unallocatedPaymentsResult,unallocatedRefundsResult];
  const failed=results.find(r=>r.error);
  if(failed){console.error('Finance data load failed',failed.error);toast('تعذر تحميل بعض الأدوات المالية: '+(failed.error.message||''),'error');return;}
  state.financeAccounts=accountsResult.data||[];
  state.financeAllAccounts=allAccountsResult.data||[];
  state.cashAccounts=cashResult.data||[];
  state.expenses=expensesResult.data||[];
  state.trialBalance=trialResult.data||[];
  state.cashBalances=balancesResult.data||[];
  state.fiscalPeriods=periodsResult.data||[];
  state.costCenters=centersResult.data||[];
  state.openingBatches=openingResult.data||[];
  state.supplierAdvances=advancesResult.data||[];
  state.supplierAdvanceAllocations=advanceAllocationsResult.data||[];
  state.fixedAssets=assetsResult.data||[];
  state.fixedAssetDepreciations=depreciationResult.data||[];
  state.bankReconciliations=reconciliationsResult.data||[];
  state.bankReconciliationLines=reconciliationLinesResult.data||[];
  state.financeJournalLines=journalLinesResult.data||[];
  state.cheques=chequesResult.data||[];
  state.recurringJournalTemplates=recurringResult.data||[];
  state.recurringJournalRuns=recurringRunsResult.data||[];
  state.taxRates=taxRatesResult.data||[];
  state.cashSessions=sessionsResult.data||[];
  state.cashHandovers=handoversResult.data||[];
  state.pettyCashTransactions=pettyCashResult.data||[];
  state.financeSettings=settingsResult.data?.[0]||null;
  state.journalReversals=reversalsResult.data||[];
  state.financeBudgets=budgetsResult.data||[];
  state.financeBudgetVsActual=budgetActualResult.data||[];
  state.accrualSchedules=accrualSchedulesResult.data||[];
  state.accrualRuns=accrualRunsResult.data||[];
  state.agingReport=agingResult.data||[];
  state.cashBook=cashBookResult.data||[];
  state.financeJournalEntries=journalEntriesResult.data||[];
  state.unallocatedSalePayments=unallocatedPaymentsResult.data||[];
  state.unallocatedCustomerRefunds=unallocatedRefundsResult.data||[];
}
async function loadBusinessData() {
  if (!state.user || !['staff', 'admin'].includes(state.user.role) || !supabase) return;
  if (state.user.role === 'staff' && !hasRequestAccess()) { set(DB.CUSTOM_REQS, []); state.contactMessages = []; return; }
  const canSeeContacts = hasPermission('customer_data_view') || hasRequestAccess();
  const requestFields = 'id,client_user_id,motorcycle_id,motorcycle_unit_id,requested_unit_vin,requested_unit_condition,requested_name,requested_model_year,budget,notes,status,created_at' +
    (canSeeContacts ? ',requester_name,requester_phone,requester_email,preferred_contact' : '');
  const [requestResult, messageResult] = await Promise.all([
    supabase.from('customer_requests').select(requestFields).order('created_at', { ascending: false }).limit(200),
    canSeeContacts ? supabase.from('contact_messages').select('id,sender_user_id,name,email,phone,message,preferred_contact,status,created_at').order('created_at', { ascending: false }).limit(200) : Promise.resolve({data:[],error:null})
  ]);
  if (requestResult.error) { console.error('Business request load failed', requestResult.error); toast('تعذر تحميل طلبات العملاء', 'error'); return; }
  if (messageResult.error) console.error('Contact inbox load failed', messageResult.error);
  const requests = requestResult.data || [];
  const ids = [...new Set(requests.filter((r) => r.client_user_id && !r.requester_name).map((r) => r.client_user_id))];
  const profileResult = ids.length && hasPermission('customer_data_view')
    ? await supabase.from('profiles').select('id,full_name,phone').in('id', ids)
    : {data:[],error:null};
  const profiles = new Map((profileResult.data || []).map((p) => [p.id, p]));
  set(DB.CUSTOM_REQS, requests.map((r) => {
    const p = profiles.get(r.client_user_id) || {};
    return {id:r.id,clientUserId:r.client_user_id,motorcycleId:r.motorcycle_id,requestedUnitId:r.motorcycle_unit_id || '',requestedUnitVin:r.requested_unit_vin || '',requestedUnitCondition:r.requested_unit_condition || '',bikeName:r.requested_name,model:r.requested_model_year || '',budget:Number(r.budget || 0),status:r.status,createdAt:r.created_at,customerName:r.requester_name || p.full_name || '',customerPhone:r.requester_phone || p.phone || '',customerEmail:r.requester_email || '',preferredContact:r.preferred_contact || 'phone',notes:r.notes || ''};
  }));
  state.contactMessages = messageResult.data || [];
  const requestIds = requests.map((r) => r.id);
  const messageIds = state.contactMessages.map((m) => m.id);
  const [requestReplies, contactReplies] = await Promise.all([
    requestIds.length ? supabase.from('customer_request_replies').select('id,request_id,reply_body,channel,sent_at,created_at').in('request_id', requestIds).order('created_at', {ascending:false}) : Promise.resolve({data:[],error:null}),
    messageIds.length ? supabase.from('contact_message_replies').select('id,message_id,reply_body,channel,sent_at,created_at').in('message_id', messageIds).order('created_at', {ascending:false}) : Promise.resolve({data:[],error:null})
  ]);
  if (requestReplies.error) console.error('Request reply history failed', requestReplies.error);
  if (contactReplies.error) console.error('Contact reply history failed', contactReplies.error);
  state.requestReplies = requestReplies.data || [];
  state.contactReplies = contactReplies.data || [];
}


async function loadPurchasingRows(table, columns, key, values) {
  if(!values?.length)return {data:[],error:null};
  const rows=[];
  for(let offset=0;;offset+=1000){
    const result=await supabase.from(table).select(columns).in(key,values).range(offset,offset+999);
    if(result.error)return {data:null,error:result.error};
    rows.push(...(result.data||[]));
    if((result.data||[]).length<1000)break;
  }
  return {data:rows,error:null};
}

function renderSupplierBillLines(orderId) {
  const container=$('#supplierBillLines');
  if(!container)return;
  const order=state.purchaseOrders.find(o=>o.id===orderId);
  const lines=(order?.receiptItems||[]).filter(item=>Number(item.available_to_bill||0)>0);
  if(!orderId){container.innerHTML='<small class="hint">اختر أمر التوريد لعرض بنود الاستلام.</small>';updateSupplierBillTotal($('#supplierBillForm'));return;}
  if(!lines.length){container.innerHTML='<div class="empty">لا توجد وحدات مستلمة غير مفوترة في أمر التوريد المحدد.</div>';updateSupplierBillTotal($('#supplierBillForm'));return;}
  container.innerHTML=lines.map(item=>{
    const bike=state.bikes.find(b=>b.id===item.motorcycle_id);
    const description=bike?.name||item.motorcycle_name||'صنف مستلم';
    const max=Number(item.available_to_bill);
    return `<div class="supplier-bill-line panel" data-receipt-item-id="${esc(item.id)}">
      <label><input type="checkbox" name="selected" value="${esc(item.id)}"> <b>${esc(description)}</b> — استلام ${esc(item.receipt_number)} — المتاح للفوترة ${max}</label>
      <div class="form-row">
        <div class="field"><label>الكمية المفوترة</label><input name="quantity" type="number" min="1" max="${max}" value="${max}" disabled></div>
        <div class="field"><label>سعر الوحدة في الفاتورة (ج.م)</label><input name="unit_cost" type="number" min="0" step="0.01" value="${Number(item.unit_cost||0).toFixed(2)}" disabled></div>
      </div>
      <small class="hint">تكلفة الاستلام المسجلة: ${money(item.unit_cost)} لكل وحدة. أي فرق سعر سيظهر كفرق تكلفة في القيد المحاسبي.</small>
    </div>`;
  }).join('');
  updateSupplierBillTotal($('#supplierBillForm'));
}

function updateSupplierBillTotal(form) {
  if(!form)return;
  let total=0;
  for(const row of form.querySelectorAll('.supplier-bill-line')){
    const checkbox=row.querySelector('[name="selected"]');
    const quantity=row.querySelector('[name="quantity"]');
    const cost=row.querySelector('[name="unit_cost"]');
    const enabled=!!checkbox?.checked;
    if(quantity)quantity.disabled=!enabled;
    if(cost)cost.disabled=!enabled;
    if(enabled)total+=Math.round(Number(quantity.value||0)*Number(cost.value||0)*100)/100;
  }
  const direct=form.querySelector('[name="direct_line_enabled"]')?.checked;
  const directAmount=form.querySelector('[name="direct_amount"]');
  const directDescription=form.querySelector('[name="direct_description"]');
  if(directAmount)directAmount.disabled=!direct;
  if(directDescription)directDescription.disabled=!direct;
  if(direct)total+=Number(directAmount?.value||0);
  const totalInput=form.querySelector('[name="total_amount"]');
  if(totalInput)totalInput.value=total>0?total.toFixed(2):'';
}

async function loadPurchasingData() {
  if (!state.user || state.user.role !== 'admin') {
    state.purchasingLoadStatus = 'forbidden';
    state.purchasingLoadErrors = [];
    state.suppliers=[]; state.purchaseOrders=[]; state.supplierBills=[]; state.supplierBillItems=[]; state.supplierPayments=[]; state.supplierReturns=[]; state.supplierReturnItems=[];
    return;
  }
  if (!supabase) {
    state.purchasingLoadStatus = 'unavailable';
    state.purchasingLoadErrors = [];
    state.suppliers=[]; state.purchaseOrders=[]; state.supplierBills=[]; state.supplierBillItems=[]; state.supplierPayments=[]; state.supplierReturns=[]; state.supplierReturnItems=[];
    return;
  }
  state.purchasingLoadStatus = 'loading';
  state.purchasingLoadErrors = [];
  try {
  const [supplierResult,orderResult,billResult,paymentResult,returnResult,advanceAllocationResult]=await Promise.all([
    supabase.from('suppliers').select('id,name,phone,email,address,tax_id,is_active').order('name'),
    supabase.from('purchase_orders').select('id,order_number,supplier_id,status,notes,created_at').order('created_at',{ascending:false}).limit(100),
    supabase.from('supplier_bills').select('id,bill_number,supplier_id,purchase_order_id,bill_date,due_date,total_amount,notes,created_at').order('bill_date',{ascending:false}).limit(200),
    supabase.from('supplier_payments').select('id,payment_number,supplier_bill_id,supplier_id,amount,method,reference,notes,paid_at,journal_entry_id').order('paid_at',{ascending:false}).limit(500),
    supabase.from('supplier_returns').select('id,return_number,supplier_id,purchase_order_id,supplier_bill_id,notes,created_by,created_at').order('created_at',{ascending:false}).limit(500),
    supabase.from('supplier_advance_allocations').select('id,advance_id,supplier_bill_id,amount,created_at').order('created_at',{ascending:false}).limit(500)
  ]);
  const reportError=(label,error)=>{state.purchasingLoadErrors.push(label);toast('تعذر تحميل '+label,'error');console.error('Purchasing query failed: '+label,error);};
  const initialLoaded=applyQueryResults(state,[
    {result:supplierResult,key:'suppliers',label:'الموردين'},
    {result:paymentResult,key:'supplierPayments',label:'مدفوعات الموردين'},
    {result:returnResult,key:'supplierReturns',label:'مرتجعات الموردين'},
    {result:advanceAllocationResult,key:'supplierAdvanceAllocations',label:'تسويات سلف الموردين'}
  ],reportError);
  const billLoaded=applyQueryResults({},[{result:billResult,key:'data',label:'فواتير الموردين'}],reportError).has('data');
  const orderLoaded=applyQueryResults({},[{result:orderResult,key:'data',label:'أوامر التوريد'}],reportError).has('data');

  let billItemsLoaded=false;
  if(billLoaded){
    const billIds=(billResult.data||[]).map(b=>b.id);
    const billItemsResult=await loadPurchasingRows('supplier_bill_items','id,supplier_bill_id,line_number,line_type,purchase_receipt_item_id,description,quantity,unit_cost,line_total','supplier_bill_id',billIds);
    billItemsLoaded=applyQueryResults(state,[{result:billItemsResult,key:'supplierBillItems',label:'تفاصيل فواتير الموردين'}],reportError).has('supplierBillItems');
  }

  let returnItemsLoaded=false;
  if(initialLoaded.has('supplierReturns')){
    const returnIds=state.supplierReturns.map(r=>r.id);
    const returnItemsResult=returnIds.length
      ?await supabase.from('supplier_return_items').select('id,supplier_return_id,purchase_receipt_item_id,motorcycle_id,quantity,unit_cost,line_total').in('supplier_return_id',returnIds)
      :{data:[],error:null};
    returnItemsLoaded=applyQueryResults(state,[{result:returnItemsResult,key:'supplierReturnItems',label:'تفاصيل مرتجعات الموردين'}],reportError).has('supplierReturnItems');
  }

  const suppliersLoaded=initialLoaded.has('suppliers');
  const billsReady=suppliersLoaded&&billLoaded&&billItemsLoaded&&initialLoaded.has('supplierPayments')&&initialLoaded.has('supplierReturns')&&returnItemsLoaded&&initialLoaded.has('supplierAdvanceAllocations');
  if(billsReady){
    state.supplierBills=(billResult.data||[]).map(b=>{
      const payments=state.supplierPayments.filter(p=>p.supplier_bill_id===b.id);
      const paid=payments.reduce((n,p)=>n+Number(p.amount||0),0);
      const credits=state.supplierReturns.filter(r=>r.supplier_bill_id===b.id).reduce((n,r)=>
        n+state.supplierReturnItems.filter(i=>i.supplier_return_id===r.id).reduce((sum,i)=>sum+Number(i.line_total||Number(i.quantity)*Number(i.unit_cost)),0),0);
      const advanceAllocated=state.supplierAdvanceAllocations.filter(a=>a.supplier_bill_id===b.id).reduce((n,a)=>n+Number(a.amount||0),0);
      return {...b,supplierName:state.suppliers.find(s=>s.id===b.supplier_id)?.name||'—',payments,amountPaid:paid,creditAmount:credits,advanceAllocated,balanceDue:Math.max(0,Number(b.total_amount)-paid-credits-advanceAllocated)};
    });
  }

  if(!orderLoaded||!suppliersLoaded)return;
  const orderIds=(orderResult.data||[]).map(o=>o.id);
  const [itemsResult,receiptResult]=await Promise.all([
    orderIds.length?supabase.from('purchase_order_items').select('id,purchase_order_id,motorcycle_id,motorcycle_name,model_year,quantity_ordered,quantity_received,unit_cost').in('purchase_order_id',orderIds):Promise.resolve({data:[],error:null}),
    orderIds.length?supabase.from('purchase_receipts').select('id,receipt_number,purchase_order_id,received_at').in('purchase_order_id',orderIds):Promise.resolve({data:[],error:null})
  ]);
  const orderDetailLoaded=applyQueryResults({},[
    {result:itemsResult,key:'items',label:'أصناف أوامر التوريد'},
    {result:receiptResult,key:'receipts',label:'إيصالات الاستلام'}
  ],reportError);
  if(!orderDetailLoaded.has('items')||!orderDetailLoaded.has('receipts')||!billItemsLoaded||!returnItemsLoaded)return;
  const receiptIds=(receiptResult.data||[]).map(r=>r.id);
  const receiptItemsResult=receiptIds.length
    ?await supabase.from('purchase_receipt_items').select('id,receipt_id,purchase_order_item_id,motorcycle_id,quantity,unit_cost').in('receipt_id',receiptIds)
    :{data:[],error:null};
  const receiptItemsLoaded=applyQueryResults({},[{result:receiptItemsResult,key:'items',label:'بنود الاستلام'}],reportError).has('items');
  if(!receiptItemsLoaded)return;
  const billItemIds=state.supplierBillItems.map(line=>line.id);
  const returnItemIds=state.supplierReturnItems.map(line=>line.id);
  const [receiptUnitsResult,billedUnitsResult,returnedUnitsResult]=await Promise.all([
    loadPurchasingRows('purchase_receipt_units','receipt_item_id,motorcycle_unit_id','receipt_id',receiptIds),
    loadPurchasingRows('supplier_bill_item_units','motorcycle_unit_id','supplier_bill_item_id',billItemIds),
    loadPurchasingRows('supplier_return_units','motorcycle_unit_id','supplier_return_item_id',returnItemIds)
  ]);
  const unitLinksLoaded=applyQueryResults({},[
    {result:receiptUnitsResult,key:'receiptUnits',label:'وحدات الاستلام'},
    {result:billedUnitsResult,key:'billedUnits',label:'الوحدات المفوترة'},
    {result:returnedUnitsResult,key:'returnedUnits',label:'الوحدات المرتجعة'}
  ],reportError);
  if(unitLinksLoaded.size!==3)return;
  const receiptItems=receiptItemsResult.data||[];
  const billedUnitIds=new Set((billedUnitsResult.data||[]).map(row=>row.motorcycle_unit_id));
  const returnedUnitIds=new Set((returnedUnitsResult.data||[]).map(row=>row.motorcycle_unit_id));
  state.purchaseOrders=(orderResult.data||[]).map(o=>({...o,
    supplierName:state.suppliers.find(s=>s.id===o.supplier_id)?.name||'—',
    items:(itemsResult.data||[]).filter(i=>i.purchase_order_id===o.id),
    receipts:(receiptResult.data||[]).filter(r=>r.purchase_order_id===o.id),
    receiptItems:receiptItems.filter(ri=>(receiptResult.data||[]).some(r=>r.id===ri.receipt_id&&r.purchase_order_id===o.id)).map(ri=>{
      const receipt=(receiptResult.data||[]).find(r=>r.id===ri.receipt_id);
      const billed=state.supplierBillItems.filter(line=>line.purchase_receipt_item_id===ri.id).reduce((n,line)=>n+Number(line.quantity||0),0);
      const available=receiptUnitsResult.data.filter(unit=>unit.receipt_item_id===ri.id&&!billedUnitIds.has(unit.motorcycle_unit_id)&&!returnedUnitIds.has(unit.motorcycle_unit_id)).length;
      return {...ri,receipt_number:receipt?.receipt_number||'—',billed_quantity:billed,available_to_bill:available};
    })
  }));
  } catch (error) {
    state.purchasingLoadErrors.push('قراءة بيانات الشراء');
    console.error('Purchasing data load failed', error);
  } finally {
    state.purchasingLoadStatus = state.purchasingLoadErrors.length ? 'partial' : 'loaded';
  }
}
async function loadStaffDirectory() {
  if (!state.user || state.user.role !== 'admin' || !supabase) return;
  const { data, error } = await supabase.functions.invoke('manage-staff', { body: { action: 'list' } });
  if (error || !Array.isArray(data?.staff)) { console.error('Staff directory load failed', error || data?.error); return; }
  set(DB.USERS, data.staff.map((person) => ({
    id: person.id,
    name: person.name || '',
    email: person.email || '',
    phone: person.phone || '',
    permissions: person.permissions || [],
    accountRole: person.account_role || 'employee',
    role: 'staff'
  })));
}

async function init() {
  // Business records come from Supabase. Legacy browser-local keys are left untouched and unused.
  if (!supabaseConfigured || !supabase) toast('إعداد Supabase غير مكتمل', 'error');
  else {
    const { data: { session } } = await supabase.auth.getSession();
    if (session?.user) {
      try {
        const profile = await getCurrentProfile(session.user.id);
        if (!profile) throw new Error('Supabase profile is missing for this account.');
        state.user = { ...profile, id: session.user.id, email: session.user.email };
        if (state.user.role === 'customer') await loadCustomerData();
        else { await loadBusinessData(); }
      } catch (error) { console.error('Profile load failed', error); }
    }
    supabase.auth.onAuthStateChange((_event, session) => {
      if (!session) { state.user = null; set(DB.ORDERS, []); set(DB.CUSTOM_REQS, []); set(DB.FAVS, {}); state.contactMessages = []; state.requestReplies = []; state.contactReplies = []; state.sales = []; render(); }
    });
    await Promise.all([loadMotorcycles(), loadStoreUnits()]);
    // Heavy sales and purchasing datasets are loaded only when their pages are opened.
  }
  render();
  if (state.user?.role === 'customer') await resumePendingAuthAction();
}

const EN = {
  'الرئيسية':'Home','اطلب موتسيكلك':'Request a motorcycle','تواصل معنا':'Contact us','تسجيل الدخول':'Sign in','حساب جديد':'Create account',
  'حسابات الموظفين':'Staff accounts','الموظفون الحاليون':'Current staff','إنشاء حساب موظف':'Create staff account',
  'اسم الموظف':'Staff name','البريد الإلكتروني':'Email address','رقم الهاتف (اختياري)':'Phone (optional)',
  'الصلاحيات الممنوحة — لا شيء محدد افتراضيًا':'Granted permissions — none selected by default',
  'عرض الكتالوج والمخزون':'View catalog and inventory','المعرض / الكتالوج والصور':'Manage motorcycles and photos',
  'عرض طلبات العملاء':'View customer requests','تحديث حالة الطلبات':'Update request status',
  'رؤية أسماء وهواتف العملاء':'View customer names and phone numbers', 
  'إعادة إرسال تأكيد البريد':'Resend email confirmation',
  'التسوق':'SHOP','الحساب':'ACCOUNT','حسابي':'My account','معرض الدراجات':'Motorcycle catalog',
  'تصفح مجموعتنا المختارة من أفضل الدراجات النارية':'Browse our selected motorcycles',
  'اقــود':'Ride','أسطورتك':'your legend','على عجلتين':'on two wheels',
  'أفضل الدراجات النارية الرياضية بأعلى جودة وأفضل الأسعار. اختر دراجتك الآن من El Khayal Motors.':'Sport motorcycles, quality and great value. Find your ride at El Khayal Motors.',
  'اطلب موتسيكلك الخاص':'Request a motorcycle','تصفح مجموعتنا المختارة من أفضل الدراجات النارية':'Browse our selected motorcycles',
  'ابحث بالاسم أو الموديل...':'Search by name or model...','كل الفئات':'All categories','كل الأسعار':'All prices',
  'أقل من 500 ألف':'Under 500,000','500 ألف - مليون':'500,000–1,000,000','أكثر من مليون':'Over 1,000,000',
  'لا توجد دراجات مطابقة للبحث':'No motorcycles match your search','اطلب موتسيكلك الخاص':'Request a motorcycle',
  'لم تجد الدراجة التي تريدها؟ اطلبها وسنتواصل معك':'Can’t find the motorcycle you want? Send a request and we’ll contact you.',
  'الاسم':'Name','رقم الهاتف':'Phone number','اسم الدراجة المطلوبة':'Motorcycle requested','الموديل / السنة':'Model year',
  'الميزانية التقريبية (ج.م)':'Approximate budget (EGP)','ملاحظات إضافية':'Additional notes','إرسال الطلب':'Send request',
  'تواصل معنا':'Contact us','نحن هنا لخدمتك':'We’re here to help','بيانات المعرض':'Showroom details','أرسل رسالة':'Send a message',
  'البريد الإلكتروني':'Email','الرسالة':'Message','إرسال':'Send','أدخل بياناتك للوصول إلى حسابك':'Sign in to access your account',
  'كلمة المرور':'Password','دخول':'Sign in','ليس لديك حساب؟':'Don’t have an account?','أنشئ حساباً جديداً':'Create an account',
  'حساب جديد':'Create account','سجل الآن لتتمكن من الشراء والمفضلة':'Create an account to make requests and save favorites',
  'الاسم الكامل':'Full name','إنشاء الحساب':'Create account','لديك حساب بالفعل؟':'Already have an account?',
  'تم تسجيل الخروج':'Signed out','سجّل الدخول لإرسال طلبك':'Sign in to send a request',
  'يرتبط الطلب بحسابك لحماية بياناتك ومتابعته.':'Requests are linked to your account so you can track them securely.',
  'تفاصيل':'Details','شراء':'Request purchase','متوفر':'Available','غير متوفر':'Unavailable','المفضلة':'Favorites','طلباتي':'My requests',
  'سجل الدخول أولاً':'Please sign in first','عميل':'Customer','موظف':'Employee','مدير':'Manager'
  ,'أدوات المالك والنسخ الاحتياطي':'Owner data tools & backups'
  ,'النسخ والاستعادة وإعادة ضبط بيانات التشغيل. جميع العمليات تتطلب كلمة مرور حساب المالك.':'Back up, restore, and reset operational data. Every action requires the owner password.'
  ,'كلمة مرور حساب المالك (تُطلب لكل عملية)':'Owner account password (required for each action)'
  ,'نسخة احتياطية':'Backup','إنشاء وتنزيل نسخة':'Create and download backup'
  ,'استعادة / استيراد':'Restore / Import','ملف النسخة الاحتياطية JSON':'Backup JSON file'
  ,'اكتب RESTORE BACKUP للتأكيد':'Type RESTORE BACKUP to confirm','استيراد النسخة':'Import backup'
  ,'حذف بيانات التشغيل':'Delete operational data','اكتب DELETE ALL DATA للتأكيد':'Type DELETE ALL DATA to confirm'
  ,'حذف كل بيانات التشغيل':'Delete all operational data','صلاحيات المالك':'Owner tools'
  ,'النسخ الاحتياطي وإعادة الضبط':'Backup & reset','تنبيه مهم:':'Important:'

  ,'الإدارة':'Management','البيع':'Sales','لوحة الإحصائيات':'Dashboard'
  ,'نظام البيع داخل المعرض':'Point of Sale (POS)','ماسح الشاسيه والموتور':'VIN & engine scanner'
  ,'الموردون والتوريد':'Suppliers & purchasing','الأسعار':'Inventory & pricing'
  ,'المعرض / الكتالوج':'Motorcycle management','التعيين وحسابات الموظفين':'Staff & performance'
  ,'النظام المالي':'Expenses & accounts','النظام المحاسبي':'Advanced finance tools'
  ,'الموارد البشرية والمرتبات':'HR & payroll','الجرد والضمان والصيانة':'Stocktake, warranty & service'
  ,'إدارة العملاء والعلاقات':'Customer relations','عروض الأسعار والتقسيط':'Quotations & installments'
  ,'طلبات العملاء':'Customer requests','عرض المتجر':'View storefront','المتجر':'Store'
  ,'النسخة تشمل بيانات جداول قاعدة البيانات الـ86، ولا تشمل الملفات الثنائية في Supabase Storage. الاستعادة تستبدل بيانات التشغيل الحالية مع الاحتفاظ بحساب المالك والإعدادات المحاسبية الأساسية وسجل التدقيق.':'The backup includes all 86 database tables, but not binary files in Supabase Storage. Restore replaces operational data while preserving the owner account, core accounting settings, and audit log.'
  ,'أدخل كلمة المرور':'Enter password'
  ,'تصدير بيانات قاعدة البيانات في ملف JSON مع بصمة تحقق SHA-256.':'Export database data to a JSON file with a SHA-256 integrity hash.'
  ,'ترفع البيانات إلى Supabase وتصبح مشتركة مع الموقع ولوحة الإدارة. الاستعادة ذرّية؛ إذا فشل التحقق تُلغى بالكامل.':'Uploads data to Supabase so it is shared with the storefront and admin panel. Restore is atomic and rolls back completely if validation fails.'
  ,'يحذف المبيعات والمشتريات والمخزون والعملاء والموظفين والقيود والحركات التشغيلية. يحتفظ بحساب المالك ودوره وإعدادات الحسابات والخزائن والضرائب وسجل التدقيق.':'Deletes sales, purchases, inventory, customers, staff, journal entries, and operational movements. Preserves the owner account, role and permissions, chart of accounts, cash accounts, tax settings, and audit log.'

  ,'يحذف بيانات التشغيل والحسابات المسجلة غير حساب المالك، وملفات الصور التي نُقلت من Telegram إلى Supabase Storage (catalog-images)، مع الاحتفاظ بحساب المالك وصلاحياته وإعدادات النظام الأساسية وسجل التدقيق.':'Deletes operational data, all registered accounts except the owner, and Telegram-synced image files in Supabase Storage (catalog-images). Preserves the owner account and permissions, core system settings, and audit log.'
  ,'تنبيه:':'Warning:'
  ,'ملف النسخة الاحتياطية JSON لا يتضمن الصور الثنائية؛ حذفها هنا نهائي من Supabase Storage، ولا يحذف الرسائل أو الصور الأصلية من محادثة Telegram.':'The JSON backup does not include binary images. Deleting them here permanently removes the Supabase Storage copies; it does not delete the original Telegram messages or images.'


};
function applyLanguage(root) {
  const en = state.language === 'en';
  document.documentElement.lang = en ? 'en' : 'ar';
  document.documentElement.dir = en ? 'ltr' : 'rtl';
  const button = $('#languageToggle');
  if (button) button.textContent = en ? 'العربية' : 'English';
  if (!en) return;
  const walker = document.createTreeWalker(root, NodeFilter.SHOW_TEXT);
  const nodes = [];
  while (walker.nextNode()) nodes.push(walker.currentNode);
  for (const node of nodes) {
    const raw = node.nodeValue || '';
    const trimmed = raw.trim();
    if (EN[trimmed]) node.nodeValue = raw.replace(trimmed, EN[trimmed]);
  }
  root.querySelectorAll('[placeholder],[aria-label],[title]').forEach((el) => {
    for (const attr of ['placeholder','aria-label','title']) {
      const value = el.getAttribute(attr);
      if (value && EN[value]) el.setAttribute(attr, EN[value]);
    }
  });
}
$('#languageToggle')?.addEventListener('click', () => {
  state.language = state.language === 'ar' ? 'en' : 'ar';
  localStorage.setItem('ekm_language', state.language);
  render();
});

init();
