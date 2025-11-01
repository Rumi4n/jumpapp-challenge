# Database Setup Guide

## Issue: Categories Not Being Saved

If you're experiencing issues with categories not being saved or listed on the Dashboard, it's likely due to a **database connection problem**.

## Root Cause

The application was unable to connect to PostgreSQL because of incorrect database credentials. The error message you might see in logs:

```
FATAL 28P01 (invalid_password) password authentication failed for user "postgres"
```

## Solution

### Step 1: Update Your `.env` File

Edit your `.env` file in the project root and set the correct PostgreSQL credentials:

```bash
# Database Configuration
POSTGRES_USER=postgres
POSTGRES_PASSWORD=your_actual_postgres_password
POSTGRES_HOST=localhost
POSTGRES_DB=jumpapp_email_sorter_dev
```

**Important:** Replace `your_actual_postgres_password` with your actual PostgreSQL password.

### Step 2: Verify PostgreSQL is Running

Make sure PostgreSQL is running on your system:

**Windows:**
```powershell
# Check if PostgreSQL service is running
Get-Service -Name postgresql*
```

**If not running, start it:**
```powershell
Start-Service postgresql-x64-16  # Adjust version number as needed
```

### Step 3: Create the Database

Once your credentials are correct, create the database:

```bash
mix ecto.create
```

### Step 4: Run Migrations

Ensure all database tables are created:

```bash
mix ecto.migrate
```

### Step 5: Restart Your Phoenix Server

Stop your current server (Ctrl+C) and restart it:

```bash
mix phx.server
```

## Verification

To verify the database connection is working:

1. Go to the Dashboard (`http://localhost:4000/dashboard`)
2. Click "New Category"
3. Fill in the form with:
   - **Category Name:** Test Category
   - **Description:** This is a test category
4. Click "Create Category"
5. You should see:
   - A success flash message: "Category created successfully!"
   - The category should appear in the list

## Alternative: Use DATABASE_URL

Instead of individual environment variables, you can use a single `DATABASE_URL`:

```bash
DATABASE_URL=ecto://postgres:your_password@localhost/jumpapp_email_sorter_dev
```

## Common Issues

### Issue: "database does not exist"
**Solution:** Run `mix ecto.create`

### Issue: "relation does not exist"
**Solution:** Run `mix ecto.migrate`

### Issue: Still getting password errors
**Solution:** 
1. Verify your PostgreSQL password by connecting with `psql`:
   ```bash
   psql -U postgres -h localhost
   ```
2. If you can't remember your password, you may need to reset it in PostgreSQL

### Issue: PostgreSQL not installed
**Solution:** Install PostgreSQL from https://www.postgresql.org/download/

## What Was Fixed

1. **Updated `config/dev.exs`:** Changed hardcoded database credentials to use environment variables
2. **Updated `env.example`:** Added clear documentation for database configuration
3. **Fixed DashboardLive:** Added proper flash message display by wrapping content in `<Layouts.app>`
4. **Improved error handling:** Added better error messages when category creation fails
5. **Fixed `Categories.create_category/2`:** Ensured proper parameter handling

## Testing the Fix

After following the steps above, test the category functionality:

1. **Create a category:** Should see success message and category appears in list
2. **Delete a category:** Click the trash icon, confirm, category should be removed
3. **View category details:** Click on a category card to view its emails (when implemented)

## Need Help?

If you're still experiencing issues:

1. Check the Phoenix server logs for error messages
2. Verify your `.env` file is in the project root
3. Ensure PostgreSQL is running and accepting connections
4. Try connecting to PostgreSQL directly with `psql` to verify credentials

