using Microsoft.AspNetCore.Http;
using Microsoft.Extensions.Configuration;
using Schuly.API.Extensions;

namespace Schuly.Tests;

public class SsoOnlyAuthMiddlewareTests
{
    [Test]
    [Arguments("/auth/login")]
    [Arguments("/auth/register")]
    [Arguments("/auth/password/forgot")]
    [Arguments("/auth/password/reset")]
    [Arguments("/auth/invitations/accept")]
    [Arguments("/auth/2fa/begin")]
    [Arguments("/auth/invite/foo")]
    [Arguments("/auth/new-local-entry-point")]
    [Arguments("/AUTH/REGISTER/")]
    [Arguments("/auth/password%2Freset")]
    [Arguments("/auth/externality")]
    public async Task Sso_only_rejects_local_and_unknown_auth_routes(string path)
    {
        var configuration = new ConfigurationBuilder()
            .AddInMemoryCollection([new KeyValuePair<string, string?>("SsoOnly", "true")])
            .Build();
        var context = new DefaultHttpContext();
        context.Request.Path = path;
        var passedToNext = false;
        var middleware = new SsoOnlyAuthMiddleware(_ =>
        {
            passedToNext = true;
            return Task.CompletedTask;
        }, configuration);

        await middleware.InvokeAsync(context);

        await Assert.That(context.Response.StatusCode).IsEqualTo(StatusCodes.Status403Forbidden);
        await Assert.That(passedToNext).IsFalse();
    }

    [Test]
    [Arguments("/auth/refresh")]
    [Arguments("/auth/logout")]
    [Arguments("/auth/external/gamepowerx/start")]
    [Arguments("/auth/external/gamepowerx/callback")]
    [Arguments("/auth/external/exchange")]
    [Arguments("/auth/providers")]
    [Arguments("/api/auth/login")]
    public async Task Sso_only_preserves_external_sign_in_and_session_routes(string path)
    {
        var configuration = new ConfigurationBuilder()
            .AddInMemoryCollection([new KeyValuePair<string, string?>("SsoOnly", "true")])
            .Build();
        var context = new DefaultHttpContext();
        context.Request.Path = path;
        var passedToNext = false;
        var middleware = new SsoOnlyAuthMiddleware(_ =>
        {
            passedToNext = true;
            return Task.CompletedTask;
        }, configuration);

        await middleware.InvokeAsync(context);

        await Assert.That(passedToNext).IsTrue();
    }

    [Test]
    public async Task Local_credentials_remain_available_when_sso_only_is_disabled()
    {
        var configuration = new ConfigurationBuilder()
            .AddInMemoryCollection([new KeyValuePair<string, string?>("SsoOnly", "false")])
            .Build();
        var context = new DefaultHttpContext();
        context.Request.Path = "/auth/login";
        var passedToNext = false;
        var middleware = new SsoOnlyAuthMiddleware(_ =>
        {
            passedToNext = true;
            return Task.CompletedTask;
        }, configuration);

        await middleware.InvokeAsync(context);

        await Assert.That(passedToNext).IsTrue();
    }
}
