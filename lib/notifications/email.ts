import "server-only";

type EmailInput = {
  to: string;
  subject: string;
  text: string;
};

export async function sendTransactionalEmail(input: EmailInput): Promise<{
  status: "sent" | "skipped_unconfigured" | "failed";
  error?: string;
}> {
  const apiKey = process.env.EMAIL_PROVIDER_API_KEY;
  const from = process.env.EMAIL_FROM;
  if (!apiKey || !from) return { status: "skipped_unconfigured" };

  const response = await fetch("https://api.resend.com/emails", {
    method: "POST",
    headers: {
      Authorization: `Bearer ${apiKey}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      from,
      to: [input.to],
      subject: input.subject,
      text: input.text,
    }),
  });

  if (!response.ok) {
    return { status: "failed", error: `Email provider returned ${response.status}.` };
  }
  return { status: "sent" };
}
