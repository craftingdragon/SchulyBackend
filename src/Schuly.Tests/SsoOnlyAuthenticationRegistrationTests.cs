using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.FileProviders;
using Microsoft.Extensions.Options;
using Schuly.API.Extensions;
using Toamaisutaa.Abstractions;

namespace Schuly.Tests;

public class SsoOnlyAuthenticationRegistrationTests
{
    [Test]
    public async Task Sso_only_authentication_registers_without_smtp_configuration()
    {
        var configuration = new ConfigurationBuilder()
            .AddInMemoryCollection(new Dictionary<string, string?>
            {
                ["SsoOnly"] = "true",
                ["LocalLogin:Issuer"] = "schuly-test",
                ["LocalLogin:Audience"] = "schuly-test",
                ["LocalLogin:SigningKey"] = Convert.ToBase64String(new byte[32]),
                ["TwoFactor:EncryptionKey"] = Convert.ToBase64String(new byte[32]),
            })
            .Build();
        var services = new ServiceCollection();
        services.AddLogging();
        services.AddSingleton<IServiceCollection>(services);
        services.AddSingleton<IHostEnvironment>(new TestHostEnvironment());

        services.AddSchulyAuthentication(configuration);

        await Assert.That(services.Any(descriptor => descriptor.ServiceType == typeof(IEmailVerificationNotifier))).IsFalse();
        await Assert.That(services.Any(descriptor => descriptor.ServiceType == typeof(IPasswordResetNotifier))).IsTrue();

        await using var provider = services.BuildServiceProvider();
        var localLoginOptions = provider.GetRequiredService<IOptions<ToamaisutaaLocalLoginOptions>>().Value;
        await Assert.That(localLoginOptions.AllowSelfRegistration).IsFalse();
        await Assert.That(localLoginOptions.RequireVerifiedEmailForPasswordReset).IsFalse();
        await Assert.That(localLoginOptions.RequireVerifiedEmailForSignIn).IsFalse();

        // Exercise Toamaisutaa's actual hosted startup checks, not just DI wiring. The
        // package's password-login check is an IHostedService, not an IStartupValidator.
        provider.GetRequiredService<IStartupValidator>().Validate();
        var passwordLoginStartupCheckType = System.Reflection.Assembly.Load("Toamaisutaa.Core")
            .GetType("Toamaisutaa.Core.PasswordLoginStartupCheck", throwOnError: true)!;
        var passwordLoginStartupCheck = (IHostedService)ActivatorUtilities.CreateInstance(provider, passwordLoginStartupCheckType);
        await passwordLoginStartupCheck.StartAsync(CancellationToken.None);
    }

    private sealed class TestHostEnvironment : IHostEnvironment
    {
        public string EnvironmentName { get; set; } = Environments.Production;
        public string ApplicationName { get; set; } = "Schuly.Tests";
        public string ContentRootPath { get; set; } = AppContext.BaseDirectory;
        public IFileProvider ContentRootFileProvider { get; set; } = new PhysicalFileProvider(AppContext.BaseDirectory);
    }
}
