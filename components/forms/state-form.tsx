"use client";

import { useActionState, useEffect, useRef } from "react";
import { FormAlert } from "@/components/ui/fields";
import { Button } from "@/components/ui/button";
import type { ActionState } from "@/lib/actions/types";

export function StateForm({
  action,
  children,
  submitLabel,
  pendingLabel = "Saving...",
}: {
  action: (state: ActionState, formData: FormData) => Promise<ActionState>;
  children: React.ReactNode;
  submitLabel: string;
  pendingLabel?: string;
}) {
  const formRef = useRef<HTMLFormElement>(null);
  const preserved = useRef<Array<[string, string]>>([]);
  const [state, formAction, pending] = useActionState(async (previous: ActionState, formData: FormData) => {
    const entries: Array<[string, string]> = [];
    for (const [key, value] of formData.entries()) {
      if (typeof value === "string") entries.push([key, value]);
    }
    preserved.current = entries;
    return action(previous, formData);
  }, {});

  useEffect(() => {
    const form = formRef.current;
    if (!form || !state.error) return;
    for (const [key, value] of preserved.current) {
      const element = form.elements.namedItem(key);
      if (!element || element instanceof RadioNodeList) continue;
      if (element instanceof HTMLInputElement) {
        if (element.type === "checkbox" || element.type === "radio") element.checked = value === "on" || value === element.value;
        else if (element.type !== "file" && element.type !== "hidden") element.value = value;
      } else if (element instanceof HTMLTextAreaElement || element instanceof HTMLSelectElement) {
        element.value = value;
      }
    }
  }, [state]);

  return (
    <form ref={formRef} action={formAction} className="space-y-4">
      <FormAlert error={state.error} message={state.message} />
      {children}
      <Button type="submit" disabled={pending}>
        {pending ? pendingLabel : submitLabel}
      </Button>
    </form>
  );
}
