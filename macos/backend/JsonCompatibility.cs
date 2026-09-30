// Compatibility boundary: keep the upstream MCP core and its wire format intact.
using System;
using System.Collections.Generic;
using System.Linq;
using System.Text.Json;
using System.Text.Json.Serialization;
using System.Text.Json.Serialization.Metadata;
using System.Text.Encodings.Web;

namespace System.Web.Script.Serialization
{
    [AttributeUsage(AttributeTargets.Field | AttributeTargets.Property, Inherited = true)]
    sealed class ScriptIgnoreAttribute : Attribute { }

    sealed class JavaScriptSerializer
    {
        int maxJsonLength = 8 * 1024 * 1024, recursionLimit = 100;
        JsonSerializerOptions options;
        public int MaxJsonLength {
            get => maxJsonLength;
            set { if (value < 1) throw new ArgumentOutOfRangeException(nameof(value)); maxJsonLength = value; }
        }
        public int RecursionLimit {
            get => recursionLimit;
            set { if (value < 1) throw new ArgumentOutOfRangeException(nameof(value)); recursionLimit = value; options = null; }
        }
        JsonSerializerOptions Options {
            get {
                if (options != null) return options;
                var resolver = new DefaultJsonTypeInfoResolver();
                resolver.Modifiers.Add(type => {
                    for (int i = type.Properties.Count - 1; i >= 0; i--)
                        if (type.Properties[i].AttributeProvider?.IsDefined(typeof(ScriptIgnoreAttribute), true) == true)
                            type.Properties.RemoveAt(i);
                });
                options = new JsonSerializerOptions {
                    IncludeFields = true, Encoder = JavaScriptEncoder.UnsafeRelaxedJsonEscaping,
                    MaxDepth = recursionLimit, TypeInfoResolver = resolver
                };
                options.Converters.Add(new DynamicValueConverter());
                return options;
            }
        }
        public string Serialize(object value) {
            string text = JsonSerializer.Serialize(value, Options);
            if (text.Length > MaxJsonLength) throw new ArgumentException("JSON exceeds the size limit");
            return text;
        }
        public T Deserialize<T>(string text)
        {
            if (text == null) throw new ArgumentNullException(nameof(text));
            if (text.Length > MaxJsonLength) throw new ArgumentException("JSON exceeds the size limit");
            // MCP arguments must keep the upstream dictionary/object[] representation.
            // Durable records, in contrast, require their real fields and DateTime values.
            if (typeof(T) == typeof(object) || typeof(T) == typeof(Dictionary<string, object>) || typeof(T) == typeof(object[])) {
                using var document = JsonDocument.Parse(text, new JsonDocumentOptions { MaxDepth = RecursionLimit });
                return (T)Read(document.RootElement);
            }
            return JsonSerializer.Deserialize<T>(text, Options);
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

        // object-typed fields in persisted records also need dictionaries, not JsonElement.
        sealed class DynamicValueConverter : JsonConverter<object>
        {
            public override object Read(ref Utf8JsonReader reader, Type type, JsonSerializerOptions options) {
                using var document = JsonDocument.ParseValue(ref reader);
                return JavaScriptSerializer.Read(document.RootElement);
            }
            public override void Write(Utf8JsonWriter writer, object value, JsonSerializerOptions options) {
                if (value == null) { writer.WriteNullValue(); return; }
                if (value.GetType() == typeof(object)) { writer.WriteStartObject(); writer.WriteEndObject(); return; }
                JsonSerializer.Serialize(writer, value, value.GetType(), options);
            }
        }
    }
}

namespace System.Windows.Forms
{
    // No Windows Forms runtime is referenced by the Mac build.
    static class Application { public static string ExecutablePath => Environment.ProcessPath; }
}
