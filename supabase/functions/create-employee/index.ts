import { serve } from "https://deno.land/std@0.168.0/http/server.ts"
import { createClient } from "https://esm.sh/@supabase/supabase-js@2"

serve(async (req) => {
  try {
    const { email, password, login_id, full_name, role, employee_id, mobile } = await req.json()

    if (!email || !password || !login_id || !full_name) {
      return new Response(JSON.stringify({ error: 'Missing required fields' }), { 
        status: 400,
        headers: { 'Content-Type': 'application/json' }
      })
    }

    // Create Supabase client with service role key
    const supabaseUrl = Deno.env.get('SUPABASE_URL')!
    const supabaseServiceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
    const supabase = createClient(supabaseUrl, supabaseServiceKey)

    // Create user with email confirmation disabled
    const { data: userData, error: userError } = await supabase.auth.admin.createUser({
      email,
      password,
      email_confirm: true,
      user_metadata: {
        login_id,
        full_name
      }
    })

    if (userError) throw userError
    if (!userData.user) throw new Error('Failed to create user')

    // Create employee profile
    const { error: profileError } = await supabase
      .from('profiles')
      .insert({
        id: userData.user.id,
        login_id,
        auth_email: email,
        full_name,
        role,
        employee_id,
        mobile,
        active: true
      })

    if (profileError) throw profileError

    return new Response(JSON.stringify({ 
      success: true, 
      userId: userData.user.id 
    }), {
      headers: { 'Content-Type': 'application/json' }
    })

  } catch (error) {
    return new Response(JSON.stringify({ error: error.message }), { 
      status: 500,
      headers: { 'Content-Type': 'application/json' }
    })
  }
})
