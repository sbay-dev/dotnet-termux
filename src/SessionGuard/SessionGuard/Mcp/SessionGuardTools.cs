using System.ComponentModel;
using System.Text.Json;
using ModelContextProtocol.Server;
using SessionGuard.Services;

namespace SessionGuard.Mcp;

[McpServerToolType]
public static class SessionGuardTools
{
    [McpServerTool(Name = "session_list"), Description("Lists all Copilot CLI sessions in the local .copilot directory")]
    public static string ListSessions(string? copilotRoot = null)
    {
        copilotRoot ??= SessionScanner.FindCopilotRoot(Directory.GetCurrentDirectory());
        if (copilotRoot == null)
            return JsonSerializer.Serialize(new { error = ".copilot directory not found" });

        var sessions = SessionScanner.ListSessions(copilotRoot);
        var results = new List<object>();

        foreach (var sid in sessions)
        {
            try
            {
                var session = SessionScanner.ScanSession(copilotRoot, sid);
                results.Add(new
                {
                    id = sid,
                    summary = session.Summary,
                    cwd = session.Cwd,
                    createdAt = session.CreatedAt,
                    eventsCount = session.Events.Count,
                    filesCount = session.Files.Count
                });
            }
            catch
            {
                results.Add(new { id = sid, error = "Failed to scan" });
            }
        }

        return JsonSerializer.Serialize(new { copilotRoot, sessions = results },
            new JsonSerializerOptions { WriteIndented = true });
    }

    [McpServerTool(Name = "session_export"), Description("Exports and encrypts a Copilot CLI session using its ID as the encryption key")]
    public static async Task<string> ExportSession(
        string sessionId,
        string? copilotRoot = null,
        string? outputPath = null)
    {
        copilotRoot ??= SessionScanner.FindCopilotRoot(Directory.GetCurrentDirectory());
        if (copilotRoot == null)
            return JsonSerializer.Serialize(new { error = ".copilot directory not found" });

        try
        {
            var archivePath = await SessionExporter.ExportAsync(copilotRoot, sessionId, outputPath);
            return JsonSerializer.Serialize(new
            {
                success = true,
                archivePath,
                sessionId,
                message = $"Session exported and encrypted to {archivePath}"
            });
        }
        catch (Exception ex)
        {
            return JsonSerializer.Serialize(new { error = ex.Message });
        }
    }

    [McpServerTool(Name = "session_import"), Description("Imports and decrypts a Copilot CLI session from a zip archive or .copilot directory")]
    public static async Task<string> ImportSession(
        string sourcePath,
        string? targetCopilotRoot = null)
    {
        try
        {
            var session = await SessionImporter.ImportAsync(sourcePath, targetCopilotRoot);
            if (session == null)
                return JsonSerializer.Serialize(new { error = "No session found in source" });

            return JsonSerializer.Serialize(new
            {
                success = true,
                sessionId = session.Id,
                summary = session.Summary,
                eventsCount = session.Events.Count,
                filesCount = session.Files.Count,
                restoredTo = targetCopilotRoot ?? "(in memory only)"
            });
        }
        catch (Exception ex)
        {
            return JsonSerializer.Serialize(new { error = ex.Message });
        }
    }

    [McpServerTool(Name = "session_publish"), Description("Publishes an encrypted session archive to a GitHub repository release")]
    public static async Task<string> PublishSession(
        string archivePath,
        string owner,
        string repo,
        string? tag = null)
    {
        try
        {
            var success = await GitHubPublisher.PublishAsync(archivePath, owner, repo, tag);
            return JsonSerializer.Serialize(new
            {
                success,
                owner,
                repo,
                tag = tag ?? "auto-generated"
            });
        }
        catch (Exception ex)
        {
            return JsonSerializer.Serialize(new { error = ex.Message });
        }
    }

    [McpServerTool(Name = "session_scan"), Description("Scans a specific session and returns its metadata and structure")]
    public static string ScanSession(string sessionId, string? copilotRoot = null)
    {
        copilotRoot ??= SessionScanner.FindCopilotRoot(Directory.GetCurrentDirectory());
        if (copilotRoot == null)
            return JsonSerializer.Serialize(new { error = ".copilot directory not found" });

        try
        {
            var session = SessionScanner.ScanSession(copilotRoot, sessionId);
            return JsonSerializer.Serialize(new
            {
                id = session.Id,
                summary = session.Summary,
                cwd = session.Cwd,
                createdAt = session.CreatedAt,
                updatedAt = session.UpdatedAt,
                eventsCount = session.Events.Count,
                filesCount = session.Files.Count,
                eventTypes = session.Events
                    .GroupBy(e => e.Type)
                    .Select(g => new { type = g.Key, count = g.Count() }),
                files = session.Files.Select(f => new
                {
                    path = f.RelativePath,
                    size = f.SizeBytes
                })
            }, new JsonSerializerOptions { WriteIndented = true });
        }
        catch (Exception ex)
        {
            return JsonSerializer.Serialize(new { error = ex.Message });
        }
    }
}
