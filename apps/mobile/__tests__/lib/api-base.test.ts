describe('API_BASE', () => {
  const original = process.env.EXPO_PUBLIC_API_BASE;

  afterEach(() => {
    if (original === undefined) delete process.env.EXPO_PUBLIC_API_BASE;
    else process.env.EXPO_PUBLIC_API_BASE = original;
    jest.resetModules();
  });

  it('defaults to the local API on :3000 when the env var is unset', () => {
    delete process.env.EXPO_PUBLIC_API_BASE;
    jest.resetModules();
    // Re-require so the module-level const re-reads process.env.
    expect(require('../../lib/api-base').API_BASE).toBe('http://localhost:3000');
  });

  it('uses EXPO_PUBLIC_API_BASE when set (deployed / LAN origin)', () => {
    process.env.EXPO_PUBLIC_API_BASE = 'https://api.example.test';
    jest.resetModules();
    expect(require('../../lib/api-base').API_BASE).toBe('https://api.example.test');
  });
});
