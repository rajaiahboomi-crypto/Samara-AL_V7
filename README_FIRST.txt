SAMARA CARE V9 CLEAN REPLACEMENT

This package replaces the older Samara-AL_V7 files completely.
It does NOT call any Supabase Edge Function.

ONE-TIME SETUP
1. In Supabase open SQL Editor and create a NEW query.
2. Open supabase/01_COMPLETE_SETUP.sql from this package.
3. Copy the complete SQL into the new query and click Run.
4. Confirm that the result says:
   SAMARA CARE V9 SETUP COMPLETED SUCCESSFULLY
5. In Supabase: Authentication > Sign In / Providers > Email:
   - Enable Email provider: ON
   - Confirm email: OFF

GITHUB REPLACEMENT
1. Delete the existing files in repository Samara-AL_V7.
2. Extract this ZIP.
3. Upload ALL files and folders inside the extracted folder to the repository root.
4. Commit the changes and wait 2-3 minutes.
5. Open:
   https://rajaiahboomi-crypto.github.io/Samara-AL_V7/?v=9
6. Press Ctrl+Shift+R once.

LOGIN
Login ID: admin
Password: the Admin password already created in Supabase.

ADDING EMPLOYEES
Admin > Employees > Add Employee.
No Edge Function is used. A temporary secondary browser client creates the Supabase Auth account without signing out the Admin. The Admin then assigns the employee profile through the protected database function.
