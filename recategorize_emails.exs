import Ecto.Query
alias JumpappEmailSorter.{Repo, Emails, Categories, AIService}
alias JumpappEmailSorter.Emails.Email

# Get all uncategorized emails
uncategorized = Repo.all(
  from e in Email,
  where: is_nil(e.category_id),
  preload: [:gmail_account]
)

IO.puts("Found #{length(uncategorized)} uncategorized emails")

# Get user's categories (assuming user_id = 1, adjust if needed)
user_id = 1
categories = Categories.list_categories(user_id)

IO.puts("Found #{length(categories)} categories")

if length(categories) == 0 do
  IO.puts("ERROR: No categories found! Create categories first.")
  System.halt(1)
end

# Recategorize each email
Enum.each(uncategorized, fn email ->
  email_content = """
  Subject: #{email.subject}
  From: #{email.from_name} <#{email.from_email}>
  Body: #{email.body_text || email.body_preview}
  """

  case AIService.categorize_email(email_content, categories) do
    {:ok, category_id} when not is_nil(category_id) ->
      {:ok, updated} = Emails.update_email(email, %{category_id: category_id})
      category = Enum.find(categories, fn c -> c.id == category_id end)
      IO.puts("✓ Email #{email.id}: #{email.subject} → [#{category.name}]")

    {:ok, nil} ->
      IO.puts("○ Email #{email.id}: #{email.subject} → [no match]")

    {:error, reason} ->
      IO.puts("✗ Email #{email.id}: Failed - #{inspect(reason)}")
  end

  # Small delay to avoid rate limiting
  Process.sleep(100)
end)

IO.puts("\n✓ Done!")

