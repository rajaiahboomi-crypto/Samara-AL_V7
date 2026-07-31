-- Create a function to create users without email confirmation
-- This bypasses the Auth API to avoid email rate limits
-- Run this in your Supabase SQL Editor

-- Enable the necessary extension
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- Create the function to create a user directly
CREATE OR REPLACE FUNCTION samara_admin_create_user(p_email TEXT, p_password TEXT)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_user_id UUID;
  v_encrypted_password TEXT;
BEGIN
  -- Generate a UUID for the new user
  v_user_id := gen_random_uuid();
  
  -- Hash the password using Supabase's method (bcrypt)
  -- Note: This uses a simple hash - for production, use the exact method Supabase uses
  v_encrypted_password := crypt(p_password, gen_salt('bf'));
  
  -- Insert directly into auth.users (bypassing Auth API)
  INSERT INTO auth.users (
    id,
    instance_id,
    email,
    encrypted_password,
    email_confirmed_at,
    raw_user_meta_data,
    created_at,
    updated_at,
    last_sign_in_at,
    raw_app_meta_data,
    is_super_admin,
    role,
    aud,
    confirmation_sent_at
  ) VALUES (
    v_user_id,
    '00000000-0000-0000-0000-000000000000',
    lower(p_email),
    v_encrypted_password,
    now(),  -- email_confirmed_at set to now to skip confirmation
    '{}'::jsonb,
    now(),
    now(),
    now(),
    '{"provider":"email","providers":["email"]}'::jsonb,
    false,
    'authenticated',
    'authenticated',
    NULL
  );
  
  RETURN v_user_id;
END;
$$;

-- Grant execute permission to authenticated users
GRANT EXECUTE ON FUNCTION samara_admin_create_user(TEXT, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION samara_admin_create_user(TEXT, TEXT) TO anon;
