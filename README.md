# AI Email Sorter

An intelligent email management application that automatically categorizes and summarizes your Gmail emails using AI, with smart unsubscribe capabilities.

## Features

- 🔐 **Google OAuth Authentication** - Secure sign-in with Gmail
- 🤖 **AI-Powered Categorization** - Automatically sorts emails into custom categories using Anthropic Claude
- 📝 **Email Summarization** - AI-generated summaries for quick email scanning
- 📧 **Multi-Account Support** - Connect and manage multiple Gmail accounts
- 🗂️ **Custom Categories** - Create categories with descriptions to guide AI sorting
- 🔕 **Smart Unsubscribe** - Intelligent unsubscribe system with one-click and form-based unsubscription
- 📦 **Auto-Archive** - Automatically archives processed emails in Gmail
- ⚡ **Background Processing** - Polls Gmail every 3 minutes for new emails
- 🎨 **Modern UI** - Clean, responsive interface built with Tailwind CSS

## Tech Stack

- **Backend**: Elixir + Phoenix 1.8 + LiveView
- **Database**: PostgreSQL
- **AI**: Anthropic Claude (Haiku model for cost efficiency)
- **OAuth**: Google OAuth 2.0 with Gmail API
- **Background Jobs**: Oban
- **HTTP Client**: Req
- **HTML Parsing**: Floki

## Prerequisites

- Elixir 1.15+ and Erlang/OTP 26+
- PostgreSQL 14+
- Node.js 18+ (for asset compilation)
- Google Cloud Project with Gmail API enabled
- Anthropic API key

## Setup Instructions

### 1. Clone the Repository

```bash
git clone <your-repo-url>
cd jumpapp-challenge
```

### 2. Install Dependencies

```bash
mix deps.get
cd assets && npm install && cd ..
```

### 3. Configure Google OAuth

1. Go to [Google Cloud Console](https://console.cloud.google.com/)
2. Create a new project or select an existing one
3. Enable the Gmail API
4. Go to "Credentials" → "Create Credentials" → "OAuth 2.0 Client ID"
5. Set application type to "Web application"
6. Add authorized redirect URI: `http://localhost:4000/auth/google/callback`
7. Copy the Client ID and Client Secret

### 4. Get Anthropic API Key

1. Sign up at [Anthropic Console](https://console.anthropic.com/)
2. Create an API key
3. Copy the key

### 5. Configure Environment Variables

Create a `.env` file in the project root (recommended for development):

```bash
# Copy the example file
cp env.example .env

# Edit .env and add your credentials:
GOOGLE_CLIENT_ID=your_google_client_id
GOOGLE_CLIENT_SECRET=your_google_client_secret
ANTHROPIC_API_KEY=your_anthropic_api_key
```

**Note**: The `.env` file is automatically loaded in development and test environments. In production, set environment variables through your hosting platform.

### 6. Configure Database

Update `config/dev.exs` with your PostgreSQL credentials:

```elixir
config :jumpapp_email_sorter, JumpappEmailSorter.Repo,
  username: "postgres",
  password: "your_password",
  hostname: "localhost",
  database: "jumpapp_email_sorter_dev"
```

### 7. Create and Migrate Database

```bash
mix ecto.create
mix ecto.migrate
```

### 8. Start the Server

```bash
mix phx.server
```

Visit `http://localhost:4000`

## Usage

### Getting Started

1. **Sign in with Google** - Click "Sign in with Google" and authorize the app
2. **Create Categories** - Add categories like "Newsletters", "Receipts", "Work", etc.
   - Give each category a descriptive name and description to help AI understand what belongs there
3. **Wait for Emails** - The system polls Gmail every 3 minutes for new unread emails
4. **View Categorized Emails** - Click on a category to see all emails sorted into it
5. **Manage Emails** - Select emails to delete or unsubscribe in bulk

### Adding Multiple Accounts

- Click "Add Account" on the dashboard
- Sign in with another Gmail account
- All accounts will be monitored for new emails

### Unsubscribe Feature

The app intelligently handles unsubscribe requests:
- Extracts unsubscribe links from email headers and body
- Attempts one-click unsubscribe for simple cases
- Uses AI to analyze and submit unsubscribe forms
- Shows status of unsubscribe attempts

## Project Structure

```
lib/
├── jumpapp_email_sorter/
│   ├── accounts.ex              # User & Gmail account management
│   ├── categories.ex            # Category CRUD operations
│   ├── emails.ex                # Email queries & operations
│   ├── gmail_client.ex          # Gmail API wrapper
│   ├── ai_service.ex            # AI categorization & summarization
│   ├── accounts/
│   │   ├── user.ex              # User schema
│   │   └── gmail_account.ex     # Gmail account schema
│   ├── categories/
│   │   └── category.ex          # Category schema
│   ├── emails/
│   │   ├── email.ex             # Email schema
│   │   └── unsubscribe_attempt.ex
│   └── workers/
│       ├── gmail_poll_worker.ex       # Scheduled email polling
│       ├── email_import_worker.ex     # Email import & processing
│       └── unsubscribe_worker.ex      # Unsubscribe handling
├── jumpapp_email_sorter_web/
│   ├── controllers/
│   │   ├── auth_controller.ex         # OAuth callbacks
│   │   └── page_controller.ex         # Home page
│   ├── live/
│   │   ├── dashboard_live.ex          # Main dashboard
│   │   └── category_live.ex           # Category detail view
│   └── user_auth.ex                   # Authentication plugs
```

## Database Schema

- **users** - User accounts with Google OAuth tokens
- **gmail_accounts** - Connected Gmail accounts (supports multiple per user)
- **categories** - User-defined email categories
- **emails** - Imported and categorized emails
- **unsubscribe_attempts** - Tracking unsubscribe requests
- **oban_jobs** - Background job queue

## Background Jobs

- **GmailPollWorker** - Runs every 3 minutes to check for new emails across all accounts
- **EmailImportWorker** - Fetches, categorizes, summarizes, and archives individual emails
- **UnsubscribeWorker** - Processes unsubscribe requests

## API Rate Limits

- Gmail API: 250 quota units per user per second
- Anthropic API: Depends on your tier (free tier has limits)

The app handles rate limiting gracefully with retries and exponential backoff.

## Development

### Running Tests

```bash
mix test
```

### Code Formatting

```bash
mix format
```

### Linting

```bash
mix precommit
```

## Deployment to Fly.io

### 1. Install Fly CLI

```bash
# macOS/Linux
curl -L https://fly.io/install.sh | sh

# Windows
powershell -Command "iwr https://fly.io/install.ps1 -useb | iex"
```

### 2. Login to Fly

```bash
fly auth login
```

### 3. Launch the App

```bash
fly launch
```

### 4. Set Secrets

```bash
fly secrets set GOOGLE_CLIENT_ID="your_client_id"
fly secrets set GOOGLE_CLIENT_SECRET="your_client_secret"
fly secrets set ANTHROPIC_API_KEY="your_api_key"
```

### 5. Update OAuth Redirect URI

Add your Fly.io URL to Google OAuth authorized redirect URIs:
- `https://your-app.fly.dev/auth/google/callback`

### 6. Deploy

```bash
fly deploy
```

## Important Notes for Submission

### Google OAuth Test Users

Since this app requires Gmail API scopes, it needs to be in "Testing" mode in Google Cloud Console. To allow the reviewer to test:

1. Go to Google Cloud Console → OAuth consent screen
2. Add the reviewer's Gmail address as a test user
3. The app will work for test users without going through Google's verification process

**Please add the reviewer's email as a test user before submission.**

### Environment Variables

Make sure all environment variables are set in production:
- `GOOGLE_CLIENT_ID`
- `GOOGLE_CLIENT_SECRET`
- `ANTHROPIC_API_KEY`
- `SECRET_KEY_BASE` (generated automatically by Fly.io)
- `DATABASE_URL` (provided by Fly.io PostgreSQL)

## Troubleshooting

### Emails Not Being Imported

- Check that Gmail API is enabled in Google Cloud Console
- Verify OAuth scopes include `gmail.modify` and `gmail.readonly`
- Check Oban dashboard at `/dev/dashboard` (in development) for job failures

### AI Categorization Not Working

- Verify `ANTHROPIC_API_KEY` is set correctly
- Check API usage limits
- Review logs for AI service errors

### Database Connection Issues

- Ensure PostgreSQL is running
- Verify database credentials in `config/dev.exs`
- Check that database exists: `mix ecto.create`

## License

This project is created as part of a recruitment challenge.

## Support

For issues or questions, please open an issue on GitHub.
