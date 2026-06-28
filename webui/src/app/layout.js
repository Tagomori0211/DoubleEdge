import "./globals.css";

export const metadata = {
  title: "DoubleEdge Dashboard — Multi-Agent Controller",
  description: "Real-time dashboard to monitor and command the DoubleEdge multi-agent collaborative development environment.",
};

export default function RootLayout({ children }) {
  return (
    <html lang="ja">
      <body>
        {children}
      </body>
    </html>
  );
}
