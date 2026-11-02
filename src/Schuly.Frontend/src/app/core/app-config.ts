import { Injectable, inject, signal } from '@angular/core';
import { firstValueFrom } from 'rxjs';
import { AppService } from '../api/api/app.service';

@Injectable({ providedIn: 'root' })
export class AppConfig {
  private readonly api = inject(AppService);
  readonly ssoOnly = signal(true);
  private loading: Promise<void> | null = null;

  load(): Promise<void> {
    this.loading ??= firstValueFrom(this.api.apiAppGet())
      .then((config) => this.ssoOnly.set(config.ssoOnly ?? false))
      .then(() => undefined)
      .catch(() => {
        // Fail closed if the deployment mode cannot be read.
        this.ssoOnly.set(true);
      });
    return this.loading;
  }
}
