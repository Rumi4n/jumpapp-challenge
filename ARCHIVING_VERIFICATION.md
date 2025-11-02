# Email Archiving Verification

## Your Questions Answered

### Question 1: Does it still archive emails that don't fall into any category?

**Answer: NO** - The code is correctly implemented to only archive categorized emails.

### How It Works

#### Step-by-Step Flow:

1. **Email Import** (line 73 in `email_import_worker.ex`):
   ```elixir
   {:ok, category_id} = AIService.categorize_email(email_content, categories)
   ```
   - Returns `{:ok, nil}` if no category matches
   - Returns `{:ok, category_id}` if a category matches

2. **Save to Database** (line 87):
   ```elixir
   category_id: category_id  # Can be nil or an integer
   ```
   - Email is saved with `category_id = nil` if uncategorized
   - Email is saved with `category_id = <number>` if categorized

3. **Archive Decision** (line 112):
   ```elixir
   if email.category_id do
     # Only runs if category_id is NOT nil
     GmailClient.archive_message(...)
   else
     Logger.info("Email imported but not categorized - leaving in inbox")
   end
   ```
   - **If `category_id` is nil**: Skips archiving, logs message
   - **If `category_id` has a value**: Archives in Gmail

### AI Service Returns

The `AIService.categorize_email/2` function returns `nil` in these cases:

1. **No categories exist** (line 17-18):
   ```elixir
   if categories == [] do
     {:ok, nil}
   ```

2. **AI responds with "NONE"** (line 164-165):
   ```elixir
   response == "NONE" ->
     {:ok, nil}
   ```

3. **AI fails or returns invalid response** (line 27-29):
   ```elixir
   {:error, error} ->
     Logger.error("AI categorization failed: #{inspect(error)}")
     {:ok, nil}
   ```

4. **AI returns invalid category ID** (line 171-174):
   ```elixir
   if Enum.any?(categories, fn cat -> cat.id == category_id end) do
     {:ok, category_id}
   else
     {:ok, nil}  # Category ID doesn't exist
   end
   ```

### Verification Test

You can verify this by checking the logs. When an email is not categorized, you'll see:

```
[info] Email <message_id> imported but not categorized - leaving in inbox
```

When an email IS categorized and archived, you'll see:

```
[info] Successfully imported and archived email <message_id> (category: <category_id>)
```

---

## Question 2: Does it work when you leave the page in the background?

**Answer: YES** - The email import happens entirely in the background via Oban workers, independent of the web page.

### How Background Processing Works

#### 1. Oban Cron Job (Scheduled)

**Configuration** (`config/config.exs` line 86):
```elixir
{"*/3 * * * *", JumpappEmailSorter.Workers.GmailPollWorker}
```

This means:
- ✅ Runs **every 3 minutes**
- ✅ Runs **automatically** (no user action needed)
- ✅ Runs **server-side** (not dependent on browser)
- ✅ Runs **even if no one is logged in**

#### 2. Worker Execution Flow

```
Every 3 minutes:
  ↓
GmailPollWorker runs
  ↓
Gets all Gmail accounts from database
  ↓
For each account:
  - Refreshes OAuth token if needed
  - Queues EmailImportWorker job
  ↓
EmailImportWorker processes each account:
  - Fetches unread emails from Gmail
  - Categorizes with AI
  - Summarizes with AI
  - Saves to database
  - Archives if categorized
  ↓
Done (repeats in 3 minutes)
```

#### 3. Independence from Web UI

The background workers are **completely independent** from the web interface:

| Aspect | Behavior |
|--------|----------|
| **Browser open?** | Not required |
| **User logged in?** | Not required |
| **Page visible?** | Not required |
| **Internet connection (server)?** | Required |
| **Server running?** | Required |

### Real-World Scenarios

#### Scenario A: Page Open
```
You're on dashboard → Worker runs every 3 minutes → 
New emails appear via LiveView updates (real-time)
```

#### Scenario B: Page Closed
```
You close browser → Worker still runs every 3 minutes → 
Emails imported and saved → When you open page later, 
they're already there
```

#### Scenario C: Not Logged In
```
You're logged out → Worker still runs every 3 minutes → 
Emails imported for ALL users' accounts → 
When you log in, emails are already processed
```

#### Scenario D: Background Tab
```
You switch to another tab → Worker runs every 3 minutes → 
LiveView updates the page in background → 
When you switch back, emails are there
```

### Technical Details

#### Oban Queue System

Oban is a robust background job processing system that:
- ✅ Persists jobs in PostgreSQL (survives server restarts)
- ✅ Retries failed jobs (up to 3 attempts)
- ✅ Runs jobs in separate processes (doesn't block web requests)
- ✅ Handles concurrency (multiple jobs can run simultaneously)

#### Queue Configuration

```elixir
queues: [
  default: 10,        # GmailPollWorker runs here (10 concurrent jobs)
  email_import: 5,    # EmailImportWorker runs here (5 concurrent jobs)
  unsubscribe: 3      # UnsubscribeWorker runs here (3 concurrent jobs)
]
```

This means:
- Up to 10 poll workers can run simultaneously
- Up to 5 email import workers can process accounts simultaneously
- System can handle multiple accounts efficiently

### Monitoring Background Jobs

You can monitor the background jobs in several ways:

#### 1. Server Logs
```bash
# On your server or locally
tail -f log/dev.log | grep "Gmail poll"
```

You'll see:
```
[info] Starting Gmail poll for all accounts
[info] Found 3 unread messages
[info] Email 123abc imported but not categorized - leaving in inbox
[info] Successfully imported and archived email 456def (category: 5)
[info] Queued email import for 2 accounts
```

#### 2. Database Query
```sql
-- Check recent email imports
SELECT id, subject, category_id, inserted_at 
FROM emails 
ORDER BY inserted_at DESC 
LIMIT 10;

-- Check Oban jobs
SELECT * FROM oban_jobs 
WHERE state = 'executing' OR state = 'scheduled'
ORDER BY inserted_at DESC;
```

#### 3. LiveView Dashboard (if configured)
Visit `/dev/dashboard` in development to see:
- Active jobs
- Job history
- Queue status

### What Happens During Server Restart?

1. **Scheduled jobs**: Resume automatically when server starts
2. **In-progress jobs**: Marked as failed, will retry
3. **Queued jobs**: Remain in database, process when server starts
4. **Imported emails**: Safely stored in database

### Performance Considerations

#### Polling Frequency
- Current: Every 3 minutes
- Configurable in `config/config.exs`
- Can be adjusted based on needs:
  - More frequent: `*/1 * * * *` (every minute)
  - Less frequent: `*/5 * * * *` (every 5 minutes)

#### API Rate Limits
- Gmail API: 250 quota units per user per second
- Each email fetch: ~5 quota units
- Current setup: Well within limits

#### Scaling
The system can handle:
- ✅ Multiple users
- ✅ Multiple Gmail accounts per user
- ✅ Thousands of emails
- ✅ Concurrent processing

---

## Summary

### Archiving Behavior ✅
- **Categorized emails**: Archived in Gmail
- **Uncategorized emails**: Stay in Gmail inbox
- **Verification**: Check server logs for confirmation

### Background Processing ✅
- **Runs automatically**: Every 3 minutes via Oban cron
- **Independent**: Doesn't require browser or user session
- **Reliable**: Persisted in database, survives restarts
- **Scalable**: Handles multiple accounts concurrently

### You Can Safely:
- ✅ Close the browser
- ✅ Log out
- ✅ Leave the page in background
- ✅ Turn off your computer (server keeps running)

### Emails Will Still:
- ✅ Import every 3 minutes
- ✅ Get categorized by AI
- ✅ Get summarized by AI
- ✅ Be saved to database
- ✅ Be archived only if categorized

---

## Testing Recommendations

### Test 1: Verify Archiving Logic
1. Create a test email that doesn't match any category
2. Wait 3 minutes for import
3. Check Gmail - email should still be in inbox
4. Check server logs for: "imported but not categorized - leaving in inbox"

### Test 2: Verify Background Processing
1. Log in and view dashboard
2. Send yourself a test email
3. Close browser completely
4. Wait 3-5 minutes
5. Open browser and log in
6. Email should already be imported and categorized

### Test 3: Verify Multi-Account
1. Add second Gmail account
2. Send email to both accounts
3. Close browser
4. Wait 3-5 minutes
5. Open browser
6. Both emails should be imported

