import type { Metadata } from "next";
import "./globals.css";
export const metadata: Metadata = { title:{default:"Linkora Finance",template:"%s | Linkora Finance"}, description:"A clear, dependable workspace for finance operations.", icons:{icon:"/brand/app-icon.png",apple:"/brand/app-icon.png"} };
export default function RootLayout({children}:{children:React.ReactNode}) { return <html lang="en" suppressHydrationWarning><body>{children}</body></html>; }
