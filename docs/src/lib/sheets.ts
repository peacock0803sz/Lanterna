import type { StarlightRouteData } from "@astrojs/starlight/route-data";

type Sidebar = StarlightRouteData["sidebar"];

const trimSlash = (path: string) => path.replace(/\/+$/, "");

/**
 * Returns the chart sheet letter for a page: its position among the top-level
 * sidebar links as A, B, C, and so on. The home page is sheet A.
 */
export function sheetKey(sidebar: Sidebar, href: string): string | undefined {
  const links = sidebar.filter((entry) => entry.type === "link");
  const index = links.findIndex(
    (entry) => trimSlash(entry.href) === trimSlash(href),
  );
  return index === -1 ? undefined : String.fromCharCode(65 + index);
}
