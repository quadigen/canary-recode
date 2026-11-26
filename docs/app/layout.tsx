import { Inter } from 'next/font/google';
import { Provider } from '@/components/provider';
import './global.css';
import { siteUrl } from '@/lib/shared';
import type { Metadata } from 'next';

export const metadata: Metadata = {
  metadataBase: new URL(siteUrl),
  title: {
    default: 'Kinemium Documentation',
    template: '%s | Kinemium Documentation',
  },
  description: 'Learn to build games and tools in Kinemium using Luau.',
};

const inter = Inter({
  subsets: ['latin'],
});

export default function Layout({ children }: LayoutProps<'/'>) {
  return (
    <html lang="en" className={inter.className} suppressHydrationWarning>
      <body className="flex flex-col min-h-screen">
        <Provider>{children}</Provider>
      </body>
    </html>
  );
}
