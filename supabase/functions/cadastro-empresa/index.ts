import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
import { enviarEmail } from '../_shared/smtp.ts'
import { emailBoasVindas } from '../_shared/email-templates.ts'

const cors = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

const json = (data: unknown, status = 200) =>
  new Response(JSON.stringify(data), { status, headers: { ...cors, 'Content-Type': 'application/json' } })

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors })

  try {
    const { empresa_id } = await req.json()

    if (!empresa_id) return json({ erro: 'empresa_id obrigatório' }, 400)

    const ASAAS_API_KEY    = Deno.env.get('ASAAS_API_KEY')!
    const ASAAS_BASE_URL   = Deno.env.get('ASAAS_BASE_URL')!
    const SUPABASE_URL     = Deno.env.get('SUPABASE_URL')!
    const SERVICE_ROLE_KEY = Deno.env.get('SERVICE_ROLE_KEY')!

    const supabase = createClient(SUPABASE_URL, SERVICE_ROLE_KEY, {
      auth: { autoRefreshToken: false, persistSession: false },
    })

    // 1. Busca empresa + plano
    const { data: emp, error: empErr } = await supabase
      .from('EMPRESA')
      .select('*, PLANO:ID_PLANO(NOME_PLANO, PRECO_PLANO)')
      .eq('ID_EMP', empresa_id)
      .single()

    if (empErr || !emp) return json({ erro: 'Empresa não encontrada', detalhe: empErr }, 400)

    // 2. Cria cliente no Asaas
    const clienteBody: Record<string, unknown> = { name: emp.NOME_EMP, notificationDisabled: true }
    if (emp.CNPJ_EMP)  clienteBody.cpfCnpj = emp.CNPJ_EMP
    if (emp.EMAIL_EMP) clienteBody.email   = emp.EMAIL_EMP

    const clienteRes = await fetch(`${ASAAS_BASE_URL}/customers`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', 'access_token': ASAAS_API_KEY },
      body: JSON.stringify(clienteBody),
    })
    const cliente = await clienteRes.json()

    if (!cliente.id) {
      await supabase
        .from('EMPRESA')
        .update({ STATUS_EMP: 'erro_asaas', ASAAS_ULTIMO_ERRO: JSON.stringify(cliente) })
        .eq('ID_EMP', empresa_id)
      return json({ erro: 'Erro ao criar cliente no Asaas', detalhe: cliente }, 400)
    }

    // 3. Cria assinatura com 14 dias de trial
    const hoje = new Date()
    const trialExpira = new Date(hoje.getTime() + 14 * 24 * 60 * 60 * 1000)
    const nextDueDate = trialExpira.toISOString().split('T')[0]

    const assinaturaRes = await fetch(`${ASAAS_BASE_URL}/subscriptions`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', 'access_token': ASAAS_API_KEY },
      body: JSON.stringify({
        customer:        cliente.id,
        billingType:     'BOLETO',
        nextDueDate,
        value:           emp.PLANO?.PRECO_PLANO ?? 0,
        cycle:           'MONTHLY',
        description:     `Vitta Sistemas — ${emp.PLANO?.NOME_PLANO ?? 'Plano'}`,
        trialPeriodDays: 14,
      }),
    })
    const assinatura = await assinaturaRes.json()

    if (!assinatura.id) {
      await supabase
        .from('EMPRESA')
        .update({
          ASAAS_CUSTOMER_ID: cliente.id,
          STATUS_EMP:        'erro_asaas',
          ASAAS_ULTIMO_ERRO: JSON.stringify(assinatura),
        })
        .eq('ID_EMP', empresa_id)
      return json({ erro: 'Erro ao criar assinatura no Asaas', detalhe: assinatura }, 400)
    }

    // 4. Atualiza EMPRESA
    const { error: updateErr } = await supabase
      .from('EMPRESA')
      .update({
        ASAAS_CUSTOMER_ID:     cliente.id,
        ASAAS_SUBSCRIPTION_ID: assinatura.id ?? null,
        STATUS_EMP:            'trial',
        TRIAL_EXPIRA_EM:       trialExpira.toISOString(),
        ACESSO_ATE:            trialExpira.toISOString(),
      })
      .eq('ID_EMP', empresa_id)

    if (updateErr) return json({ erro: 'Erro ao atualizar empresa', detalhe: updateErr }, 500)

    // 5. Envia email de boas-vindas ao admin da empresa em background (não bloqueia a resposta do cadastro)
    const enviarBoasVindas = async () => {
      const { data: adminUsu } = await supabase
        .from('USUARIO')
        .select('NOME_USU, EMAIL_USU')
        .eq('ID_EMP', empresa_id)
        .eq('TIPO_USU', 'ADMIN_EMPRESA')
        .limit(1)
        .maybeSingle()

      if (adminUsu?.EMAIL_USU) {
        const { subject, html } = emailBoasVindas({
          nomeAdmin:   adminUsu.NOME_USU ?? '',
          nomeEmpresa: emp.NOME_EMP,
        })
        await enviarEmail({ to: adminUsu.EMAIL_USU, toName: adminUsu.NOME_USU, subject, html })
      }
    }

    const emailPromise = enviarBoasVindas().catch((emailErr) => {
      console.error('Falha ao enviar email de boas-vindas:', emailErr)
    })

    // deno-lint-ignore no-explicit-any
    const edgeRuntime = (globalThis as any).EdgeRuntime
    if (edgeRuntime?.waitUntil) {
      edgeRuntime.waitUntil(emailPromise)
    }

    return json({
      sucesso: true,
      asaas_customer_id:     cliente.id,
      asaas_subscription_id: assinatura.id ?? null,
      trial_expira:          trialExpira.toISOString(),
    })

  } catch (e: unknown) {
    return json({ erro: e instanceof Error ? e.message : String(e) }, 500)
  }
})
