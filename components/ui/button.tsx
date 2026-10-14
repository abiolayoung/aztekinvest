import { Slot } from "@radix-ui/react-slot";
import { cva, type VariantProps } from "class-variance-authority";
import * as React from "react";
import { cn } from "@/lib/utils";

const buttonVariants = cva(
  "inline-flex items-center justify-center gap-2 rounded-lg text-sm font-medium transition duration-ui disabled:pointer-events-none disabled:opacity-50",
  {
    variants: {
      variant: {
        primary: "bg-brand text-white hover:bg-brand-hover",
        secondary: "border border-line bg-white text-ink hover:bg-muted",
        ghost: "text-ink hover:bg-muted",
        danger: "bg-danger text-white hover:opacity-90",
      },
      size: {
        sm: "h-9 px-3",
        md: "h-11 px-4",
      },
    },
    defaultVariants: { variant: "primary", size: "md" },
  },
);

export function Button({
  className,
  variant,
  size,
  asChild = false,
  ...props
}: React.ButtonHTMLAttributes<HTMLButtonElement> &
  VariantProps<typeof buttonVariants> & { asChild?: boolean }) {
  const Comp = asChild ? Slot : "button";
  return <Comp className={cn(buttonVariants({ variant, size }), className)} {...props} />;
}
