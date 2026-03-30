# EEON Design System

## Brand Identity

**App Name**: EEON — AI Voice Memory
**Tagline**: "Talk. Your AI remembers everything."
**App Icon**: Abstract coral waveform bars (5 vertical capsules) on black background

---

## Color Palette

### Primary Accent
| Token | Light Mode | Dark Mode | Usage |
|-------|-----------|-----------|-------|
| **Coral (Accent)** | `#E85D4A` | `#FF6B5A` | Record button, CTAs, tab indicators, selected states, paywall button |
| **AI Blue** | `#4A7AD4` | `#5B8DEF` | AI magic button, chat bubbles, active threads, sparkles, secondary actions |

### Semantic Colors
| Token | Color | Usage |
|-------|-------|-------|
| **Success** | `#34C759` | Checkmarks, resolved items, pro badge, all-clear states |
| **Warning** | `#FF9F0A` | Urgent actions, free tier warnings, overdue items |
| **Danger** | `#FF453A` | Delete actions, overdue, needs-attention section |
| **Decision** | `#BF5AF2` | Decision badges, people section accents |
| **Stale** | `#FFD60A` | Going-stale items, forgotten notes |

### Backgrounds
| Token | Light Mode | Dark Mode | Usage |
|-------|-----------|-----------|-------|
| **Background** | `#F8F7F5` (warm off-white) | `#000000` | Main app background |
| **Background Secondary** | `#FFFFFF` | `#1C1C1E` | Sheets, modals, settings |
| **Card Background** | `#FFFFFF` | `#1A1A1A` | Note cards, section cards, input fields |

### Text
| Token | Light Mode | Dark Mode | Usage |
|-------|-----------|-----------|-------|
| **Text Primary** | `#1A1A1A` | `#FFFFFF` | Titles, body text, primary content |
| **Text Secondary** | `#6B6B70` | `#8E8E93` | Dates, subtitles, secondary labels |
| **Text Tertiary** | `#9A9A9E` | `#5A5A5E` | Placeholders, disabled states, hints |

### Dividers & Borders
| Token | Light Mode | Dark Mode | Usage |
|-------|-----------|-----------|-------|
| **Divider** | `#E5E5E5` | `#2C2C2E` | Section separators, card borders |

---

## Typography

| Element | Font | Weight | Size | Notes |
|---------|------|--------|------|-------|
| Greeting / large titles | SF Pro Rounded | Bold | 24-28pt | Warm, approachable |
| Section headers | SF Pro | Semibold | Caption | Uppercase for month headers |
| Note card titles | SF Pro | Semibold | Subheadline | Truncated to 2 lines |
| Body text (enhanced notes) | SF Pro | Regular | Body | `lineSpacing(4)` for readability |
| Timer / monospaced | SF Mono | Semibold | 16pt | Recording timer, durations |
| Tab labels | SF Pro | Medium/Semibold | Subheadline | Active tab uses accent color |
| Empty state titles | SF Pro Rounded | Semibold | Title3 | Match greeting warmth |
| Badges (intent, PRO) | SF Pro | Semibold | Caption2 | Pill-shaped |

---

## Iconography

| Icon | SF Symbol | Color | Usage |
|------|-----------|-------|-------|
| Record | `mic.fill` | White on coral circle | Bottom bar center, recording screen |
| Write | `square.and.pencil` | Text Secondary | Bottom bar left |
| Search | `magnifyingglass` | Text Secondary | Bottom bar right |
| AI Magic | `sparkles` | White on AI Blue circle | Note detail bottom toolbar |
| Tags | `tag.fill` | Text Secondary | Greeting bar |
| Settings | User avatar circle | Coral gradient | Greeting bar right |
| Copy | `doc.on.doc` | Text Secondary | Note detail toolbar |
| Share | `square.and.arrow.up` | Text Secondary | Note detail toolbar |
| More | `ellipsis` | Text Secondary | Note detail toolbar |
| Close | `xmark` | Text Primary | Sheet close buttons |
| Back | `chevron.left` | Text Primary | Navigation back |
| Sort | `arrow.up.arrow.down` | Text Secondary | Feed sort toggle |
| Favorite | `heart.fill` / `heart` | Coral / Text Tertiary | Note cards, detail |
| Archive | `archivebox` | Text Secondary | Context menus |
| Play | `play.fill` | Text Primary | Audio pill |
| Stop | Rounded square | Coral (#FF3B30) | Recording controls |
| Restart | `arrow.counterclockwise` | Text Tertiary | Recording controls |

---

## Components

### Record Button (Bottom Bar)
- 64pt coral circle with white `mic.fill` icon (24pt)
- Offset -6pt Y from bar baseline
- Subtle shadow: `coral.opacity(0.3), radius: 8, y: 2`
- When recording: replaced by full-screen recording overlay

### Note Card (2-Column Grid)
- Background: Card Background color
- Corner radius: 16pt
- Light mode: subtle shadow `(black.opacity(0.06), radius: 8, y: 2)`
- Dark mode: no shadow
- Content: title (semibold), date (secondary), preview text (secondary, 2-line clamp), topic chip
- Long-press: context menu (Favorite, Archive)

### Tag Chip (Filter Strip)
- Pill shape: 16pt corner radius
- Default: Card Background, Text Secondary
- Selected: Coral accent background, white text
- Content: tag name + note count in parentheses
- Font: Caption weight medium

### Intent Badge
- Pill shape: 8pt corner radius
- Font: Caption2 semibold
- Colors by type:
  - Action: `#FF9F0A` background at 15% opacity, orange text
  - Decision: `#BF5AF2` background at 15% opacity, purple text
  - Idea: `#5B8DEF` background at 15% opacity, blue text
  - Update: `#34C759` background at 15% opacity, green text
  - Reminder: `#FFD60A` background at 15% opacity, yellow text

### Audio Pill
- Capsule shape: 16pt corner radius
- Background: Card Background (dark) / subtle gray (light)
- Content: play icon + duration ("0:11")
- While playing: tint changes to AI Blue

### AI Magic Button (Note Detail Toolbar)
- 48pt circle, solid AI Blue
- White `sparkles` icon (Title3 semibold)
- Shadow: `blue.opacity(0.3), radius: 8, y: 2`
- Offset -6pt Y from toolbar baseline

### Bottom Toolbar (Note Detail)
- 5 items: Copy | Tags | AI Magic | Share | More
- AI Magic elevated in center
- Icons in Text Secondary, 18pt body font
- Background: matches main background

---

## Layout

### Home Screen
```
┌─────────────────────────────────────┐
│ Good morning          [tag] [avatar]│
│ Monday, March 30                    │
│                                     │
│ [2 free notes left        Upgrade]  │ ← conditional
│                                     │
│ All   AI   Favorites   Archive  [↕] │ ← tabs + sort
│ ────                                │
│ [tag1] [tag2] [tag3] [+N more]      │ ← tag chip strip
│                                     │
│ MARCH 2026                          │
│ ┌─────────┐ ┌─────────┐            │
│ │ Note    │ │ Note    │            │
│ │ card    │ │ card    │            │
│ └─────────┘ └─────────┘            │
│ ┌─────────┐ ┌─────────┐            │
│ │ Note    │ │ Note    │            │
│ └─────────┘ └─────────┘            │
│                                     │
│   [✏️]      [🎙]      [🔍]         │ ← bottom bar
└─────────────────────────────────────┘
```

### Note Detail
```
┌─────────────────────────────────────┐
│ [←]                    [share] […] │
│                                     │
│ [▶ 0:11]  Mar 30, 9:23  [Action]  │
│                                     │
│ Urgent Health App Launch     [♡]   │
│ Reminder                            │
│                                     │
│ [Enhanced] [Original]               │
│                                     │
│ ┌─────────────────────────────────┐ │
│ │ We need to launch the health   │ │
│ │ app within the next two days.  │ │
│ │ Let's ensure all final checks  │ │
│ │ are completed...               │ │
│ └─────────────────────────────────┘ │
│                                     │
│  [📋] [#] [✨ AI] [↗] […]         │ ← toolbar
└─────────────────────────────────────┘
```

### Recording Screen
```
┌─────────────────────────────────────┐
│ [✕]        [● 02:58]               │
│                                     │
│         ╭ ring pulses ╮             │
│    ▌▌  ▌▌▌▌  ▌▌▌▌▌▌  ▌▌▌▌  ▌▌     │ ← bold coral bars
│         ╰─────────────╯             │
│                                     │
│ We need to launch the health app   │
│ within the next two days. Let's    │
│ ensure all final checks are        │
│ completed and the app is ready     │
│ for release                        │ ← live transcript
│                                     │
│ 7 notes left · Get PRO             │
│                                     │
│    [↻]      [■]      [⏸]          │ ← controls
└─────────────────────────────────────┘
```

---

## Appearance Modes

- **System** (default): follows iOS light/dark setting
- **Light**: forced light mode via `.preferredColorScheme(.light)`
- **Dark**: forced dark mode via `.preferredColorScheme(.dark)`
- User selects in Settings → Appearance (segmented picker)
- Recording overlay always dark regardless of mode

---

## Tone of Voice

| Context | Style | Example |
|---------|-------|---------|
| Empty states | Warm, encouraging | "Your memory starts here" |
| Errors | Honest, brief | "Something went wrong. Try again?" |
| Success | Confident, one exclamation allowed | "Saved!" |
| Paywall | Direct, value-focused | "You've reached 5 notes. Upgrade for unlimited memory." |
| AI thinking | Calm, active | "Reading your notes..." |
| Proactive nudges | Helpful, not pushy | "You promised Sarah a doc review 4 days ago" |

Rules: Second person always ("you/your"). No first person plural ("we"). No exclamation marks in errors. One allowed in celebrations.

---

## SwiftUI Implementation

### Color References
```swift
// In code, use semantic tokens:
Color.eeonAccent          // Coral accent
Color.eeonAccentAI        // AI Blue
Color.eeonBackground      // Main background (adapts light/dark)
Color.eeonBackgroundSecondary
Color.eeonCard            // Card surfaces
Color.eeonTextPrimary     // Primary text
Color.eeonTextSecondary   // Secondary text
Color.eeonTextTertiary    // Tertiary text
Color.eeonDivider         // Dividers and borders
```

### Card Modifier
```swift
// Apply consistent card styling:
myView.eeonCard()
// Adds: Card background, 16pt corners, light-mode shadow
```

### Color Assets Location
```
voice notes/Assets.xcassets/
├── EEONAccent.colorset/
├── EEONAccentAI.colorset/
├── EEONBackground.colorset/
├── EEONBackgroundSecondary.colorset/
├── EEONCardBackground.colorset/
├── EEONTextPrimary.colorset/
├── EEONTextSecondary.colorset/
├── EEONTextTertiary.colorset/
├── EEONDivider.colorset/
└── AccentColor.colorset/  (coral, system-wide)
```

### Theme.swift Location
```
voice notes/Theme.swift
```
