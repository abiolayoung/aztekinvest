import * as React from "react";
import { cn } from "@/lib/utils";

export function Label({ className, ...props }: React.LabelHTMLAttributes<HTMLLabelElement>) {
  return <label className={cn("mb-1.5 block text-sm font-medium text-ink", className)} {...props} />;
}

export function Input({ className, ...props }: React.InputHTMLAttributes<HTMLInputElement>) {
  return (
    <input
      className={cn(
        "h-11 w-full rounded-lg border border-line bg-white px-3 text-sm text-ink outline-none transition duration-ui placeholder:text-ink-muted focus:border-brand",
        className,
      )}
      {...props}
    />
  );
}

export function Textarea({ className, ...props }: React.TextareaHTMLAttributes<HTMLTextAreaElement>) {
  return (
    <textarea
      className={cn(
        "min-h-28 w-full rounded-lg border border-line bg-white px-3 py-2 text-sm text-ink outline-none transition duration-ui placeholder:text-ink-muted focus:border-brand",
        className,
      )}
      {...props}
    />
  );
}

export function Select({ className, ...props }: React.SelectHTMLAttributes<HTMLSelectElement>) {
  return (
    <select
      className={cn(
        "h-11 w-full rounded-lg border border-line bg-white px-3 text-sm text-ink outline-none transition duration-ui focus:border-brand",
        className,
      )}
      {...props}
    />
  );
}

export function FormAlert({ error, message }: { error?: string; message?: string }) {
  if (error) {
    return (
      <div role="alert" className="rounded-lg border border-red-200 bg-red-50 px-3 py-2 text-sm text-danger">
        {error}
      </div>
    );
  }
  if (message) {
    return (
      <div role="status" className="rounded-lg border border-emerald-200 bg-emerald-50 px-3 py-2 text-sm text-success">
        {message}
      </div>
    );
  }
  return null;
}
