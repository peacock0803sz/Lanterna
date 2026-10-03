import { execFileSync } from "node:child_process";
import { defineConfig } from "astro/config";
import starlight from "@astrojs/starlight";

// Same shape and tag selection as scripts/build-versioned-docs.sh, read from the
// local clone without fetching.
function localVersionsJson() {
  const git = (...args) =>
    execFileSync("git", args, { encoding: "utf8", stdio: "pipe" }).trim();
  const hasDocs = (tag) => {
    try {
      git("cat-file", "-e", `${tag}:docs/package.json`);
      return true;
    } catch {
      return false;
    }
  };
  try {
    const tags = git("tag", "--sort=version:refname")
      .split("\n")
      .filter((tag) => tag !== "" && hasDocs(tag));
    let stable;
    try {
      stable = git("describe", "--tags", "--abbrev=0", "origin/stable");
    } catch {
      stable = tags.at(-1);
    }
    if (stable === undefined) return undefined;
    return JSON.stringify({ stable, versions: [...tags, "main"] });
  } catch {
    return undefined;
  }
}

// `astro dev` has no version build around it, so the edition selector and the
// notice work from the local tags instead.
if (process.argv.includes("dev") && process.env.DOCS_VERSIONS_JSON == null) {
  const versionsJson = localVersionsJson();
  if (versionsJson !== undefined) process.env.DOCS_VERSIONS_JSON = versionsJson;
}

const fonts =
  "https://fonts.googleapis.com/css2?family=IBM+Plex+Mono&family=Inter:wght@400;500;600&family=Newsreader:ital,wght@0,400;0,500;1,400&family=Noto+Serif+JP:wght@500&display=swap";

const docsBase = process.env.DOCS_BASE ?? "/";
const docsRef = process.env.DOCS_REF ?? "main";
const editRef = docsBase === "/" || docsRef === "main" ? "main" : docsRef;

export default defineConfig({
  base: docsBase,
  integrations: [
    starlight({
      title: "Lanterna",
      customCss: ["./src/styles/custom.css"],
      favicon: "/favicon.png",
      head: [
        {
          tag: "link",
          attrs: { rel: "apple-touch-icon", href: "/apple-touch-icon.png" },
        },
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
        baseUrl: `https://github.com/peacock0803sz/Lanterna/edit/${editRef}/docs/`,
      },
      components: {
        Footer: "./src/components/Footer.astro",
        Header: "./src/components/Header.astro",
        Hero: "./src/components/Hero.astro",
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
