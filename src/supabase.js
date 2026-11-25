import { createClient } from '@supabase/supabase-js';

const url = import.meta.env.NEXT_PUBLIC_SUPABASE_URL;
const key = import.meta.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY;

export const supabaseConfigured = Boolean(url && key);
export const supabase = supabaseConfigured
  ? createClient(url, key, {
      auth: {
        persistSession: true,
        autoRefreshToken: true,
        detectSessionInUrl: true,
        storageKey: 'ekm-auth-session'
      },
      global: { headers: { 'X-Client-Info': 'elkhayal-motors-web' } }
    })
  : null;

export async function getCurrentProfile(userId) {
  const [{ data: profile, error: profileError }, { data: roles, error: rolesError }, { data: permissions, error: permissionError }] = await Promise.all([
    supabase.from('profiles').select('id, full_name, phone, preferred_language').eq('id', userId).maybeSingle(),
    supabase.from('user_roles').select('role').eq('user_id', userId),
    supabase.from('employee_permissions').select('permission_key').eq('user_id', userId)
  ]);
  if (profileError) throw profileError;
  if (rolesError) throw rolesError;
  if (permissionError) throw permissionError;
  const roleNames = (roles || []).map((entry) => entry.role);
  const systemRole = roleNames.includes('owner') ? 'owner'
    : roleNames.includes('admin') ? 'admin'
    : roleNames.includes('manager') ? 'manager'
    : roleNames.includes('employee') ? 'employee' : 'customer';
  const role = ['owner', 'admin', 'manager'].includes(systemRole)
    ? 'admin'
    : systemRole === 'employee' ? 'staff' : 'customer';
  return profile ? {
    id: profile.id,
    name: profile.full_name || '',
    phone: profile.phone || '',
    preferredLanguage: profile.preferred_language || 'ar',
    role,
    systemRole,
    permissions: (permissions || []).map((entry) => entry.permission_key)
  } : null;
}
