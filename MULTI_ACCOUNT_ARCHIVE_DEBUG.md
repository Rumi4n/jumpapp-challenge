# Multi-Account Archive Debugging

## Issue Reported

**Symptom**: Categorized emails from the second (non-main) account are NOT being archived in Gmail, even though they are successfully categorized and saved to the database.

**Working**: 
- ✅ Main account: Categorized emails ARE archived
- ✅ Second account: Emails ARE imported
- ✅ Second account: Emails ARE categorized correctly
- ❌ Second account: Categorized emails are NOT archived

## Theory

The code looks correct - it uses `gmail_account.access_token` which should be the correct token for each account. However, there might be:

1. **Token Issue**: The second account's access token might be expired or invalid
2. **Permissions Issue**: The second account might not have granted the necessary Gmail permissions
3. **API Error**: The Gmail API might be returning an error that we're not seeing
4. **Silent Failure**: The archive call might be failing but we're catching the error and continuing

## Enhanced Logging

I've added detailed logging to help diagnose the issue:

### In `email_import_worker.ex` (lines 113-139):

**Before archiving**:
```
[info] Attempting to archive email <message_id> from account <email> (category: <category_id>)
```

**Success**:
```
[info] ✓ Successfully archived email <message_id> in <email>
```

**Failure**:
```
[error] ✗ Failed to archive email <message_id> in <email>: <error_details>
```

**Uncategorized**:
```
[info] Email <message_id> from <email> not categorized - leaving in inbox
```

### In `gmail_client.ex` (lines 80-104):

**API Call**:
```
[debug] Archiving message <message_id> via Gmail API
```

**Success**:
```
[debug] Gmail API: Successfully archived message <message_id>
```

**Unauthorized**:
```
[error] Gmail API: Unauthorized (401) when archiving <message_id>
```

**Other Error**:
```
[error] Gmail API error when archiving <message_id>: <status> - <body>
```

## How to Diagnose

### Step 1: Check Server Logs

After deploying these changes, send a test email to your second account that matches a category, then check the logs:

```bash
# On Render
render logs -t <your-service-name>

# Or locally
tail -f log/dev.log | grep -E "(Attempting to archive|Successfully archived|Failed to archive)"
```

### Step 2: Look for These Patterns

#### Pattern A: Archive is Being Attempted
```
[info] Attempting to archive email abc123 from account second@gmail.com (category: 5)
[info] ✓ Successfully archived email abc123 in second@gmail.com
```
**Diagnosis**: Archive is working! The email should be archived in Gmail.

#### Pattern B: Archive is Failing with 401
```
[info] Attempting to archive email abc123 from account second@gmail.com (category: 5)
[error] Gmail API: Unauthorized (401) when archiving abc123
[error] ✗ Failed to archive email abc123 in second@gmail.com: :unauthorized
```
**Diagnosis**: Token is expired or invalid. Need to refresh token or re-authenticate.

#### Pattern C: Archive is Failing with Other Error
```
[info] Attempting to archive email abc123 from account second@gmail.com (category: 5)
[error] Gmail API error when archiving abc123: 403 - %{"error" => ...}
[error] ✗ Failed to archive email abc123 in second@gmail.com: {:api_error, 403, ...}
```
**Diagnosis**: Permission issue or API error. Check the error details.

#### Pattern D: Archive is Not Being Attempted
```
[info] Email abc123 from second@gmail.com not categorized - leaving in inbox
```
**Diagnosis**: Email is not being categorized. Check AI service and categories.

### Step 3: Check Database

Verify the email was saved with a category:

```sql
SELECT 
  e.id,
  e.subject,
  e.category_id,
  c.name as category_name,
  ga.email as gmail_account,
  e.inserted_at
FROM emails e
LEFT JOIN categories c ON e.category_id = c.id
LEFT JOIN gmail_accounts ga ON e.gmail_account_id = ga.id
ORDER BY e.inserted_at DESC
LIMIT 10;
```

Look for:
- ✅ `category_id` should NOT be null
- ✅ `gmail_account` should show the second account
- ✅ `category_name` should match your categories

### Step 4: Check Gmail Accounts Table

Verify both accounts have valid tokens:

```sql
SELECT 
  id,
  email,
  token_expires_at,
  CASE 
    WHEN token_expires_at > NOW() THEN 'Valid'
    ELSE 'EXPIRED'
  END as token_status
FROM gmail_accounts;
```

Look for:
- ✅ Both accounts should be listed
- ✅ Both should have `token_status = 'Valid'`
- ❌ If second account shows 'EXPIRED', that's the issue!

## Possible Root Causes

### Cause 1: Token Expired

**Symptoms**:
- Logs show "Unauthorized (401)"
- Token expires_at is in the past

**Solution**:
```elixir
# The GmailPollWorker should auto-refresh tokens
# But if it's not working, manually trigger:
# 1. Remove the second account from dashboard
# 2. Re-add it via "+ Add Account"
```

### Cause 2: Missing Gmail Permissions

**Symptoms**:
- Logs show "403 Forbidden"
- Error mentions insufficient permissions

**Solution**:
When adding the second account, ensure you grant ALL requested permissions:
- ✅ Read Gmail messages
- ✅ Modify Gmail messages (required for archiving!)
- ✅ Manage labels

### Cause 3: OAuth Scope Issue

**Symptoms**:
- Can read emails but can't archive
- 403 error with scope-related message

**Check OAuth Scopes** in `config/config.exs`:
```elixir
config :ueberauth, Ueberauth.Strategy.Google.OAuth,
  default_scope: "email profile https://www.googleapis.com/auth/gmail.modify"
```

The `gmail.modify` scope is REQUIRED for archiving.

### Cause 4: Different User Context

**Symptoms**:
- No error in logs
- Email appears archived but in wrong account

**Unlikely** because Gmail API uses `/users/me/` which is the authenticated user.

## Testing Plan

### Test 1: Verify Logging Works

1. Deploy the updated code
2. Send test email to MAIN account (should work)
3. Check logs for new detailed messages
4. Confirm you see "Attempting to archive..." and "✓ Successfully archived..."

### Test 2: Diagnose Second Account

1. Send test email to SECOND account that matches a category
2. Wait 3 minutes for import
3. Check logs for archive attempt
4. Note the exact error message if it fails

### Test 3: Re-authenticate Second Account

1. Remove second account from dashboard (if possible)
2. Click "+ Add Account"
3. Sign in with second account again
4. **Carefully review and accept ALL permissions**
5. Send test email
6. Check if archiving now works

## Expected Behavior

After fixing, you should see:

```
[info] Importing emails for account 1
[info] Found 1 unread messages
[info] Attempting to archive email abc123 from account main@company.com (category: 3)
[debug] Archiving message abc123 via Gmail API
[debug] Gmail API: Successfully archived message abc123
[info] ✓ Successfully archived email abc123 in main@company.com

[info] Importing emails for account 2
[info] Found 1 unread messages
[info] Attempting to archive email def456 from account second@gmail.com (category: 5)
[debug] Archiving message def456 via Gmail API
[debug] Gmail API: Successfully archived message def456
[info] ✓ Successfully archived email def456 in second@gmail.com
```

## Next Steps

1. **Deploy** the updated code with enhanced logging
2. **Send test email** to second account
3. **Check logs** and report back what you see
4. Based on the logs, we'll know exactly what's wrong

## Quick Fix Commands

### If Token is Expired:
```elixir
# In IEx console
alias JumpappEmailSorter.{Accounts, GmailClient}
account = Accounts.get_gmail_account!(2)  # Replace 2 with actual ID
{:ok, new_tokens} = GmailClient.refresh_access_token(account.refresh_token)
Accounts.update_gmail_account_tokens(account, new_tokens)
```

### If Need to Check Scopes:
```bash
# Check what scopes were granted
# In your Google Account: https://myaccount.google.com/permissions
# Look for your app and verify "Gmail" permissions
```

---

## Summary

The code logic is correct - it uses the right access token for each account. The issue is likely:

1. **Most Likely**: Token expired or invalid for second account
2. **Possible**: Missing Gmail modify permissions for second account
3. **Unlikely**: OAuth scope configuration issue

The enhanced logging will tell us exactly what's happening. Please deploy and check the logs!

