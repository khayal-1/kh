#!/usr/bin/env python3
"""Apply operations-board sidebar + account chip layout to app.js/style.css."""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
APP = ROOT / 'app.js'
CSS = ROOT / 'style.css'

OLD_SIDEBAR = '''  if (u.role === 'staff') {
    const items = [{ section: 'الموظف' }];
    if (hasAnyPermission('catalog_view', 'catalog_manage')) items.push({ route: 'inventory', label: 'المخزن والأسعار', icon: 'fa-boxes-stacked' });
    if (hasPermission('catalog_manage')) items.push({ route: 'manage-bikes', label: 'إدارة الدراجات', icon: 'fa-motorcycle' });
    if (hasRequestAccess()) items.push({ route: 'staff-orders', label: 'طلبات العملاء', icon: 'fa-clipboard-list', badge: pendingTotal || null });
    if (hasPermission('sales_manage')) items.push({ route: 'vin-scanner', label: 'ماسح الشاسيه والموتور', icon: 'fa-barcode' });
    if (hasPermission('expenses_manage') || hasPermission('accounting_view')) items.push({ route: 'expenses', label: 'المصروفات والحسابات', icon: 'fa-money-bill-transfer' });
    if (hasPermission('finance_manage') || hasPermission('accounting_view')) items.push({ route: 'finance-tools', label: 'الأدوات المالية المتقدمة', icon: 'fa-building-columns' });
    if (hasPermission('finance_manage')) items.push({ route: 'hr', label: 'الموارد البشرية والرواتب', icon: 'fa-users-gear' });
    if (hasPermission('catalog_manage') || hasPermission('finance_manage')) items.push({ route: 'inventory-tools', label: 'الجرد والضمان والصيانة', icon: 'fa-warehouse' });
    if (hasPermission('customer_data_view') || hasPermission('customer_data_manage')) items.push({ route: 'customer-relations', label: 'إدارة العملاء والعلاقات', icon: 'fa-address-book' });
    if (hasPermission('sales_manage')) items.push({ route: 'sales-tools', label: 'عروض الأسعار والتقسيط', icon: 'fa-file-invoice-dollar' });
    items.push({ section: 'المتجر' }, { route: 'home', label: 'عرض المتجر', icon: 'fa-store' });
    return items;
  }

  /* Admin */
  const items = [
    { section: 'الإدارة' },
    { route: 'dashboard', label: 'لوحة الإحصائيات', icon: 'fa-chart-line' },
    { section: 'البيع' },
    { route: 'pos', label: 'نقطة البيع POS', icon: 'fa-cash-register' },
    { route: 'vin-scanner', label: 'ماسح الشاسيه والموتور', icon: 'fa-barcode' },
    { route: 'suppliers', label: 'الموردون والتوريد', icon: 'fa-truck-ramp-box' },
    { route: 'inventory', label: 'المخزن والأسعار', icon: 'fa-boxes-stacked' },
    { section: 'الإدارة' },
    { route: 'manage-bikes', label: 'إدارة الدراجات', icon: 'fa-motorcycle' },
    { route: 'staff', label: 'الموظفين والأداء', icon: 'fa-users-gear' },
    { route: 'expenses', label: 'المصروفات والحسابات', icon: 'fa-money-bill-transfer' },
    { route: 'finance-tools', label: 'الأدوات المالية المتقدمة', icon: 'fa-building-columns' },
    { route: 'hr', label: 'الموارد البشرية والرواتب', icon: 'fa-users-gear' },
    { route: 'inventory-tools', label: 'الجرد والضمان والصيانة', icon: 'fa-warehouse' },
    { route: 'customer-relations', label: 'إدارة العملاء والعلاقات', icon: 'fa-address-book' },
    { route: 'sales-tools', label: 'عروض الأسعار والتقسيط', icon: 'fa-file-invoice-dollar' },
    { route: 'staff-orders', label: 'طلبات العملاء', icon: 'fa-clipboard-list', badge: pendingTotal || null },
    { section: 'المتجر' },
    { route: 'home', label: 'عرض المتجر', icon: 'fa-store' }
  ];
  if (u.systemRole === 'owner') items.push({ section: 'صلاحيات المالك' }, { route: 'owner-data', label: 'النسخ الاحتياطي وإعادة الضبط', icon: 'fa-shield-halved' });
  return items;
}'''

NEW_SIDEBAR = '''  /* Staff / Manager / Admin — menu matches operations board layout */
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
}'''

OLD_ACCOUNT = '''function renderAccountArea() {
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
  const roleLabel = u.systemRole === 'manager' ? 'مدير مساعد' : u.role === 'admin' ? 'مدير' : u.role === 'staff' ? 'موظف' : 'عميل';
  area.innerHTML = `
    <div class="user-chip">
      <div class="avatar">${esc((u.name || '?').charAt(0))}</div>
      <span class="name">${esc((u.name || '').split(' ')[0])}</span>
      <span class="role-badge">${roleLabel}</span>
    </div>
    <button class="btn btn-ghost-light btn-sm" data-nav="account">
      <i class="fa-solid fa-user"></i> حسابي
    </button>
    <button class="btn btn-primary btn-sm" id="logoutBtn" title="تسجيل الخروج">
      <i class="fa-solid fa-right-from-bracket"></i>
    </button>`;
}'''

NEW_ACCOUNT = '''function renderAccountArea() {
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
}'''

OLD_CSS = '''.user-chip {
  display: inline-flex; align-items: center; gap: 8px;
  background: rgba(255, 255, 255, 0.08);
  padding: 5px 12px 5px 6px;
  border-radius: var(--radius-pill);
  font-size: 0.8rem;
  max-width: 260px;
}
.user-chip .avatar {
  width: 28px; height: 28px;
  background: var(--red);
  border-radius: 50%;
  display: flex; align-items: center; justify-content: center;
  font-weight: 800; font-size: 0.8rem; color: var(--white);
  flex-shrink: 0;
}
.user-chip .name {
  font-weight: 700; color: var(--white);
  overflow: hidden; text-overflow: ellipsis; white-space: nowrap;
}
.user-chip .role-badge {
  font-size: 0.6rem;
  background: var(--red);
  color: var(--white);
  padding: 2px 8px;
  border-radius: var(--radius-pill);
  font-weight: 700;
  flex-shrink: 0;
}'''

NEW_CSS = '''.user-chip {
  display: inline-flex; align-items: center; gap: 8px;
  background: rgba(255, 255, 255, 0.08);
  padding: 5px 12px 5px 6px;
  border-radius: var(--radius-pill);
  font-size: 0.8rem;
  max-width: 280px;
  border: 1px solid rgba(255,255,255,0.08);
  color: inherit;
  cursor: pointer;
}
button.user-chip { font: inherit; }
.user-chip .avatar {
  width: 32px; height: 32px;
  background: var(--red);
  border-radius: 50%;
  display: flex; align-items: center; justify-content: center;
  font-weight: 800; font-size: 0.85rem; color: var(--white);
  flex-shrink: 0;
}
.user-chip-meta {
  display: flex; flex-direction: column; gap: 2px; min-width: 0;
  align-items: flex-start;
}
.user-chip .name {
  font-weight: 700; color: var(--white);
  overflow: hidden; text-overflow: ellipsis; white-space: nowrap;
  max-width: 160px;
  line-height: 1.2;
}
.user-chip .role-badge {
  font-size: 0.6rem;
  background: var(--red);
  color: var(--white);
  padding: 1px 8px;
  border-radius: var(--radius-pill);
  font-weight: 700;
  flex-shrink: 0;
}'''

def main():
    app = APP.read_text(encoding='utf-8')
    if 'menu matches operations board layout' in app:
        print('app.js already patched')
    else:
        if OLD_SIDEBAR not in app:
            raise SystemExit('OLD_SIDEBAR block not found in app.js')
        if OLD_ACCOUNT not in app:
            raise SystemExit('OLD_ACCOUNT block not found in app.js')
        app = app.replace(OLD_SIDEBAR, NEW_SIDEBAR, 1).replace(OLD_ACCOUNT, NEW_ACCOUNT, 1)
        for a, b in [
            ('المخزن والأسعار', 'الأسعار'),
            ('إدارة الدراجات', 'المعرض / الكتالوج'),
            ('نقطة البيع POS', 'نظام البيع داخل المعرض'),
            ('المصروفات والحسابات', 'النظام المالي'),
            ('الأدوات المالية المتقدمة', 'النظام المحاسبي'),
            ('الموارد البشرية والرواتب', 'الموارد البشرية والمرتبات'),
            ('الموظفين والأداء', 'التعيين وحسابات الموظفين'),
        ]:
            app = app.replace(a, b)
        APP.write_text(app, encoding='utf-8')
        print('app.js patched')

    css = CSS.read_text(encoding='utf-8')
    if 'user-chip-meta' in css:
        print('style.css already patched')
    else:
        if OLD_CSS not in css:
            raise SystemExit('OLD_CSS block not found in style.css')
        CSS.write_text(css.replace(OLD_CSS, NEW_CSS, 1), encoding='utf-8')
        print('style.css patched')

if __name__ == '__main__':
    main()
