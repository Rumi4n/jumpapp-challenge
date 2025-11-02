ExUnit.start()
Ecto.Adapters.SQL.Sandbox.mode(JumpappEmailSorter.Repo, :manual)

# Set up Mox for mocking
Mox.defmock(JumpappEmailSorter.GmailClientMock, for: JumpappEmailSorter.GmailClientBehaviour)
Mox.defmock(JumpappEmailSorter.AIServiceMock, for: JumpappEmailSorter.AIServiceBehaviour)
