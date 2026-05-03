using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;
using ModelContextProtocol.Server;
using SessionGuard.Services;

var mode = args.Length > 0 ? args[0] : "--help";

switch (mode)
{
    case "--mcp":
        await RunMcpServer(args);
        break;

    case "export":
        await RunExport(args);
        break;

    case "import":
        await RunImport(args);
        break;

    case "list":
        RunList(args);
        break;

    case "scan":
        RunScan(args);
        break;

    case "publish":
        await RunPublish(args);
        break;

    default:
        ShowHelp();
        break;
}

// ─── MCP Server Mode ─────────────────────────────────────────
async Task RunMcpServer(string[] args)
{
    Console.Error.WriteLine("🔐 SessionGuard MCP Server starting...");
    var builder = Host.CreateApplicationBuilder(args);
    builder.Services
        .AddMcpServer()
        .WithStdioServerTransport()
        .WithToolsFromAssembly();
    await builder.Build().RunAsync();
}

// ─── CLI Commands ────────────────────────────────────────────
async Task RunExport(string[] args)
{
    var sessionId = GetArg(args, 1, "--session-id");
    var copilotRoot = GetArg(args, 2, "--copilot-root");
    var output = GetArg(args, 3, "--output");

    if (string.IsNullOrEmpty(sessionId))
    {
        Console.Error.WriteLine("❌ --session-id required");
        Console.Error.WriteLine("   Usage: session-guard export <session-id> [copilot-root] [output-path]");
        return;
    }

    copilotRoot ??= SessionScanner.FindCopilotRoot(Directory.GetCurrentDirectory());
    if (copilotRoot == null)
    {
        Console.Error.WriteLine("❌ .copilot directory not found");
        return;
    }

    Console.Error.WriteLine($"🔍 Scanning session {sessionId[..8]}...");
    var archivePath = await SessionExporter.ExportAsync(copilotRoot, sessionId, output);
    Console.WriteLine($"✅ Exported to: {archivePath}");
}

async Task RunImport(string[] args)
{
    var source = GetArg(args, 1, "--source");
    var target = GetArg(args, 2, "--target");

    if (string.IsNullOrEmpty(source))
    {
        Console.Error.WriteLine("❌ Source path required");
        Console.Error.WriteLine("   Usage: session-guard import <source-path> [target-copilot-root]");
        return;
    }

    Console.Error.WriteLine($"📥 Importing from {source}...");
    var session = await SessionImporter.ImportAsync(source, target);
    if (session != null)
    {
        Console.WriteLine($"✅ Imported session: {session.Id}");
        Console.WriteLine($"   Summary: {session.Summary}");
        Console.WriteLine($"   Events:  {session.Events.Count}");
        Console.WriteLine($"   Files:   {session.Files.Count}");
        if (target != null) Console.WriteLine($"   Restored to: {target}");
    }
    else
    {
        Console.Error.WriteLine("❌ No session found in source");
    }
}

void RunList(string[] args)
{
    var copilotRoot = GetArg(args, 1, "--copilot-root")
        ?? SessionScanner.FindCopilotRoot(Directory.GetCurrentDirectory());

    if (copilotRoot == null)
    {
        Console.Error.WriteLine("❌ .copilot directory not found");
        return;
    }

    Console.WriteLine($"📁 {copilotRoot}\n");
    var sessions = SessionScanner.ListSessions(copilotRoot);
    if (sessions.Count == 0)
    {
        Console.WriteLine("   (no sessions found)");
        return;
    }

    foreach (var sid in sessions)
    {
        try
        {
            var s = SessionScanner.ScanSession(copilotRoot, sid);
            Console.WriteLine($"  {sid[..8]}  │ {s.Summary,-40} │ Events: {s.Events.Count,4} │ {s.CreatedAt}");
        }
        catch
        {
            Console.WriteLine($"  {sid[..8]}  │ (error scanning)");
        }
    }
}

void RunScan(string[] args)
{
    var sessionId = GetArg(args, 1, "--session-id");
    if (string.IsNullOrEmpty(sessionId))
    {
        Console.Error.WriteLine("❌ Session ID required");
        return;
    }

    var copilotRoot = GetArg(args, 2, "--copilot-root")
        ?? SessionScanner.FindCopilotRoot(Directory.GetCurrentDirectory());

    if (copilotRoot == null)
    {
        Console.Error.WriteLine("❌ .copilot directory not found");
        return;
    }

    var session = SessionScanner.ScanSession(copilotRoot, sessionId);
    Console.WriteLine($"🔍 Session: {session.Id}");
    Console.WriteLine($"   Summary:    {session.Summary}");
    Console.WriteLine($"   CWD:        {session.Cwd}");
    Console.WriteLine($"   Created:    {session.CreatedAt}");
    Console.WriteLine($"   Events:     {session.Events.Count}");
    Console.WriteLine($"   Files:      {session.Files.Count}");

    if (session.Events.Count > 0)
    {
        Console.WriteLine("\n   Event Types:");
        foreach (var group in session.Events.GroupBy(e => e.Type))
            Console.WriteLine($"     {group.Key,-30} × {group.Count()}");
    }

    if (session.Files.Count > 0)
    {
        Console.WriteLine("\n   Session Files:");
        foreach (var f in session.Files)
            Console.WriteLine($"     {f.RelativePath,-50} ({f.SizeBytes:N0} bytes)");
    }
}

async Task RunPublish(string[] args)
{
    var archive = GetArg(args, 1, "--archive");
    var owner = GetArg(args, 2, "--owner");
    var repo = GetArg(args, 3, "--repo");
    var tag = GetArg(args, 4, "--tag");

    if (string.IsNullOrEmpty(archive) || string.IsNullOrEmpty(owner) || string.IsNullOrEmpty(repo))
    {
        Console.Error.WriteLine("❌ Required: archive, owner, repo");
        Console.Error.WriteLine("   Usage: session-guard publish <archive> <owner> <repo> [tag]");
        return;
    }

    await GitHubPublisher.PublishAsync(archive, owner, repo, tag);
}

void ShowHelp()
{
    Console.WriteLine("""

    🔐 SessionGuard — Copilot CLI Session Manager

    Usage: session-guard <command> [options]

    Commands:
      --mcp                          Start as MCP server (for Copilot CLI)
      list     [copilot-root]        List all sessions
      scan     <session-id>          Scan session details
      export   <session-id> [root] [output]  Export encrypted session
      import   <source> [target]     Import session from archive/directory
      publish  <archive> <owner> <repo> [tag]  Publish to GitHub

    MCP Tools (when running as --mcp server):
      session_list      — List sessions
      session_scan      — Scan session details
      session_export    — Export encrypted session
      session_import    — Import session from archive
      session_publish   — Publish to GitHub release

    Encryption:
      Sessions are encrypted using the session ID as the key via
      EntityCrypt.EFCore. Only the correct session ID can decrypt
      the exported data.

    """);
}

string? GetArg(string[] args, int positionalIndex, string namedFlag)
{
    // Check named flag
    for (int i = 0; i < args.Length - 1; i++)
        if (args[i] == namedFlag) return args[i + 1];

    // Check positional (skip command name)
    var positionals = args.Where(a => !a.StartsWith("--")).ToArray();
    return positionalIndex < positionals.Length ? positionals[positionalIndex] : null;
}
