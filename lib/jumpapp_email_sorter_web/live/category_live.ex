defmodule JumpappEmailSorterWeb.CategoryLive do
  use JumpappEmailSorterWeb, :live_view

  alias JumpappEmailSorter.{Categories, Emails}
  alias JumpappEmailSorter.Workers.UnsubscribeWorker

  @impl true
  def mount(%{"id" => category_id}, _session, socket) do
    user = socket.assigns.current_user
    category = Categories.get_user_category(user.id, category_id)

    if category do
      emails = Emails.list_emails_by_category(category.id)

      socket =
        socket
        |> assign(:category, category)
        |> assign(:emails, emails)
        |> assign(:selected_emails, MapSet.new())
        |> assign(:show_email_modal, false)
        |> assign(:selected_email, nil)

      {:ok, socket}
    else
      {:ok,
       socket
       |> put_flash(:error, "Category not found")
       |> redirect(to: "/dashboard")}
    end
  end

  @impl true
  def handle_event("toggle_select", %{"id" => email_id}, socket) do
    email_id = String.to_integer(email_id)
    selected = socket.assigns.selected_emails

    selected =
      if MapSet.member?(selected, email_id) do
        MapSet.delete(selected, email_id)
      else
        MapSet.put(selected, email_id)
      end

    {:noreply, assign(socket, :selected_emails, selected)}
  end

  @impl true
  def handle_event("select_all", _params, socket) do
    all_ids = Enum.map(socket.assigns.emails, & &1.id) |> MapSet.new()
    {:noreply, assign(socket, :selected_emails, all_ids)}
  end

  @impl true
  def handle_event("deselect_all", _params, socket) do
    {:noreply, assign(socket, :selected_emails, MapSet.new())}
  end

  @impl true
  def handle_event("delete_selected", _params, socket) do
    selected_ids = MapSet.to_list(socket.assigns.selected_emails)

    if selected_ids != [] do
      Emails.delete_emails(selected_ids)

      emails = Emails.list_emails_by_category(socket.assigns.category.id)

      socket =
        socket
        |> assign(:emails, emails)
        |> assign(:selected_emails, MapSet.new())
        |> put_flash(:info, "Deleted #{length(selected_ids)} email(s)")

      {:noreply, socket}
    else
      {:noreply, put_flash(socket, :error, "No emails selected")}
    end
  end

  @impl true
  def handle_event("unsubscribe_selected", _params, socket) do
    selected_ids = MapSet.to_list(socket.assigns.selected_emails)

    if selected_ids != [] do
      # Queue unsubscribe jobs
      Enum.each(selected_ids, fn email_id ->
        %{email_id: email_id}
        |> UnsubscribeWorker.new()
        |> Oban.insert()
      end)

      socket =
        socket
        |> assign(:selected_emails, MapSet.new())
        |> put_flash(:info, "Queued #{length(selected_ids)} unsubscribe request(s)")

      {:noreply, socket}
    else
      {:noreply, put_flash(socket, :error, "No emails selected")}
    end
  end

  @impl true
  def handle_event("show_email", %{"id" => email_id}, socket) do
    email = Emails.get_email!(email_id)

    socket =
      socket
      |> assign(:show_email_modal, true)
      |> assign(:selected_email, email)

    {:noreply, socket}
  end

  @impl true
  def handle_event("hide_email_modal", _params, socket) do
    {:noreply, assign(socket, show_email_modal: false, selected_email: nil)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-gray-50">
      <div class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-8">
        <%!-- Header --%>
        <div class="mb-8">
          <a href="/dashboard" class="text-blue-600 hover:text-blue-700 mb-4 inline-block">
            ← Back to Dashboard
          </a>
          <h1 class="text-3xl font-bold text-gray-900">{@category.name}</h1>
          <p class="mt-2 text-gray-600">{@category.description || "No description"}</p>
        </div>

        <%!-- Bulk Actions --%>
        <%= if MapSet.size(@selected_emails) > 0 do %>
          <div class="bg-blue-50 border border-blue-200 rounded-lg p-4 mb-6">
            <div class="flex items-center justify-between">
              <span class="text-blue-900 font-medium">
                {MapSet.size(@selected_emails)} email(s) selected
              </span>
              <div class="flex space-x-3">
                <button
                  phx-click="deselect_all"
                  class="px-4 py-2 text-blue-700 hover:bg-blue-100 rounded-md transition-colors"
                >
                  Deselect All
                </button>
                <button
                  phx-click="unsubscribe_selected"
                  class="px-4 py-2 bg-yellow-600 text-white rounded-md hover:bg-yellow-700 transition-colors"
                >
                  Unsubscribe
                </button>
                <button
                  phx-click="delete_selected"
                  data-confirm="Are you sure you want to delete the selected emails?"
                  class="px-4 py-2 bg-red-600 text-white rounded-md hover:bg-red-700 transition-colors"
                >
                  Delete
                </button>
              </div>
            </div>
          </div>
        <% end %>

        <%!-- Emails List --%>
        <div class="bg-white rounded-lg shadow">
          <%= if @emails == [] do %>
            <div class="text-center py-12">
              <p class="text-gray-500">No emails in this category yet.</p>
            </div>
          <% else %>
            <div class="divide-y divide-gray-200">
              <div class="p-4 bg-gray-50 flex items-center space-x-4">
                <input
                  type="checkbox"
                  phx-click={
                    if MapSet.size(@selected_emails) == length(@emails),
                      do: "deselect_all",
                      else: "select_all"
                  }
                  checked={MapSet.size(@selected_emails) == length(@emails)}
                  class="w-4 h-4 text-blue-600 rounded"
                />
                <span class="text-sm font-medium text-gray-700">Select All</span>
              </div>

              <%= for email <- @emails do %>
                <div class="p-4 hover:bg-gray-50 transition-colors">
                  <div class="flex items-start space-x-4">
                    <input
                      type="checkbox"
                      phx-click="toggle_select"
                      phx-value-id={email.id}
                      checked={MapSet.member?(@selected_emails, email.id)}
                      class="mt-1 w-4 h-4 text-blue-600 rounded"
                    />

                    <div class="flex-1 min-w-0 cursor-pointer" phx-click="show_email" phx-value-id={email.id}>
                      <div class="flex items-start justify-between">
                        <div class="flex-1">
                          <p class="text-sm font-medium text-gray-900">
                            {email.from_name || email.from_email}
                          </p>
                          <p class="text-sm text-gray-500">{email.from_email}</p>
                        </div>
                        <span class="text-xs text-gray-500">
                          {format_date(email.received_at)}
                        </span>
                      </div>

                      <h3 class="mt-2 text-base font-semibold text-gray-900">
                        {email.subject || "(No subject)"}
                      </h3>

                      <p class="mt-1 text-sm text-gray-600 line-clamp-2">
                        {email.summary || email.body_preview}
                      </p>
                    </div>
                  </div>
                </div>
              <% end %>
            </div>
          <% end %>
        </div>
      </div>
    </div>

    <%!-- Email Detail Modal --%>
    <%= if @show_email_modal && @selected_email do %>
      <div
        class="fixed inset-0 bg-black bg-opacity-50 flex items-center justify-center z-50 p-4"
        phx-click="hide_email_modal"
      >
        <div
          class="bg-white rounded-lg shadow-xl w-full max-w-3xl max-h-[90vh] overflow-y-auto"
          onclick="event.stopPropagation()"
        >
          <div class="sticky top-0 bg-white border-b border-gray-200 p-6">
            <div class="flex items-start justify-between">
              <div class="flex-1">
                <h2 class="text-2xl font-bold text-gray-900">
                  {@selected_email.subject || "(No subject)"}
                </h2>
                <div class="mt-2 text-sm text-gray-600">
                  <p>
                    <span class="font-medium">From:</span>
                    {@selected_email.from_name || @selected_email.from_email}
                    &lt;{@selected_email.from_email}&gt;
                  </p>
                  <p>
                    <span class="font-medium">Date:</span>
                    {format_full_date(@selected_email.received_at)}
                  </p>
                </div>
              </div>
              <button
                phx-click="hide_email_modal"
                class="ml-4 text-gray-400 hover:text-gray-600"
              >
                <.icon name="hero-x-mark" class="w-6 h-6" />
              </button>
            </div>
          </div>

          <div class="p-6">
            <%= if @selected_email.summary do %>
              <div class="mb-4 p-4 bg-blue-50 border border-blue-200 rounded-lg">
                <p class="text-sm font-medium text-blue-900 mb-1">AI Summary</p>
                <p class="text-blue-800">{@selected_email.summary}</p>
              </div>
            <% end %>

            <div class="prose max-w-none">
              <pre class="whitespace-pre-wrap text-sm text-gray-700 font-sans">
                {@selected_email.body_text || @selected_email.body_preview}
              </pre>
            </div>
          </div>
        </div>
      </div>
    <% end %>
    """
  end

  defp format_date(datetime) do
    Calendar.strftime(datetime, "%b %d")
  end

  defp format_full_date(datetime) do
    Calendar.strftime(datetime, "%B %d, %Y at %I:%M %p")
  end
end

