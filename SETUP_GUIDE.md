# Setup Guide

1. Keep the existing Supabase project used for cloud employee login.
2. In Supabase **SQL Editor**, run `supabase/sql/03_operational_cloud.sql`.
3. Confirm `config.js` contains the correct Supabase Project URL and public anon/publishable key. Never use the service-role key in GitHub.
4. Ensure the `admin-users` Edge Function from the previous release is deployed.
5. Replace the files in the GitHub repository root with this package and commit.
6. Open the live GitHub Pages URL, sign in, and create a test patient.
7. Sign in from another device. Changes should appear automatically; otherwise refresh once and check Supabase Realtime is enabled for the six operational tables.

## Existing local prototype data
Local-browser records are not automatically uploaded. This release starts with the shared Supabase records. Add real records afresh, or import them later through a controlled migration.

## Security
- Row Level Security is enabled.
- Only active staff may read.
- Writes are limited by role.
- Every record stores the employee who entered it.
- Audit entries are visible only to Admin and Manager roles.
