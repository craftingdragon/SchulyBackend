using Microsoft.AspNetCore.Http;

namespace Schuly.API.Extensions;

/// <summary>Restricts the local auth endpoint namespace to federated sign-in and session operations.</summary>
public sealed class SsoOnlyAuthMiddleware(RequestDelegate next, IConfiguration configuration)
{
    private static readonly HashSet<string> AllowedLocalAuthPaths = new(StringComparer.OrdinalIgnoreCase)
    {
        "/auth/providers",
        "/auth/refresh",
        "/auth/logout"
    };

    public async Task InvokeAsync(HttpContext context)
    {
        if (configuration.GetValue<bool>("SsoOnly") && IsBlockedSsoOnlyPath(context.Request.Path))
        {
            context.Response.StatusCode = StatusCodes.Status403Forbidden;
            await context.Response.WriteAsJsonAsync(new
            {
                error = "sso_required",
                message = "This deployment accepts sign-in through its configured identity provider."
            }, context.RequestAborted);
            return;
        }

        await next(context);
    }

    internal static bool IsBlockedSsoOnlyPath(PathString path)
    {
        if (!path.StartsWithSegments("/auth", StringComparison.OrdinalIgnoreCase))
            return false;

        if (AllowedLocalAuthPaths.Contains(path.Value?.TrimEnd('/') ?? string.Empty))
            return false;

        // Includes provider start, callback, exchange, link, and unlink routes. PathString
        // enforces a segment boundary, so /externality does not inherit this exception.
        return !path.StartsWithSegments("/auth/external", StringComparison.OrdinalIgnoreCase);
    }
}
