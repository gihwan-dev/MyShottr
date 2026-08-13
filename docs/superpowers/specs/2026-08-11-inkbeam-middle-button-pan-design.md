# Inkbeam Middle-Button Canvas Pan Design

- Date: 2026-08-11
- Status: Approved
- Target: Inkbeam editor after `v0.2.0`
- Authority: Extends the established Inkbeam editor viewport interaction contract.

## 1. Outcome

Pressing and holding the mouse wheel, then dragging anywhere inside the editor
canvas, pans the viewport immediately. The gesture works regardless of the
active annotation tool and regardless of whether it begins over the source
image, empty workspace, an annotation, a selected annotation, or a transform
handle.

The gesture is temporary. Releasing or cancelling the middle button ends the
pan exactly once and restores the previously selected tool without changing
the document or selection.

## 2. Scope

### In scope

- middle-button drag as a viewport-pan gesture;
- precedence over annotation creation, selection, movement, resizing, text
  editing, and marquee selection for the initiating pointer;
- `grabbing` cursor feedback while the gesture is active;
- reuse of the existing viewport transform, pan bounds, pointer capture, and
  animation-frame throttling;
- clean termination on pointer-up, pointer-cancel, window blur, Escape, and
  component unmount;
- suppression of browser middle-button defaults such as auto-scroll;
- shortcut/help copy documenting both `Space + drag` and `Middle drag`;
- regression tests at the `EditorCanvas` input boundary.

### Not in scope

- changing normal wheel or trackpad scrolling;
- changing Command/Control-wheel pointer-anchored zoom;
- kinetic or inertial panning;
- remappable mouse buttons;
- right-button panning;
- changing viewport bounds or zoom limits;
- browser-specific navigation buttons or touch gestures.

## 3. Considered Approaches

### A. Generalize the existing pan interaction — selected

`EditorCanvas` classifies pointer-down as an ordinary tool gesture or a
viewport-pan gesture at its DOM capture boundary, before Konva annotation,
Transformer, or text-editor targets can start their own mouse lifecycle. The
canvas shell owns middle-button pointer capture and forwards its workspace
coordinates into the existing `InteractionController` preview/commit path.
Space-pan continues to enter the same semantic path through the Konva Stage.
Both inputs reuse `onViewportPanBy`.

Benefits:

- one lifecycle for Space-pan and middle-button pan;
- existing pointer capture, requestAnimationFrame throttling, cleanup, cursor,
  viewport bounds, and interaction-active signaling remain authoritative;
- future temporary pan inputs can be added without another parallel state
  machine;
- tests can assert user-visible behavior at one boundary.

Cost:

- keyboard-specific names such as `spaceHeld` and `isSpacePanning` must be
  generalized carefully.

### B. Add a separate middle-button state machine

Keep Space-pan unchanged and add separate refs, pointer handlers, and cleanup
for middle-button pan.

Benefit: the first diff can appear smaller. Costs: duplicated lifecycle and
cleanup, conflicting pointer capture, two sources of cursor truth, and greater
risk of a stuck interaction after blur or cancellation. This is rejected.

### C. Translate middle-button input into synthetic wheel events

Convert pointer displacement into wheel-like viewport inputs.

Benefit: it could reuse wheel routing. Costs: synthetic event semantics,
incorrect continuous-drag lifecycle, weaker pointer capture, and unnecessary
coupling between two distinct input devices. This is rejected.

## 4. Interaction Contract

### 4.1 Start

- A pointer-down whose native `button` is `1` starts middle-button pan.
- It starts without Space being held and under every selected tool.
- It has priority over the hit annotation, selection, transformer, and canvas
  creation handlers.
- It is ignored when viewport pan is explicitly locked or another pointer
  interaction is already active. An annotation-interaction lock caused by an
  active text editor does not lock middle-button viewport pan.
- A middle-button press arriving after a left-button annotation interaction
  has begun does not convert or hijack that interaction.
- Right-button input remains inert and left-button behavior remains unchanged.

### 4.2 Update

- A middle-button initiating pointer is captured by the canvas shell. A
  Space-pan initiating pointer retains the existing Stage-content capture.
- Pointer movement is measured in workspace/screen coordinates, not source
  image coordinates.
- A movement of `(dx, dy)` calls the existing viewport pan boundary with that
  same delta even when zoom is not `1`.
- Updates retain the current animation-frame throttling behavior.
- No annotation preview, marquee preview, selection change, command, or
  document-history entry is produced.

### 4.3 Finish and cancellation

- Pointer-up from the initiating pointer applies the final pending delta and
  ends the interaction exactly once.
- Pointer-cancel, blur, Escape, or unmount releases capture when possible,
  discards any pending frame, and ends the interaction exactly once.
- Pointer-up or pointer-cancel from a different pointer does not end the active
  gesture.
- The active tool and prior selection remain unchanged.

### 4.4 Feedback

- The canvas cursor is `grabbing` from accepted middle-button pointer-down
  until cleanup.
- Middle-button pan has no pre-press `grab` state because the editor cannot
  know the physical button will be used before it is pressed.
- Existing Space readiness remains `grab`; active Space-pan remains
  `grabbing`.
- Browser middle-button defaults are prevented at the accepted pointer-down
  and auxiliary-click boundary so no auto-scroll indicator or unintended
  browser action appears.

## 5. Architecture

```text
native pointer event
        |
        v
EditorCanvas classifies gesture
  shell-captured middle -+--> viewport pan interaction
  Stage left + Space ----+
  ordinary Stage left ---+--> active annotation tool interaction
                                 |
                                 v
InteractionController preview/commit
        |
        v
onViewportPanBy(screen delta)
        |
        v
EditorWorkspace -> ViewportController.panBy
```

`EditorCanvas` remains the only component that understands mouse-button
numbers. Its shell capture handler accepts and stops the initiating middle
pointer before the event reaches an annotation, Transformer anchor, or the
DOM-based text editor. It computes workspace coordinates from the shell's
bounding rectangle, starts the shared semantic pan interaction, and owns
middle-pointer move/up/cancel until cleanup. The shell also suppresses the
follow-on middle-button `mousedown` before Konva's internal draggable and
Transformer handlers or the textarea can consume it.

`InteractionController` understands the semantic fact that a viewport-pan
gesture was selected, not whether the gesture came from Space or a particular
mouse button. `ViewportController` remains input-device agnostic.

`EditorCanvas` receives separate annotation-interaction and viewport-pan lock
signals. In `App`, an active nudge transaction locks both; an active text edit
locks annotation creation/selection/transform but leaves middle-button pan
available. This prevents panning from committing the textarea's `onBlur` while
preserving the existing rule that ordinary canvas editing is disabled during a
text session.

The implementation should generalize keyboard-specific internal names toward
semantic names such as `viewportPanRequested`, `viewportPanActive`, or a small
pan-source value. It must not introduce a second viewport state or bypass
`EditorWorkspace.panBy`.

## 6. Event Precedence

For a new pointer-down, evaluation order is:

1. at the canvas-shell capture boundary, classify a middle-button pointer,
   prevent its browser default, and stop it before Konva or text-editor target
   handling;
2. reject when viewport pan is locked or another interaction is active;
3. classify accepted middle-button or Space-held input as viewport pan;
4. suppress the compatibility middle-button `mousedown` so Konva's default
   `[left, middle]` draggable configuration and Transformer anchor handling do
   not start a competing gesture;
5. only for ordinary Stage left-button input, evaluate
   annotation/transformer conflicts and the selected drawing tool;
6. reject other buttons.

This ordering guarantees that beginning on an annotation, transform handle, or
active text textarea still pans and never briefly selects, transforms, edits,
or previews an annotation.

## 7. Test Strategy

The primary tests belong in `EditorCanvas.test.tsx`, where native pointer input
is translated into observable editor behavior. The Konva Stage test seam must
preserve native `button`, `buttons`, and pointer identity.

Required regression contracts:

1. Middle-button drag at zoom `2` pans by the raw workspace delta while Space
   is not held.
2. The gesture works over an annotation or selected handle and produces no
   selection, creation, movement, resize, marquee preview, command, or history
   mutation.
3. The cursor is `grabbing` only for the active gesture and restores on
   pointer-up.
4. Pointer-cancel or blur ends the interaction exactly once, and the next
   ordinary interaction works.
5. A late middle-button press cannot convert an existing left-button gesture.
6. Right-button and existing left-button behavior are unchanged.
7. The shortcut/help registry exposes the new input without removing
   `Space + drag`.
8. A middle drag starting on the active text-editor textarea pans without
   moving focus, changing text, committing the edit, or closing the editor.
   The test passes an annotation-interaction lock together with an unlocked
   viewport-pan signal to mirror the real App state.
9. An App-level Escape test proves the first Escape cancels active middle-pan
   and a later shortcut works normally.

Real-browser Playwright interaction coverage is also required:

- one case begins directly over a selected annotation's Transformer handle,
  uses Playwright's middle mouse button, observes viewport displacement, and
  confirms that transform geometry, selection, and document state did not
  change;
- one case enters live text editing, begins directly over the textarea, and
  confirms that the viewport pans while focus, draft text, and edit-session
  state remain unchanged.

These browser boundaries are necessary because Konva owns native `mousedown`
behavior for draggable nodes and Transformer anchors, while the text editor is
a separate focusable DOM control. The unit Stage mock cannot faithfully
reproduce either browser interaction boundary.

Viewport mathematics do not need a middle-button-specific test because those
tests already exist below the input-routing boundary.

## 8. Acceptance Criteria

- With any annotation tool selected, middle-button drag from empty canvas pans
  smoothly.
- Middle-button drag that begins directly over an annotation or transform
  handle also pans smoothly and does not mutate the document or selection.
- The gesture behaves identically at fit zoom and a non-default zoom.
- Releasing the wheel button immediately stops pan and restores the tool
  cursor.
- Cancelling, blurring, or pressing Escape cannot leave the editor stuck in
  pan mode or suppress later shortcuts.
- No browser auto-scroll indicator or auxiliary action appears.
- Existing Space-pan, wheel/trackpad pan, pointer-anchored zoom, selection,
  creation, move, resize, undo, and redo tests remain green.
