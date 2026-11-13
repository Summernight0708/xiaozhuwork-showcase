# Design — XiaozhuWork / 小猪作业

A locked design system for the XiaozhuWork app. Every page redesign reads this file before emitting UI code. The product is a workbench, not a marketing dashboard.

## Genre

modern-minimal

## Macrostructure family

- Marketing / entry pages: Utility — compact single-column or split utility, no dashboard hero.
- App pages: Workbench — fixed project navigation, full remaining-width canvas, dense list/table workflows.
- Content pages: Long Document — restrained reading width, persistent hierarchy, no decorative cards.

## Theme

Warm oat neutrals with a low-saturation sage accent. Light and dark keep the same hue family; dark mode changes lightness/chroma rather than switching to blue-black.

The canonical values live in `tokens.css`.

## Typography

- Display: existing project sans stack, weight 700, roman.
- Body: existing project sans stack, weight 400.
- Mono: existing system monospace stack for identifiers only.
- No italic headings, no uppercase eyebrow labels, no decorative copy.

## Spacing

4-point named scale in `tokens.css`. Shared UI must consume spacing tokens rather than inventing per-component gaps.

## Motion

- UI transitions: color/background/border/opacity only, 100–160 ms.
- No hover scale, bounce, universal translate/lift, or scroll-reveal choreography.
- `prefers-reduced-motion` collapses transitions to near-instant.

## Microinteractions stance

- Focus indication is immediate.
- Reversible notification deletion uses inline Undo rather than a confirmation modal.
- Irreversible or bulk destructive actions may use confirmation.
- Hover never contains functionality unavailable to keyboard/touch users.

## CTA voice

- Primary actions: compact solid sage button, 4–6 px radius, direct verb labels.
- Secondary actions: neutral border or text action; no pill buttons.
- Clickable labels stay on one line.

## Per-page allowances

- App pages: no enrichment; function carries the page.
- Help/content pages: typography and rules only.
- Login/download/upgrade: minimal illustration only if already part of the product; no decorative hero effects.

## What pages MUST share

- Project/sidebar chrome and canvas alignment.
- Warm oat/sage light and dark palette.
- Type stack and hierarchy.
- 4-point spacing system.
- Status vocabulary from one presentation dictionary.
- Button/input/table/list treatment.
- Compact 4–6 px control radii; content lists and ordinary sections use no radius. Keep rounded surfaces only for actual popovers or dialogs.

## What pages MAY differ on

- Information density according to task.
- Table vs list vs split-pane within the Workbench family.
- Reading width on long-form content.

## Workbench rules

- Project pages use the full width remaining after the sidebar.
- Data-dense global utility pages (notifications, account settings, plan comparison, help index) use the full AppShell canvas with shared page gutters.
- Reading articles and focused creation forms keep deliberate line/form widths; never inherit a global narrow cap onto workbench pages.
- Sidebar is a solid 248 px rail with a single right border; no detached/floating shell.
- Dense records use separators and column alignment, not card-per-row.
- Quotas/usage are inline metadata, not KPI/progress cards.
- Avoid nested bordered containers and card-in-card composition. Use text, alignment, section rules and record rows ahead of cards.
- Desktop data rows must use the available width; mobile changes structure instead of squeezing desktop columns.

## Light / dark

- Light: warm paper canvas, slightly brighter content surface, warm ink, sage accent.
- Dark: warm charcoal canvas, progressively lighter elevated surfaces, softened sage accent.
- No pure white/black and no blue-black “premium SaaS” dark theme.
- Surface flips must set both background and foreground semantics.

## Status and language

- Database/RPC enum values remain English internally.
- User-facing status, state, role and decision values use a single Chinese presentation layer.
- Unknown internal values display “状态待确认” or an equivalent safe label; raw enums must never leak to the UI.
- Product terms such as DDL, Free/Pro, PDF/DOCX remain unchanged where useful.

## System notifications

- Release/update announcements are first-class project-independent notifications.
- Publishing is server/admin-only and idempotent per recipient.
- Only valid, non-banned, non-deleting accounts receive a broadcast.
- Announcement navigation uses an allow-listed in-app destination.
- Personal dismissal hides the inbox row for that user; it never deletes announcement/audit provenance.

## Responsive contract

Must be explicitly checked at 320, 375, 414, 768 px and desktop/wide desktop:

- no horizontal page scroll;
- clickable labels do not wrap;
- task/file rows switch to mobile record layouts;
- long headings use overflow-wrap;
- dark and light modes both remain readable.

## Hallmark stamp

`/* Hallmark · genre: modern-minimal · macrostructure: Workbench/Long Document/Utility · design-system: design.md · designed-as-app */`
