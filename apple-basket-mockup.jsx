import { useState } from "react";
import { Calendar, CheckSquare, Heart } from "lucide-react";

// ─── Theme ────────────────────────────────────────────────────────────────────

const T = {
  light: {
    bg: "rgba(246,246,246,0.95)",
    text: "#1c1c1e",
    secondary: "#636366",
    caption: "#8e8e93",
    divider: "rgba(0,0,0,0.09)",
    btnBg: "rgba(0,0,0,0.055)",
    btnHover: "rgba(0,0,0,0.09)",
    bar: "rgba(24,24,26,0.93)",
    shadow: "0 10px 40px rgba(0,0,0,0.22), 0 2px 8px rgba(0,0,0,0.10)",
    border: "rgba(0,0,0,0.11)",
    caret: "rgba(246,246,246,0.98)",
  },
  dark: {
    bg: "rgba(36,36,38,0.97)",
    text: "#f2f2f7",
    secondary: "#aeaeb2",
    caption: "#636366",
    divider: "rgba(255,255,255,0.09)",
    btnBg: "rgba(255,255,255,0.07)",
    btnHover: "rgba(255,255,255,0.12)",
    bar: "rgba(18,18,20,0.97)",
    shadow: "0 10px 40px rgba(0,0,0,0.60), 0 2px 8px rgba(0,0,0,0.35)",
    border: "rgba(255,255,255,0.10)",
    caret: "rgba(36,36,38,0.98)",
  },
};

// ─── Data ─────────────────────────────────────────────────────────────────────

const SECTIONS = [
  { id: "cal",       label: "Calendar",  Icon: Calendar,    color: "#3478F6" },
  { id: "reminders", label: "Reminders", Icon: CheckSquare, color: "#FF9500" },
  { id: "health",    label: "Health",    Icon: Heart,       color: "#FF2D55" },
];

const STATUS_COLOR = {
  ok:       "#34C759",
  stale:    "#FF9F0A",
  error:    "#FF3B30",
  noAccess: "#FF9F0A",
  planned:  "#8E8E93",
};

const STATUS_LABELS = {
  ok: "ok", stale: "stale", error: "error", noAccess: "no-ac", planned: "planned",
};

function hexRgb(hex) {
  const r = parseInt(hex.slice(1, 3), 16);
  const g = parseInt(hex.slice(3, 5), 16);
  const b = parseInt(hex.slice(5, 7), 16);
  return `${r},${g},${b}`;
}

// ─── Primitives ───────────────────────────────────────────────────────────────

function Dot({ color, size = 7 }) {
  return (
    <div style={{
      width: size, height: size, borderRadius: "50%", background: color, flexShrink: 0,
      boxShadow: `0 0 0 1.5px rgba(0,0,0,0.10), 0 0 ${size + 2}px ${color}55`,
    }} />
  );
}

function Hr({ t }) {
  return <div style={{ height: 1, background: t.divider, margin: "8px 0" }} />;
}

function FooterBtn({ children, t, muted }) {
  const [hov, setHov] = useState(false);
  return (
    <button
      onMouseEnter={() => setHov(true)} onMouseLeave={() => setHov(false)}
      style={{
        background: hov ? t.btnHover : "transparent", border: "none", borderRadius: 5,
        color: muted ? t.caption : t.text, cursor: "pointer",
        fontFamily: "-apple-system, BlinkMacSystemFont, 'SF Pro Text', sans-serif",
        fontSize: 11, padding: "3px 8px", transition: "background 0.1s",
      }}
    >
      {children}
    </button>
  );
}

// ─── Section Button ───────────────────────────────────────────────────────────

function SectionBtn({ section, selected, statusColor, onClick, t }) {
  const { label, Icon, color } = section;
  const [hov, setHov] = useState(false);
  return (
    <button
      onClick={onClick}
      onMouseEnter={() => setHov(true)} onMouseLeave={() => setHov(false)}
      style={{
        flex: 1,
        background: selected
          ? `rgba(${hexRgb(color)}, 0.11)`
          : hov ? t.btnHover : t.btnBg,
        border: selected
          ? `1.5px solid rgba(${hexRgb(color)}, 0.32)`
          : "1.5px solid transparent",
        borderRadius: 10, cursor: "pointer",
        padding: "10px 0 9px",
        display: "flex", flexDirection: "column", alignItems: "center", gap: 5,
        transition: "all 0.14s ease", position: "relative",
      }}
    >
      <div style={{ position: "absolute", top: 6, right: 6 }}>
        <Dot color={statusColor} size={6} />
      </div>
      <Icon
        size={19} strokeWidth={1.75}
        color={selected ? color : t.secondary}
        style={{ transition: "color 0.14s" }}
      />
      <span style={{
        fontFamily: "-apple-system, BlinkMacSystemFont, 'SF Pro Text', sans-serif",
        fontSize: 11, fontWeight: selected ? 600 : 400,
        color: selected ? color : t.secondary,
        letterSpacing: "-0.01em", transition: "color 0.14s",
      }}>
        {label}
      </span>
    </button>
  );
}

// ─── Detail Panels ────────────────────────────────────────────────────────────

function Planned({ label, phase, t }) {
  return (
    <p style={{ margin: 0, color: t.caption, fontSize: 11, lineHeight: 1.55 }}>
      {label} bridging arrives in Phase {phase}.
    </p>
  );
}

function NoAccess({ service, t }) {
  return (
    <p style={{ margin: 0, color: t.secondary, fontSize: 11, lineHeight: 1.55 }}>
      Approve {service} in System Settings → Privacy & Security → {service}.
    </p>
  );
}

function ErrMsg({ t }) {
  return (
    <p style={{ margin: 0, color: "#FF3B30", fontSize: 11, lineHeight: 1.55 }}>
      EventKit error — check ~/Library/Logs/AppleBasket.err.log.
    </p>
  );
}

function CalDetail({ status, t }) {
  if (status === "planned")  return <Planned label="Calendar" phase="2" t={t} />;
  if (status === "noAccess") return <NoAccess service="Calendars" t={t} />;
  if (status === "error")    return <ErrMsg t={t} />;

  const events = [
    { time: "10:00 AM", title: "Team standup",    dot: "#3478F6" },
    { time: "12:30 PM", title: "Lunch w/ Sarah",  dot: "#34C759" },
    { time:  "3:00 PM", title: "Dentist",         dot: "#FF9500" },
  ];

  return (
    <div style={{ display: "flex", flexDirection: "column" }}>
      <div style={{ fontSize: 11, marginBottom: 8,
        color: status === "stale" ? "#FF9F0A" : t.secondary }}>
        {status === "stale" ? "⚠ HA unreachable · cached 4 min ago" : "Last sync 2 min ago"}
      </div>
      <div style={{ fontSize: 10, fontWeight: 600, letterSpacing: "0.04em",
        textTransform: "uppercase", color: t.caption, marginBottom: 5 }}>
        Today · 3 events
      </div>
      {events.map((e, i) => (
        <div key={i} style={{ display: "flex", alignItems: "center", gap: 7, padding: "2.5px 0" }}>
          <div style={{ width: 3, height: 13, borderRadius: 2, background: e.dot, flexShrink: 0 }} />
          <span style={{ color: t.caption, fontSize: 11, width: 54, flexShrink: 0 }}>{e.time}</span>
          <span style={{ color: t.text, fontSize: 11 }}>{e.title}</span>
        </div>
      ))}
      <div style={{ fontSize: 10, fontWeight: 600, letterSpacing: "0.04em",
        textTransform: "uppercase", color: t.caption, margin: "7px 0 5px" }}>
        Tomorrow · 1 event
      </div>
      <div style={{ display: "flex", alignItems: "center", gap: 7, padding: "2.5px 0" }}>
        <div style={{ width: 3, height: 13, borderRadius: 2, background: "#8E59D2", flexShrink: 0 }} />
        <span style={{ color: t.caption, fontSize: 11, width: 54, flexShrink: 0 }}>9:00 AM</span>
        <span style={{ color: t.text, fontSize: 11 }}>Haircut</span>
      </div>
    </div>
  );
}

function RemindersDetail({ status, t }) {
  if (status === "noAccess") return <NoAccess service="Reminders" t={t} />;
  if (status === "error")    return <ErrMsg t={t} />;

  const lists = [
    { name: "Household",       n: 3 },
    { name: "Shopping",        n: 2 },
    { name: "Home Automation", n: 1 },
    { name: "Work",            n: 1 },
  ];

  return (
    <div style={{ display: "flex", flexDirection: "column" }}>
      <div style={{ fontSize: 11, marginBottom: 8,
        color: status === "stale" ? "#FF9F0A" : t.secondary }}>
        {status === "stale" ? "⚠ HA unreachable · 7 open cached" : "7 open · last change 2 min ago"}
      </div>
      {lists.map((l, i) => (
        <div key={i} style={{ display: "flex", alignItems: "center",
          justifyContent: "space-between", padding: "3px 0" }}>
          <div style={{ display: "flex", alignItems: "center", gap: 6 }}>
            <span style={{ color: "#FF9500", fontSize: 11, lineHeight: 1 }}>≡</span>
            <span style={{ color: t.text, fontSize: 11 }}>{l.name}</span>
          </div>
          <span style={{ color: t.caption, fontSize: 11 }}>{l.n}</span>
        </div>
      ))}
    </div>
  );
}

function HealthDetail({ status, t }) {
  if (status === "planned")  return <Planned label="Health" phase="3" t={t} />;
  if (status === "noAccess") return <NoAccess service="Health" t={t} />;
  if (status === "error")    return <ErrMsg t={t} />;

  const metrics = [
    { label: "Steps", value: "6,421",  sub: "today" },
    { label: "Sleep", value: "7h 12m", sub: "last night" },
    { label: "HRV",   value: "42 ms",  sub: "this morning" },
  ];

  return (
    <div style={{ display: "flex", flexDirection: "column" }}>
      <div style={{ fontSize: 11, marginBottom: 8,
        color: status === "stale" ? "#FF9F0A" : t.secondary }}>
        {status === "stale" ? "⚠ HA unreachable · synced 8 min ago" : "Last sync 8 min ago"}
      </div>
      {metrics.map((m, i) => (
        <div key={i} style={{ display: "flex", alignItems: "baseline", gap: 8, padding: "3px 0" }}>
          <span style={{ color: t.secondary, fontSize: 11, width: 40, flexShrink: 0 }}>{m.label}</span>
          <span style={{ color: t.text, fontSize: 12, fontWeight: 500,
            fontVariantNumeric: "tabular-nums" }}>{m.value}</span>
          <span style={{ color: t.caption, fontSize: 11 }}>{m.sub}</span>
        </div>
      ))}
    </div>
  );
}

const DETAIL = { cal: CalDetail, reminders: RemindersDetail, health: HealthDetail };

// ─── Popover ──────────────────────────────────────────────────────────────────

function Popover({ selected, setSelected, statuses, colorMode, t }) {
  const Detail = selected ? DETAIL[selected] : null;

  return (
    <div style={{
      position: "absolute", top: 28, right: 0,
      width: 260,
      background: t.bg,
      backdropFilter: "blur(24px) saturate(180%)",
      WebkitBackdropFilter: "blur(24px) saturate(180%)",
      borderRadius: 12, border: `1px solid ${t.border}`,
      boxShadow: t.shadow, padding: 12, zIndex: 100,
      fontFamily: "-apple-system, BlinkMacSystemFont, 'SF Pro Text', sans-serif",
    }}>
      {/* Caret */}
      <div style={{
        position: "absolute", top: -5, right: 18,
        width: 10, height: 10, background: t.caret,
        border: `1px solid ${t.border}`, borderBottom: "none", borderRight: "none",
        transform: "rotate(45deg)",
      }} />

      {/* Three section buttons */}
      <div style={{ display: "flex", gap: 6 }}>
        {SECTIONS.map(s => (
          <SectionBtn
            key={s.id} section={s} selected={selected === s.id}
            statusColor={STATUS_COLOR[statuses[s.id]]}
            onClick={() => setSelected(selected === s.id ? null : s.id)}
            t={t}
          />
        ))}
      </div>

      {/* Expandable detail */}
      <div style={{
        overflow: "hidden",
        maxHeight: selected ? "240px" : "0px",
        transition: "max-height 0.22s ease",
      }}>
        {selected && (
          <div key={selected} style={{ animation: "fadeUp 0.18s ease" }}>
            <Hr t={t} />
            <Detail status={statuses[selected]} t={t} />
          </div>
        )}
      </div>

      <Hr t={t} />

      <div style={{ display: "flex", justifyContent: "space-between" }}>
        <FooterBtn t={t}>Refresh</FooterBtn>
        <FooterBtn t={t} muted>Quit</FooterBtn>
      </div>

      <style>{`
        @keyframes fadeUp {
          from { opacity: 0; transform: translateY(-5px); }
          to   { opacity: 1; transform: translateY(0); }
        }
      `}</style>
    </div>
  );
}

// ─── Controls ─────────────────────────────────────────────────────────────────

function Controls({ statuses, setStatuses, colorMode, setColorMode, open, setOpen, t }) {
  const opts = Object.keys(STATUS_COLOR);
  return (
    <div style={{
      background: colorMode === "light" ? "rgba(255,255,255,0.62)" : "rgba(44,44,46,0.78)",
      backdropFilter: "blur(12px)", WebkitBackdropFilter: "blur(12px)",
      borderRadius: 12, padding: "14px 16px",
      border: `1px solid ${t.border}`, boxShadow: t.shadow,
      width: 286, display: "flex", flexDirection: "column", gap: 11,
    }}>
      <div style={{ color: t.caption, fontSize: 10, fontWeight: 600,
        letterSpacing: "0.05em", textTransform: "uppercase" }}>
        Section status
      </div>

      {SECTIONS.map(({ id, label, Icon }) => (
        <div key={id} style={{ display: "flex", alignItems: "center", gap: 8 }}>
          <Icon size={12} color={t.secondary} strokeWidth={1.75} style={{ flexShrink: 0 }} />
          <span style={{ color: t.secondary, fontSize: 11, width: 62, flexShrink: 0 }}>{label}</span>
          <div style={{ display: "flex", gap: 3, flex: 1 }}>
            {opts.map(s => (
              <button
                key={s}
                onClick={() => setStatuses(p => ({ ...p, [id]: s }))}
                style={{
                  flex: 1, padding: "3px 0",
                  background: statuses[id] === s
                    ? STATUS_COLOR[s]
                    : colorMode === "light" ? "rgba(0,0,0,0.06)" : "rgba(255,255,255,0.07)",
                  color: statuses[id] === s ? "#fff" : t.caption,
                  border: "none", borderRadius: 5,
                  fontSize: 9.5, cursor: "pointer", transition: "all 0.12s",
                }}
              >
                {STATUS_LABELS[s]}
              </button>
            ))}
          </div>
        </div>
      ))}

      <div style={{ height: 1, background: t.divider }} />

      <div style={{ display: "flex", gap: 6 }}>
        {[
          { label: colorMode === "light" ? "☽ Dark" : "☀ Light", fn: () => setColorMode(m => m === "light" ? "dark" : "light") },
          { label: open ? "Close popover" : "Open popover", fn: () => setOpen(o => !o) },
        ].map(({ label, fn }) => (
          <button key={label} onClick={fn} style={{
            flex: 1, padding: "5px 0", fontSize: 11,
            background: colorMode === "light" ? "rgba(0,0,0,0.06)" : "rgba(255,255,255,0.07)",
            color: t.text, border: "none", borderRadius: 7, cursor: "pointer",
          }}>
            {label}
          </button>
        ))}
      </div>
    </div>
  );
}

// ─── App ──────────────────────────────────────────────────────────────────────

export default function App() {
  const [open, setOpen] = useState(true);
  const [selected, setSelected] = useState("reminders");
  const [colorMode, setColorMode] = useState("light");
  const [statuses, setStatuses] = useState({
    cal: "planned", reminders: "ok", health: "planned",
  });

  const t = T[colorMode];

  // Menu bar icon reflects worst live status
  const worstStatus = Object.values(statuses).includes("error") ? "error"
    : Object.values(statuses).includes("stale") ? "stale"
    : Object.values(statuses).some(s => s !== "planned" && s !== "ok") ? "noAccess"
    : "ok";

  const barGlyph = worstStatus === "error" ? "⚠" : worstStatus === "noAccess" ? "⊘" : "☑";

  const contentPaddingTop = open ? (selected ? 370 : 220) : 60;

  return (
    <div style={{
      minHeight: "100vh",
      background: colorMode === "light"
        ? "linear-gradient(140deg, #d4d4da 0%, #c6c6cc 100%)"
        : "linear-gradient(140deg, #18181a 0%, #28282c 100%)",
      display: "flex", flexDirection: "column",
      fontFamily: "-apple-system, BlinkMacSystemFont, 'SF Pro Text', sans-serif",
    }}>
      {/* Menu bar */}
      <div style={{
        width: "100%", height: 26, background: t.bar, flexShrink: 0,
        display: "flex", alignItems: "center", justifyContent: "flex-end",
        paddingRight: 12, gap: 14,
      }}>
        {["wifi", "▶", "🔊"].map(i => (
          <span key={i} style={{ color: "rgba(255,255,255,0.22)", fontSize: 12 }}>{i}</span>
        ))}
        <div
          onClick={() => setOpen(o => !o)}
          style={{
            position: "relative", cursor: "pointer",
            padding: "0 8px", height: "100%",
            display: "flex", alignItems: "center",
            background: open ? "rgba(255,255,255,0.16)" : "transparent",
            borderRadius: 4, transition: "background 0.1s",
          }}
        >
          <span style={{ color: "#fff", fontSize: 13, userSelect: "none" }}>{barGlyph}</span>
          {open && (
            <div style={{ position: "absolute", top: 0, right: 0 }}>
              <Popover
                selected={selected} setSelected={setSelected}
                statuses={statuses} colorMode={colorMode} t={t}
              />
            </div>
          )}
        </div>
      </div>

      {/* Desktop */}
      <div style={{
        flex: 1, display: "flex", flexDirection: "column",
        alignItems: "center", paddingTop: contentPaddingTop,
        transition: "padding-top 0.22s ease", gap: 12,
      }}>
        <Controls
          statuses={statuses} setStatuses={setStatuses}
          colorMode={colorMode} setColorMode={setColorMode}
          open={open} setOpen={setOpen} t={t}
        />
        <span style={{ color: t.caption, fontSize: 11, opacity: 0.5 }}>
          Click sections in the popover to expand · click menu bar icon to toggle
        </span>
      </div>
    </div>
  );
}
