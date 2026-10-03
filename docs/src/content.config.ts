import { defineCollection } from "astro:content";
import { z } from "astro/zod";
import { docsLoader, i18nLoader } from "@astrojs/starlight/loaders";
import { docsSchema, i18nSchema } from "@astrojs/starlight/schema";

export const collections = {
  docs: defineCollection({ loader: docsLoader(), schema: docsSchema() }),
  i18n: defineCollection({
    loader: i18nLoader(),
    schema: i18nSchema({
      extend: z.object({
        "editions.accessibleLabel": z.string().optional(),
        "editions.unreleased": z.string().optional(),
        "editions.allReleases": z.string().optional(),
        "notice.archived": z.string().optional(),
        "notice.archivedLink": z.string().optional(),
        "notice.preview": z.string().optional(),
        "notice.previewLink": z.string().optional(),
      }),
    }),
  }),
};
