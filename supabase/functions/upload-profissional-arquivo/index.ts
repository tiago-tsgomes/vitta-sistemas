import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const cors = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

const json = (data: unknown, status = 200) =>
  new Response(JSON.stringify(data), { status, headers: { ...cors, 'Content-Type': 'application/json' } })

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors })

  try {
    const SUPABASE_URL     = Deno.env.get('SUPABASE_URL')!
    const SERVICE_ROLE_KEY = Deno.env.get('SERVICE_ROLE_KEY')!

    const supabase = createClient(SUPABASE_URL, SERVICE_ROLE_KEY, {
      auth: { autoRefreshToken: false, persistSession: false },
    })

    const authHeader = req.headers.get('Authorization')
    if (!authHeader) return json({ erro: 'Autenticação necessária' }, 401)

    const token = authHeader.replace('Bearer ', '')
    const { data: userData, error: authErr } = await supabase.auth.getUser(token)
    if (authErr || !userData.user) return json({ erro: 'Token inválido' }, 401)
    const user = userData.user

    const body = await req.json() as {
      profId?: string; tipo?: 'foto' | 'assinatura'; base64?: string; contentType?: string; ext?: string;
    }
    const { profId, tipo, base64, contentType, ext } = body
    if (!profId || !tipo || !base64 || !contentType) return json({ erro: 'Parâmetros obrigatórios ausentes' }, 400)
    if (tipo !== 'foto' && tipo !== 'assinatura') return json({ erro: 'Tipo inválido' }, 400)

    const { data: prof, error: profErr } = await supabase
      .from('PROFISSIONAL')
      .select('ID_EMP')
      .eq('ID_PROF', profId)
      .single()

    if (profErr || !prof) return json({ erro: 'Profissional não encontrado' }, 404)

    const { data: usuarios } = await supabase
      .from('USUARIO')
      .select('TIPO_USU, ID_EMP, ATIVO_USU')
      .eq('AUTH_ID', user.id)

    const usuario = usuarios?.find(u => u.ATIVO_USU !== false && (u.ID_EMP === prof.ID_EMP || u.TIPO_USU === 'ADMIN_GLOBAL'))

    if (!usuario) return json({ erro: 'Usuário não encontrado' }, 403)
    if (!['ADMIN_GLOBAL', 'ADMIN_EMPRESA', 'SECRETARIA'].includes(usuario.TIPO_USU)) {
      return json({ erro: 'Sem permissão para esta operação' }, 403)
    }
    if (usuario.TIPO_USU !== 'ADMIN_GLOBAL' && prof.ID_EMP !== usuario.ID_EMP) {
      return json({ erro: 'Sem permissão para este profissional' }, 403)
    }

    const path = tipo === 'foto' ? `${profId}/foto` : `${profId}/assinatura.${(ext || 'png').toLowerCase()}`
    const bytes = Uint8Array.from(atob(base64), c => c.charCodeAt(0))

    const { error: upErr } = await supabase.storage
      .from('profissionais-fotos')
      .upload(path, bytes, { upsert: true, contentType })

    if (upErr) return json({ erro: upErr.message }, 500)

    const { data: pub } = supabase.storage.from('profissionais-fotos').getPublicUrl(path)
    // cache-busting: o path é fixo por profissional (upsert sobrescreve o mesmo
    // arquivo), então sem isso a URL pública não muda e o navegador/CDN continua
    // servindo a imagem antiga em cache após trocar a foto.
    return json({ url: `${pub.publicUrl}?v=${Date.now()}` })
  } catch (e: unknown) {
    return json({ erro: e instanceof Error ? e.message : String(e) }, 500)
  }
})
