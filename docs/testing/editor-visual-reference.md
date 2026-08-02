# Editor visual reference

## Authority and artifacts

- Immutable approved reference:
  `docs/images/editor-context-rail-approved-reference.png`
- Reference source:
  `.superpowers/brainstorm/87931-1785458907/content/option-2-context-rail.png`
- Reference SHA-256:
  `cd7ae5d3c6d46fa88ec4100654f51fb44bff595ff5a26516bba7c7c3b38958f8`
- Reference dimensions: `1487 × 1058`
- Fixed Light implementation capture dimensions: `1487 × 1058`
- Fixed Light implementation capture SHA-256:
  `a66fe868b3aa1fda63a4a2ebe654ce51a37ad77d55c71afe83273465473c43e1`
- Side-by-side comparison:
  `docs/images/editor-context-rail-implementation-comparison.png`
- Comparison dimensions: `2974 × 1058`
- Comparison SHA-256:
  `83b4d9a39ae5160b6fbf1576d69e30050cec9141be9a8b762c7e170879b2704e`
- Implementation provenance: working tree based on
  `a647f4eabe6fe9690445165fcc05663b8961a11c`; Task 16 is intentionally
  uncommitted at this checkpoint, so a final implementation commit SHA does
  not yet exist.

The immutable approved reference remains the design authority. Generated
screenshots never approve themselves; after the fixed-size comparison was
accepted, all 14 Playwright images were regenerated from the current fixture,
opened at original detail, inspected, and accepted as per-state regression
baselines. The exact per-file hashes and inspection checklist are recorded in
the Task 16 report.

## Deterministic comparison method

The implementation capture used a `1487 × 1058` viewport and device scale 1.
The test-only fixture first mounted as Selection with no selection so the
production `EditorWorkspace` could measure the hidden-rail viewport. It then
applied the selected Rectangle state, exercised the real hidden-to-visible rail
reflow, waited for the source image and viewport transform to settle, and sent
a strict native `setAppearance(light)` envelope through `createNativeBridge`.
The browser console contained no errors or warnings.

The comparison image is a lossless horizontal composition: approved reference
on the left, fixed-size implementation capture on the right. Neither input was
scaled or cropped.

## Geometry inspection

Approximate reference geometry, read from the immutable image:

- Context Rail: `x ≈ 20`, `y ≈ 176`, `width ≈ 296`, `bottom ≈ 973`
- tool palette: `x ≈ 464`, `y ≈ 46`, `width ≈ 692`, `height ≈ 93`
- canvas/source frame: `x ≈ 358`, `y ≈ 190`, `right ≈ 1448`,
  `bottom ≈ 935`
- selected Rectangle: `x ≈ 399`, `y ≈ 298`, `right ≈ 844`,
  `bottom ≈ 568`

Measured implementation geometry:

- Context Rail: `x = 16`, `y = 76`, `width = 248`,
  `height = 545.75`, `right = 264`
- tool palette: `x = 527.5`, `y = 16`, `width = 432`, `height = 54`
- zoom cluster: `x = 1044.59375`, `y = 992`, `width = 426.40625`,
  `height = 50`, `right = 1471`, `bottom = 1042`
- settled canvas transform: `translate(275.5,184) scale(1)`
- preserved source center: `(600, 375)`
- selected Rectangle: `x = 395.5`, `y = 289`, `width = 470`,
  `height = 290`, `right = 865.5`, `bottom = 579`

The selected object and source are fully visible after the real rail reflow.
The selection geometry is close to the approved reference and no longer
intersects the rail.

## Visual contract checklist

### Preserved

- Canvas-first hierarchy: both images keep the annotated source as the dominant
  surface, with floating controls outside the source content.
- Active coral state: both use a high-salience coral active tool treatment.
  The reference shows Rectangle active; the implementation correctly shows
  Selection active because a persisted Rectangle is selected and the real app
  clears selection when a creation tool becomes active.
- Direct controls: color/fill choices, stroke width, roughness, opacity, and
  selection actions are visible without a nested settings dialog.
- Selection presentation: coral rough stroke plus blue transformer handles is
  fully visible over a representative dashboard card.
- Cream/coral/ink palette: Light appearance preserves the approved warm shell,
  coral emphasis, and dark ink hierarchy.

### Intentional frozen differences

- The implementation rail is the frozen `248 px` Task 7 geometry, not the
  approximately `296 px` concept rail.
- The implementation palette is more compact and keeps the shipped ten-tool
  shortcut registry. It is not widened to match the concept image.
- Rail options include accessible text labels alongside swatches and segments;
  the reference relies more heavily on unlabeled visual swatches.
- Selection actions use the frozen icon-only four-column contract. They are not
  replaced with the concept image's full-width text action rows.
- The implementation zoom cluster contains six visible items: five buttons plus
  zoom status, including required `Fit Image` and `Fit Selection`. Those
  controls are intentionally absent from the concept image and must not be
  removed for visual similarity.
- The selected-rectangle state does not show the reference's Saved toast;
  `save-success` is a separate deterministic fixture state driven by strict
  operation-status messages.
- Native window chrome and native Copy/Save/Undo/Redo toolbar commands are not
  rendered by the web-only fixture.

### Mixed, hover, and focus evidence

- The mixed Rectangle/Text fixture derives its rail through
  `deriveContextRailModel` and exposes visible `Mixed` text, unchecked color
  radios, and `aria-valuetext="Mixed"`.
- Real-browser tests verify every tool's focus ring, focus tooltip, hover
  tooltip, accessible shortcut name, and hidden visual `<kbd>` announcement.
- Light and Dark rendered token tests enforce text contrast `≥ 4.5`, control
  boundary contrast `≥ 3`, and active-state contrast `≥ 3`.

## Review conclusion

The original-size manual review found no material rail/source/selection overlap
after the fixture began using the real hidden-to-visible reflow. Canvas-first
hierarchy, active coral state, and direct controls remain intact. The compact
rail/palette, icon-only actions, and expanded Fit controls are intentional
frozen product contracts and are documented rather than changed to imitate the
concept image.

The fixed-size comparison cleared the design checkpoint before baseline
generation. The accepted Darwin matrix now contains exactly seven states in
Light and Dark, all at `1280 × 860`, device scale 1. A subsequent run without
snapshot updates passed all 14 pixel comparisons plus all 8 accessibility and
reduced-motion tests.

The two authorities remain intentionally distinct:

- the immutable `1487 × 1058` reference governs product direction, hierarchy,
  placement, coral emphasis, and direct controls;
- the 14 inspected Darwin PNGs govern deterministic per-state pixel
  regression for the current frozen implementation.

The fixture is the Task 16 deterministic browser shell, not a second
production `App`. It composes production workspace, canvas, palette, rail,
dialog, feedback, zoom, bridge, and appearance units while owning only the
closed fixture inputs. The production `App` remains covered by its unit suite;
its real bundled lifecycle remains the responsibility of the pending WKWebView
smoke test. No fixture-only forcing props were added to production `App`.
