import { defineMiddleware } from "astro:middleware";

// `astro dev` serves a single build, so a `/<ref>/` path for another edition
// is rewritten onto the same page here, and the page renders as that edition.
// Query strings cannot carry the edition: Astro drops them on prerendered pages.
export const onRequest = defineMiddleware((context, next) => {
  if (!import.meta.env.DEV) return next();
  const match = /^\/(v\d[^/]*|main)(\/.*)$/.exec(context.url.pathname);
  if (match === null) return next();
  context.locals.devEdition = match[1];
  return next(match[2]);
});
