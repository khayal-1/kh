import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.49.1';

const productionOrigin = 'https://khayal-1.github.io';
const allowedOrigins = new Set([
  productionOrigin,
  'https://elkhayal-motors-website.vercel.app',
  'https://khayal01.vercel.app',
  'https://el-khayal.vercel.app',
  'http://localhost:5173',
  'http://127.0.0.1:5173',
]);

const responseHeaders = (origin: string | null) => ({
  ...(origin && allowedOrigins.has(origin)
    ? { 'Access-Control-Allow-Origin': origin, Vary: 'Origin' }
    : {}),
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
  'Content-Type': 'application/json',
  'Cache-Control': 'no-store',
});

const json = (body: unknown, status: number, origin: string | null) =>
  new Response(JSON.stringify(body), { status, headers: responseHeaders(origin) });

type Row = {
  id: number;
  title: string;
  category: 'جديد' | 'مستعمل' | 'غير مصنف';
  current: number | null;
  best: number | null;
  change: number | null;
  history: number[];
  urls: { url: string; store?: string }[];
};

const num = (v: unknown) =>
  v === undefined || v === null || Number.isNaN(Number(v)) ? null : Number(v);

function normalize(p: any): Row {
  const ins = p.insights ?? {};
  const stats = ins.stats ?? p.stats ?? {};
  const current = num(stats.current ?? p.current_price ?? p.price);
  const avg = num(stats.average);
  const tags: string[] = (p.tags ?? []).map((t: any) => (typeof t === 'string' ? t : t?.name));
  const history = (ins.history ?? p.history ?? [])
    .map((h: any) => num(typeof h === 'number' ? h : h?.price))
    .filter((n: number | null): n is number => n !== null);
  return {
    id: p.id,
    title: p.title ?? p.name ?? 'بدون اسم',
    category: tags.includes('جديد') ? 'جديد' : tags.includes('مستعمل') ? 'مستعمل' : 'غير مصنف',
    current,
    best: num(ins.bestPrice ?? stats.lowest ?? current),
    change: current != null && avg ? ((current - avg) / avg) * 100 : null,
    history,
    urls: (p.urls ?? []).map((u: any) => ({ url: u.url, store: u.store?.name })),
  };
}

let cache: { at: number; rows: Row[] } | null = null;
const TTL = 5 * 60 * 1000;

async function pb(path: string, init?: RequestInit) {
  const base = Deno.env.get('PRICEBUDDY_BASE_URL');
  const token = Deno.env.get('PRICEBUDDY_API_TOKEN');
  if (!base || !token) throw new Error('PriceBuddy is not configured on the server.');
  const res = await fetch(`${base.replace(/\/$/, '')}${path}`, {
    ...init,
    headers: {
      Authorization: `Bearer ${token}`,
      Accept: 'application/json',
      'Content-Type': 'application/json',
      ...(init?.headers || {}),
    },
  });
  if (!res.ok) throw new Error(`PriceBuddy ${res.status}`);
  return res.json();
}

async function getRows(force = false) {
  if (!force && cache && Date.now() - cache.at < TTL) {
    return { rows: cache.rows, at: cache.at, stale: false };
  }
  try {
    const data = await pb('/products?include=insights');
    const list = Array.isArray(data) ? data : data?.data ?? [];
    cache = { at: Date.now(), rows: list.map(normalize) };
    return { rows: cache.rows, at: cache.at, stale: false };
  } catch (e) {
    if (cache) return { rows: cache.rows, at: cache.at, stale: true };
    throw e;
  }
}

async function addUrl(productId: number, url: string) {
  cache = null;
  return pb(`/products/${productId}/urls`, {
    method: 'POST',
    body: JSON.stringify({ url }),
  });
}

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
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const { data: authData, error: authError } = await userClient.auth.getUser();
  const actor = authData?.user;
  if (authError || !actor) return json({ error: 'Sign in is required.' }, 401, origin);

  const admin = createClient(supabaseUrl, serviceRoleKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  const { data: roleRows, error: roleError } = await admin
    .from('user_roles')
    .select('role')
    .eq('user_id', actor.id);
  if (roleError) return json({ error: 'Could not verify access.' }, 503, origin);

  const roles = (roleRows || []).map((r) => r.role);
  const isAdminLike = roles.some((r) => ['manager', 'owner', 'admin'].includes(r));

  if (!isAdminLike) {
    const { data: perms, error: permError } = await admin
      .from('employee_permissions')
      .select('permission_key')
      .eq('user_id', actor.id)
      .in('permission_key', ['catalog_view', 'catalog_manage']);
    if (permError) return json({ error: 'Could not verify permissions.' }, 503, origin);
    if (!(perms || []).length) {
      return json({ error: 'Not authorized for catalog tools.' }, 403, origin);
    }
  }

  let body: Record<string, unknown>;
  try {
    body = await req.json();
  } catch {
    return json({ error: 'Invalid request body.' }, 400, origin);
  }

  const action = String(body.action || 'list');

  if (action === 'list') {
    try {
      const force = body.refresh === true || body.refresh === 1 || body.refresh === '1';
      const result = await getRows(Boolean(force));
      return json(result, 200, origin);
    } catch {
      return json({ error: 'تعذر تحديث الأسعار، حاول لاحقاً' }, 502, origin);
    }
  }

  if (action === 'add_url') {
    const productId = Number(body.product_id);
    const url = String(body.url || '').trim();
    if (!Number.isFinite(productId) || productId <= 0) {
      return json({ error: 'معرّف المنتج غير صالح' }, 400, origin);
    }
    try {
      new URL(url);
    } catch {
      return json({ error: 'رابط غير صالح' }, 400, origin);
    }
    try {
      await addUrl(productId, url);
      return json({ ok: true }, 200, origin);
    } catch {
      return json({ error: 'تعذرت إضافة الرابط' }, 502, origin);
    }
  }

  return json({ error: 'Unsupported action.' }, 400, origin);
});
