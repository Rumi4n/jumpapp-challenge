# Script to list available Gemini models
# Run with: mix run scripts/list_gemini_models.exs

api_key = System.get_env("GOOGLE_GEMINI_API_KEY")

if !api_key do
  IO.puts("❌ GOOGLE_GEMINI_API_KEY not set in environment")
  System.halt(1)
end

IO.puts("🔍 Fetching available Gemini models...\n")

url = "https://generativelanguage.googleapis.com/v1beta/models?key=#{api_key}"

case Req.get(url) do
  {:ok, %{status: 200, body: response}} ->
    models = response["models"] || []
    
    IO.puts("✅ Found #{length(models)} models:\n")
    
    Enum.each(models, fn model ->
      name = model["name"]
      display_name = model["displayName"]
      description = model["description"]
      supported_methods = model["supportedGenerationMethods"] || []
      
      IO.puts("📦 Model: #{name}")
      IO.puts("   Display Name: #{display_name}")
      IO.puts("   Description: #{String.slice(description || "N/A", 0, 100)}...")
      IO.puts("   Supported Methods: #{Enum.join(supported_methods, ", ")}")
      IO.puts("")
    end)
    
    # Find models that support generateContent
    content_models = Enum.filter(models, fn model ->
      methods = model["supportedGenerationMethods"] || []
      "generateContent" in methods
    end)
    
    IO.puts("\n✅ Models that support generateContent (#{length(content_models)}):\n")
    
    Enum.each(content_models, fn model ->
      name = model["name"] |> String.replace("models/", "")
      IO.puts("   - #{name}")
    end)
    
    # Suggest the best model
    flash_model = Enum.find(content_models, fn model ->
      String.contains?(model["name"], "flash")
    end)
    
    if flash_model do
      suggested_name = flash_model["name"] |> String.replace("models/", "")
      IO.puts("\n💡 Suggested model for your app: #{suggested_name}")
    end

  {:ok, %{status: status, body: body}} ->
    IO.puts("❌ API Error: #{status}")
    IO.inspect(body, label: "Response")

  {:error, error} ->
    IO.puts("❌ Request failed:")
    IO.inspect(error)
end

