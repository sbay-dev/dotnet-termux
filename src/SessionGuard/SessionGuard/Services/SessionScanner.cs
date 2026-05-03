using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using SessionGuard.Data;
using SessionGuard.Models;

namespace SessionGuard.Services;

public class SessionScanner
{
    /// <summary>
    /// Finds .copilot root directory starting from a given path
    /// </summary>
    public static string? FindCopilotRoot(string startPath)
    {
        var dir = new DirectoryInfo(startPath);
        while (dir != null)
        {
            var copilotDir = Path.Combine(dir.FullName, ".copilot");
            if (Directory.Exists(copilotDir))
                return copilotDir;
            dir = dir.Parent;
        }

        // Check home directory
        var home = Environment.GetFolderPath(Environment.SpecialFolder.UserProfile);
        if (string.IsNullOrEmpty(home)) home = Environment.GetEnvironmentVariable("HOME") ?? "/root";
        var homeDir = Path.Combine(home, ".copilot");
        return Directory.Exists(homeDir) ? homeDir : null;
    }

    /// <summary>
    /// Lists all session IDs in a .copilot root
    /// </summary>
    public static List<string> ListSessions(string copilotRoot)
    {
        var sessionDir = Path.Combine(copilotRoot, "session-state");
        if (!Directory.Exists(sessionDir))
            return [];

        return Directory.GetDirectories(sessionDir)
            .Select(Path.GetFileName)
            .Where(n => n != null && Guid.TryParse(n, out _))
            .Cast<string>()
            .ToList();
    }

    /// <summary>
    /// Scans a session directory and populates a SessionRecord
    /// </summary>
    public static SessionRecord ScanSession(string copilotRoot, string sessionId)
    {
        var sessionDir = Path.Combine(copilotRoot, "session-state", sessionId);
        if (!Directory.Exists(sessionDir))
            throw new DirectoryNotFoundException($"Session directory not found: {sessionDir}");

        var record = new SessionRecord { Id = sessionId };

        // Parse workspace.yaml
        var workspaceFile = Path.Combine(sessionDir, "workspace.yaml");
        if (File.Exists(workspaceFile))
        {
            var yaml = File.ReadAllText(workspaceFile);
            record.WorkspaceYaml = yaml;
            record.Cwd = ExtractYamlValue(yaml, "cwd") ?? "";
            record.Summary = ExtractYamlValue(yaml, "summary") ?? "";
            record.CreatedAt = ExtractYamlValue(yaml, "created_at") ?? "";
            record.UpdatedAt = ExtractYamlValue(yaml, "updated_at") ?? "";
        }

        // Parse events.jsonl
        var eventsFile = Path.Combine(sessionDir, "events.jsonl");
        if (File.Exists(eventsFile))
        {
            foreach (var line in File.ReadLines(eventsFile))
            {
                if (string.IsNullOrWhiteSpace(line)) continue;
                try
                {
                    using var doc = JsonDocument.Parse(line);
                    var root = doc.RootElement;
                    record.Events.Add(new EventRecord
                    {
                        Id = root.TryGetProperty("id", out var idProp)
                            ? idProp.GetString() ?? Guid.NewGuid().ToString()
                            : Guid.NewGuid().ToString(),
                        SessionId = sessionId,
                        Type = root.TryGetProperty("type", out var typeProp)
                            ? typeProp.GetString() ?? ""
                            : "",
                        JsonData = line,
                        Timestamp = root.TryGetProperty("timestamp", out var tsProp)
                            ? tsProp.GetString() ?? ""
                            : "",
                        ParentId = root.TryGetProperty("parentId", out var pidProp)
                            ? pidProp.GetString()
                            : null
                    });
                }
                catch (JsonException)
                {
                    // Skip malformed lines
                }
            }
        }

        // Scan files directory
        var filesDir = Path.Combine(sessionDir, "files");
        if (Directory.Exists(filesDir))
        {
            foreach (var file in Directory.GetFiles(filesDir, "*", SearchOption.AllDirectories))
            {
                var content = File.ReadAllBytes(file);
                var relativePath = Path.GetRelativePath(sessionDir, file);
                record.Files.Add(new FileRecord
                {
                    SessionId = sessionId,
                    RelativePath = relativePath,
                    ContentBase64 = Convert.ToBase64String(content),
                    ContentHash = ComputeHash(content),
                    SizeBytes = content.LongLength
                });
            }
        }

        // Also capture checkpoints, research, etc.
        foreach (var subdir in new[] { "checkpoints", "research" })
        {
            var subPath = Path.Combine(sessionDir, subdir);
            if (!Directory.Exists(subPath)) continue;
            foreach (var file in Directory.GetFiles(subPath, "*", SearchOption.AllDirectories))
            {
                var content = File.ReadAllBytes(file);
                var relativePath = Path.GetRelativePath(sessionDir, file);
                record.Files.Add(new FileRecord
                {
                    SessionId = sessionId,
                    RelativePath = relativePath,
                    ContentBase64 = Convert.ToBase64String(content),
                    ContentHash = ComputeHash(content),
                    SizeBytes = content.LongLength
                });
            }
        }

        return record;
    }

    /// <summary>
    /// Scans global config from .copilot root (excluding tokens)
    /// </summary>
    public static List<ConfigRecord> ScanConfig(string copilotRoot)
    {
        var configs = new List<ConfigRecord>();
        var configFile = Path.Combine(copilotRoot, "config.json");
        if (!File.Exists(configFile)) return configs;

        try
        {
            using var doc = JsonDocument.Parse(File.ReadAllText(configFile));
            foreach (var prop in doc.RootElement.EnumerateObject())
            {
                // Skip sensitive token data
                if (prop.Name.Contains("token", StringComparison.OrdinalIgnoreCase))
                    continue;

                configs.Add(new ConfigRecord
                {
                    Key = prop.Name,
                    Value = prop.Value.ToString()
                });
            }
        }
        catch (JsonException) { }

        return configs;
    }

    static string ExtractYamlValue(string yaml, string key)
    {
        foreach (var line in yaml.Split('\n'))
        {
            var trimmed = line.Trim();
            if (trimmed.StartsWith(key + ":"))
                return trimmed[(key.Length + 1)..].Trim();
        }
        return "";
    }

    static string ComputeHash(byte[] data)
    {
        var hash = SHA256.HashData(data);
        return Convert.ToHexStringLower(hash);
    }
}
