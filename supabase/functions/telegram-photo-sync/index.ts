import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.49.1';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS'
};
const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { ...corsHeaders, 'Content-Type': 'application/json' } });

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders });
  if (req.method !== 'POST') return json({ error: 'Method not allowed' }, 405);

  const authHeader = req.headers.get('Authorization');
  const supabaseUrl = Deno.env.get('SUPABASE_URL');
  const anonKey = Deno.env.get('SUPABASE_ANON_KEY');
  const botToken = Deno.env.get('TELEGRAM_BOT_TOKEN');
  if (!authHeader || !supabaseUrl || !anonKey) return json({ error: 'Authentication is required.' }, 401);
  if (!botToken) return json({ error: 'Telegram integration is not configured.' }, 503);

  const supabase = createClient(supabaseUrl, anonKey, {
    global: { headers: { Authorization: authHeader } },
    auth: { persistSession: false, autoRefreshToken: false }
  });
  const { data: { user }, error: authError } = await supabase.auth.getUser();
  if (authError || !user) return json({ error: 'Sign in is required.' }, 401);

  const { data: roles, error: roleError } = await supabase.from('user_roles').select('role').eq('user_id', user.id);
  if (roleError || !(roles || []).some(({ role }) => ['employee','manager','owner','admin'].includes(role))) {
    return json({ error: 'Management catalog permission is required.' }, 403);
  }
  const isOwner = (roles || []).some(({ role }) => role === 'owner');
  const { data: canManage, error: permissionError } = await supabase.rpc('has_employee_permission', { p_permission: 'catalog_manage' });
  if (!isOwner && (permissionError || canManage !== true)) {
    return json({ error: 'Management catalog permission is required.' }, 403);
  }

  // Retry failed photo syncs after a five-minute cooldown instead of permanently skipping them.
  const retryBefore = new Date(Date.now() - 5 * 60 * 1000).toISOString();
  const { data: pending, error: listError } = await supabase.from('photo_assets')
    .select('id,motorcycle_id,telegram_file_id')
    .is('storage_path', null)
    .or(`sync_error.is.null,sync_attempted_at.is.null,sync_attempted_at.lt.${retryBefore}`)
    .order('created_at', { ascending: true })
    .limit(8);
  if (listError) return json({ error: 'Could not load pending Telegram photo records.' }, 500);

  const storage = supabase.storage.from('catalog-images');
  const results: Array<{id:string; status:string; error?:string}> = [];
  for (const asset of pending || []) {
    let storagePath: string | null = null;
    try {
      const infoResponse = await fetch(`https://api.telegram.org/bot${botToken}/getFile?file_id=${encodeURIComponent(asset.telegram_file_id)}`);
      const info = await infoResponse.json().catch(() => null);
      if (!infoResponse.ok || !info?.ok || !info.result?.file_path) throw new Error('Telegram file path is unavailable');

      const fileResponse = await fetch(`https://api.telegram.org/file/bot${botToken}/${info.result.file_path}`);
      if (!fileResponse.ok) throw new Error('Telegram image download failed');
      const bytes = await fileResponse.arrayBuffer();
      if (!bytes.byteLength || bytes.byteLength > 8 * 1024 * 1024) throw new Error('Image exceeds the 8 MB storage limit');

      storagePath = `motorcycles/${asset.motorcycle_id || 'unlinked'}/${asset.id}.jpg`;
      const { error: uploadError } = await storage.upload(storagePath, new Blob([bytes], { type: 'image/jpeg' }), {
        contentType: 'image/jpeg',
        cacheControl: '31536000',
        upsert: false
      });
      if (uploadError) throw new Error(uploadError.message);

      const publicUrl = storage.getPublicUrl(storagePath).data.publicUrl;
      if (asset.motorcycle_id) {
        const { data: bike, error: readError } = await supabase.from('motorcycles').select('image_urls').eq('id', asset.motorcycle_id).single();
        if (readError) throw new Error('Motorcycle record could not be loaded');
        const urls = Array.isArray(bike.image_urls) ? bike.image_urls : [];
        const next = urls.includes(publicUrl) ? urls : [...urls, publicUrl];
        const { error: linkError } = await supabase.from('motorcycles').update({ image_urls: next }).eq('id', asset.motorcycle_id);
        if (linkError) throw new Error('Could not link image to motorcycle: ' + linkError.message);
      }

      const { error: updateError } = await supabase.from('photo_assets').update({
        storage_path: storagePath,
        public_url: publicUrl,
        byte_size: bytes.byteLength,
        mime_type: 'image/jpeg',
        optimized: true,
        sync_error: null,
        sync_attempted_at: new Date().toISOString()
      }).eq('id', asset.id);
      if (updateError) throw new Error('Could not update photo record: ' + updateError.message);
      results.push({ id: asset.id, status: 'synced' });
    } catch (error) {
      if (storagePath) await storage.remove([storagePath]);
      const message = error instanceof Error ? error.message : 'Unknown synchronization error';
      await supabase.from('photo_assets').update({
        sync_error: message.slice(0, 500),
        sync_attempted_at: new Date().toISOString()
      }).eq('id', asset.id);
      results.push({ id: asset.id, status: 'failed', error: message });
    }
  }

  const { count, error: countError } = await supabase.from('photo_assets')
    .select('id', { count: 'exact', head: true })
    .is('storage_path', null);
  return json({
    synced_count: results.filter((item) => item.status === 'synced').length,
    failed_count: results.filter((item) => item.status === 'failed').length,
    pending_remaining: countError ? null : count,
    results
  });
});
