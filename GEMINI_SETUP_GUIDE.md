# Google Gemini API Setup Guide

## Why Gemini?

We switched to Google Gemini because it offers:
- **Completely free** with no time limits
- **15 requests per minute** (vs OpenAI's 3 RPM on free tier)
- **1,500 requests per day** (vs OpenAI's 200 RPD)
- **1 million tokens per minute**
- **No credit card required**
- High quality responses comparable to GPT-4

## How to Get Your API Key

### Step 1: Go to Google AI Studio
Visit: https://aistudio.google.com

### Step 2: Sign In
- Sign in with your Google account
- Accept the terms of service

### Step 3: Get API Key
1. Click **"Get API Key"** in the left sidebar
2. Click **"Create API Key"**
3. You'll be prompted to select or create a Google Cloud project:
   - If you have an existing project, select it
   - Or click "Create API key in new project"
4. Copy the API key (it will look like: `AIzaSy...`)

### Step 4: Add to Your .env File
Open your `.env` file and add:
```bash
GOOGLE_GEMINI_API_KEY=AIzaSy...your_key_here...
```

## Testing the Integration

Run the test suite to verify everything is working:
```bash
mix test test/jumpapp_email_sorter/ai_service_test.exs
```

You should see:
```
✅ Google Gemini API is working!
✅ Email categorization is working!
```

## Rate Limits

### Free Tier Limits (Gemini 1.5 Flash):
- **15 RPM** (Requests Per Minute)
- **1,500 RPD** (Requests Per Day)
- **1 million TPM** (Tokens Per Minute)

This is more than enough for development and testing!

## Model Information

We're using **Gemini 1.5 Flash** which is:
- Fast and efficient
- Great for production use
- Optimized for speed
- High quality responses

## Troubleshooting

### "API key not set" error
Make sure your `.env` file has:
```bash
GOOGLE_GEMINI_API_KEY=your_actual_key_here
```

### Rate limit errors
If you hit rate limits:
- Wait 1 minute before trying again
- The free tier resets every minute (15 requests)
- Daily limit resets at midnight UTC

### API key not working
1. Make sure you copied the entire key
2. Check there are no extra spaces
3. Verify the key is active in Google AI Studio
4. Try regenerating the key if needed

## Additional Resources

- [Google AI Studio](https://aistudio.google.com)
- [Gemini API Documentation](https://ai.google.dev/docs)
- [Pricing & Limits](https://ai.google.dev/pricing)

## Next Steps

Once you have your API key set up:
1. Start the server: `mix phx.server`
2. Visit: http://localhost:4000
3. Sign in with Google
4. Create categories and let the AI categorize your emails!

