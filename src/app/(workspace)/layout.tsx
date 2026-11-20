import { redirect } from "next/navigation";
import { supabaseConfigured } from "@/lib/supabase/config";
import { getWorkspace } from "@/lib/data";
import { WorkspaceShell } from "@/components/workspace-shell";
import { SetupOrganization } from "@/components/setup-organization";
import { WorkspaceUnavailable } from "@/components/workspace-unavailable";

export const dynamic = "force-dynamic";

export default async function WorkspaceLayout({ children }: { children: React.ReactNode }) {
  if (!supabaseConfigured) {
    return (
      <div className="grid min-h-screen place-items-center p-6">
        <div className="surface max-w-xl p-8">
          <p className="text-xs font-bold uppercase tracking-widest text-blue-600">Supabase connection needed</p>
          <h1 className="mt-3 text-2xl font-bold">Connect the selected Linkora project</h1>
          <p className="mt-3 text-sm leading-6 text-slate-500">
            Use the existing Linkora Finance project (reference jztejhppiepczvqiebik). Apply the versioned migrations with the Supabase CLI,
            then set NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY in .env.local. The approved project URL is preconfigured; set NEXT_PUBLIC_SUPABASE_URL only to override it for local Supabase. Never put a service-role key or database password in browser variables.
          </p>
        </div>
      </div>
    );
  }

  const workspace = await getWorkspace();
  const supabase = workspace.supabase;
  if (!supabase) return <WorkspaceUnavailable />;
  if (workspace.error) return <WorkspaceUnavailable />;
  const { org, orgs, user } = workspace;
  if (!user) redirect("/login");
  if (!org) return <SetupOrganization userName={user.email ?? ""} />;
  if (org.role === "employee") {
    return (
      <main className="grid min-h-screen place-items-center p-6">
        <section className="surface max-w-lg p-8 text-center">
          <h1 className="text-2xl font-bold">Workspace access is restricted</h1>
          <p className="mt-3 text-sm leading-6 text-slate-500">The Employee role does not have access to financial reports or accounting records. Ask an organization owner to assign an authorized finance role.</p>
          <p className="mt-4 text-xs text-slate-400">Signed in as {user.email}</p>
        </section>
      </main>
    );
  }

  const { data: workflowRows, error: workflowError } = await supabase
    .from("journal_entries")
    .select("id,entry_no,description,status")
    .eq("org_id", org.id)
    .in("status", ["pending_approval", "approved"])
    .order("created_at", { ascending: false })
    .limit(10);
  const workflowItems = (workflowRows ?? []).map((row) => ({
    id: row.id,
    entryNo: row.entry_no,
    description: row.description,
    status: row.status,
  }));

  return (
    <WorkspaceShell
      org={org}
      orgs={orgs}
      user={{ email: user.email }}
      workflowItems={workflowItems}
      workflowUnavailable={Boolean(workflowError)}
    >
      {children}
    </WorkspaceShell>
  );
}
