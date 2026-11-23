import { brand } from "@/config/brand";

type LogoProps = {
  variant?: "mark" | "horizontal";
  theme?: "dark" | "light";
  loading?: boolean;
  className?: string;
};

export function Logo({ variant = "mark", theme = "dark", loading = false, className = "" }: LogoProps) {
  const light = theme === "light";
  const ring = "url(#ring)";
  const lColor = light ? "#0B3340" : "#FFFFFF";
  const pulse = light ? "#0891B2" : "#A7F3D0";
  const mark = (
    <svg viewBox="0 0 140 120" role="img" aria-label="LabCore" className={className}>
      <defs>
        <linearGradient id="ring" x1="0" y1="0" x2="1" y2="1">
          <stop offset="0" stopColor="#2DD4BF" />
          <stop offset="1" stopColor="#0891B2" />
        </linearGradient>
      </defs>
      <path d="M107.3 37 A44 44 0 1 0 107.3 83" fill="none" stroke={ring} strokeWidth="9" strokeLinecap="round" />
      <path d="M56 36 V82 H82" fill="none" stroke={lColor} strokeWidth="10" strokeLinecap="round" strokeLinejoin="round" />
      <path d="M68 60 H80 L87 42 L95 78 L101 56 L105 60 H126" fill="none" stroke={lColor} strokeOpacity=".18" strokeWidth="4" strokeLinecap="round" strokeLinejoin="round" />
      <path className="logo-beat" style={{ animationDuration: loading ? "1.35s" : "2.2s" }} pathLength="1" d="M68 60 H80 L87 42 L95 78 L101 56 L105 60 H126" fill="none" stroke={pulse} strokeWidth="4" strokeLinecap="round" strokeLinejoin="round" />
    </svg>
  );

  if (variant === "mark") return mark;
  return (
    <div className={`flex items-center gap-2 ${className}`}>
      <div className="w-11 shrink-0">{mark}</div>
      <div>
        <div className="text-xl font-extrabold tracking-tight" style={{ fontFamily: "var(--font-jakarta)" }}>
          <span style={{ color: lColor }}>Lab</span>
          <span className="bg-clip-text text-transparent" style={{ backgroundImage: light ? "linear-gradient(90deg,#0891B2,#0A7490)" : "linear-gradient(90deg,#2DD4BF,#0891B2)" }}>Core</span>
        </div>
        <div className="text-[10px] tracking-wide" style={{ color: lColor }}>{brand.tagline}</div>
      </div>
    </div>
  );
}
