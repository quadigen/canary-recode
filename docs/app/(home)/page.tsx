import Link from 'next/link';
import type { ReactNode } from 'react';

const buttonClass =
  'group flex min-h-[52px] w-full items-center justify-between gap-8 ' +
  'bg-neutral-900 px-5 py-3 text-sm font-semibold text-white ' +
  'transition-colors hover:bg-neutral-700 dark:bg-neutral-200 ' +
  'dark:text-neutral-900 dark:hover:bg-white sm:w-[254px]';

function Arrow({ down = false }: { down?: boolean }) {
  return (
    <svg width="18" height="18" viewBox="0 0 24 24" fill="none"
      stroke="currentColor" strokeWidth="1.8" strokeLinecap="round"
      strokeLinejoin="round" aria-hidden="true"
      className={down ? 'rotate-90' : undefined}>
      <path d="M5 12h14m-6-6 6 6-6 6" />
    </svg>
  );
}

function GeometricArtwork() {
  const triangles = [
    ['0,250 100,300 0,300', 1],
    ['100,200 200,250 100,300', 1],
    ['200,250 300,300 200,300', 1],
    ['300,100 400,150 300,200', 1],
    ['400,150 500,200 400,250', 1],
    ['400,250 500,300 400,300', 1],
    ['500,100 600,150 500,200', 1],
    ['600,150 700,200 600,250', 1],
    ['600,250 700,300 600,300', 1],
    ['700,200 800,250 700,300', 1],
    ['900,100 1000,150 900,200', 1],
    ['1000,150 1100,200 1000,250', 1],
    ['1000,250 1100,300 1000,300', 1],
    ['1100,100 1200,150 1100,200', 1],
    ['1100,200 1200,250 1100,300', 1],
    ['1200,50 1300,100 1200,150', 0.22],
    ['1200,150 1300,200 1200,250', 1],
    ['1300,0 1400,50 1300,100', 1],
    ['1300,100 1400,150 1300,200', 1],
    ['1300,200 1400,250 1300,300', 1],
    ['1400,150 1500,200 1400,250', 1],
    ['1400,250 1500,300 1400,300', 1],
  ] as const;

  return (
    <svg viewBox="0 0 1500 300" className="block w-full select-none" aria-hidden="true">
      <defs>
        <linearGradient id="kinemium-ember" x1="0" y1="0" x2="850" y2="450"
          gradientUnits="userSpaceOnUse">
          <stop offset="0%" stopColor="#ed4815" />
          <stop offset="55%" stopColor="#ff7920" />
          <stop offset="100%" stopColor="#ffac08" />
        </linearGradient>
      </defs>
      {triangles.map(([points, opacity], index) => (
        <polygon key={index} points={points} opacity={opacity} fill="url(#kinemium-ember)" />
      ))}
    </svg>
  );
}

function Illustration({ children }: { children: ReactNode }) {
  return (
    <svg viewBox="0 0 720 245" fill="none" stroke="currentColor" strokeWidth="1.5"
      strokeLinecap="round" strokeLinejoin="round" aria-hidden="true"
      className="mb-9 block h-auto w-full text-neutral-500 dark:text-neutral-400">
      {children}
    </svg>
  );
}

function SceneIllustration() {
  return (
    <Illustration>
      {/* Floor plane */}
      <g opacity=".3" strokeWidth="1.3">
        <path d="M275 137 150 174 360 236 570 174 445 137" />
      </g>

      {/* Part */}
      <g stroke="#f97316" strokeWidth="1.7">
        {/* Top face */}
        <path
          d="M360 58 445 86 360 114 275 86Z"
          fill="#f97316"
          fillOpacity=".14"
        />

        {/* Left face */}
        <path
          d="M275 86 360 114 360 198 275 170Z"
          fill="#f97316"
          fillOpacity=".035"
        />

        {/* Right face */}
        <path
          d="M360 114 445 86 445 170 360 198Z"
          fill="#f97316"
          fillOpacity=".075"
        />

        {/* Anchor */}
        <path
          d="M360 58V22"
          strokeDasharray="4 6"
          opacity=".65"
        />

        <circle
          cx="360"
          cy="22"
          r="3"
          fill="#f97316"
        />

        {/* Label connector */}
        <path
          d="M445 112H480L495 97"
          strokeWidth="1"
          opacity=".6"
        />
      </g>

      {/* Labels */}
      <g
        fontSize="11"
        fontFamily="monospace"
        stroke="none"
        fill="currentColor"
      >
        <text x="505" y="100" fill="#f97316">
          PART
        </text>

        <text x="150" y="155" opacity=".7">
          WORKSPACE
        </text>
      </g>
    </Illustration>
  );
}

function ScriptingIllustration() {
  return (
    <Illustration>
      <g opacity=".35">
        <path d="M26 51h125m-125 142h125m418-142h125m-125 142h125M88 51v142m544-142v142" />
        <circle cx="88" cy="51" r="4" /><circle cx="88" cy="193" r="4" />
        <circle cx="632" cy="51" r="4" /><circle cx="632" cy="193" r="4" />
      </g>
      <g opacity=".8">
        <rect x="30" y="90" width="142" height="65" rx="2" />
        <path d="M172 122h74m-8-6 8 6-8 6M474 122h74m-8-6 8 6-8 6" />
        <rect x="548" y="90" width="142" height="65" rx="2" />
        <path d="M66 122h70m-44-11-11 11 11 11m18-22 11 11-11 11M582 135v-25m19 25v-15m19 15v-35m19 35v-20m19 20v-28" />
      </g>
      <g stroke="#f97316" strokeWidth="2">
        <rect x="246" y="47" width="228" height="150" rx="3" fill="#f97316" fillOpacity=".055" />
        <path d="M246 73h228" />
        <circle cx="261" cy="60" r="2" fill="#f97316" /><circle cx="271" cy="60" r="2" fill="#f97316" /><circle cx="281" cy="60" r="2" fill="#f97316" />
        <path d="m329 100-24 22 24 22m62-44 24 22-24 22m-22-51-18 58" />
        <path opacity=".55" d="M290 169h140" />
      </g>
      <g fill="currentColor" stroke="none" fontSize="11" fontFamily="monospace" textAnchor="middle">
        <text x="101" y="174">EVENT</text><text x="360" y="187" fill="#f97316">LUAU</text><text x="619" y="174">BEHAVIOUR</text>
      </g>
    </Illustration>
  );
}

function UIIllustration() {
  return (
    <Illustration>
      <g opacity=".4">
        <rect x="27" y="39" width="175" height="168" rx="2" />
        <path d="M27 65h175M43 83h82m-68 25h100m-100 25h75m-89 25h82m-68 25h100" />
        <path d="M202 122h44M474 122h45" strokeDasharray="4 6" />
        <rect x="519" y="39" width="174" height="168" rx="2" />
        <path d="M519 65h174M535 86h43m-43 30h43m-43 30h43m-43 30h43" />
        <rect x="598" y="78" width="77" height="16" rx="1" /><rect x="598" y="108" width="77" height="16" rx="1" /><rect x="598" y="138" width="77" height="16" rx="1" /><rect x="598" y="168" width="77" height="16" rx="1" />
      </g>
      <g stroke="#f97316" strokeWidth="2">
        <rect x="246" y="20" width="228" height="205" rx="3" fill="#f97316" fillOpacity=".05" />
        <path d="M246 49h228" />
        <rect x="271" y="70" width="178" height="131" strokeDasharray="5 5" opacity=".65" />
        <rect x="295" y="89" width="130" height="37" rx="2" />
        <path d="M310 103h100m-100 10h64" opacity=".75" />
        <rect x="295" y="143" width="130" height="34" rx="2" fill="#f97316" fillOpacity=".15" />
        <path d="M329 160h62" />
        {[ [271,70], [449,70], [271,201], [449,201] ].map(([x,y]) => (
          <rect key={`${x}-${y}`} x={x-3} y={y-3} width="6" height="6" fill="#f97316" />
        ))}
      </g>
      <g fontSize="11" stroke="none" fill="currentColor" fontFamily="monospace">
        <text x="42" y="56">EXPLORER</text><text x="534" y="56">PROPERTIES</text><text x="261" y="39" fill="#f97316">CANVAS</text>
      </g>
    </Illustration>
  );
}

// A lightweight Luau highlighter for these static examples. React escapes text.
const tokenPattern = /(--[^\n]*|"(?:\\.|[^"\\])*"|'(?:\\.|[^'\\])*'|\b(?:local|function|end|if|then|else|return|for|in|do|true|false|nil)\b|\b\d+(?:\.\d+)?\b|\b(?:Instance|Vector3|Color3|UDim2|CFrame)\b)/g;

function Code({ children }: { children: string }) {
  const pieces = children.trim().split(tokenPattern);
  return (
    <div className="my-4 overflow-hidden rounded-sm border border-black/10 bg-neutral-100 dark:border-white/5 dark:bg-[#101012]">
      <div className="flex items-center justify-between border-b border-black/10 px-4 py-2 text-[11px] text-neutral-500 dark:border-white/5 dark:text-neutral-500">
        <span>Luau</span><span className="font-mono">.luau</span>
      </div>
      <pre className="overflow-x-auto px-4 py-4 text-[13px] leading-[1.75] text-neutral-800 dark:text-neutral-300"><code>
        {pieces.map((piece, i) => {
          let color = '';
          if (i % 2 === 1) {
            if (piece.startsWith('--')) color = 'text-neutral-500 dark:text-neutral-500';
            else if (piece.startsWith('"') || piece.startsWith("'")) color = 'text-emerald-700 dark:text-emerald-300';
            else if (/^\d/.test(piece)) color = 'text-orange-700 dark:text-amber-300';
            else color = 'text-orange-700 dark:text-orange-300';
          }
          return <span key={i} className={color}>{piece}</span>;
        })}
      </code></pre>
    </div>
  );
}

function Feature({ number, id, title, intro, artwork, children }: {
  number: number; id: string; title: string; intro: string;
  artwork: ReactNode; children: ReactNode;
}) {
  return (
    <section id={id} className="scroll-mt-28 py-14 sm:py-20">
      {artwork}
      <div className="mb-6 border-b border-current/15 pb-6">
        <h2 className="flex items-center gap-3 text-2xl font-semibold tracking-tight sm:text-[26px]">
          <span className="inline-flex size-8 shrink-0 items-center justify-center rounded-full border border-current text-lg font-medium">{number}</span>
          {title}
        </h2>
        <p className="mt-4 text-[15px] leading-7 opacity-75">{intro}</p>
      </div>
      <div className="space-y-4 text-[15px] leading-7">{children}</div>
    </section>
  );
}

export default function HomePage() {
  return (
    <main className="flex min-w-0 flex-1 flex-col">
      <section className="mx-auto w-full max-w-[1680px] px-5 sm:px-10">
        <div className="relative z-10 mx-auto max-w-[1060px] pt-16 sm:pt-24 lg:pt-32">
          <h1 className="mb-6 text-[34px] font-semibold leading-tight tracking-tight sm:text-[44px]">
            A game engine for building intuitive games.
          </h1>
          <p className="mb-6 text-lg leading-relaxed opacity-85 sm:text-[21px]">
            Kinemium is a game engine that lets you build 3D worlds, write games in Luau,
            and create your own interfaces, all from the same editor.
          </p>
          <p className="mb-7 text-lg leading-relaxed opacity-85 sm:text-[21px]">
            If you’ve used Roblox Studio before, a lot of Kinemium will feel familiar.
            You work with instances, organise them in a hierarchy, and use scripts to make
            things happen. You don’t need to write a renderer or an editor just to get a game running.
          </p>
          <div className="flex flex-col gap-1.5 sm:flex-row">
            <Link href="/docs" className={buttonClass}>Get started <Arrow /></Link>
            <Link href="#overview" className={buttonClass}>How it works <Arrow /></Link>
          </div>
          <p className="mt-4 flex flex-wrap gap-x-5 gap-y-2 text-sm font-medium">
            <Link className="underline underline-offset-4 hover:text-orange-500" href="/docs/native-sdk">Kinemium Native SDK</Link>
          </p>
        </div>
        <div className="pointer-events-none relative mt-8 border-b border-current/15 xl:-mt-12">
          <GeometricArtwork />
        </div>
        <a href="#overview" className="flex items-center justify-center gap-2 py-9 text-sm opacity-65 transition-opacity hover:opacity-100">
          <Arrow down /> A quick look at how Kinemium works.
        </a>
      </section>

      <div id="overview" className="mx-auto w-full max-w-[820px] scroll-mt-20 px-6 sm:px-10">
        <Feature number={1} id="worlds" title="Everything is an object."
          intro="Parts, models, scripts and other objects in your game are instances. Each has its own properties and can be placed inside another instance."
          artwork={<SceneIllustration />}>
          <p>For example, here is how you can create an orange platform in your world.</p>
          <Code>{`-- Create a new object in the world.
local part = Instance.new("Part")
part.Name = "Platform"
part.Size = Vector3.new(12, 1, 12)
part.Position = Vector3.new(0, 4, 0)
part.Anchored = true
part.Color = Color3.fromRGB(249, 115, 22)
part.Parent = workspace`}</Code>
          <p>If you want to keep several parts together, put them inside a model. You can move an object into a model by changing its Parent property.</p>
          <Code>{`local model = Instance.new("Model")
model.Name = "MyWorld"
model.Parent = workspace

part.Parent = model`}</Code>
        </Feature>

        <div className="border-t border-current/10" />
        <Feature number={2} id="scripting" title="Write your game in Luau."
          intro="Kinemium uses Luau for scripting. You can work with objects directly, listen for events, and access engine features through services."
          artwork={<ScriptingIllustration />}>
          <p>Let’s make the platform from the previous example move up and down. Heartbeat runs every frame and gives us the time since the last update.</p>
          <Code>{`local RunService = game:GetService("RunService")
local part = workspace.MyWorld.Platform
local origin = part.Position
local elapsed = 0

RunService.Heartbeat:Connect(function(dt)
    elapsed = elapsed + dt
    local offset = math.sin(elapsed * 2) * 2
    part.Position = origin + Vector3.new(0, offset, 0)
end)`}</Code>
          <p>We use that time to keep the platform moving at the same speed, even if the frame rate changes. You can use the same approach for other kinds of movement.</p>
        </Feature>

        <div className="border-t border-current/10" />
        <Feature number={3} id="interfaces" title="Make your own interfaces."
          intro="UI works a lot like the rest of the engine. Frames, labels and buttons are instances, and you can change their properties or interact with them from a script."
          artwork={<UIIllustration />}>
          <p>Here’s a small panel with a text label inside it. To display it, parent the frame to a GUI container in your project.</p>
          <Code>{`local frame = Instance.new("Frame")
frame.Name = "WelcomePanel"
frame.Size = UDim2.new(0, 320, 0, 180)
frame.BackgroundColor3 = Color3.fromRGB(24, 24, 27)

local title = Instance.new("TextLabel")
title.Size = UDim2.new(1, 0, 0, 48)
title.BackgroundTransparency = 1
title.Text = "Hello, Kinemium!"
title.TextColor3 = Color3.fromRGB(249, 115, 22)
title.Parent = frame

-- Parent frame to your project's GUI container.`}</Code>
          <p>You can build on this to make a pause menu, a HUD, or even tools for the editor itself.</p>
        </Feature>

        <section className="border-t border-current/15 pb-24 pt-14">
          <h2 className="mb-4 text-3xl font-semibold tracking-tight">Give it a try.</h2>
          <p className="mb-7 text-base leading-7 opacity-75">If you’re new to Kinemium, start with the documentation. You can also use the API reference to look up individual classes and services as you go.</p>
          <Link href="/docs" className={buttonClass}>Read the documentation <Arrow /></Link>
        </section>
      </div>
    </main>
  );
}
