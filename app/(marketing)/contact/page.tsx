import type { Metadata } from "next";
import { contactAction } from "@/lib/actions/support";
import { StateForm } from "@/components/forms/state-form";
import { Input, Label, Textarea } from "@/components/ui/fields";

export const metadata: Metadata = { title: "Contact" };

export default function ContactPage() {
  const email = process.env.NEXT_PUBLIC_SUPPORT_EMAIL;
  return (
    <main className="mx-auto grid max-w-content gap-10 px-5 py-14 md:grid-cols-2">
      <div>
        <h1 className="text-3xl font-medium tracking-tight">Contact</h1>
        <p className="mt-3 text-sm leading-7 text-ink-muted">
          Use this form for a general enquiry. Account-specific messages are available after you sign in.
        </p>
        <p className="mt-4 text-sm text-ink">
          {email ? <a href={`mailto:${email}`}>{email}</a> : "A public support email has not been configured."}
        </p>
      </div>
      <div className="rounded-card border border-line bg-white p-5">
        <StateForm action={contactAction} submitLabel="Send message" pendingLabel="Sending...">
          <div className="hidden" aria-hidden="true">
            <label htmlFor="companyWebsite">Company website</label>
            <input id="companyWebsite" name="companyWebsite" tabIndex={-1} autoComplete="off" />
          </div>
          <div>
            <Label htmlFor="fullName">Name</Label>
            <Input id="fullName" name="fullName" required />
          </div>
          <div>
            <Label htmlFor="email">Email</Label>
            <Input id="email" name="email" type="email" required />
          </div>
          <div>
            <Label htmlFor="message">Message</Label>
            <Textarea id="message" name="message" required />
          </div>
        </StateForm>
      </div>
    </main>
  );
}
