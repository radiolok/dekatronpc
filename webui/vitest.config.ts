import { defineConfig } from 'vitest/config';
import path from 'path';

export default defineConfig({
  resolve: {
    alias: {
      '@': path.resolve(__dirname, './src'),
    },
  },
  test: {
    globals: true,
    // Konva needs the native `canvas` package under Node; tests use a DOM stand-in
    alias: {
      'react-konva': path.resolve(__dirname, './test/mocks/react-konva.tsx'),
    },
    include: ['test/**/*.test.{ts,tsx}'],
  },
});
