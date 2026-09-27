Generate comprehensive tests for the specified code, function, or module.

First, read the source file to understand the implementation before writing tests.

## Test Generation Guidelines

### Coverage Required
- **Happy path**: Normal successful execution with valid inputs
- **Edge cases**: Empty strings, null/undefined, zero, negative numbers, max values, empty arrays
- **Error cases**: Invalid input, missing required fields, service failures, network errors
- **Boundary conditions**: Off-by-one, exact limits, just over limits

### Test Structure
Each test must follow Arrange → Act → Assert:
```typescript
it('returns 404 when user does not exist', async () => {
  // Arrange
  const nonExistentId = 'user-does-not-exist';

  // Act
  const result = await getUser(nonExistentId);

  // Assert
  expect(result.status).toBe(404);
  expect(result.body.error.code).toBe('USER_NOT_FOUND');
});
```

### Test Naming
Format: `'<does what> when <condition>'`
- Good: `'returns empty array when no users match the filter'`
- Bad: `'test getUserList'`

### Mocking Strategy
- Mock all external dependencies: database, HTTP clients, file system, clock, random
- Use factory functions for test data — never raw object literals
- Do NOT mock the module under test

### Framework
Use the project's configured test framework (from AGENTS.md). If not configured, use the most appropriate for the language.

### What to Generate
1. Import statements and test setup
2. `describe` block named after the module/function under test
3. All test cases listed above
4. Shared fixtures or factory functions at the top
5. Teardown if needed

---
Generate tests for: $ARGUMENTS
