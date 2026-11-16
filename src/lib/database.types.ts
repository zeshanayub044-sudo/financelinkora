// Schema types reflect the preserved foundation migration plus additive accounting hardening.
export type Json = string | number | boolean | null | { [key: string]: Json | undefined } | Json[];
export type MemberRole = "owner" | "administrator" | "accountant" | "finance_manager" | "auditor" | "employee" | "approver" | "viewer";
export type AccountType = "asset" | "liability" | "equity" | "revenue" | "expense";
export type EntryStatus = "draft" | "submitted" | "pending_approval" | "approved" | "posted" | "reversed";
type Table<Row, Insert = Partial<Row>, Update = Partial<Insert>> = { Row: Row; Insert: Insert; Update: Update; Relationships: [] };
type JournalLineInput = { account_id: string; debit: number; credit: number; memo?: string | null };

export type Database = { public: {
  Tables: {
    organizations: Table<{ id:string; name:string; legal_name:string|null; country:string|null; city:string|null; base_currency:string; fy_start_month:number; accounting_method:string; require_approval:boolean; journal_seq:number; created_at:string }, { id?:string; name:string; legal_name?:string|null; country?:string|null; city?:string|null; base_currency?:string; fy_start_month?:number; accounting_method?:string; require_approval?:boolean; journal_seq?:number; created_at?:string }>;
    user_profiles: Table<{id:string;full_name:string|null;created_at:string}>;
    organization_members: Table<{org_id:string;user_id:string;role:MemberRole}>;
    accounts: Table<{id:string;org_id:string;code:string;name:string;description:string|null;type:AccountType;normal_balance:"debit"|"credit";parent_id:string|null;is_active:boolean;created_at:string}, {id?:string;org_id:string;code:string;name:string;description?:string|null;type:AccountType;parent_id?:string|null;is_active?:boolean}>;
    accounting_periods: Table<{id:string;org_id:string;start_date:string;end_date:string;is_closed:boolean}, {id?:string;org_id:string;start_date:string;end_date:string;is_closed?:boolean}>;
    journal_entries: Table<{id:string;org_id:string;entry_no:string|null;entry_date:string;reference:string|null;description:string;currency:string;exchange_rate:number;status:EntryStatus;created_by:string;approved_by:string|null;posted_at:string|null;reverses_id:string|null;submitted_at:string|null;rejected_at:string|null;rejected_by:string|null;rejection_reason:string|null;reversal_reason:string|null;entry_kind:string;created_at:string}, {id?:string;org_id:string;entry_date:string;reference?:string|null;description:string;currency?:string;exchange_rate?:number;status?:EntryStatus;created_by?:string;approved_by?:string|null;posted_at?:string|null;reverses_id?:string|null;submitted_at?:string|null;rejected_at?:string|null;rejected_by?:string|null;rejection_reason?:string|null;reversal_reason?:string|null;entry_kind?:string;created_at?:string}>;
    journal_lines: Table<{id:string;entry_id:string;org_id:string;account_id:string;debit:number;credit:number;base_debit:number;base_credit:number;exchange_rate:number;memo:string|null}, {id?:string;entry_id:string;org_id:string;account_id:string;debit?:number;credit?:number;memo?:string|null}>;
    audit_logs: Table<{id:number;org_id:string|null;user_id:string|null;action:string;entity_type:string;entity_id:string|null;old_values:Json|null;new_values:Json|null;at:string}>;
  };
  Views: { ledger: { Row: {org_id:string;account_id:string;code:string;account_name:string;entry_id:string;entry_no:string;entry_date:string;description:string;memo:string|null;debit:number;credit:number;running_balance:number;currency:string;exchange_rate:number;transaction_debit:number;transaction_credit:number}; Relationships: [] } };
  Functions: {
    create_organization: { Args:{p_name:string;p_legal:string|null;p_country:string|null;p_city:string|null;p_base_currency:string;p_fy_start_month:number;p_method:string;p_owner_name:string}; Returns:string };
    create_journal_entry_draft: { Args:{p_org:string;p_entry_date:string;p_reference:string|null;p_description:string;p_currency:string;p_exchange_rate:number;p_entry_kind:string;p_lines:JournalLineInput[]}; Returns:string };
    submit_journal_entry: { Args:{p_entry:string}; Returns:undefined };
    queue_journal_entry: { Args:{p_entry:string}; Returns:undefined };
    approve_journal_entry: { Args:{p_entry:string}; Returns:undefined };
    reject_journal_entry: { Args:{p_entry:string;p_reason:string}; Returns:undefined };
    post_journal_entry: { Args:{p_entry:string}; Returns:undefined };
    reverse_journal_entry: { Args:{p_entry:string;p_date?:string;p_reason:string}; Returns:string };
    set_organization_member_role: { Args:{p_org:string;p_user:string;p_role:MemberRole}; Returns:undefined };
    add_organization_member: { Args:{p_org:string;p_user:string;p_role:MemberRole}; Returns:undefined };
    remove_organization_member: { Args:{p_org:string;p_user:string}; Returns:undefined };
    trial_balance: { Args:{p_org:string;p_from:string;p_to:string}; Returns:{code:string;name:string;type:AccountType;debit:number;credit:number}[] };
    trial_balance_as_of: { Args:{p_org:string;p_as_of:string}; Returns:{code:string;name:string;type:AccountType;debit:number;credit:number}[] };
    profit_and_loss: { Args:{p_org:string;p_from:string;p_to:string}; Returns:{code:string;name:string;type:AccountType;amount:number}[] };
    balance_sheet: { Args:{p_org:string;p_as_of:string}; Returns:{section:string;code:string;name:string;balance:number}[] };
    financial_summary: { Args:{p_org:string;p_from:string;p_to:string;p_as_of:string}; Returns:{income:number;expenses:number;profit:number;assets:number;liabilities:number;equity:number;cash_balance:number;bank_balance:number;accounts_receivable:number;accounts_payable:number}[] };
    monthly_financial_activity: { Args:{p_org:string;p_from:string}; Returns:{month_start:string;revenue:number;expenses:number}[] };
    is_member: { Args:{p_org:string}; Returns:boolean };
    has_role: { Args:{p_org:string;p_roles:MemberRole[]}; Returns:boolean };
  };
  Enums: { member_role:MemberRole;account_type:AccountType;entry_status:EntryStatus };
  CompositeTypes: { [_ in never]: never };
} };

