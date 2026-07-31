/* Samara Care V8 – employee account creation without Edge Functions */
(() => {
  'use strict';

  function cleanLogin(value) {
    return String(value || '').trim().toLowerCase().replace(/[^a-z0-9._-]/g, '');
  }

  function employeeEmail(loginId) {
    return `${cleanLogin(loginId)}@users.samaracare.local`;
  }

  window.loadUsers = async function loadUsersNoEdge() {
    if (!window.me || window.me.role !== 'Admin') return;
    const { data, error } = await window.SAMARA_DB
      .from('profiles')
      .select('id,login_id,full_name,role,employee_id,mobile,active,created_at')
      .order('created_at', { ascending: true });

    if (error) {
      alert(error.message);
      return;
    }

    window.USERS = {};
    (data || []).forEach((p) => {
      window.USERS[p.id] = {
        id: p.login_id,
        name: p.full_name,
        role: p.role,
        employeeId: p.employee_id,
        mobile: p.mobile,
        active: p.active
      };
    });
  };

  window.createUser = async function createUserNoEdge() {
    const fullName = window.val('u_n').trim();
    const employeeId = window.val('u_e').trim();
    const mobile = window.val('u_m').trim();
    const role = window.val('u_r');
    const loginId = cleanLogin(window.val('u_l'));
    const password = window.val('u_p');

    if (!fullName || !loginId || !password) {
      alert('Name, Login ID and Temporary Password are required.');
      return;
    }
    if (password.length < 6) {
      alert('Temporary Password must contain at least 6 characters.');
      return;
    }

    const button = document.querySelector('.modal-card .primary');
    if (button) {
      button.disabled = true;
      button.textContent = 'Creating…';
    }

    try {
      // A separate non-persistent client creates the new Auth user without
      // replacing the currently logged-in administrator session.
      const creator = window.supabase.createClient(
        window.SAMARA_CONFIG.supabaseUrl,
        window.SAMARA_CONFIG.supabaseAnonKey,
        {
          auth: {
            persistSession: false,
            autoRefreshToken: false,
            detectSessionInUrl: false,
            storageKey: `samara-employee-create-${Date.now()}`
          }
        }
      );

      const { data: signUpData, error: signUpError } = await creator.auth.signUp({
        email: employeeEmail(loginId),
        password,
        options: {
          data: {
            login_id: loginId,
            full_name: fullName,
            employee_id: employeeId,
            mobile,
            requested_role: role
          }
        }
      });

      if (signUpError) throw signUpError;
      if (!signUpData?.user?.id) throw new Error('Supabase did not return the new employee account.');

      const { data: activated, error: activateError } = await window.SAMARA_DB.rpc(
        'admin_activate_employee',
        {
          p_user_id: signUpData.user.id,
          p_login_id: loginId,
          p_full_name: fullName,
          p_employee_id: employeeId || null,
          p_mobile: mobile || null,
          p_role: role
        }
      );

      if (activateError) throw activateError;
      if (!activated) throw new Error('The employee profile could not be activated.');

      window.closeModal();
      await window.loadUsers();
      window.render();
      alert('Employee account created. The employee can now sign in from any device.');
    } catch (error) {
      const message = error?.message || String(error);
      if (/email.*confirm|confirmation/i.test(message)) {
        alert('Account created, but Supabase email confirmation is enabled. Turn off Confirm Email in Authentication → Sign In / Providers → Email.');
      } else {
        alert(message);
      }
    } finally {
      if (button) {
        button.disabled = false;
        button.textContent = 'Create';
      }
    }
  };

  console.info('Samara Care V8 employee fix loaded. Edge Function is not required.');
})();
