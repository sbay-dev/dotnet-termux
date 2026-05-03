using EntityCrypt.Core.Encryption;
using Microsoft.EntityFrameworkCore;
using SessionGuard.Models;

namespace SessionGuard.Data;

/// <summary>
/// Simple wrapper around AES256EncryptionProvider that binds a key
/// </summary>
public class BoundCrypto(string key)
{
    private readonly AES256EncryptionProvider _provider = new();
    private readonly string _key = key;

    public string Encrypt(string plaintext) => _provider.Encrypt(plaintext, _key);
    public string Decrypt(string ciphertext) => _provider.Decrypt(ciphertext, _key);
}

public class SessionGuardContext : DbContext
{
    private readonly string _dbPath;
    private readonly BoundCrypto _crypto;

    public DbSet<SessionRecord> Sessions => Set<SessionRecord>();
    public DbSet<EventRecord> Events => Set<EventRecord>();
    public DbSet<FileRecord> Files => Set<FileRecord>();
    public DbSet<ConfigRecord> Config => Set<ConfigRecord>();

    public BoundCrypto Crypto => _crypto;

    public SessionGuardContext(string dbPath, string encryptionKey)
    {
        _dbPath = dbPath;
        _crypto = new BoundCrypto(encryptionKey);
    }

    protected override void OnConfiguring(DbContextOptionsBuilder options)
    {
        options.UseSqlite($"Data Source={_dbPath}");
    }

    protected override void OnModelCreating(ModelBuilder modelBuilder)
    {
        modelBuilder.Entity<EventRecord>()
            .HasOne(e => e.Session)
            .WithMany(s => s.Events)
            .HasForeignKey(e => e.SessionId);

        modelBuilder.Entity<FileRecord>()
            .HasOne(f => f.Session)
            .WithMany(s => s.Files)
            .HasForeignKey(f => f.SessionId);
    }
}
