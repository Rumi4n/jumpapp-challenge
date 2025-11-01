defmodule JumpappEmailSorterWeb.DashboardLive do
  use JumpappEmailSorterWeb, :live_view

  alias JumpappEmailSorter.{Categories, Accounts}

  @impl true
  def mount(_params, _session, socket) do
    user = socket.assigns.current_user

    # Subscribe to email updates for this user
    if connected?(socket) do
      Phoenix.PubSub.subscribe(JumpappEmailSorter.PubSub, "user:#{user.id}")
    end

    # Load data
    categories = Categories.list_categories_with_counts(user.id)
    gmail_accounts = Accounts.list_gmail_accounts(user.id)

    socket =
      socket
      |> assign(:categories, categories)
      |> assign(:gmail_accounts, gmail_accounts)
      |> assign(:show_category_modal, false)
      |> assign(:category_form, to_form(%{}))

    {:ok, socket}
  end

  @impl true
  def handle_event("show_add_category", _params, socket) do
    changeset = Categories.change_category(%JumpappEmailSorter.Categories.Category{})
    {:noreply, assign(socket, show_category_modal: true, category_form: to_form(changeset))}
  end

  @impl true
  def handle_event("hide_category_modal", _params, socket) do
    {:noreply, assign(socket, show_category_modal: false)}
  end

  @impl true
  def handle_event("save_category", %{"category" => category_params}, socket) do
    case Categories.create_category(socket.assigns.current_user.id, category_params) do
      {:ok, _category} ->
        categories = Categories.list_categories_with_counts(socket.assigns.current_user.id)

        socket =
          socket
          |> assign(:categories, categories)
          |> assign(:show_category_modal, false)
          |> put_flash(:info, "Category created successfully!")

        {:noreply, socket}

      {:error, changeset} ->
        socket =
          socket
          |> assign(:category_form, to_form(changeset))
          |> put_flash(:error, "Failed to create category. Please check the form.")

        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("delete_category", %{"id" => id}, socket) do
    category = Categories.get_category!(id)

    case Categories.delete_category(category) do
      {:ok, _} ->
        categories = Categories.list_categories_with_counts(socket.assigns.current_user.id)

        socket =
          socket
          |> assign(:categories, categories)
          |> put_flash(:info, "Category deleted successfully!")

        {:noreply, socket}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to delete category")}
    end
  end

  @impl true
  def handle_info({:email_imported, _email}, socket) do
    # Reload categories with updated counts
    categories = Categories.list_categories_with_counts(socket.assigns.current_user.id)
    {:noreply, assign(socket, :categories, categories)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <div class="min-h-screen bg-gray-50">
        <div class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-8">
          <%!-- Header --%>
          <div class="mb-8">
            <h1 class="text-3xl font-bold text-gray-900">Email Dashboard</h1>
            
            <p class="mt-2 text-gray-600">Manage your email categories and accounts</p>
          </div>
           <%!-- Gmail Accounts Section --%>
          <div class="bg-white rounded-lg shadow p-6 mb-8">
            <div class="flex items-center justify-between mb-4">
              <h2 class="text-xl font-semibold text-gray-900">Connected Accounts</h2>
              
              <a
                href="/auth/google"
                class="px-4 py-2 bg-blue-600 text-white rounded-md hover:bg-blue-700 transition-colors"
              >
                + Add Account
              </a>
            </div>
            
            <%= if @gmail_accounts == [] do %>
              <p class="text-gray-500 text-center py-8">
                No Gmail accounts connected yet. Click "Add Account" to get started.
              </p>
            <% else %>
              <div class="space-y-3">
                <%= for account <- @gmail_accounts do %>
                  <div class="flex items-center justify-between p-4 bg-gray-50 rounded-lg">
                    <div class="flex items-center space-x-3">
                      <div class="w-10 h-10 bg-blue-500 rounded-full flex items-center justify-center text-white font-semibold">
                        {String.first(account.email)}
                      </div>
                      
                      <div>
                        <p class="font-medium text-gray-900">{account.email}</p>
                        
                        <p class="text-sm text-gray-500">
                          Connected {Calendar.strftime(account.inserted_at, "%B %d, %Y")}
                        </p>
                      </div>
                    </div>
                  </div>
                <% end %>
              </div>
            <% end %>
          </div>
           <%!-- Categories Section --%>
          <div class="bg-white rounded-lg shadow p-6">
            <div class="flex items-center justify-between mb-6">
              <h2 class="text-xl font-semibold text-gray-900">Email Categories</h2>
              
              <button
                phx-click="show_add_category"
                class="px-4 py-2 bg-green-600 text-white rounded-md hover:bg-green-700 transition-colors"
              >
                + New Category
              </button>
            </div>
            
            <%= if @categories == [] do %>
              <div class="text-center py-12">
                <p class="text-gray-500 mb-4">
                  No categories yet. Create your first category to start organizing emails!
                </p>
                
                <button
                  phx-click="show_add_category"
                  class="px-6 py-3 bg-green-600 text-white rounded-md hover:bg-green-700 transition-colors"
                >
                  Create First Category
                </button>
              </div>
            <% else %>
              <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
                <%= for %{category: category, email_count: count} <- @categories do %>
                  <a
                    href={"/categories/#{category.id}"}
                    class="block p-6 bg-gradient-to-br from-white to-gray-50 border-2 border-gray-200 rounded-lg hover:border-blue-500 hover:shadow-lg transition-all"
                  >
                    <div class="flex items-start justify-between">
                      <div class="flex-1">
                        <h3 class="text-lg font-semibold text-gray-900 mb-2">{category.name}</h3>
                        
                        <p class="text-sm text-gray-600 mb-4 line-clamp-2">
                          {category.description || "No description"}
                        </p>
                        
                        <div class="flex items-center justify-between">
                          <span class="inline-flex items-center px-3 py-1 rounded-full text-sm font-medium bg-blue-100 text-blue-800">
                            {count} {if count == 1, do: "email", else: "emails"}
                          </span>
                        </div>
                      </div>
                      
                      <button
                        phx-click="delete_category"
                        phx-value-id={category.id}
                        data-confirm="Are you sure you want to delete this category?"
                        class="ml-2 text-gray-400 hover:text-red-600 transition-colors"
                        onclick="event.preventDefault(); event.stopPropagation(); if(confirm('Are you sure?')) { this.dispatchEvent(new Event('click', {bubbles: true})); }"
                      >
                        <.icon name="hero-trash" class="w-5 h-5" />
                      </button>
                    </div>
                  </a>
                <% end %>
              </div>
            <% end %>
          </div>
        </div>
      </div>
       <%!-- Add Category Modal --%>
      <%= if @show_category_modal do %>
        <div class="fixed inset-0 bg-black bg-opacity-50 flex items-center justify-center z-50">
          <div class="bg-white rounded-lg shadow-xl p-6 w-full max-w-md">
            <h3 class="text-xl font-semibold text-gray-900 mb-4">Create New Category</h3>
            
            <.form for={@category_form} phx-submit="save_category" id="category-form">
              <div class="space-y-4">
                <div>
                  <label class="block text-sm font-medium text-gray-700 mb-1">Category Name</label>
                  <.input
                    field={@category_form[:name]}
                    type="text"
                    placeholder="e.g., Newsletters, Receipts, Work"
                    required
                  />
                </div>
                
                <div>
                  <label class="block text-sm font-medium text-gray-700 mb-1">Description</label>
                  <.input
                    field={@category_form[:description]}
                    type="textarea"
                    placeholder="Help AI understand what emails belong in this category..."
                    rows="3"
                  />
                </div>
                
                <div class="flex justify-end space-x-3 mt-6">
                  <button
                    type="button"
                    phx-click="hide_category_modal"
                    class="px-4 py-2 border border-gray-300 rounded-md text-gray-700 hover:bg-gray-50 transition-colors"
                  >
                    Cancel
                  </button>
                  <button
                    type="submit"
                    class="px-4 py-2 bg-green-600 text-white rounded-md hover:bg-green-700 transition-colors"
                  >
                    Create Category
                  </button>
                </div>
              </div>
            </.form>
          </div>
        </div>
      <% end %>
    </Layouts.app>
    """
  end
end
