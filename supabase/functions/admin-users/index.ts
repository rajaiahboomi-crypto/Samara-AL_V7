import { createClient } from 'npm:@supabase/supabase-js@2'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

const json = (body: unknown, status = 200) => new Response(JSON.stringify(body), {
  status,
  headers: { ...corsHeaders, 'Content-Type': 'application/json' },
})

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders })
  try {
    const authHeader = req.headers.get('Authorization')
    if (!authHeader) return json({ error: 'Missing authorization token' }, 401)

    const url = Deno.env.get('SUPABASE_URL')!
    const anonKey = Deno.env.get('SUPABASE_ANON_KEY')!
    const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
    const callerClient = createClient(url, anonKey, { global: { headers: { Authorization: authHeader } } })
    const adminClient = createClient(url, serviceKey, { auth: { autoRefreshToken: false, persistSession: false } })

    const { data: { user }, error: userError } = await callerClient.auth.getUser()
    if (userError || !user) return json({ error: 'Invalid session' }, 401)

    const { data: caller } = await adminClient.from('profiles').select('role,active').eq('id', user.id).single()
    if (!caller || caller.role !== 'Admin' || caller.active !== true) return json({ error: 'Administrator access required' }, 403)

    const body = await req.json()
    const action = body.action
    const emailFor = (loginId: string) => `${loginId.trim().toLowerCase()}@users.samaracare.local`

    if (action === 'list') {
      const { data, error } = await adminClient.from('profiles').select('*').order('created_at')
      if (error) throw error
      return json({ users: data })
    }

    if (action === 'create') {
      const loginId = String(body.loginId || '').trim().toLowerCase()
      if (!loginId || !body.fullName || !body.password) return json({ error: 'Login ID, name and password are required' }, 400)
      const { data, error } = await adminClient.auth.admin.createUser({
        email: emailFor(loginId), password: body.password, email_confirm: true,
        user_metadata: { login_id: loginId, full_name: body.fullName },
      })
      if (error) throw error
      const { error: profileError } = await adminClient.from('profiles').insert({
        id: data.user.id, login_id: loginId, full_name: body.fullName,
        employee_id: body.employeeId || null, mobile: body.mobile || null,
        role: body.role || 'Caregiver', active: true,
      })
      if (profileError) { await adminClient.auth.admin.deleteUser(data.user.id); throw profileError }
      return json({ ok: true })
    }

    const loginId = String(body.originalLoginId || body.loginId || '').trim().toLowerCase()
    const { data: profile, error: findError } = await adminClient.from('profiles').select('*').eq('login_id', loginId).single()
    if (findError || !profile) return json({ error: 'Employee not found' }, 404)

    if (action === 'update') {
      const newLogin = String(body.loginId || loginId).trim().toLowerCase()
      const authUpdate: Record<string, unknown> = { email: emailFor(newLogin), email_confirm: true }
      if (body.password) authUpdate.password = body.password
      const { error: authError } = await adminClient.auth.admin.updateUserById(profile.id, authUpdate)
      if (authError) throw authError
      const { error } = await adminClient.from('profiles').update({
        login_id: newLogin, full_name: body.fullName, employee_id: body.employeeId || null,
        mobile: body.mobile || null, role: body.role, updated_at: new Date().toISOString(),
      }).eq('id', profile.id)
      if (error) throw error
      return json({ ok: true })
    }

    if (action === 'toggle') {
      if (profile.id === user.id && body.active === false) return json({ error: 'You cannot disable your own administrator account' }, 400)
      const { error } = await adminClient.from('profiles').update({ active: Boolean(body.active), updated_at: new Date().toISOString() }).eq('id', profile.id)
      if (error) throw error
      return json({ ok: true })
    }

    if (action === 'reset_password') {
      if (!body.password || String(body.password).length < 6) return json({ error: 'Password must contain at least 6 characters' }, 400)
      const { error } = await adminClient.auth.admin.updateUserById(profile.id, { password: body.password })
      if (error) throw error
      return json({ ok: true })
    }

    return json({ error: 'Unsupported action' }, 400)
  } catch (error) {
    return json({ error: error instanceof Error ? error.message : String(error) }, 400)
  }
})
