import Ecto.Query
alias JumpappEmailSorter.Repo
alias JumpappEmailSorter.Emails.Email

emails = Repo.all(
  from e in Email,
  order_by: [desc: e.inserted_at],
  limit: 5,
  select: %{
    id: e.id,
    subject: e.subject,
    summary: fragment("LEFT(?, 60)", e.summary),
    category_id: e.category_id,
    inserted_at: e.inserted_at
  }
)

IO.puts("\n=== Recent Emails ===")
IO.puts("Total emails: #{Repo.aggregate(Email, :count)}")
IO.puts("\nLast 5 emails:")

Enum.each(emails, fn email ->
  IO.puts("\n#{email.id}. #{email.subject}")
  IO.puts("   Summary: #{email.summary}")
  IO.puts("   Category: #{email.category_id || "uncategorized"}")
  IO.puts("   Inserted: #{email.inserted_at}")
end)

