# Setup Notes

## Current Status

### ✅ Completed
1. Phoenix project initialized with LiveView and PostgreSQL
2. All dependencies added (Ueberauth, Oban, Floki, etc.)
3. Database migrations created for:
   - users
   - gmail_accounts
   - categories
   - emails
   - unsubscribe_attempts
   - oban_jobs
4. Ecto schemas created for all tables
5. Context modules created (Accounts, Categories, Emails)
6. OAuth configuration added for Google
7. Auth controller and routes set up
8. UserAuth module for authentication
9. Home page with "Sign in with Google" button

### ⚠️ PostgreSQL Setup Required

The database needs to be configured before running the app. Update `config/dev.exs` with your PostgreSQL credentials:

```elixir
config :jumpapp_email_sorter, JumpappEmailSorter.Repo,
  username: "postgres",
  password: "YOUR_PASSWORD_HERE",  # Update this!
  hostname: "localhost",
  database: "jumpapp_email_sorter_dev"
```

Then run:
```bash
mix ecto.create
mix ecto.migrate
```

### 🔑 Environment Variables Needed

Before running the app, set these environment variables (or create a `.env` file):

```bash
# Google OAuth (get from https://console.cloud.google.com/)
export GOOGLE_CLIENT_ID="your_client_id"
export GOOGLE_CLIENT_SECRET="your_client_secret"

# OpenAI API (get from https://platform.openai.com)
export OPENAI_API_KEY="your_api_key"
```

### 📋 Next Steps

1. **Gmail API Client** - Create wrapper for Gmail API calls
2. **AI Service** - Implement email categorization and summarization
3. **Background Workers** - Create Oban workers for email polling
4. **Dashboard LiveView** - Main UI for managing categories
5. **Category Detail LiveView** - View and manage emails in categories
6. **Unsubscribe Service** - Intelligent unsubscribe functionality
7. **Tests** - Unit and integration tests
8. **Deployment** - Deploy to Fly.io

### 🚀 Running the App

Once PostgreSQL and environment variables are configured:

```bash
mix phx.server
```

Visit `http://localhost:4000`

