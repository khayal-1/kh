import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.49.1';

const allowedPermissions = new Set([
  'catalog_view',
  'catalog_manage',
  'requests_view',
  'requests_manage',
  'customer_data_view',
  'sales_manage',
  'expenses_manage',
  'accounting_view',
  'finance_manage'
]);
const productionOrigin = 'https://khayal-1.github.io';
const allowedOrigins = new Set([
  productionOrigin,
  'https://elkhayal-motors-website.vercel.app',
  'https://khayal01.vercel.app',
  'https://el-khayal.vercel.app',
  'http://localhost:5173'
]);
const responseHeaders = (origin: string | null) => ({
  ...(origin && allowedOrigins.has(origin) ? { 'Access-Control-Allow-Origin': origin, Vary: 'Origin' } : {}),
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
  'Content-Type': 'application/json',
  'Cache-Control': 'no-store'
});
const json = (body: unknown, status: number, origin: string | null) =>
  new Response(JSON.stringify(body), { status, headers: responseHeaders(origin) });

Deno.serve(async (req) => {
  const origin = req.headers.get('Origin');
  if (req.method === 'OPTIONS') return new Response('ok', { headers: responseHeaders(origin) });
  if (req.method !== 'POST') return json({ error: 'Method not allowed.' }, 405, origin);
  if (origin && !allowedOrigins.has(origin)) return json({ error: 'Origin not allowed.' }, 403, origin);

  const supabaseUrl = Deno.env.get('SUPABASE_URL');
  const anonKey = Deno.env.get('SUPABASE_ANON_KEY');
  const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
  const authorization = req.headers.get('Authorization');
  if (!supabaseUrl || !anonKey || !serviceRoleKey || !authorization) {
    return json({ error: 'Service configuration or sign-in is missing.' }, 401, origin);
  }

  const userClient = createClient(supabaseUrl, anonKey, {
    global: { headers: { Authorization: authorization } },
    auth: { persistSession: false, autoRefreshToken: false }
  });
  const { data: authData, error: authError } = await userClient.auth.getUser();
  const actor = authData?.user;
  if (authError || !actor) return json({ error: 'Sign in is required.' }, 401, origin);

  const admin = createClient(supabaseUrl, serviceRoleKey, {
    auth: { persistSession: false, autoRefreshToken: false }
  });
  const { data: roleRows, error: roleError } = await admin
    .from('user_roles')
    .select('role')
    .eq('user_id', actor.id);
  if (roleError) return json({ error: 'Could not verify manager access.' }, 503, origin);
  if (!(roleRows || []).some(({ role }) => ['manager', 'owner', 'admin'].includes(role))) {
    return json({ error: 'Only the manager can create staff accounts.' }, 403, origin);
  }

  let body: Record<string, unknown>;
  try { body = await req.json(); } catch { return json({ error: 'Invalid request body.' }, 400, origin); }
  if (body.action === 'list') {
    const { data: roles, error: listError } = await admin.from('user_roles').select('user_id,role').in('role', ['employee', 'manager']);
    if (listError) return json({ error: 'Could not load staff accounts.' }, 503, origin);
    const roleById = new Map<string, string>();
    for (const row of roles || []) roleById.set(row.user_id, row.role);
    const ids = [...roleById.keys()];
    if (!ids.length) return json({ staff: [] }, 200, origin);
    const [{ data: profiles, error: profileError }, { data: permissions, error: permissionsError }] = await Promise.all([
      admin.from('profiles').select('id,full_name,phone').in('id', ids),
      admin.from('employee_permissions').select('user_id,permission_key').in('user_id', ids)
    ]);
    if (profileError || permissionsError) return json({ error: 'Could not load the staff directory.' }, 503, origin);
    const profileById = new Map((profiles || []).map((profile) => [profile.id, profile]));
    const permissionsById = new Map<string, string[]>();
    for (const row of permissions || []) {
      if (!permissionsById.has(row.user_id)) permissionsById.set(row.user_id, []);
      permissionsById.get(row.user_id)!.push(row.permission_key);
    }
    const users = await Promise.all(ids.map(async (id) => {
      const { data, error } = await admin.auth.admin.getUserById(id);
      if (error || !data.user) return null;
      const profile = profileById.get(id);
      return {
        id, email: data.user.email || '', name: profile?.full_name || '',
        phone: profile?.phone || '', permissions: permissionsById.get(id) || [],
        account_role: roleById.get(id) || 'employee'
      };
    }));
    return json({ staff: users.filter(Boolean) }, 200, origin);
  }
  if (body.action === 'update') {
    const userId = String(body.user_id || '');
    const fullName = String(body.full_name || '').trim();
    const phone = String(body.phone || '').trim();
    const rawPermissions = body.permissions;
    const accountRole = String(body.account_role || 'employee');
    if (!/^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(userId)) return json({ error: 'Invalid employee account.' }, 400, origin);
    if (!fullName || fullName.length > 120) return json({ error: 'Name must be 1–120 characters.' }, 400, origin);
    if (phone.length > 32) return json({ error: 'Phone number must be 32 characters or fewer.' }, 400, origin);
    if (!['employee', 'manager'].includes(accountRole)) return json({ error: 'Unsupported account role.' }, 400, origin);
    if (!Array.isArray(rawPermissions) || rawPermissions.length > allowedPermissions.size ||
        rawPermissions.some((permission) => typeof permission !== 'string' || !allowedPermissions.has(permission)) ||
        new Set(rawPermissions).size !== rawPermissions.length) return json({ error: 'Choose only available employee permissions.' }, 400, origin);
    const permissions = rawPermissions as string[];
    if (permissions.includes('customer_data_view') && !permissions.some((permission) => ['requests_view', 'requests_manage'].includes(permission))) {
      return json({ error: 'Customer names and phones can only be granted with request access.' }, 400, origin);
    }
    const { data, error } = await admin.rpc('manage_employee_account', {
      p_user_id: userId, p_actor_id: actor.id, p_full_name: fullName,
      p_phone: phone || null, p_permissions: permissions, p_role: accountRole
    });
    if (error || !data?.success) return json({ error: error?.message || 'Could not update the employee account.' }, 400, origin);
    return json({ success: true, account_role: data.role }, 200, origin);
  }
  if (body.action !== 'create') return json({ error: 'Unsupported action.' }, 400, origin);

  const email = String(body.email || '').trim().toLowerCase();
  const fullName = String(body.full_name || '').trim();
  const phone = String(body.phone || '').trim();
  const password = String(body.password || '');
  const rawPermissions = body.permissions;
  if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email) || email.length > 254) {
    return json({ error: 'Enter a valid staff email address.' }, 400, origin);
  }
  if (!fullName || fullName.length > 120) return json({ error: 'Name must be 1–120 characters.' }, 400, origin);
  if (password.length < 8 || password.length > 128) return json({ error: 'Password must be 8–128 characters.' }, 400, origin);
  if (phone.length > 32) return json({ error: 'Phone number must be 32 characters or fewer.' }, 400, origin);
  if (!Array.isArray(rawPermissions) || rawPermissions.length > allowedPermissions.size ||
      rawPermissions.some((permission) => typeof permission !== 'string' || !allowedPermissions.has(permission)) ||
      new Set(rawPermissions).size !== rawPermissions.length) {
    return json({ error: 'Choose only available employee permissions.' }, 400, origin);
  }
  const permissions = rawPermissions as string[];
  if (permissions.includes('customer_data_view') && !permissions.some((permission) => ['requests_view', 'requests_manage'].includes(permission))) {
    return json({ error: 'Customer names and phones can only be granted with request access.' }, 400, origin);
  }
  const { data: created, error: createError } = await admin.auth.admin.createUser({
    email,
    password,
    email_confirm: true,
    user_metadata: { full_name: fullName, phone: phone || null },
    app_metadata: { account_type: 'employee', staff_assigned_by: actor.id }
  });
  if (createError || !created.user) {
    const conflict = createError?.code === 'email_exists' || createError?.message?.toLowerCase().includes('already') === true;
    return json({ error: conflict ? 'An account already uses this email.' : 'Could not create the staff account.' }, conflict ? 409 : 400, origin);
  }

  const rollbackCreatedUser = async () => {
    const { error } = await admin.auth.admin.deleteUser(created.user!.id);
    return !error;
  };
  const { error: removeCustomerRoleError } = await admin.from('user_roles').delete()
    .eq('user_id', created.user.id).eq('role', 'customer');
  if (removeCustomerRoleError) {
    const rolledBack = await rollbackCreatedUser();
    return json({ error: rolledBack ? 'Could not assign employee role; the new account was removed.' : 'Account creation needs administrator repair.' }, 500, origin);
  }
  const { error: employeeRoleError } = await admin.from('user_roles').upsert(
    { user_id: created.user.id, role: 'employee', assigned_by: actor.id }, { onConflict: 'user_id,role' }
  );
  if (employeeRoleError) {
    const rolledBack = await rollbackCreatedUser();
    return json({ error: rolledBack ? 'Could not assign employee role; the new account was removed.' : 'Account creation needs administrator repair.' }, 500, origin);
  }
  const { error: clientDeleteError } = await admin.from('clients').delete().eq('user_id', created.user.id);
  if (clientDeleteError) {
    const rolledBack = await rollbackCreatedUser();
    return json({ error: rolledBack ? 'Could not remove the customer-only profile; the new account was removed.' : 'Account creation needs administrator repair.' }, 500, origin);
  }

  if (permissions.length) {
    const { error: permissionError } = await admin.from('employee_permissions').insert(
      permissions.map((permission_key) => ({ user_id: created.user!.id, permission_key, granted_by: actor.id }))
    );
    if (permissionError) {
      const rolledBack = await rollbackCreatedUser();
      return json({
        error: rolledBack
          ? 'Could not save permissions; the new account was removed.'
          : 'Account creation needs administrator repair.'
      }, 500, origin);
    }
  }

  return json({
    staff: { id: created.user.id, email: created.user.email, full_name: fullName, phone: phone || null, permissions },
    email_confirmation_required: false,
  }, 201, origin);
});
