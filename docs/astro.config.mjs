import { defineConfig } from 'astro/config';
import starlight from '@astrojs/starlight';

export default defineConfig({
  css: ['./src/styles/custom.css'],
  integrations: [
    starlight({
      title: 'Lanterna',
      defaultLocale: 'en',
      locales: {
        en: { label: 'English' },
        ja: { label: '日本語' },
      },
      sidebar: [
        { slug: 'index', label: 'Home', translations: { ja: 'ホーム' } },
        { slug: 'guide', label: 'Guide', translations: { ja: 'ガイド' } },
        { slug: 'usage', label: 'Usage', translations: { ja: '使い方' } },
      ],
      social: [
        {
          icon: 'github',
          label: 'GitHub',
          href: 'https://github.com/peacock0803sz/Lanterna',
        },
      ],
    }),
  ],
});
