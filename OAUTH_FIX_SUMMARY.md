# OAuth Configuration Fix Summary

## Problem
When clicking "Sign in with Google", you were getting an error:
```
Access blocked: Authorization Error
Missing required parameter: client_id
```

## Root Cause
Phoenix doesn't automatically load `.env` files. The `GOOGLE_CLIENT_ID` and `GOOGLE_CLIENT_SECRET` environment variables from your `.env` file weren't being loaded before the OAuth configuration was set up.

## Solution Implemented

### 1. Environment Variable Loading in `config/runtime.exs`
Added code to load the `.env` file before configuring OAuth:

```elixir
# Load .env file in development/test
if config_env() in [:dev, :test] and File.exists?(".env") do
  File.read!(".env")
  |> String.split("\n", trim: true)
  |> Enum.each(fn line ->
    line = String.trim(line)
    # Skip comments and empty lines
    unless String.starts_with?(line, "#") or line == "" do
      case String.split(line, "=", parts: 2) do
        [key, value] ->
          key = String.trim(key)
          value = String.trim(value)
          System.put_env(key, value)
        _ ->
          :ok
      end
    end
  end)
end

# Configure Google OAuth for all environments
config :ueberauth, Ueberauth.Strategy.Google.OAuth,
  client_id: System.get_env("GOOGLE_CLIENT_ID"),
  client_secret: System.get_env("GOOGLE_CLIENT_SECRET")
```

### 2. Removed Duplicate Configuration
Removed the duplicate OAuth configuration from `config/dev.exs` since it's now handled in `runtime.exs`.

## Verification

The configuration has been verified to work:
- ✓ Environment variables are loaded from `.env` file
- ✓ OAuth client_id is set: `1089081421677-8e63v2aqr9s2rdcb1banbjoos2qfkca5.apps.googleusercontent.com`
- ✓ OAuth client_secret is set (35 characters)

## How to Test

1. Make sure your `.env` file in the project root contains:
   ```
   GOOGLE_CLIENT_ID=your_client_id_here
   GOOGLE_CLIENT_SECRET=your_client_secret_here
   ```

2. Start the Phoenix server:
   ```bash
   mix phx.server
   ```

3. Open your browser to `http://localhost:4000`

4. Click "Sign in with Google"

5. You should now be redirected to Google's OAuth consent screen instead of seeing the "Missing required parameter: client_id" error.

## Important Notes

- The `.env` file is automatically loaded in development and test environments
- In production, you should set environment variables through your hosting platform (not using a `.env` file)
- The `.env` file is gitignored for security reasons
- Make sure your Google OAuth redirect URI is set to: `http://localhost:4000/auth/google/callback`

## Next Steps

If you still see the error after restarting the server:
1. Verify your `.env` file exists in the project root
2. Check that the file contains valid `GOOGLE_CLIENT_ID` and `GOOGLE_CLIENT_SECRET` values
3. Restart the Phoenix server completely (stop and start again)
4. Check the Google Cloud Console to ensure your OAuth credentials are correct and the redirect URI is properly configured

