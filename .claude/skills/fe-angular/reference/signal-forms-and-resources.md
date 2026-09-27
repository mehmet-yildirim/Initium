# Signal Forms, resources, and stores (Angular 22)

## Port and HTTP adapter

```ts
// features/projects/application/project-repository.ts
export abstract class ProjectRepository {
  abstract create(input: { name: string }): Promise<Result<Project, 'NAME_TAKEN' | 'FORBIDDEN'>>;
}

// features/projects/data-access/http-project-repository.ts
@Injectable()
export class HttpProjectRepository extends ProjectRepository {
  private readonly http = inject(HttpClient);
  private readonly apiUrl = inject(API_URL);

  async create(input: { name: string }): Promise<Result<Project, 'NAME_TAKEN' | 'FORBIDDEN'>> {
    try {
      const body = await firstValueFrom(this.http.post<unknown>(`${this.apiUrl}/projects`, input));
      return { ok: true, value: ProjectDto.parse(body) }; // Zod schema validates the response
    } catch (error) {
      if (error instanceof HttpErrorResponse && error.status === 409) return { ok: false, error: 'NAME_TAKEN' };
      if (error instanceof HttpErrorResponse && error.status === 403) return { ok: false, error: 'FORBIDDEN' };
      throw error; // unexpected: reaches the global ErrorHandler → logger
    }
  }
}

// app.config.ts
export const appConfig: ApplicationConfig = {
  providers: [
    provideRouter(routes, withComponentInputBinding()),
    provideHttpClient(withInterceptors([correlationIdInterceptor, authInterceptor])),
    { provide: ProjectRepository, useClass: HttpProjectRepository },
    { provide: ErrorHandler, useClass: LoggingErrorHandler },
  ],
};
```

## Signal Form with server errors

```ts
import { Component, inject, signal } from '@angular/core';
import { form, FormField, maxLength, required, submit } from '@angular/forms/signals';
import { ProjectRepository } from '../application/project-repository';

@Component({
  selector: 'app-create-project',
  imports: [FormField],
  templateUrl: './create-project.html',
})
export class CreateProject {
  private readonly projects = inject(ProjectRepository);

  protected readonly model = signal({ name: '' });
  protected readonly projectForm = form(this.model, (path) => {
    required(path.name, { message: 'Name is required' });
    maxLength(path.name, 100, { message: 'Use at most 100 characters' });
  });

  protected async onSubmit(event: Event): Promise<void> {
    event.preventDefault();
    await submit(this.projectForm, async (field) => {
      const result = await this.projects.create({ name: field.name().value().trim() });
      if (result.ok) return undefined;
      return result.error === 'NAME_TAKEN'
        ? { kind: 'server', field: field.name, message: 'A project with this name already exists' }
        : { kind: 'server', message: 'You do not have permission to create projects' };
    });
  }
}
```

```html
<!-- create-project.html -->
<form (submit)="onSubmit($event)" novalidate>
  <label for="project-name">Name</label>
  <input id="project-name" [formField]="projectForm.name" />
  @if (projectForm.name().touched() && projectForm.name().invalid()) {
    <ul id="project-name-errors">
      @for (error of projectForm.name().errors(); track error.kind) {
        <li>{{ error.message }}</li>
      }
    </ul>
  }
  <button type="submit" [disabled]="projectForm().submitting()">Create project</button>
</form>
```

- `submit()` marks fields touched, runs the action only when the form is valid, and applies
  returned errors to the form/fields.
- Validators and dynamic rules (`disabled`, `hidden`, `readonly`) take a `{ when }` option in v22;
  the positional predicate form is deprecated.
- Async checks: `validateHttp(path.email, { request: ..., debounce: 400, ... })`.

## Reading data with `httpResource`

```ts
@Component({
  selector: 'app-project-detail',
  templateUrl: './project-detail.html',
})
export class ProjectDetail {
  readonly id = input.required<string>(); // bound from the route via withComponentInputBinding()
  private readonly apiUrl = inject(API_URL);

  protected readonly project = httpResource(() => `${this.apiUrl}/projects/${encodeURIComponent(this.id())}`, {
    parse: (body) => ProjectDto.parse(body),
  });
}
```

```html
@if (project.isLoading()) {
  <app-spinner />
} @else if (project.error()) {
  <app-error-state (retry)="project.reload()" />
} @else if (project.hasValue()) {
  <h1>{{ project.value().name }}</h1>
}
```

- Put the URL builder in the data-access layer (a function returning the request) if several
  components share it; components must not hard-code API paths in larger apps.
- `value()` throws in the error state — always branch on `error()`/`hasValue()` first.

## Signal Store (NgRx 22)

```ts
export const ProjectsStore = signalStore(
  withState({ filter: '' }),
  withProps(() => ({ repository: inject(ProjectRepository) })),
  withComputed(({ filter }) => ({ hasFilter: computed(() => filter().length > 0) })),
  withMethods((store) => ({
    setFilter(filter: string) {
      patchState(store, { filter });
    },
  })),
);
```

Provide feature stores at the route or component level (`providers: [ProjectsStore]`) unless the
state is truly global.
