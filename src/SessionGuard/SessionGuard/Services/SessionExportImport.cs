using System.IO.Compression;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using Microsoft.EntityFrameworkCore;
using SessionGuard.Data;
using SessionGuard.Models;

namespace SessionGuard.Services;

public class SessionExporter
{
    public static async Task<string> ExportAsync(
        string copilotRoot,
        string sessionId,
        string? outputPath = null)
    {
        var session = SessionScanner.ScanSession(copilotRoot, sessionId);
        var configs = SessionScanner.ScanConfig(copilotRoot);

        outputPath ??= Path.Combine(
            Directory.GetCurrentDirectory(),
            $"session-{sessionId[..8]}.zip");

        var tempDir = Path.Combine(Path.GetTempPath(), $"sg-export-{Guid.NewGuid():N}");
        Directory.CreateDirectory(tempDir);

        try
        {
            var dbPath = Path.Combine(tempDir, "session.db");

            await using (var ctx = new SessionGuardContext(dbPath, sessionId))
            {
                await ctx.Database.EnsureCreatedAsync();
                var crypto = ctx.Crypto;

                // Encrypt and save session
                var dbSession = new SessionRecord
                {
                    Id = session.Id,
                    Cwd = crypto.Encrypt(session.Cwd),
                    Summary = crypto.Encrypt(session.Summary),
                    Model = session.Model != null ? crypto.Encrypt(session.Model) : null,
                    CreatedAt = session.CreatedAt,
                    UpdatedAt = session.UpdatedAt,
                    WorkspaceYaml = crypto.Encrypt(session.WorkspaceYaml)
                };
                ctx.Sessions.Add(dbSession);
                await ctx.SaveChangesAsync();

                // Save events with encrypted data
                foreach (var batch in session.Events.Chunk(50))
                {
                    foreach (var ev in batch)
                    {
                        ctx.Events.Add(new EventRecord
                        {
                            Id = ev.Id,
                            SessionId = ev.SessionId,
                            Type = ev.Type,
                            JsonData = crypto.Encrypt(ev.JsonData),
                            Timestamp = ev.Timestamp,
                            ParentId = ev.ParentId
                        });
                    }
                    await ctx.SaveChangesAsync();
                }

                // Save files with encrypted content
                foreach (var file in session.Files)
                {
                    ctx.Files.Add(new FileRecord
                    {
                        Id = file.Id,
                        SessionId = file.SessionId,
                        RelativePath = crypto.Encrypt(file.RelativePath),
                        ContentBase64 = crypto.Encrypt(file.ContentBase64),
                        ContentHash = file.ContentHash,
                        SizeBytes = file.SizeBytes
                    });
                    await ctx.SaveChangesAsync();
                }

                // Save configs
                foreach (var c in configs)
                {
                    ctx.Config.Add(new ConfigRecord
                    {
                        Key = c.Key,
                        Value = crypto.Encrypt(c.Value)
                    });
                }
                await ctx.SaveChangesAsync();
            }

            // Write manifest (unencrypted metadata)
            var manifest = new
            {
                version = "1.0.0",
                sessionId,
                exportedAt = DateTime.UtcNow.ToString("O"),
                summary = session.Summary,
                eventsCount = session.Events.Count,
                filesCount = session.Files.Count,
                tool = "SessionGuard"
            };
            await File.WriteAllTextAsync(
                Path.Combine(tempDir, "manifest.json"),
                JsonSerializer.Serialize(manifest, new JsonSerializerOptions { WriteIndented = true }));

            if (File.Exists(outputPath)) File.Delete(outputPath);
            ZipFile.CreateFromDirectory(tempDir, outputPath);

            return outputPath;
        }
        finally
        {
            Directory.Delete(tempDir, true);
        }
    }
}

public class SessionImporter
{
    public static async Task<SessionRecord?> ImportAsync(
        string sourcePath,
        string? targetCopilotRoot = null)
    {
        string workDir;
        bool isZip = false;

        if (File.Exists(sourcePath) && Path.GetExtension(sourcePath).Equals(".zip", StringComparison.OrdinalIgnoreCase))
        {
            workDir = Path.Combine(Path.GetTempPath(), $"sg-import-{Guid.NewGuid():N}");
            ZipFile.ExtractToDirectory(sourcePath, workDir);
            isZip = true;
        }
        else if (Directory.Exists(sourcePath))
        {
            var copilotDir = Path.Combine(sourcePath, ".copilot");
            if (Directory.Exists(copilotDir))
                return await ImportFromRawCopilotAsync(copilotDir, targetCopilotRoot);
            workDir = sourcePath;
        }
        else
        {
            throw new FileNotFoundException($"Source not found: {sourcePath}");
        }

        try
        {
            return await ImportFromEncryptedAsync(workDir, targetCopilotRoot);
        }
        finally
        {
            if (isZip && Directory.Exists(workDir))
                Directory.Delete(workDir, true);
        }
    }

    static async Task<SessionRecord?> ImportFromEncryptedAsync(
        string workDir, string? targetCopilotRoot)
    {
        var manifestPath = Path.Combine(workDir, "manifest.json");
        if (!File.Exists(manifestPath))
            throw new InvalidOperationException("Invalid archive: manifest.json not found");

        var manifestJson = await File.ReadAllTextAsync(manifestPath);
        using var manifest = JsonDocument.Parse(manifestJson);
        var sessionId = manifest.RootElement.GetProperty("sessionId").GetString()
            ?? throw new InvalidOperationException("Session ID not found in manifest");

        var dbPath = Path.Combine(workDir, "session.db");
        if (!File.Exists(dbPath))
            throw new InvalidOperationException("Invalid archive: session.db not found");

        await using var ctx = new SessionGuardContext(dbPath, sessionId);
        var crypto = ctx.Crypto;

        var dbSession = await ctx.Sessions
            .Include(s => s.Events)
            .Include(s => s.Files)
            .FirstOrDefaultAsync(s => s.Id == sessionId);

        if (dbSession == null)
            throw new InvalidOperationException("Session data not found in encrypted database");

        // Decrypt into a clean session
        var session = new SessionRecord
        {
            Id = dbSession.Id,
            Cwd = crypto.Decrypt(dbSession.Cwd),
            Summary = crypto.Decrypt(dbSession.Summary),
            Model = dbSession.Model != null ? crypto.Decrypt(dbSession.Model) : null,
            CreatedAt = dbSession.CreatedAt,
            UpdatedAt = dbSession.UpdatedAt,
            WorkspaceYaml = crypto.Decrypt(dbSession.WorkspaceYaml),
            Events = dbSession.Events.Select(e => new EventRecord
            {
                Id = e.Id,
                SessionId = e.SessionId,
                Type = e.Type,
                JsonData = crypto.Decrypt(e.JsonData),
                Timestamp = e.Timestamp,
                ParentId = e.ParentId
            }).ToList(),
            Files = dbSession.Files.Select(f => new FileRecord
            {
                Id = f.Id,
                SessionId = f.SessionId,
                RelativePath = crypto.Decrypt(f.RelativePath),
                ContentBase64 = crypto.Decrypt(f.ContentBase64),
                ContentHash = f.ContentHash,
                SizeBytes = f.SizeBytes
            }).ToList()
        };

        if (targetCopilotRoot != null)
            await RestoreSessionAsync(session, ctx, targetCopilotRoot);

        return session;
    }

    static async Task<SessionRecord?> ImportFromRawCopilotAsync(
        string copilotDir, string? targetCopilotRoot)
    {
        var sessions = SessionScanner.ListSessions(copilotDir);
        if (sessions.Count == 0) return null;

        var session = SessionScanner.ScanSession(copilotDir, sessions[0]);

        if (targetCopilotRoot != null)
        {
            var dbPath = Path.Combine(Path.GetTempPath(), $"sg-temp-{Guid.NewGuid():N}.db");
            try
            {
                await using var ctx = new SessionGuardContext(dbPath, sessions[0]);
                await ctx.Database.EnsureCreatedAsync();
                ctx.Sessions.Add(session);
                await ctx.SaveChangesAsync();
                await RestoreSessionAsync(session, ctx, targetCopilotRoot);
            }
            finally
            {
                File.Delete(dbPath);
            }
        }

        return session;
    }

    static async Task RestoreSessionAsync(
        SessionRecord session,
        SessionGuardContext ctx,
        string copilotRoot)
    {
        var sessionDir = Path.Combine(copilotRoot, "session-state", session.Id);
        Directory.CreateDirectory(sessionDir);

        if (!string.IsNullOrEmpty(session.WorkspaceYaml))
        {
            await File.WriteAllTextAsync(
                Path.Combine(sessionDir, "workspace.yaml"),
                session.WorkspaceYaml);
        }

        if (session.Events.Count > 0)
        {
            var sb = new StringBuilder();
            foreach (var ev in session.Events.OrderBy(e => e.Timestamp))
                sb.AppendLine(ev.JsonData);
            await File.WriteAllTextAsync(
                Path.Combine(sessionDir, "events.jsonl"),
                sb.ToString());
        }

        foreach (var file in session.Files)
        {
            var filePath = Path.Combine(sessionDir, file.RelativePath);
            var fileDir = Path.GetDirectoryName(filePath);
            if (fileDir != null) Directory.CreateDirectory(fileDir);
            var content = Convert.FromBase64String(file.ContentBase64);
            await File.WriteAllBytesAsync(filePath, content);
        }

        var configs = await ctx.Config.ToListAsync();
        if (configs.Count > 0)
        {
            var crypto = ctx.Crypto;
            var configDict = new Dictionary<string, object>();
            foreach (var c in configs)
            {
                var decVal = crypto.Decrypt(c.Value);
                try { configDict[c.Key] = JsonSerializer.Deserialize<object>(decVal)!; }
                catch { configDict[c.Key] = decVal; }
            }
            await File.WriteAllTextAsync(
                Path.Combine(copilotRoot, "config.json"),
                JsonSerializer.Serialize(configDict, new JsonSerializerOptions { WriteIndented = true }));
        }
    }
}

public class GitHubPublisher
{
    public static async Task<bool> PublishAsync(
        string archivePath,
        string owner,
        string repo,
        string? tagName = null)
    {
        if (!File.Exists(archivePath))
            throw new FileNotFoundException("Archive not found", archivePath);

        tagName ??= $"session-{DateTime.UtcNow:yyyyMMdd-HHmmss}";

        var ghPath = FindGhCli();
        if (ghPath == null)
        {
            Console.Error.WriteLine("❌ GitHub CLI (gh) not found. Install it first.");
            return false;
        }

        var process = new System.Diagnostics.Process
        {
            StartInfo = new System.Diagnostics.ProcessStartInfo
            {
                FileName = ghPath,
                Arguments = $"release create {tagName} \"{archivePath}\" " +
                            $"--repo {owner}/{repo} " +
                            $"--title \"Session Export {tagName}\" " +
                            $"--notes \"Encrypted session export by SessionGuard\"",
                RedirectStandardOutput = true,
                RedirectStandardError = true,
                UseShellExecute = false
            }
        };

        process.Start();
        var output = await process.StandardOutput.ReadToEndAsync();
        var error = await process.StandardError.ReadToEndAsync();
        await process.WaitForExitAsync();

        if (process.ExitCode == 0)
        {
            Console.WriteLine($"✅ Published to {owner}/{repo} as {tagName}");
            return true;
        }

        Console.Error.WriteLine($"❌ Publish failed: {error}");
        return false;
    }

    static string? FindGhCli()
    {
        var paths = (Environment.GetEnvironmentVariable("PATH") ?? "").Split(':');
        foreach (var p in paths)
        {
            var ghPath = Path.Combine(p, "gh");
            if (File.Exists(ghPath)) return ghPath;
        }
        return null;
    }
}
