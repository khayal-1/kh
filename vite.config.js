import { defineConfig } from 'vite';

export default defineConfig({
  // GitHub Pages is the primary project site; Vercel serves from the domain root.
  base: process.env.VERCEL ? '/' : '/elkhayal-motors/',
  envPrefix: ['VITE_', 'NEXT_PUBLIC_'],
  build: {
    target: 'es2020',
    sourcemap: false
  }
});
