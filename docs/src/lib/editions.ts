// Version metadata comes from DOCS_VERSIONS_JSON, exported per version build
// by scripts/build-versioned-docs.sh as a compact JSON string shaped
// {"stable":"<tag>","versions":["<tag>",...,"main"]}; `astro dev` fills it
// from the local tags. Without it there are no editions and the selector and
// notice render nothing.
type VersionsFile = { stable?: unknown; versions?: unknown };

export type EditionGroup = "stable" | "preview" | "archive";

export interface Edition {
  group: EditionGroup;
  /** Git ref the edition was built from: a tag, or `main`. */
  ref: string;
  /** Minor version shown as the edition number (`0.8`), or `NEXT` for main. */
  number: string;
  /** The same page in this edition. */
  href: string;
  isCurrent: boolean;
}

export interface Editions {
  all: Edition[];
  current?: Edition;
  stable?: Edition;
}

const editionNumber = (ref: string) =>
  ref === "main"
    ? "NEXT"
    : ref.replace(/^v/, "").split(".").slice(0, 2).join(".");

/**
 * Lists the editions for the page at `pathname`. `devRef` is the edition the
 * dev middleware rewrote a `/<ref>/` path from; `pathname` then lacks that
 * prefix.
 */
export function getEditions(pathname: string, devRef?: string): Editions {
  const versionsRaw = import.meta.env.DOCS_VERSIONS_JSON ?? "";
  const docsRef = devRef ?? import.meta.env.DOCS_REF ?? "main";
  // The pathname includes the configured `base` (e.g. `/v0.8.4/en/`), so strip
  // it before re-rooting the same page under another version.
  const base = import.meta.env.BASE_URL;
  const basePrefix = base === "/" ? "" : base.replace(/\/$/, "");
  const currentPrefix = devRef === undefined ? basePrefix : `/${devRef}`;

  let stableRef = "";
  let versions: string[] = [];
  try {
    const parsed = JSON.parse(versionsRaw) as VersionsFile;
    if (typeof parsed.stable === "string") stableRef = parsed.stable;
    if (Array.isArray(parsed.versions))
      versions = parsed.versions.filter(
        (version): version is string => typeof version === "string",
      );
  } catch {
    // No version metadata: there are no editions.
  }

  const suffix = pathname.slice(basePrefix.length) || "/";
  const all: Edition[] = [
    // The stable tag lives at the root, not under its own /<tag>/ prefix.
    ...(stableRef === ""
      ? []
      : [{ group: "stable" as const, ref: stableRef, prefix: "" }]),
    ...(versions.includes("main")
      ? [{ group: "preview" as const, ref: "main", prefix: "/main" }]
      : []),
    // versions.json lists tags oldest first; the menu shows the newest first.
    ...versions
      .filter((version) => version !== stableRef && version !== "main")
      .reverse()
      .map((version) => ({
        group: "archive" as const,
        ref: version,
        prefix: `/${version}`,
      })),
  ].map(({ group, ref, prefix }) => ({
    group,
    ref,
    number: editionNumber(ref),
    href: `${prefix}${suffix}`,
    // The /<stable-tag>/ snapshot build shares DOCS_REF with the stable root
    // build, so fall back to a ref match when no base prefix matches.
    isCurrent:
      prefix === currentPrefix ||
      (prefix === "" &&
        currentPrefix === `/${docsRef}` &&
        docsRef === stableRef),
  }));

  return {
    all,
    current: all.find((edition) => edition.isCurrent),
    stable: all.find((edition) => edition.group === "stable"),
  };
}
