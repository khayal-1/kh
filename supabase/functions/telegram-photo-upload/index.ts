import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.49.1';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS'
};
const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { ...corsHeaders, 'Content-Type': 'application/json' } });
const uuidPattern = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders });
  if (req.method !== 'POST') return json({ error: 'Method not allowed' }, 405);

  const authHeader = req.headers.get('Authorization');
  const supabaseUrl = Deno.env.get('SUPABASE_URL');
  const anonKey = Deno.env.get('SUPABASE_ANON_KEY');
  const botToken = Deno.env.get('TELEGRAM_BOT_TOKEN');
  const destination = Deno.env.get('TELEGRAM_CHAT_ID');
  if (!authHeader || !supabaseUrl || !anonKey) return json({ error: 'Authentication is required.' }, 401);
  if (!botToken || !destination) return json({ error: 'Telegram integration is not configured.' }, 503);

  const supabase = createClient(supabaseUrl, anonKey, {
    global: { headers: { Authorization: authHeader } },
    auth: { persistSession: false, autoRefreshToken: false }
  });
  const { data: { user }, error: authError } = await supabase.auth.getUser();
  if (authError || !user) return json({ error: 'Sign in is required.' }, 401);

  const { data: roles, error: roleError } = await supabase.from('user_roles').select('role').eq('user_id', user.id);
  if (roleError) return json({ error: 'Could not verify upload permission.' }, 403);
  if (!(roles || []).some(({ role }) => ['employee', 'manager', 'owner', 'admin'].includes(role))) {
    return json({ error: 'You do not have permission to upload catalog photos.' }, 403);
  }
  const isOwner = (roles || []).some(({ role }) => role === 'owner');
  const { data: canManage, error: permissionError } = await supabase.rpc('has_employee_permission', { p_permission: 'catalog_manage' });
  if (!isOwner && (permissionError || canManage !== true)) {
    return json({ error: 'You do not have permission to upload catalog photos.' }, 403);
  }

  let form: FormData;
  try { form = await req.formData(); } catch { return json({ error: 'Expected multipart form data.' }, 400); }
  const image = form.get('photo');
  const motorcycleId = String(form.get('motorcycle_id') || '').trim() || null;
  if (!(image instanceof File) || !['image/jpeg','image/png','image/webp'].includes(image.type)) {
    return json({ error: 'Choose a JPEG, PNG, or WebP image.' }, 400);
  }
  if (image.size < 1 || image.size > 10 * 1024 * 1024) return json({ error: 'Images must be 10 MB or smaller.' }, 413);
  if (motorcycleId && !uuidPattern.test(motorcycleId)) return json({ error: 'Invalid motorcycle id.' }, 400);

  const telegramForm = new FormData();
  telegramForm.set('chat_id', destination);
  telegramForm.set('photo', image, image.name || 'motorcycle-photo.jpg');
  telegramForm.set('caption', 'El Khayal Motors catalog image');
  const telegramResponse = await fetch(`https://api.telegram.org/bot${botToken}/sendPhoto`, { method: 'POST', body: telegramForm });
  const telegramResult = await telegramResponse.json().catch(() => null);
  if (!telegramResponse.ok || !telegramResult?.ok) return json({ error: 'Telegram did not accept the image.' }, 502);

  const photo = telegramResult.result.photo?.at(-1);
  if (!photo?.file_id) return json({ error: 'Telegram response did not include an image reference.' }, 502);

  const fileInfoResponse = await fetch(`https://api.telegram.org/bot${botToken}/getFile?file_id=${encodeURIComponent(photo.file_id)}`);
  const fileInfo = await fileInfoResponse.json().catch(() => null);
  if (!fileInfoResponse.ok || !fileInfo?.ok || !fileInfo.result?.file_path) {
    return json({ error: 'Telegram stored the image but did not return a downloadable file path.' }, 502);
  }

  const telegramFileResponse = await fetch(`https://api.telegram.org/file/bot${botToken}/${fileInfo.result.file_path}`);
  if (!telegramFileResponse.ok) return json({ error: 'Could not download the image from Telegram.' }, 502);
  const imageBytes = await telegramFileResponse.arrayBuffer();
  if (!imageBytes.byteLength || imageBytes.byteLength > 8 * 1024 * 1024) {
    return json({ error: 'The optimized image is empty or exceeds the 8 MB storage limit.' }, 413);
  }

  const storagePath = `motorcycles/${motorcycleId || 'unlinked'}/${crypto.randomUUID()}.jpg`;
  const storage = supabase.storage.from('catalog-images');
  const { error: storageError } = await storage.upload(storagePath, new Blob([imageBytes], { type: 'image/jpeg' }), {
    contentType: 'image/jpeg',
    cacheControl: '31536000',
    upsert: false
  });
  if (storageError) return json({ error: `Telegram saved the photo, but Supabase Storage upload failed: ${storageError.message}` }, 502);

  const publicUrl = storage.getPublicUrl(storagePath).data.publicUrl;
  const { data: saved, error: saveError } = await supabase.from('photo_assets').insert({
    motorcycle_id: motorcycleId,
    telegram_file_id: photo.file_id,
    telegram_file_unique_id: photo.file_unique_id || null,
    telegram_message_id: telegramResult.result.message_id,
    mime_type: 'image/jpeg',
    storage_path: storagePath,
    public_url: publicUrl,
    byte_size: imageBytes.byteLength,
    optimized: true,
    created_by: user.id
  }).select('id, motorcycle_id, public_url, storage_path, byte_size, created_at').single();

  if (saveError) {
    await storage.remove([storagePath]);
    return json({ error: `Image was stored but its photo record could not be saved: ${saveError.message}` }, 502);
  }

  if (motorcycleId) {
    const { data: bike, error: bikeReadError } = await supabase.from('motorcycles').select('image_urls').eq('id', motorcycleId).single();
    if (bikeReadError) {
      await supabase.from('photo_assets').delete().eq('id', saved.id);
      await storage.remove([storagePath]);
      return json({ error: 'The image is stored, but the motorcycle record could not be read.' }, 502);
    }
    const currentUrls = Array.isArray(bike.image_urls) ? bike.image_urls : [];
    const nextUrls = currentUrls.includes(publicUrl) ? currentUrls : [...currentUrls, publicUrl];
    const { error: linkError } = await supabase.from('motorcycles').update({ image_urls: nextUrls }).eq('id', motorcycleId);
    if (linkError) {
      await supabase.from('photo_assets').delete().eq('id', saved.id);
      await storage.remove([storagePath]);
      return json({ error: `The image upload was rolled back because the motorcycle could not be updated: ${linkError.message}` }, 502);
    }
  }

  return json({ photo_asset: saved, public_url: publicUrl, optimized: true, byte_size: imageBytes.byteLength });
});
