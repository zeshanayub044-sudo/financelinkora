"use client";

import { useState } from "react";
import { Button } from "@/components/ui";

export function WorkspaceUnavailable({ onRetry }: { onRetry?: () => void } = {}) {
  const [retrying, setRetrying] = useState(false);
  return (
    <main className="grid min-h-screen place-items-center p-6">
      <section role="alert" className="surface max-w-xl p-8">
        <p className="text-xs font-bold uppercase tracking-widest text-amber-700">Workspace unavailable</p>
        <h1 className="mt-3 text-2xl font-bold">We couldn’t verify your workspace</h1>
        <p className="mt-3 text-sm leading-6 text-slate-500">
          Organization access could not be loaded. No organization was created. Check your connection and retry; if the problem continues, ask an organization owner to check Supabase availability and membership access.
        </p>
        <Button className="mt-5" disabled={retrying} onClick={() => { setRetrying(true); if (onRetry) onRetry(); else window.location.reload(); }}>
          {retrying ? "Retrying…" : "Retry"}
        </Button>
      </section>
    </main>
  );
}
