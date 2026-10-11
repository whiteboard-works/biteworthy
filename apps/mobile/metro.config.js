// Expo's default Metro config. Since SDK 52 it detects the pnpm workspace
// and sets watchFolders and nodeModulesPaths itself. The hand-rolled
// version this replaces also set disableHierarchicalLookup, which hid each
// package's own node_modules from Metro: under pnpm's isolated layout
// react-native could not find its own `invariant`, and every EAS build
// failed in the JS bundle phase.
const { getDefaultConfig } = require('expo/metro-config');

module.exports = getDefaultConfig(__dirname);
