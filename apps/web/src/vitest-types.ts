// Phase post-5 — pulls @testing-library/jest-dom's vitest matcher
// augmentation into tsc's view. The runtime registration happens in
// `vitest.setup.ts`; this file is for the type-checker only (tsconfig
// `include` covers src but not the setup file at the package root).
import '@testing-library/jest-dom/vitest';
