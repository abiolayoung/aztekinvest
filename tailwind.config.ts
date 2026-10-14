import type { Config } from "tailwindcss";

const config: Config = {
  content: [
    "./app/**/*.{ts,tsx}",
    "./components/**/*.{ts,tsx}",
    "./lib/**/*.{ts,tsx}",
  ],
  theme: {
    extend: {
      colors: {
        brand: {
          DEFAULT: "#123C32",
          hover: "#194F42",
          gold: "#D4B36A",
        },
        canvas: "#F6F7F5",
        ink: {
          DEFAULT: "#202923",
          muted: "#6B756E",
        },
        line: "#E2E7E2",
        muted: "#EEF2EF",
        success: "#247A50",
        warning: "#9A6A19",
        danger: "#B54747",
        info: "#426D8C",
      },
      fontFamily: {
        sans: [
          "Inter",
          "Segoe UI",
          "ui-sans-serif",
          "system-ui",
          "sans-serif",
        ],
      },
      boxShadow: {
        card: "0 1px 2px rgba(18, 60, 50, 0.04)",
      },
      borderRadius: {
        card: "12px",
      },
      maxWidth: {
        form: "32rem",
        content: "72rem",
      },
      transitionDuration: {
        ui: "180ms",
      },
    },
  },
  plugins: [],
};

export default config;
