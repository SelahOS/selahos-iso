# Motion

Plymouth schedules refresh callbacks; there is no separate timer or daemon.
Its script plugin nominally refreshes at 50Hz. We change opacity every second
callback (at most 25 visual updates/second). After 160 callbacks the sequence
settles and returns immediately without recurring redraw or image allocation.
Timing is approximate under load; animation never delays boot or claims boot
has completed. An early daemon quit ends the animation immediately.

Pause: first ~350ms still. Reflect: three pre-rasterized concentric rings enter
with staggered opacity, then recede. Create: the existing Selah mark and tagline
fade in by ~3.2s and remain static. No shader, blur, particle system or scaling
inside refresh. Progress messages and credential prompts update on events.
A boot longer than 12s displays a neutral preparing message; it is not a timer
or promise of completion. Prompts interrupt decoration immediately.

The separately selectable `selah-experience-static` theme has no animation.
The SDDM scaffold and scene placeholders are static; no clock timer or spinner.
