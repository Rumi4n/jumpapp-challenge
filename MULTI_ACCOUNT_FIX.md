# Multi-Account Support Fix

## Problem Identified

The "Add Account" button was causing the user to be logged out and switched to a different account instead of adding a secondary Gmail account to the existing user.

### Root Cause

The OAuth callback (`/auth/google/callback`) was treating **every** Google authentication as a new user login:

1. User logs in with `account1@gmail.com` → Creates User A, sets session to User A
2. User clicks "+ Add Account" → Goes to `/auth/google`
3. User authenticates with `account2@gmail.com` → Creates/finds User B
4. **Problem**: Sets session to User B (logs out of User A!)
5. Result: User A's categories disappear, only User B's account shows

### Why This Happened

The original `AuthController.callback/2` always called:
```elixir
conn |> put_session(:user_id, user.id)
```

This changed the session to whatever user was authenticated, regardless of whether someone was already logged in.

## Solution Implemented

Modified the auth flow to distinguish between:
1. **Initial Login** - User not logged in, authenticating for the first time
2. **Adding Account** - User already logged in, adding additional Gmail account

### Code Changes

**File**: `lib/jumpapp_email_sorter_web/controllers/auth_controller.ex`

#### Before (Problematic)
```elixir
def callback(%{assigns: %{ueberauth_auth: auth}} = conn, _params) do
  # Always creates/updates user and changes session
  case Accounts.upsert_user_from_oauth(user_params) do
    {:ok, user} ->
      conn
      |> put_session(:user_id, user.id)  # ❌ Always changes session!
      |> redirect(to: ~p"/dashboard")
  end
end
```

#### After (Fixed)
```elixir
def callback(%{assigns: %{ueberauth_auth: auth}} = conn, _params) do
  # Check if user is already logged in
  case get_session(conn, :user_id) do
    nil ->
      # Initial login - create user and set session
      handle_initial_login(conn, auth, gmail_account_params)
    
    user_id ->
      # Already logged in - just add gmail account to existing user
      handle_add_account(conn, user_id, gmail_account_params)
  end
end
```

### New Behavior

#### Scenario 1: Initial Login (First Time)
1. User visits home page, not logged in
2. Clicks "Sign in with Google"
3. Authenticates with `main@gmail.com`
4. System:
   - Creates/updates User record (with `google_id` from `main@gmail.com`)
   - Creates GmailAccount record for `main@gmail.com`
   - **Sets session to this user**
   - Redirects to dashboard
5. ✅ User is logged in, sees their account and can create categories

#### Scenario 2: Adding Additional Account
1. User already logged in as `main@gmail.com`
2. Clicks "+ Add Account" on dashboard
3. Authenticates with `secondary@gmail.com`
4. System:
   - **Checks session - user already logged in!**
   - **Does NOT create new User**
   - **Does NOT change session**
   - Creates GmailAccount record for `secondary@gmail.com` linked to existing user
   - Redirects to dashboard
5. ✅ User still logged in as main account
6. ✅ Both accounts now visible in "Connected Accounts"
7. ✅ Categories remain visible (belong to main user)

## Key Features

### 1. Session Preservation
- When adding an account, the session is NOT changed
- User remains logged in as their main account
- No data loss or confusion

### 2. Proper Account Linking
- All Gmail accounts are linked to the **main user** (the one who logged in first)
- Categories belong to the user, not to individual Gmail accounts
- Emails from all accounts are imported and visible

### 3. User-Friendly Messages
- Initial login: "Successfully authenticated!"
- Adding account: "Gmail account added successfully!"
- Duplicate account: "This Gmail account is already connected."

### 4. Error Handling
- Prevents adding the same Gmail account twice
- Gracefully handles authentication failures
- Clear error messages for users

## Database Structure

### Users Table
- Represents the **main account** (person using the app)
- Has `google_id` from their primary Google account
- One user can have multiple Gmail accounts

### Gmail Accounts Table
- Represents individual Gmail inboxes
- Linked to a user via `user_id`
- Stores OAuth tokens for accessing that specific Gmail
- Multiple gmail accounts can belong to one user

### Categories Table
- Belong to a **user** (not to individual Gmail accounts)
- Shared across all of the user's Gmail accounts
- Visible regardless of which Gmail account received the email

### Emails Table
- Linked to specific `gmail_account_id` (which inbox it came from)
- Also linked to `category_id` (which category it was sorted into)
- User can see emails from all their connected accounts

## User Flow Example

### Complete Multi-Account Setup

1. **Day 1 - Initial Setup**
   ```
   User visits app → Signs in with work@company.com
   → System creates User (google_id from work@company.com)
   → System creates GmailAccount for work@company.com
   → User creates categories: "Work", "Personal", "Shopping"
   → Emails from work@company.com start importing
   ```

2. **Day 2 - Add Personal Account**
   ```
   User clicks "+ Add Account" → Authenticates with personal@gmail.com
   → System checks: user already logged in ✓
   → System creates GmailAccount for personal@gmail.com (linked to same user)
   → User still sees all their categories
   → Emails from BOTH accounts now importing
   ```

3. **Day 3 - Using the App**
   ```
   Dashboard shows:
   - Connected Accounts: work@company.com, personal@gmail.com
   - Categories: Work (50 emails), Personal (30 emails), Shopping (20 emails)
   
   Emails are categorized from BOTH accounts:
   - Work emails from work@company.com → "Work" category
   - Personal emails from personal@gmail.com → "Personal" category
   - Shopping emails from BOTH accounts → "Shopping" category
   ```

## Testing Checklist

- [x] Initial login creates user and gmail account
- [x] Session is set correctly on initial login
- [x] Add Account button doesn't change session
- [x] Second Gmail account is linked to same user
- [x] Categories remain visible after adding account
- [x] Both accounts show in Connected Accounts section
- [x] Duplicate account prevention works
- [x] Error messages are user-friendly

## Benefits

1. **No Data Loss**: Categories and emails are never lost when adding accounts
2. **Intuitive**: Matches user expectations - "add" means add, not replace
3. **Flexible**: Users can manage multiple email addresses from one dashboard
4. **Secure**: Each Gmail account has its own OAuth tokens
5. **Scalable**: Users can add as many Gmail accounts as needed

## Technical Notes

### Session Management
- Session stores only `user_id`
- User record contains the primary Google account info
- Gmail accounts are separate records with their own tokens

### OAuth Flow
- Same `/auth/google` endpoint for both login and add account
- Logic branches based on session state
- No need for separate routes or parameters

### Token Management
- Each Gmail account has its own `access_token` and `refresh_token`
- Tokens are refreshed independently
- If one account's token expires, others are unaffected

## Future Enhancements

Potential improvements:
1. Add "Remove Account" button for each Gmail account
2. Show which account each email came from in the UI
3. Allow filtering emails by source account
4. Add account nicknames/labels
5. Set a "primary" account indicator
6. Account-specific settings (e.g., import frequency)

## Migration Notes

No database migration needed! The existing schema already supports this:
- `gmail_accounts` table has `user_id` foreign key
- Unique constraint on `(user_id, email)` prevents duplicates
- Existing data structure is compatible

Users who previously had issues can:
1. Log out completely
2. Log in with their main account
3. Use "+ Add Account" to add additional accounts
4. All will work correctly now

