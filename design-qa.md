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
