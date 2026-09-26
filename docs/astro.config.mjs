import { defineConfig } from "astro/config";
import starlight from "@astrojs/starlight";

const fonts =
  "https://fonts.googleapis.com/css2?family=IBM+Plex+Mono&family=Inter:wght@400;500;600&family=Newsreader:ital,wght@0,400;0,500;1,400&family=Noto+Serif+JP:wght@500&display=swap";

export default defineConfig({
  integrations: [
    starlight({
      title: "Lanterna",
      customCss: ["./src/styles/custom.css"],
      head: [
        {
          tag: "meta",
          attrs: {
            property: "og:image",
            content: "https://img.p3ac0ck.net/figs/Lanterna.png",
          },
        },
        {
          tag: "link",
          attrs: { rel: "preconnect", href: "https://fonts.googleapis.com" },
        },
        {
          tag: "link",
          attrs: {
            rel: "preconnect",
            href: "https://fonts.gstatic.com",
            crossorigin: true,
          },
        },
        { tag: "link", attrs: { rel: "stylesheet", href: fonts } },
      ],
      defaultLocale: "en",
      locales: {
        en: { label: "English" },
        ja: { label: "日本語" },
      },
      sidebar: [
        { slug: "index", label: "Home", translations: { ja: "ホーム" } },
        { slug: "guide", label: "Guide", translations: { ja: "ガイド" } },
        { slug: "usage", label: "Usage", translations: { ja: "使い方" } },
      ],
      social: [
        {
          icon: "github",
          label: "GitHub",
          href: "https://github.com/peacock0803sz/Lanterna",
        },
      ],
      editLink: {
        baseUrl: "https://github.com/peacock0803sz/Lanterna/edit/main/docs/",
      },
      components: {
        Footer: "./src/components/Footer.astro",
        Header: "./src/components/Header.astro",
        LanguageSelect: "./src/components/LanguageSelect.astro",
        PageFrame: "./src/components/PageFrame.astro",
        PageTitle: "./src/components/PageTitle.astro",
        Pagination: "./src/components/Pagination.astro",
        ThemeSelect: "./src/components/ThemeSelect.astro",
        TwoColumnContent: "./src/components/TwoColumnContent.astro",
      },
      expressiveCode: {
        // Starlight switches between these with the site theme.
        themes: ["github-dark-default", "github-light-default"],
        useStarlightUiThemeColors: false,
        styleOverrides: {
          borderRadius: "6px",
          borderColor: "var(--ln-hairline)",
          codeBackground: "var(--ln-code)",
          codeFontFamily: "var(--ln-font-mono)",
          codeFontSize: "13px",
          codeLineHeight: "1.65",
          codePaddingBlock: "16px",
          codePaddingInline: "18px",
          frames: {
            frameBoxShadowCssValue: "none",
            terminalBackground: "var(--ln-code)",
            terminalTitlebarBackground: "var(--ln-code)",
            terminalTitlebarBorderBottomColor: "var(--ln-hairline)",
            terminalTitlebarDotsOpacity: "0",
            terminalTitlebarForeground: "var(--ln-muted)",
            editorBackground: "var(--ln-code)",
          },
        },
      },
    }),
  ],
});
