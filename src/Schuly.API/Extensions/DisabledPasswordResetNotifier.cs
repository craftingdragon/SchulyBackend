using Toamaisutaa.Abstractions;

namespace Schuly.API.Extensions;

/// <summary>No-op reset-mail registration used only when the server rejects all local password routes.</summary>
internal sealed class DisabledPasswordResetNotifier : IPasswordResetNotifier
{
    public Task SendAsync(ToamaisutaaUser user, string resetToken, CancellationToken cancellationToken = default) =>
        Task.CompletedTask;
}
