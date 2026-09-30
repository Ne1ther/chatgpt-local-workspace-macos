// Compatibility boundary: keep the upstream MCP core and its wire format intact.
using System;
using System.Collections.Generic;
using System.Linq;
using System.Text.Json;
using System.Text.Encodings.Web;

namespace System.Web.Script.Serialization
{
    sealed class JavaScriptSerializer
    {
        public int MaxJsonLength { get; set; } = 8 * 1024 * 1024;
        static readonly JsonSerializerOptions Options = new JsonSerializerOptions {
            IncludeFields = true, Encoder = JavaScriptEncoder.UnsafeRelaxedJsonEscaping,
            MaxDepth = 100
        };
        public string Serialize(object value) => JsonSerializer.Serialize(value, Options);
        public T Deserialize<T>(string text)
        {
            if (text.Length > MaxJsonLength) throw new ArgumentException("JSON exceeds the size limit");
            using var document = JsonDocument.Parse(text, new JsonDocumentOptions { MaxDepth = 100 });
            return (T)Read(document.RootElement);
        }
        static object Read(JsonElement value)
        {
            switch (value.ValueKind) {
                case JsonValueKind.Object: return value.EnumerateObject().ToDictionary(p => p.Name, p => Read(p.Value));
                case JsonValueKind.Array: return value.EnumerateArray().Select(Read).ToArray();
                case JsonValueKind.String: return value.GetString();
                case JsonValueKind.Number: return value.TryGetInt64(out long n) ? (object)n : value.GetDouble();
                case JsonValueKind.True: return true;
                case JsonValueKind.False: return false;
                default: return null;
            }
        }
    }
}

namespace System.Windows.Forms
{
    // No Windows Forms runtime is referenced by the Mac build.
    static class Application { public static string ExecutablePath => Environment.ProcessPath; }
}
