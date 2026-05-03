using System.ComponentModel.DataAnnotations;

namespace SessionGuard.Models;

public class SessionRecord
{
    [Key]
    public string Id { get; set; } = string.Empty;
    public string Cwd { get; set; } = string.Empty;
    public string Summary { get; set; } = string.Empty;
    public string? Model { get; set; }
    public string CreatedAt { get; set; } = string.Empty;
    public string UpdatedAt { get; set; } = string.Empty;
    public string WorkspaceYaml { get; set; } = string.Empty;
    public List<EventRecord> Events { get; set; } = [];
    public List<FileRecord> Files { get; set; } = [];
}

public class EventRecord
{
    [Key]
    public string Id { get; set; } = Guid.NewGuid().ToString();
    public string SessionId { get; set; } = string.Empty;
    public string Type { get; set; } = string.Empty;
    public string JsonData { get; set; } = string.Empty;
    public string Timestamp { get; set; } = string.Empty;
    public string? ParentId { get; set; }
    public SessionRecord Session { get; set; } = null!;
}

public class FileRecord
{
    [Key]
    public string Id { get; set; } = Guid.NewGuid().ToString();
    public string SessionId { get; set; } = string.Empty;
    public string RelativePath { get; set; } = string.Empty;
    public string ContentBase64 { get; set; } = string.Empty;
    public string ContentHash { get; set; } = string.Empty;
    public long SizeBytes { get; set; }
    public SessionRecord Session { get; set; } = null!;
}

public class ConfigRecord
{
    [Key]
    public string Key { get; set; } = string.Empty;
    public string Value { get; set; } = string.Empty;
}
