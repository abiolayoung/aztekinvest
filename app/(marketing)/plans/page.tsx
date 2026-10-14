import type { Metadata } from "next";
import { PricingSection } from "@/components/plans/pricing-section";

export const metadata: Metadata = { title: "Investment plans" };

export default function PlansPage() {
  return (
    <main>
      <PricingSection />
    </main>
  );
}
