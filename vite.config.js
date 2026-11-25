import { defineConfig } from 'vite';

export default defineConfig({
  // GitHub Pages project site path matches the repository name.
  base: process.env.VERCEL ? '/' : '/kh/',
  envPrefix: ['VITE_', 'NEXT_PUBLIC_'],
  build: {
    target: 'es2020',
    sourcemap: false
  }
});
