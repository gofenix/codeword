# Design QA: CodeWord editorial material system

- Target: approved five-screen editorial prototypes
- Runtime: Flutter on iPhone 17 Pro simulator, iOS 26.5
- Screens checked: Words, Reading, Charts, Library, Settings
- Responsive coverage: 320x568, 393x852, 140% and 200% text scale

## Material system

- Canvas uses a restrained warm-light gradient instead of a flat cream fill.
- Paper surfaces use a subtle diagonal value shift, thin taupe edge, top highlight, and low soft shadow.
- Primary command surfaces use a bronze light-to-dark gradient, highlight edge, shadow, and press feedback.
- Navigation chrome uses a translucent blurred glass layer with reflected tint, specular edge, and floating geometry.
- Interactive glass is limited to the bottom navigation, settings/back controls, and pronunciation control.
- Reading and learning content remain paper surfaces instead of becoming translucent.
- Semantic success, danger, and target-word colors remain distinct from decorative bronze.
- Dark mode keeps solid dark surfaces so light-theme highlights do not turn into glare.

## Screen review

- Words: serif prompt remains dominant; option papers are clearly separated; pronunciation and navigation float as glass controls.
- Reading: hero, archive cards, and primary generation action establish three distinct depth levels.
- Charts: action, mastery, trend, and rhythm remain scannable; shadows are not clipped by the scroll layout.
- Library: current collection is visually primary; search, filters, and book list stay quieter; settings uses interactive glass.
- Settings: grouped preferences read as physical sections; connection and destructive states keep semantic priority; back control uses interactive glass.

## Findings

- P0: none
- P1: none
- P2: none
- P3: none

## Acceptance

- No visible overflow, clipped shadow, accidental nested-card treatment, or tab-layout shift.
- Primary actions preserve at least a 44px touch target and remain usable with enlarged text.
- Material depth is visible at normal simulator scale without becoming glossy or skeuomorphic.
- Light and dark themes explicitly preserve readable system status-bar foregrounds.

final result: passed

---

# Design QA: Apple-design polish pass (65+ findings)

- Scope: highlights, shadows, materials, liquid glass, interaction flows, motion — app-wide.
- Verification: `flutter analyze` clean on all 4 packages; 118 app tests + 17 lib_ui tests green.

## Root-cause fixes

- AppCard and AppGlassSurface/GlassAppBar now host a transparent Material, so every
  descendant InkWell (settings rows, book rows, history cards, mastery header, metric
  switch, reader actions, glass icon buttons) renders a visible ripple instead of
  painting behind the opaque surface.
- New tokens close the duplication classes: `sageSoftDark` + `sageContainerOf`,
  `AppShadows.glass/bronze/hero`, `AppRadii.xxl`, `AppBorders.hairline`, category
  monogram tints. One blur sigma constant drives all glass chrome.
- Card radius unified at 12 (AppCard == CardTheme); glass pills at 28.

## Materials & dark mode

- Words correct-answer wash uses `sageContainerOf` (no more pale-green glow in dark).
- Section labels resolve bronze per-brightness; dark snackbar is inverse; light and
  dark surface ramps are monotonic and hue-consistent; PillTag soft variant lightens
  in dark; option-tile success/danger accents lift toward white in dark.
- Primary CTAs unified to the bronze gradient command surface (确认 / 继续 / 验证并保存 /
  选择词书); secondary buttons guarantee ≥44px via the new outlined/text button themes.
- Bottom chrome unified to floating glass (article toolbar, reading composer, AI submit);
  composer hairline shelf removed; AI provider sheet no longer stacks two drag handles.
- The large pronunciation control is now a floating glass disc (sanctioned interactive
  glass); all three 播放发音 call sites share one size/color treatment.

## Motion & interaction

- Session phases (loading → asking → wrongDetail → finished) crossfade with
  AppMotion.medium + reduced-motion collapse — no more hard cuts in the learning loop.
- Swipe cards use AppMotion.slow/easeOut, Apple's exponential flick projection, and the
  under-damped momentum spring for spring-back (replacing elasticOut).
- Trend bars animate on AppMotion.easeOut; the metric switch lifts its selected segment
  with AppShadows.sm; quiz options gained a visible pressed state and ≥44px rows;
  inline target words dip opacity on press; all reader/provider/refresh actions haptic.

## Dead code removed

- `stats_widgets.dart` (six drifted duplicate chart widgets), `QuoteMark`, `MobileFrame`,
  `FavoriteStar`, and the orphan tokens (`starIdle*`, `bezel`, `desktopWall*`).

final result: passed
