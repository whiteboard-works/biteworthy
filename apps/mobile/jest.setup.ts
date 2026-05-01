/**
 * Phase post-5 — jest setup file.
 *
 * @testing-library/react-native v12.4+ ships built-in matchers
 * (toBeOnTheScreen, toHaveTextContent, etc.) — no separate
 * jest-native import needed.
 *
 * The jest-expo preset handles RN globals + transformer config;
 * this file is for future per-test-suite extensions.
 */
import '@testing-library/react-native/extend-expect';
