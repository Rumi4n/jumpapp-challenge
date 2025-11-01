# Google OAuth Setup Guide

This guide will walk you through creating a Google OAuth application to get test credentials for the JumpApp Email Sorter.

## Prerequisites
- A Google account (Gmail)
- Access to Google Cloud Console

---

## Step-by-Step Instructions

### Step 1: Access Google Cloud Console
1. Go to [Google Cloud Console](https://console.cloud.google.com/)
2. Sign in with your Google account

### Step 2: Create a New Project
1. Click on the **project dropdown** at the top of the page (next to "Google Cloud")
2. Click **"NEW PROJECT"** button in the top right
3. Enter project details:
   - **Project name**: `JumpApp Email Sorter Test` (or any name you prefer)
   - **Organization**: Leave as "No organization" (unless you have one)
4. Click **"CREATE"**
5. Wait a few seconds for the project to be created
6. Select your new project from the project dropdown

### Step 3: Enable Required APIs
1. In the left sidebar, go to **"APIs & Services"** → **"Library"**
2. Search for and enable these APIs (click on each, then click "ENABLE"):
   - **Gmail API** - Required for reading and managing emails
   - **Google+ API** (or **People API**) - Required for user profile information

### Step 4: Configure OAuth Consent Screen
1. In the left sidebar, go to **"APIs & Services"** → **"OAuth consent screen"**
2. Choose **"External"** user type (unless you have a Google Workspace account)
3. Click **"CREATE"**
4. Fill in the required fields:

   **App information:**
   - **App name**: `JumpApp Email Sorter`
   - **User support email**: Your email address
   - **App logo**: (Optional - you can skip this)

   **App domain (Optional):**
   - Leave blank for local testing

   **Developer contact information:**
   - **Email addresses**: Your email address

5. Click **"SAVE AND CONTINUE"**

### Step 5: Add Scopes
1. Click **"ADD OR REMOVE SCOPES"**
2. Filter and select these scopes:
   - `userinfo.email` - View your email address
   - `userinfo.profile` - View your basic profile info
   - `gmail.modify` - Read, compose, send, and permanently delete all your email from Gmail
   - `gmail.readonly` - View your email messages and settings

   Or manually add these scope URLs:
   ```
   https://www.googleapis.com/auth/userinfo.email
   https://www.googleapis.com/auth/userinfo.profile
   https://www.googleapis.com/auth/gmail.modify
   https://www.googleapis.com/auth/gmail.readonly
   ```

3. Click **"UPDATE"**
4. Click **"SAVE AND CONTINUE"**

### Step 6: Add Test Users
Since your app is in "External" mode and not published, you need to add test users:

1. Click **"ADD USERS"**
2. Enter the Gmail addresses you want to test with (including your own)
3. Click **"ADD"**
4. Click **"SAVE AND CONTINUE"**
5. Review the summary and click **"BACK TO DASHBOARD"**

### Step 7: Create OAuth 2.0 Credentials
1. In the left sidebar, go to **"APIs & Services"** → **"Credentials"**
2. Click **"+ CREATE CREDENTIALS"** at the top
3. Select **"OAuth client ID"**
4. Choose application type:
   - **Application type**: `Web application`
   - **Name**: `JumpApp Email Sorter - Local Dev`

5. Add **Authorized JavaScript origins**:
   - Click **"+ ADD URI"**
   - Enter: `http://localhost:4000`

6. Add **Authorized redirect URIs**:
   - Click **"+ ADD URI"**
   - Enter: `http://localhost:4000/auth/google/callback`

7. Click **"CREATE"**

### Step 8: Save Your Credentials
1. A popup will appear with your credentials:
   - **Client ID**: Looks like `123456789-abcdefg.apps.googleusercontent.com`
   - **Client Secret**: Looks like `GOCSPX-abc123xyz`

2. **IMPORTANT**: Copy these values immediately!
3. Click **"DOWNLOAD JSON"** to save a backup (optional but recommended)
4. Click **"OK"**

---

## Step 9: Add Credentials to Your App

### Option A: Using Environment Variables (Recommended for testing)

**Windows PowerShell:**
```powershell
$env:GOOGLE_CLIENT_ID="your_client_id_here"
$env:GOOGLE_CLIENT_SECRET="your_client_secret_here"
```

**Windows CMD:**
```cmd
set GOOGLE_CLIENT_ID=your_client_id_here
set GOOGLE_CLIENT_SECRET=your_client_secret_here
```

**Linux/Mac:**
```bash
export GOOGLE_CLIENT_ID="your_client_id_here"
export GOOGLE_CLIENT_SECRET="your_client_secret_here"
```

### Option B: Using .env File (Recommended for development)

1. Create a `.env` file in the project root:
```bash
# Google OAuth
GOOGLE_CLIENT_ID=your_client_id_here
GOOGLE_CLIENT_SECRET=your_client_secret_here

# Anthropic AI (optional for now)
ANTHROPIC_API_KEY=your_api_key_here
```

2. **Note**: The `.env` file is already in `.gitignore`, so it won't be committed to Git

3. Load the environment variables before starting the server:

**Windows PowerShell:**
```powershell
Get-Content .env | ForEach-Object {
    if ($_ -match '^([^=]+)=(.*)$') {
        [System.Environment]::SetEnvironmentVariable($matches[1], $matches[2])
    }
}
mix phx.server
```

**Or manually set them each time you open a new terminal**

---

## Step 10: Test the OAuth Flow

1. Make sure your environment variables are set
2. Start the Phoenix server:
   ```bash
   mix phx.server
   ```

3. Open your browser to: `http://localhost:4000`
4. Click **"Sign in with Google"**
5. You should see the Google OAuth consent screen
6. Select your test account
7. Review and accept the permissions
8. You should be redirected back to your app and signed in!

---

## Troubleshooting

### "Error 400: redirect_uri_mismatch"
- Make sure you added `http://localhost:4000/auth/google/callback` exactly as shown in the Authorized redirect URIs
- Check that you're accessing the app at `http://localhost:4000` (not `127.0.0.1`)

### "Error 403: access_denied"
- Make sure you added your Google account as a test user in Step 6
- Your app is in testing mode and only test users can sign in

### "This app isn't verified"
- This is normal for apps in testing mode
- Click **"Advanced"** → **"Go to [App Name] (unsafe)"** to continue
- This warning won't appear for test users you've added

### Environment variables not working
- Make sure you set them in the same terminal session where you run `mix phx.server`
- Try closing and reopening your terminal
- Verify they're set: `echo $env:GOOGLE_CLIENT_ID` (PowerShell) or `echo %GOOGLE_CLIENT_ID%` (CMD)

### "Invalid client" error
- Double-check that you copied the Client ID and Client Secret correctly
- Make sure there are no extra spaces or quotes

---

## Optional: Publishing Your App (Not Required for Testing)

If you want to allow any Google user to sign in (not just test users):

1. Go to **"OAuth consent screen"**
2. Click **"PUBLISH APP"**
3. Click **"CONFIRM"**

**Note**: For this project, keeping it in testing mode is fine since you're the only user.

---

## Security Notes

⚠️ **IMPORTANT**:
- **NEVER** commit your Client ID and Client Secret to Git
- The `.env` file is already in `.gitignore`
- If you accidentally expose your credentials, revoke them immediately in Google Cloud Console
- For production deployment, use secure environment variable management (like Fly.io secrets)

---

## Next Steps

Once you have OAuth working:
1. ✅ Sign in with Google
2. ✅ Test the authentication flow
3. 🔜 Set up Anthropic API key for AI features
4. 🔜 Start using the email sorting features

---

## Useful Links

- [Google Cloud Console](https://console.cloud.google.com/)
- [Gmail API Documentation](https://developers.google.com/gmail/api)
- [OAuth 2.0 Scopes](https://developers.google.com/identity/protocols/oauth2/scopes)
- [Phoenix Ueberauth Documentation](https://hexdocs.pm/ueberauth/readme.html)

