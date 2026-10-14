import { noticeAction } from "@/lib/actions/admin";
import { StateForm } from "@/components/forms/state-form";
import { Input, Label, Select, Textarea } from "@/components/ui/fields";
import { PageIntro } from "@/components/ui/page";
import { can } from "@/lib/auth/permissions";
import { requireUser } from "@/lib/auth/session";

export default async function NoticesPage() {
  const { supabase, profile } = await requireUser();
  if (!can(profile.role, "sendNotices")) return <p>You do not have permission to send notices.</p>;
  const { data: clients } = await supabase.from("profiles").select("id, full_name").eq("role", "client").order("full_name").limit(200);
  return (
    <div className="max-w-form">
      <PageIntro title="Send a notice" body="The email subject stays generic. The full message is shown after the client signs in." />
      <StateForm action={noticeAction} submitLabel="Send notice">
        <Label htmlFor="userId">Client</Label>
        <Select id="userId" name="userId" defaultValue={clients?.[0]?.id ?? ""}>
          {(clients ?? []).map((client) => <option key={client.id} value={client.id}>{client.full_name}</option>)}
        </Select>
        <Label htmlFor="title">Title</Label>
        <Input id="title" name="title" required />
        <Label htmlFor="message">Message</Label>
        <Textarea id="message" name="message" required />
      </StateForm>
    </div>
  );
}
