import { Component, OnInit, inject, input, signal } from '@angular/core';
import { Router } from '@angular/router';
import { HlmAlertImports } from '@spartan-ng/helm/alert';
import { HlmButton } from '@spartan-ng/helm/button';
import { HlmCardImports } from '@spartan-ng/helm/card';
import { HlmSpinner } from '@spartan-ng/helm/spinner';
import { firstValueFrom } from 'rxjs';
import { AuthApi, SignInProvider } from '../../core/auth-api';
import { beginExternalSignIn, externalErrors, takePending } from '../../core/external-sign-in';
import { rememberReturnUrl, takeReturnUrl } from '../../core/return-url';
import { AuthStore, authErrorMessage } from '../../stores/auth.store';
import { AuthLayout } from './auth-layout';

@Component({
  selector: 'app-login',
  imports: [HlmAlertImports, HlmButton, HlmCardImports, HlmSpinner, AuthLayout],
  template: `
    <app-auth-layout title="Sign in to Schuly" subtitle="Continue with your school identity provider.">
      <section hlmCard>
        <div hlmCardContent class="flex flex-col gap-4">
          @if (error()) {
            <div hlmAlert>
              <p hlmAlertDescription>{{ error() }}</p>
            </div>
          }
          @if (loading()) {
            <div class="flex justify-center py-2"><hlm-spinner /></div>
          } @else if (providers().length) {
            @for (provider of providers(); track provider.key) {
              <button
                hlmBtn
                size="lg"
                type="button"
                [disabled]="redirecting()"
                (click)="signInWith(provider.key)"
              >
                @if (redirecting()) { <hlm-spinner /> }
                Continue with {{ provider.display_name }}
              </button>
            }
          } @else {
            <p class="text-muted-foreground text-center text-sm">
              Sign-in is temporarily unavailable. Please try again later.
            </p>
          }
        </div>
      </section>
    </app-auth-layout>
  `,
})
export class Login implements OnInit {
  readonly returnUrl = input<string>();
  readonly code = input<string>();
  readonly state = input<string>();
  readonly failure = input<string>(undefined, { alias: 'error' });
  private readonly api = inject(AuthApi);
  private readonly auth = inject(AuthStore);
  private readonly router = inject(Router);

  protected readonly providers = signal<SignInProvider[]>([]);
  protected readonly error = signal<string | null>(null);
  protected readonly loading = signal(true);
  protected readonly redirecting = signal(false);

  async ngOnInit(): Promise<void> {
    rememberReturnUrl(this.returnUrl());
    const code = this.code();
    const failure = this.failure();
    if (code || failure) {
      const pending = takePending(this.state() ?? null);
      void this.router.navigate([], { queryParams: {}, replaceUrl: true });
      if (failure) this.error.set(externalErrors[failure] ?? externalErrors['external_login_failed']);
      else if (!pending) this.error.set(externalErrors['external_login_failed']);
      else await this.finishExternal(code!, pending.verifier);
    }

    this.providers.set(await firstValueFrom(this.api.providers()).catch(() => []));
    this.loading.set(false);
  }

  protected async signInWith(provider: string): Promise<void> {
    this.redirecting.set(true);
    try {
      await beginExternalSignIn(provider, '/login');
    } catch (error) {
      this.redirecting.set(false);
      this.error.set(authErrorMessage(error, externalErrors['external_login_failed']));
    }
  }

  private async finishExternal(code: string, verifier: string): Promise<void> {
    try {
      const result = await this.auth.signInExternal(code, verifier);
      if (result === 'signedIn') await this.router.navigateByUrl(takeReturnUrl(this.returnUrl()));
      else this.error.set('Complete the additional sign-in step with your identity provider, then try again.');
    } catch (error) {
      this.error.set(authErrorMessage(error, externalErrors['external_login_failed']));
    }
  }
}
