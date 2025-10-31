# AI Email Sorting App - 72 Hour Implementation Plan

## Tech Stack
- **Framework**: Phoenix 1.7 + LiveView
- **Database**: PostgreSQL
- **AI Provider**: Anthropic Claude (free tier) with provider-agnostic design
- **OAuth**: Google OAuth 2.0 (ueberauth_google)
- **Email**: Gmail API
- **Background Jobs**: Oban
- **Deployment**: Fly.io
- **Testing**: ExUnit (unit + integration tests)

## Day 1 (Hours 1-24): Foundation & Authentication

### Morning (Hours 1-8): Project Setup & OAuth
1. **Initialize Phoenix project** with LiveView and PostgreSQL
   - `mix phx.new jumpapp_email_sorter --live --database postgres`
   - Set up Tailwind CSS for modern UI
   - Configure environment variables structure

2. **Implement Google OAuth authentication**
   - Add dependencies: `ueberauth`, `ueberauth_google`
   - Create User schema with Google tokens (access_token, refresh_token, expires_at)
   - Set up OAuth callback routes
   - Request Gmail scopes: `gmail.modify`, `gmail.readonly`
   - Implement token refresh logic

3. **Build authentication system**
   - Create auth context and user sessions
   - Add LiveView authentication hooks
   - Build sign-in page with "Sign in with Google" button

### Afternoon (Hours 9-16): Database Schema & Core Models
4. **Design and implement database schemas**
   - `users` table: email, google_id, tokens, inserted_at, updated_at
   - `gmail_accounts` table: user_id, email, access_token, refresh_token (for multiple accounts)
   - `categories` table: user_id, name, description, color, position
   - `emails` table: gmail_account_id, category_id, gmail_message_id, subject, from, received_at, summary, body_preview, archived_at
   - `unsubscribe_attempts` table: email_id, status, unsubscribe_url, attempted_at

5. **Create Ecto schemas and contexts**
   - Accounts context (users, gmail_accounts)
   - Categories context (CRUD operations)
   - Emails context (queries, filtering)

### Evening (Hours 17-24): Gmail Integration Foundation
6. **Build Gmail API client**
   - Create Gmail API wrapper module using HTTPoison/Req
   - Implement authentication with access tokens
   - Build functions: list_messages, get_message, modify_message (archive)
   - Handle token refresh on 401 errors

7. **Write tests for Day 1 work**
   - Auth context tests
   - Gmail API client tests (with mocks)
   - Schema validation tests

## Day 2 (Hours 25-48): AI Integration & Email Processing

### Morning (Hours 25-32): AI Service Layer
8. **Implement AI service module**
   - Create provider-agnostic AI interface
   - Implement Anthropic Claude client
   - Build two main functions:
     - `categorize_email(email_content, categories)` - returns category match
     - `summarize_email(email_content)` - returns summary
   - Add retry logic and error handling

9. **Set up Oban for background jobs**
   - Configure Oban with PostgreSQL
   - Create job: `EmailImportWorker` - fetches and processes new emails
   - Create job: `EmailCategorizationWorker` - categorizes single email
   - Create job: `GmailPollWorker` - scheduled job (every 2-5 minutes)

### Afternoon (Hours 33-40): Email Import Pipeline
10. **Build email import system**
    - Fetch unread emails from Gmail API
    - Parse email content (handle HTML/plain text)
    - Use AI to categorize based on user's categories
    - Generate AI summary
    - Save to database
    - Archive email in Gmail
    - Handle duplicates (check gmail_message_id)

11. **Implement Gmail Push Notifications (Pub/Sub)**
    - Set up Google Cloud Pub/Sub topic
    - Create webhook endpoint to receive notifications
    - Trigger email import on new message
    - Fallback to polling if push fails

### Evening (Hours 41-48): LiveView UI - Dashboard
12. **Build main dashboard LiveView**
    - Show connected Gmail accounts with "Add Account" button
    - Display categories in a grid/list with email counts
    - "Add Category" modal with name/description form
    - Real-time updates when new emails arrive
    - Modern, clean UI with Tailwind

13. **Write tests for Day 2 work**
    - AI service tests (mocked responses)
    - Email import pipeline tests
    - Oban job tests
    - LiveView dashboard tests

## Day 3 (Hours 49-72): Category View, Unsubscribe & Deployment

### Morning (Hours 49-56): Category Detail View
14. **Build category detail LiveView**
    - List all emails in category with summaries
    - Checkbox selection (individual + select all)
    - Bulk action buttons: Delete, Unsubscribe
    - Click email to view full content in modal/slide-over
    - Show email metadata (from, date, subject)

15. **Implement email actions**
    - Delete: Remove from database, optionally trash in Gmail
    - View full email: Fetch full body if needed, display nicely

### Afternoon (Hours 57-64): Intelligent Unsubscribe
16. **Build unsubscribe system (Hybrid approach)**
    - Extract unsubscribe links from email headers (`List-Unsubscribe`)
    - Parse email body for unsubscribe URLs (regex patterns)
    - For one-click unsubscribe: Make HTTP request directly
    - For web pages:
      - Fetch page HTML
      - Use AI to identify unsubscribe form/button
      - Attempt to construct and submit form
      - Track success/failure in database
    - Create `UnsubscribeWorker` Oban job
    - Show status to user (pending, success, failed with link)

17. **Multi-account support**
    - Add additional Gmail accounts via OAuth
    - List all connected accounts on dashboard
    - Import emails from all accounts
    - Show account indicator on emails

### Evening (Hours 65-72): Testing, Polish & Deployment
18. **Comprehensive testing**
    - Integration tests for email flow end-to-end
    - LiveView interaction tests
    - Unsubscribe logic tests
    - Fix any bugs discovered

19. **UI polish and UX improvements**
    - Loading states for all async operations
    - Error messages and user feedback
    - Empty states (no categories, no emails)
    - Responsive design for mobile
    - Add email count badges on categories

20. **Deploy to Fly.io**
    - Initialize Fly.io app: `fly launch`
    - Configure PostgreSQL on Fly.io
    - Set environment variables (Google OAuth, AI API keys)
    - Configure secrets for production
    - Set up releases and migrations
    - Deploy: `fly deploy`
    - Test production deployment thoroughly
    - Set up monitoring/logging

21. **Documentation and submission**
    - Update README with setup instructions
    - Document environment variables needed
    - Add screenshots to README
    - Note about adding test Gmail user in Google Console
    - Push to GitHub
    - Submit deployment URL and repo link

## Key Files to Create

### Core Application
- `lib/jumpapp_email_sorter/accounts.ex` - User & account management
- `lib/jumpapp_email_sorter/categories.ex` - Category CRUD
- `lib/jumpapp_email_sorter/emails.ex` - Email queries & operations
- `lib/jumpapp_email_sorter/gmail_client.ex` - Gmail API wrapper
- `lib/jumpapp_email_sorter/ai_service.ex` - AI categorization & summarization
- `lib/jumpapp_email_sorter/unsubscribe_service.ex` - Unsubscribe logic

### Background Jobs
- `lib/jumpapp_email_sorter/workers/gmail_poll_worker.ex`
- `lib/jumpapp_email_sorter/workers/email_import_worker.ex`
- `lib/jumpapp_email_sorter/workers/unsubscribe_worker.ex`

### LiveViews
- `lib/jumpapp_email_sorter_web/live/auth_live.ex` - Sign in page
- `lib/jumpapp_email_sorter_web/live/dashboard_live.ex` - Main dashboard
- `lib/jumpapp_email_sorter_web/live/category_live.ex` - Category detail view
- `lib/jumpapp_email_sorter_web/live/components/email_card.ex` - Email display component

### Configuration
- `config/runtime.exs` - Environment-based config
- `fly.toml` - Fly.io deployment config
- `.env.example` - Environment variables template

## Critical Success Factors
1. **Token Management**: Properly refresh Google OAuth tokens before expiry
2. **Rate Limiting**: Handle Gmail API rate limits gracefully
3. **AI Costs**: Monitor AI API usage to stay within free tier
4. **Error Handling**: Graceful degradation when services fail
5. **Testing**: Focus on integration tests for critical paths
6. **Performance**: Use database indexes on foreign keys and gmail_message_id

## Environment Variables Needed
```
GOOGLE_CLIENT_ID=
GOOGLE_CLIENT_SECRET=
ANTHROPIC_API_KEY=
SECRET_KEY_BASE=
DATABASE_URL=
PHX_HOST=
GOOGLE_PUBSUB_TOPIC= (optional, for push notifications)
```

## Contingency Plans
- **If Pub/Sub is complex**: Stick with polling (Option A) - works reliably
- **If AI costs exceed free tier**: Implement caching, reduce summary length
- **If unsubscribe is too complex**: Show extracted links, let user click manually
- **If time runs short**: Prioritize core flow (auth → categories → import → view) over polish

