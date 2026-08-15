import type { Metadata } from "next";
import { Geist, Geist_Mono } from "next/font/google";
import { headers } from "next/headers";
import "./globals.css";

const geistSans = Geist({
  variable: "--font-geist-sans",
  subsets: ["latin"],
});

const geistMono = Geist_Mono({
  variable: "--font-geist-mono",
  subsets: ["latin"],
});

export async function generateMetadata(): Promise<Metadata> {
  const requestHeaders = await headers();
  const forwardedHost = requestHeaders.get("x-forwarded-host");
  const rawHost = forwardedHost || requestHeaders.get("host") || "localhost:3000";
  const host = /^[a-zA-Z0-9.:[\]-]+$/.test(rawHost) ? rawHost : "localhost:3000";
  const forwardedProtocol = requestHeaders.get("x-forwarded-proto");
  const protocol = forwardedProtocol === "http" || forwardedProtocol === "https"
    ? forwardedProtocol
    : host.startsWith("localhost")
      ? "http"
      : "https";
  const origin = `${protocol}://${host}`;
  const description =
    "A considered workspace for generating, reviewing, and keeping track of AI video.";

  return {
    metadataBase: new URL(origin),
    title: {
      default: "Clawnsole",
      template: "%s · Clawnsole",
    },
    description,
    openGraph: {
      type: "website",
      title: "Clawnsole · Make it move.",
      description,
      url: origin,
      siteName: "Clawnsole",
      images: [{ url: `${origin}/og.png`, width: 1731, height: 909, alt: "Clawnsole — Make it move." }],
    },
    twitter: {
      card: "summary_large_image",
      title: "Clawnsole · Make it move.",
      description,
      images: [`${origin}/og.png`],
    },
  };
}

export default function RootLayout({
  children,
}: Readonly<{
  children: React.ReactNode;
}>) {
  return (
    <html lang="en">
      <body
        className={`${geistSans.variable} ${geistMono.variable} antialiased`}
      >
        {children}
      </body>
    </html>
  );
}
