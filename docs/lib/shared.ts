import { createGetUrl } from 'fumadocs-core/source';

export const appName = 'Kinemium Documentation';
export const docsRoute = '/docs';
export const docsImageRoute = '/og/docs';
export const siteUrl = 'https://kinemium.docs.quadigen.com';

export const gitConfig = {
  user: 'quadigen',
  repo: 'canary-recode',
  branch: 'master',
};

const getImageUrl = createGetUrl(docsImageRoute);

export function getPageImageUrl(page: { slugs: string[]; locale?: string }) {
  const segments = [...page.slugs, 'image.png'];

  return { segments, url: getImageUrl(segments, page.locale) };
}
