# <NNN> <title>

One vertical slice, end to end: it crosses every layer it needs and lands on
something a test can check. Fill every heading, delete none of them.

## Objective

<the end-to-end behaviour this slice makes work, in the user's terms. Not a
layer-by-layer list of edits: a ticket someone can demo.>

## Done when

<one command a test can run, and the gate row it turns green. A sentence is not
a gate.>

## Blocks

<the numbers of the tickets that cannot start until this one lands, or "None
(can start immediately)". Every edge here must be one this slice really gates.>

## Seams

<the contracts this slice must respect: the inputs it takes, the outputs it
returns, the invariants it holds. By contract, never by file path, because a
location stops being true the moment the code moves.>

## Notes

<what is deliberately out of scope and which slice takes it next. Leave the
line empty when there is nothing; do not delete the heading.>
