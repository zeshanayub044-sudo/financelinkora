export type Json = string | number | boolean | null | { [key: string]: Json | undefined } | Json[];
export type MemberRole = "owner" | "administrator" | "accountant" | "finance_manager" | "auditor" | "employee";
export type AccountType = "asset" | "liability" | "equity" | "revenue" | "expense";
export type EntryStatus = "draft" | "approved" | "posted" | "reversed";
type Table<Row, Insert = Partial<Row>, Update = Partial<Insert>> = { Row: Row; Insert: Insert; Update: Update; Relationships: [] };
export type Database = { public: {
  Tables: {
    organizations: Table<{ id:string; name:string; legal_name:string|null; country:string|null; city:string|null; base_currency:string; fy_start_month:number; accounting_method:string; require_approval:boolean; journal_seq:number; created_at:string }, { id?:string; name:string; legal_name?:string|null; country?:string|null; city?:string|null; base_currency?:string; fy_start_month?:number; accounting_method?:string; require_approval?:boolean; journal_seq?:number; created_at?:string }>;
    user_profiles: Table<{id:string;full_name:string|null;created_at:string}>;
    organization_members: Table<{org_id:string;user_id:string;role:MemberRole}>;
    accounts: Table<{id:string;org_id:string;code:string;name:string;description:string|null;type:AccountType;normal_balance:"debit"|"credit";parent_id:string|null;is_active:boolean;created_at:string}, {id?:string;org_id:string;code:string;name:string;description?:string|null;type:AccountType;parent_id?:string|null;is_active?:boolean}>;
    accounting_periods: Table<{id:string;org_id:string;start_date:string;end_date:string;is_closed:boolean}, {id?:string;org_id:string;start_date:string;end_date:string;is_closed?:boolean}>;
    journal_entries: Table<{id:string;org_id:string;entry_no:string|null;entry_date:string;reference:string|null;description:string;currency:string;exchange_rate:number;status:EntryStatus;created_by:string;approved_by:string|null;posted_at:string|null;reverses_id:string|null;created_at:string}, {id?:string;org_id:string;entry_date:string;reference?:string|null;description:string;currency?:string;exchange_rate?:number;status?:EntryStatus;created_by?:string;approved_by?:string|null;posted_at?:string|null;reverses_id?:string|null;created_at?:string}>;
    journal_lines: Table<{id:string;entry_id:string;org_id:string;account_id:string;debit:number;credit:number;memo:string|null}, {id?:string;entry_id:string;org_id:string;account_id:string;debit?:number;credit?:number;memo?:string|null}>;
    audit_logs: Table<{id:number;org_id:string|null;user_id:string|null;action:string;entity_type:string;entity_id:string|null;old_values:Json|null;new_values:Json|null;at:string}>;
  };
  Views: { ledger: { Row: {org_id:string;account_id:string;code:string;account_name:string;entry_id:string;entry_no:string;entry_date:string;description:string;memo:string|null;debit:number;credit:number;running_balance:number}; Relationships: [] } };
  Functions: {
    approve_journal_entry: { Args:{p_entry:string}; Returns:undefined };
    post_journal_entry: { Args:{p_entry:string}; Returns:undefined };
    reverse_journal_entry: { Args:{p_entry:string;p_date?:string;p_reason?:string|null}; Returns:string };
    trial_balance: { Args:{p_org:string;p_from:string;p_to:string}; Returns:{code:string;name:string;type:AccountType;debit:number;credit:number}[] };
    create_organization: { Args:{p_name:string;p_legal:string|null;p_country:string|null;p_city:string|null;p_base_currency:string;p_fy_start_month:number;p_method:string;p_owner_name:string}; Returns:string };
    is_member: { Args:{p_org:string}; Returns:boolean };
    has_role: { Args:{p_org:string;p_roles:MemberRole[]}; Returns:boolean };
  };
  Enums: { member_role:MemberRole;account_type:AccountType;entry_status:EntryStatus };
  CompositeTypes: { [_ in never]: never };
} };
