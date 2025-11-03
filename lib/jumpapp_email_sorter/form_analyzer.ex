defmodule JumpappEmailSorter.FormAnalyzer do
  @moduledoc """
  Analyzes HTML pages to extract form structure, fields, and interactive elements.
  Used by the AI agent to understand how to interact with unsubscribe pages.
  """

  require Logger

  @doc """
  Analyzes an HTML page and extracts structured information about forms,
  buttons, and links that might be used for unsubscribing.
  """
  def analyze_page(html) when is_binary(html) do
    case Floki.parse_document(html) do
      {:ok, document} ->
        {:ok,
         %{
           forms: extract_forms(document),
           buttons: extract_buttons(document),
           links: extract_unsubscribe_links(document),
           page_text: extract_visible_text(document)
         }}

      {:error, error} ->
        Logger.error("Failed to parse HTML: #{inspect(error)}")
        {:error, :parse_failed}
    end
  end

  def analyze_page(_), do: {:error, :invalid_html}

  # Extracts all forms from the document with their fields and attributes.
  defp extract_forms(document) do
    document
    |> Floki.find("form")
    |> Enum.with_index()
    |> Enum.map(fn {form, index} -> parse_form(form, index) end)
  end

  defp parse_form(form, index) do
    action = Floki.attribute(form, "action") |> List.first()
    method = Floki.attribute(form, "method") |> List.first() || "post"
    form_id = Floki.attribute(form, "id") |> List.first()
    form_class = Floki.attribute(form, "class") |> List.first()

    %{
      index: index,
      id: form_id,
      class: form_class,
      action: action,
      method: String.downcase(method),
      fields: extract_form_fields(form),
      submit_buttons: extract_submit_buttons(form)
    }
  end

  # Extracts all input fields, selects, and textareas from a form.
  defp extract_form_fields(form) do
    inputs = extract_inputs(form)
    selects = extract_selects(form)
    textareas = extract_textareas(form)

    inputs ++ selects ++ textareas
  end

  defp extract_inputs(form) do
    form
    |> Floki.find("input")
    |> Enum.map(fn input ->
      type = Floki.attribute(input, "type") |> List.first() || "text"
      name = Floki.attribute(input, "name") |> List.first()
      id = Floki.attribute(input, "id") |> List.first()
      value = Floki.attribute(input, "value") |> List.first()
      required = Floki.attribute(input, "required") != []
      placeholder = Floki.attribute(input, "placeholder") |> List.first()

      %{
        element: "input",
        type: type,
        name: name,
        id: id,
        value: value,
        required: required,
        placeholder: placeholder,
        selector: build_selector("input", id, name, type)
      }
    end)
  end

  defp extract_selects(form) do
    form
    |> Floki.find("select")
    |> Enum.map(fn select ->
      name = Floki.attribute(select, "name") |> List.first()
      id = Floki.attribute(select, "id") |> List.first()
      required = Floki.attribute(select, "required") != []
      options = extract_select_options(select)

      %{
        element: "select",
        name: name,
        id: id,
        required: required,
        options: options,
        selector: build_selector("select", id, name)
      }
    end)
  end

  defp extract_select_options(select) do
    select
    |> Floki.find("option")
    |> Enum.map(fn option ->
      value = Floki.attribute(option, "value") |> List.first()
      text = Floki.text(option) |> String.trim()
      selected = Floki.attribute(option, "selected") != []

      %{value: value, text: text, selected: selected}
    end)
  end

  defp extract_textareas(form) do
    form
    |> Floki.find("textarea")
    |> Enum.map(fn textarea ->
      name = Floki.attribute(textarea, "name") |> List.first()
      id = Floki.attribute(textarea, "id") |> List.first()
      required = Floki.attribute(textarea, "required") != []
      placeholder = Floki.attribute(textarea, "placeholder") |> List.first()

      %{
        element: "textarea",
        name: name,
        id: id,
        required: required,
        placeholder: placeholder,
        selector: build_selector("textarea", id, name)
      }
    end)
  end

  defp extract_submit_buttons(form) do
    # Find submit buttons and input[type=submit]
    buttons =
      form
      |> Floki.find("button")
      |> Enum.filter(fn button ->
        type = Floki.attribute(button, "type") |> List.first() || "submit"
        type == "submit"
      end)
      |> Enum.map(&parse_button/1)

    submit_inputs =
      form
      |> Floki.find("input[type=submit]")
      |> Enum.map(&parse_button/1)

    buttons ++ submit_inputs
  end

  # Extracts all buttons from the document (not just in forms).
  defp extract_buttons(document) do
    document
    |> Floki.find("button, input[type=submit], input[type=button]")
    |> Enum.map(&parse_button/1)
  end

  defp parse_button(button) do
    {tag, _attrs, _children} = button
    type = Floki.attribute(button, "type") |> List.first() || "button"
    id = Floki.attribute(button, "id") |> List.first()
    class = Floki.attribute(button, "class") |> List.first()
    name = Floki.attribute(button, "name") |> List.first()
    value = Floki.attribute(button, "value") |> List.first()
    text = Floki.text(button) |> String.trim()

    %{
      tag: tag,
      type: type,
      id: id,
      class: class,
      name: name,
      value: value,
      text: text,
      selector: build_selector(tag, id, name, type),
      is_unsubscribe: looks_like_unsubscribe?(text, class, id)
    }
  end

  # Extracts links that might be unsubscribe links.
  defp extract_unsubscribe_links(document) do
    document
    |> Floki.find("a")
    |> Enum.map(fn link ->
      href = Floki.attribute(link, "href") |> List.first()
      text = Floki.text(link) |> String.trim()
      id = Floki.attribute(link, "id") |> List.first()
      class = Floki.attribute(link, "class") |> List.first()

      %{
        href: href,
        text: text,
        id: id,
        class: class,
        selector: build_selector("a", id, nil),
        is_unsubscribe: looks_like_unsubscribe?(text, class, id, href)
      }
    end)
    |> Enum.filter(fn link -> link.is_unsubscribe end)
  end

  # Extracts visible text from the page for context.
  defp extract_visible_text(document) do
    document
    |> Floki.find("body")
    |> Floki.text()
    |> String.trim()
    |> String.slice(0, 500)
  end

  # Builds a CSS selector for an element.
  defp build_selector(tag, id, name, type \\ nil) do
    cond do
      id && id != "" -> "##{id}"
      name && name != "" && type -> "#{tag}[name='#{name}'][type='#{type}']"
      name && name != "" -> "#{tag}[name='#{name}']"
      type -> "#{tag}[type='#{type}']"
      true -> tag
    end
  end

  # Determines if text/attributes suggest this is an unsubscribe element.
  defp looks_like_unsubscribe?(text, class \\ nil, id \\ nil, href \\ nil) do
    text_lower = String.downcase(text || "")
    class_lower = String.downcase(class || "")
    id_lower = String.downcase(id || "")
    href_lower = String.downcase(href || "")

    unsubscribe_patterns = [
      "unsubscribe",
      "opt out",
      "opt-out",
      "remove",
      "stop email",
      "manage preference",
      "email preference"
    ]

    Enum.any?(unsubscribe_patterns, fn pattern ->
      String.contains?(text_lower, pattern) ||
        String.contains?(class_lower, pattern) ||
        String.contains?(id_lower, pattern) ||
        String.contains?(href_lower, pattern)
    end)
  end

  @doc """
  Simplifies form structure for AI analysis by removing unnecessary details.
  """
  def simplify_for_ai(analysis) do
    %{
      forms:
        Enum.map(analysis.forms, fn form ->
          %{
            index: form.index,
            action: form.action,
            method: form.method,
            fields:
              Enum.map(form.fields, fn field ->
                %{
                  type: field.type || field.element,
                  name: field.name,
                  selector: field.selector,
                  required: field.required,
                  placeholder: field[:placeholder],
                  options: field[:options]
                }
              end),
            submit_buttons:
              Enum.map(form.submit_buttons, fn btn ->
                %{text: btn.text, selector: btn.selector}
              end)
          }
        end),
      standalone_buttons:
        analysis.buttons
        |> Enum.filter(fn btn -> btn.is_unsubscribe end)
        |> Enum.map(fn btn ->
          %{text: btn.text, selector: btn.selector}
        end),
      unsubscribe_links:
        Enum.map(analysis.links, fn link ->
          %{text: link.text, href: link.href, selector: link.selector}
        end),
      page_context: String.slice(analysis.page_text, 0, 300)
    }
  end
end

